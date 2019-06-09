#!/usr/bin/env perl
# gpx2geojson.pl
# GUI application for merging kashmir3d-generated GPX files
# and converting into GeoJSON file with style specified in
# https://github.com/gsi-cyberjapan/geojson-with-style-spec

# Official website:
# https://github.com/anineco/gpx2geojson

# Copyright (c) 2019 anineco@nifty.com
# Released under the MIT license
# https://opensource.org/licenses/mit-license.php

use strict;
use warnings;
use utf8;
use open ':utf8';
use open ':std';
use XML::Simple;
use JSON;
use File::HomeDir;
use File::Basename qw(dirname);
use File::Temp qw(:POSIX);
use Tk;
use Data::Dumper;
# include iconlut.pm
use FindBin qw($Bin);
use lib "$Bin";
use iconlut;

my $version = '0.1';

my %param = (
  line_style => 13,
  line_size => 3,
  opacity => 0.5,
  xt_state => 1,
  xt_error => 0.005, # allowable cross-track error in kilometer
  indir => '',
  outdir => ''
);

my $home = File::HomeDir->my_home;

sub openParam {
  open(IN, "<$home/.gpx2geojson") || return;
  while (<IN>) {
    chomp;
    my ($k, $v) = split('=');
    if (exists($param{$k})) {
      $param{$k} = $v;
    }
  }
  close(IN);
}

sub saveParam {
  open(OUT, ">$home/.gpx2geojson") || return;
  foreach (keys(%param)) {
    print OUT "$_=$param{$_}\n";
  }
  close(OUT);
}

my $outfile = '';
my $n_point = 0; # number of points in the result

my $parser = XML::Simple->new(
  forcearray => ['trk','trkseg','trkpt','wte','rte','rtept'],
  keyattr => []
);

sub readGpxFiles {
  my @files = @_;
  my $gpx = {wpt => [], rte => [], trk => []};
# merge GPX files
  foreach my $file (@files) {
    my $xml = $parser->XMLin($file);
    foreach my $tag ('wpt', 'rte', 'trk') {
      my $i = $#{$gpx->{$tag}} + 1;
      my $j = 0;
      my $n = $#{$xml->{$tag}};
      while ($j <= $n) {
        $gpx->{$tag}[$i++] = $xml->{$tag}[$j++];
      }
    }
  }
  return $gpx;
}

sub pointFeature {
  my $p = $_[0]; # wpt or rtept
  my $q = {
    type => 'Feature',
    properties => {
      name => $p->{name},
      _iconUrl => iconlut::iconUrl($p->{extensions}->{'kashmir3d:icon'}),
      _iconSize => [24,24], # FIXME: hard-coded parameter
      _iconAnchor => [12,12] # FIXME: hard-coded parameter
    },
    geometry => {
      type => 'Point',
      coordinates => []
    }
  };
  @{$q->{geometry}->{coordinates}} = (0+$p->{lon}, 0+$p->{lat});
  foreach my $kv (split /,/, $p->{cmt}) {
    my ($k,$v) = split /=/, $kv;
    if ($k !~ /^[[:blank:]]*$/) {
      $q->{properties}->{$k} = $v;
    }
  }
  return $q;
}

my %dash = (
# kashmir3d:line_style => dashArray
  11 => [4,2],        # short dash
  12 => [6,2],        # long dash
  13 => [1,2],        # dot
  14 => [1,2,5,2],    # dot-dash (one dot chain)
  15 => [1,2,1,2,6,2] # dot-dot-dash (two-dot chain)
);

sub getProperties {
  my $p = $_[0]; # rte or trk
  $p->{extensions}->{'kashmir3d:line_color'} =~ /^(..)(..)(..)$/;
  my $c = "#$3$2$1";
  my $w = 0 + ($param{line_size} ? $param{line_size}
                                 : $p->{extensions}->{'kashmir3d:line_size'});
  my $q = {
    _color => $c,
    _weight => $w,
    _opacity => $param{opacity}
  };
  my $s = $dash{$param{line_style} ? $param{line_style}
                                   : $p->{extensions}->{'kashmir3d:line_style'}};
  if ($s) {
    $q->{_dashArray} = join(',', map { ($_ * $w) . '' } @{$s});
  }
  return $q;
}

sub lineStringFeature {
  my ($p, $tag, $properties) = @_; # rte or trkseg
  my $q = {
    type => 'Feature',
    properties => $properties,
    geometry => {
      type => 'LineString',
      coordinates => []
    }
  };
  my $i = 0;
  if ($tag eq 'rtept') {
    foreach my $rtept (@{$p->{rtept}}) {
      @{$q->{geometry}->{coordinates}[$i++]} = (0+$rtept->{lon}, 0+$rtept->{lat});
    }
    return $q;
  }
  if (!$param{xt_state}) {
    foreach my $trkpt (@{$p->{trkpt}}) {
      @{$q->{geometry}->{coordinates}[$i++]} = (0+$trkpt->{lon}, 0+$trkpt->{lat});
    }
    $n_point += $i;
    return $q;
  }
# decimate track points in a segment using gpsbabel
  my $tmp1 = tmpnam();
  my $tmp2 = tmpnam();
  open(OUT, ">$tmp1");
  print OUT "<gpx><trk><trkseg>\n";
  foreach my $trkpt (@{$p->{trkpt}}) {
    print OUT qq!<trkpt lat="$trkpt->{lat}" lon="$trkpt->{lon}"/>\n!;
  }
  print OUT "</trkseg></trk></gpx>\n";
  close(OUT);

  system("gpsbabel -t -i gpx -f $tmp1 -x simplify,error=$param{xt_error}k -o gpx -F $tmp2");

  open(IN, "<$tmp2");
  while (<IN>) {
    next if (!/<trkpt/);
    m%<trkpt lat="(.*)" lon="(.*)"/>%;
    @{$q->{geometry}->{coordinates}[$i++]} = (0+sprintf("%.6f",$2), 0+sprintf("%.6f",$1));
  }
  close(IN);
  $n_point += $i;
  unlink $tmp1, $tmp2;
  return $q;
}

sub gpx2geojson {
  my $gpx = $_[0];
  $n_point = 0;
  my $q = {
    type => 'FeatureCollection',
    features => []
  };
  my $n = 0;

  foreach my $wpt (@{$gpx->{wpt}}) {
    $q->{features}[$n++] = pointFeature($wpt);
  }

  foreach my $rte (@{$gpx->{rte}}) {
    foreach my $rtept (@{$rte->{rtept}}) {
      next if ($rtept->{extensions}->{'kashmir3d:icon'} eq '901001'); # skip blank icon
      $q->{features}[$n++] = pointFeature($rtept);
    }
    $q->{features}[$n++] = lineStringFeature($rte, 'rtept', getProperties($rte));
  }

  foreach my $trk (@{$gpx->{trk}}) {
    my $properties = getProperties($trk);
    foreach my $trkseg (@{$trk->{trkseg}}) {
      $q->{features}[$n++] = lineStringFeature($trkseg, 'trkpt', $properties);
    }
  }
  return $q;
}

# CUI

openParam();

if (@ARGV > 0) {
  my $gpx = readGpxFiles(@ARGV);
  my $json = gpx2geojson($gpx);
  print JSON->new->pretty->encode($json);
  exit 0;
}

# GUI

my $top = MainWindow->new();
$top->optionAdd('*font', ['MS Gothic', 10]);
$top->title('GPX2GEOJSON');
$top->resizable(0, 0);
$top->Label(
  -text => "GPX→GeoJSONコンバータ Ver.$version"
)->grid(-row => 0, -column => 0, -columnspan => 5);

$top->Label(-text => 'GPXファイル')->grid(-row => 1, -column => 0, -sticky => 'e');
$top->Label(-text => '出力ファイル')->grid(-row => 4, -column => 0, -sticky => 'e');

my $gpxfiles = $top->Scrolled('Listbox',
  -scrollbars => 'oe',
  -selectmode => 'single',
  -width => 80,
  -height => 3
)->grid(-row => 1, -column => 1, -rowspan => 3, -columnspan => 3, -sticky => 'nsew');

$top->Button(-text => '←追加', -command => sub {
  my $ret = $top->getOpenFile(
    -filetypes => [['GPXファイル', '.gpx'], ['すべて', '*']],
    -initialdir => $param{indir},
    -multiple => 'yes'
  );
  foreach (@{$ret}) {
    $gpxfiles->insert('end', $_);
    $param{indir} = dirname($_);
  }
})->grid(-row => 1, -column => 4, -sticky => 'ew');

$top->Button(-text => '除外', -command => sub {
  my $i = $gpxfiles->curselection;
  if ($i ne "") { $gpxfiles->delete($i); }
})->grid(-row => 2, -column => 4, -sticky => 'ew');

$top->Button(-text => 'クリア', -command => sub {
  $gpxfiles->delete(0, 'end');
})->grid(-row => 3, -column => 4, -sticky => 'ew');

$top->Entry(
  -textvariable => \$outfile
)->grid(-row => 4, -column => 1, -columnspan => 3, -sticky => 'nsew');
$top->Button(-text => '選択', -command => sub {
  my $ret = $top->getSaveFile(
    -filetypes => [['GeoJSONファイル', '.geojson'], ['すべて', '*']],
    -initialdir => $param{outdir} ? $param{outdir} : $param{indir},
    -initialfile => 'routemap.geojson',
    -defaultextension => '.geojson'
  );
  if (defined($ret)) {
    $outfile = $ret;
    $param{outdir} = dirname($ret);
  }
})->grid(-row => 4, -column => 4, -sticky => 'ew');

$top->Label(-text => '変換設定')->grid(-row => 5, -column => 1, -sticky => 'ew');
$top->Label(-text => '線の透過率')->grid(-row => 6, -column => 0, -sticky => 'e');
$top->Label(-text => '線種')->grid(-row => 7, -column => 0, -sticky => 'e');
$top->Label(-text => '線幅')->grid(-row => 8, -column => 0, -sticky => 'e');
$top->Label(-text => '許容誤差[km]')->grid(-row => 6, -column => 2, -sticky => 'e');

$top->Spinbox(
  -textvariable => \$param{opacity},
  -format => '%3.1f',
  -from => 0.0,
  -to => 1.0,
  -increment => 0.1
)->grid(-row => 6, -column => 1, -sticky => 'nsew');

my $styles = [['GPX', 0], ['実線', 1], ['破線', 11], ['点線', 13]];
my $sizes =  [['GPX', 0], [' 1pt', 1], [' 3pt',  3], [' 5pt',  5]];

my $f1 = $top->Frame(
  -borderwidth => 2, -relief => 'sunken'
)->grid(-row => 7, -column => 1, -sticky => 'nsew');
foreach (@{$styles}) {
  $f1->Radiobutton(
    -text => $_->[0], -value => $_->[1], -variable => \$param{line_style}
  )->pack(-side => 'left');
}
my $f2 = $top->Frame(
  -borderwidth => 2, -relief => 'sunken'
)->grid(-row => 8, -column => 1, -sticky => 'nsew');
foreach (@{$sizes}) {
  $f2->Radiobutton(
    -text => $_->[0], -value => $_->[1], -variable => \$param{line_size}
  )->pack(-side => 'left');
}

my $xt_widget = $top->Spinbox(
  -textvariable => \$param{xt_error},
  -format => '%5.3f',
  -from => 0.001,
  -to => 9.999,
  -increment => 0.001,
  -state => $param{xt_state} ? 'normal' : 'disabled'
)->grid(-row => 6, -column => 3, -sticky => 'nsew');

$top->Checkbutton(
  -text => '軌跡を間引く',
  -variable => \$param{xt_state},
  -command => sub {
    $xt_widget->configure(-state => $param{xt_state} ? 'normal' : 'disabled');
  }
)->grid(-row => 5, -column => 3, -sticky => 'w');

$top->Label(-text => '変換結果情報')->grid(-row => 7, -column => 3, -sticky => 'w');
$top->Label(-text => '軌跡点数')->grid(-row => 8, -column => 2, -sticky => 'e');
$top->Entry(
  -textvariable => \$n_point,
  -foreground => 'blue',
  -state => 'readonly'
)->grid(-row => 8, -column => 3, -sticky => 'nsew');

$top->Button(-text => '変換', -command => sub {
  if ($gpxfiles->size == 0) {
    $top->messageBox(-type => 'ok', -icon => 'warning', -title => '警告',
      -message => "GPXファイルが未設定"
    );
    return;
  }
  if ($outfile eq "") {
    $top->messageBox(-type => 'ok', -icon => 'warning', -title => '警告',
      -message => "出力ファイルが未設定"
    );
    return;
  }
  my $gpx = readGpxFiles($gpxfiles->get(0, 'end'));
  my $geojson = gpx2geojson($gpx);
  open(OUT, ">$outfile");
  print OUT JSON->new->utf8(0)->encode($geojson), "\n";
  close(OUT);
  $top->messageBox(-type => 'ok', -title => '成功',
    -message => "変換結果を${outfile}に出力しました"
  );
})->grid(-row => 9, -column => 1);

$top->Button(-text => '終了', -command => sub {
  saveParam();
  exit;
})->grid(-row => 9, -column => 4);

MainLoop;

# end of gpx2geojson.pl
