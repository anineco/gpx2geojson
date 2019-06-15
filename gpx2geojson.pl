#!/usr/bin/env perl
# gpx2geojson.pl
# GUI application for merging kashmir3d-generated GPX files
# and converting into GeoJSON file with style specified in
# https://github.com/gsi-cyberjapan/geojson-with-style-spec
#
# Official website:
# https://github.com/anineco/gpx2geojson
#
# Copyright (c) 2019 anineco@nifty.com
# Released under the MIT license
# https://github.com/anineco/gpx2geojson/blob/master/LICENSE

use strict;
use warnings;
use utf8;
use open ':utf8';
use open ':std';
use XML::Simple qw(:strict);
use JSON;
use File::Basename qw(dirname);
use File::HomeDir;
use File::Temp qw(:POSIX);
use File::Spec;
use IPC::Open2;
use Tk;
use constant OS_MSWIN => $^O eq 'MSWin32';
BEGIN {
  if (OS_MSWIN) {
    require Win32::Process;
    Win32::Process->import();
  }
}
# include iconlut.pm for customizing icon of waypoint
use FindBin qw($Bin);
use lib "$Bin";
require iconlut;

my $version = "0.9";

my %param = (
  line_style => 13,
  line_size => 3,
  opacity => 0.5,
  xt_state => 1,
  xt_error => 0.005, # allowable cross-track error in kilometer
  indir => '',
  outdir => ''
);

my $dotfile = File::Spec->catfile(File::HomeDir->my_home, '.gpx2geojson');

sub open_param {
  open(my $in, '<', $dotfile) or return;
  while (<$in>) {
    chomp;
    my ($k, $v) = split '=';
    if (exists($param{$k})) {
      $param{$k} = $v;
    }
  }
  close($in);
}

sub save_param {
  open(my $out, '>', $dotfile) or return;
  foreach my $key (keys(%param)) {
    print $out $key, '=', $param{$key}, "\n";
  }
  close($out);
}

my $parser = XML::Simple->new(
  forcearray => ['trk','trkseg','trkpt','wte','rte','rtept'],
  keyattr => []
);

sub read_gpxfiles {
  my @files = @_;
  my $gpx = {wpt => [], rte => [], trk => []};
# merge GPX files
  foreach my $file (@files) {
    my $xml = $parser->XMLin($file) or die "Can't parse $file: $!";
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

sub get_point_feature {
  my $pt = shift; # wpt or rtept
  my $icon = $pt->{extensions}->{'kashmir3d:icon'};
  my $feature = {
    type => 'Feature',
    properties => {
      name => $pt->{name},
      _iconUrl => iconlut::iconUrl($icon),
      _iconSize => iconlut::iconSize($icon),
      _iconAnchor => iconlut::iconAnchor($icon)
    },
    geometry => {
      type => 'Point',
      coordinates => [0+$pt->{lon}, 0+$pt->{lat}]
    }
  };
  foreach (split /,/, $pt->{cmt}) {
    my ($key, $value) = split /=/;
    if ($key !~ /^[[:blank:]]*$/) { # using POSIX character class
      $feature->{properties}->{$key} = $value;
    }
  }
  return $feature;
}

my %dash = (
# kashmir3d:line_style => dashArray
  11 => [4,2],        # short dash
  12 => [6,2],        # long dash
  13 => [1,2],        # dot
  14 => [1,2,5,2],    # dot-dash (one dot chain)
  15 => [1,2,1,2,6,2] # dot-dot-dash (two-dot chain)
);

sub get_properties {
  my $t = shift; # trk or rte
  $t->{extensions}->{'kashmir3d:line_color'} =~ /^(..)(..)(..)$/;
  my $c = "#$3$2$1";
  my $w = 0+($param{line_size} || $t->{extensions}->{'kashmir3d:line_size'});
  my $properties = {
    _color => $c,
    _weight => $w,
    _opacity => $param{opacity}
  };
  my $s = $dash{$param{line_style} || $t->{extensions}->{'kashmir3d:line_style'}};
  if ($s) {
    $properties->{_dashArray} = join ',', map { '' . ($_ * $w) } @{$s};
  }
  return $properties;
}

my $n_point; # number of track points after conversion

sub write_trkseg {
  my ($out, $trkseg) = @_;
  print $out "<gpx><trk><trkseg>\n";
  foreach my $trkpt (@{$trkseg->{trkpt}}) {
    print $out qq!<trkpt lat="$trkpt->{lat}" lon="$trkpt->{lon}"/>\n!;
  }
  print $out "</trkseg></trk></gpx>\n";
}

sub read_trkseg {
  my ($in, $feature) = @_;
  my $i = 0;
  while (<$in>) {
    next if (!/<trkpt/);
    m%<trkpt lat="(.*)" lon="(.*)"/>%;
    @{$feature->{geometry}->{coordinates}[$i++]} = (0+sprintf("%.6f",$2), 0+sprintf("%.6f",$1));
  }
  $n_point += $i;
}

sub get_linestring_feature {
  my ($segment, $tag, $properties) = @_; # trkseg or rte
  my $feature = {
    type => 'Feature',
    properties => $properties,
    geometry => {
      type => 'LineString',
      coordinates => []
    }
  };
  if ($tag eq 'rtept' or !$param{xt_state}) {
    my $i = 0;
    foreach (@{$segment->{$tag}}) {
      @{$feature->{geometry}->{coordinates}[$i++]} = (0+$_->{lon}, 0+$_->{lat});
    }
    $n_point += $i;
    return $feature;
  }

# decimate track points in a segment using gpsbabel
  if (OS_MSWIN) {
    my $tmp1 = tmpnam();
    my $tmp2 = tmpnam();
    open(my $out, '>', $tmp1);
    write_trkseg($out, $segment);
    close($out);
    my $cmd = "gpsbabel -t -i gpx -f $tmp1 -x simplify,error=$param{xt_error}k -o gpx -F $tmp2";

    # since system($cmd) opens annoying console window, call gpsbabel.exe directly
    Win32::Process::Create(my $process,
      'C:\Program Files (x86)\GPSBabel\gpsbabel.exe', # FIXME: hard-coded
      $cmd, 0, CREATE_NO_WINDOW, '.'
    );
    $process->Wait(INFINITE);

    open(my $in, '<', $tmp2);
    read_trkseg($in, $feature);
    close($in);
    unlink $tmp1, $tmp2;
  } else {
    my $cmd = "gpsbabel -t -i gpx -f - -x simplify,error=$param{xt_error}k -o gpx -F -";
    open2(my $in, my $out, $cmd);
    write_trkseg($out, $segment);
    close($out);
    read_trkseg($in, $feature);
    close($in);
  }
  return $feature;
}

sub gpx2geojson {
  my $gpx = shift;
  $n_point = 0;
  my $geojson = {
    type => 'FeatureCollection',
    features => []
  };
  my $n = 0;

  foreach my $wpt (@{$gpx->{wpt}}) {
    $geojson->{features}[$n++] = get_point_feature($wpt);
  }

  foreach my $rte (@{$gpx->{rte}}) {
    foreach my $rtept (@{$rte->{rtept}}) {
      next if ($rtept->{extensions}->{'kashmir3d:icon'} eq '901001'); # skip blank icon
      $geojson->{features}[$n++] = get_point_feature($rtept);
    }
    $geojson->{features}[$n++] = get_linestring_feature($rte, 'rtept', get_properties($rte));
  }

  foreach my $trk (@{$gpx->{trk}}) {
    my $properties = get_properties($trk);
    foreach my $trkseg (@{$trk->{trkseg}}) {
      $geojson->{features}[$n++] = get_linestring_feature($trkseg, 'trkpt', $properties);
    }
  }
  return $geojson;
}

open_param();

# command line interface

if (@ARGV > 0) {
  my $gpx = read_gpxfiles(@ARGV);
  my $geojson = gpx2geojson($gpx);
  print JSON->new->utf8(0)->encode($geojson);
  exit;
}

# graphical user interface

my $top = MainWindow->new();
$top->optionAdd('*font', ['MS Gothic', 10]);
$top->title('GPX2GeoJSON');
$top->resizable(0, 0);
$top->Label(
  -text => "GPX→GeoJSONコンバータ Ver.$version"
)->grid(-row => 0, -column => 0, -columnspan => 5);

$top->Label(-text => 'GPXファイル' )->grid(-row => 1, -column => 0, -sticky => 'e');
$top->Label(-text => '出力ファイル')->grid(-row => 4, -column => 0, -sticky => 'e');
$top->Label(-text => '変換設定'    )->grid(-row => 5, -column => 1, -sticky => 'ew');
$top->Label(-text => '線の透過率'  )->grid(-row => 6, -column => 0, -sticky => 'e');
$top->Label(-text => '線種'        )->grid(-row => 7, -column => 0, -sticky => 'e');
$top->Label(-text => '線幅'        )->grid(-row => 8, -column => 0, -sticky => 'e');
$top->Label(-text => '許容誤差[km]')->grid(-row => 6, -column => 2, -sticky => 'e');
$top->Label(-text => '変換結果情報')->grid(-row => 7, -column => 3, -sticky => 'w');
$top->Label(-text => '軌跡点数'    )->grid(-row => 8, -column => 2, -sticky => 'e');

# GPXファイル

my $gpxfiles = $top->Scrolled('Listbox',
  -scrollbars => 'oe',
  -selectmode => 'single',
  -width => 80,
  -height => 3
)->grid(-row => 1, -column => 1, -rowspan => 3, -columnspan => 3, -sticky => 'nsew');

$top->Button(
  -text => '←追加',
  -command => sub {
    my $ret = $top->getOpenFile(
      -filetypes => [['GPXファイル', '.gpx'], ['すべて', '*']],
      -initialdir => $param{indir},
      -multiple => 'yes'
    );
    foreach my $path (@{$ret}) {
      $gpxfiles->insert('end', $path);
      $param{indir} = dirname($path);
    }
  }
)->grid(-row => 1, -column => 4, -sticky => 'ew');

$top->Button(
  -text => '除外',
  -command => sub {
    my $i = $gpxfiles->curselection;
    if ($i ne "") {
      $gpxfiles->delete($i);
    }
  }
)->grid(-row => 2, -column => 4, -sticky => 'ew');

$top->Button(
  -text => 'クリア',
  -command => sub {
    $gpxfiles->delete(0, 'end');
  }
)->grid(-row => 3, -column => 4, -sticky => 'ew');

# 出力ファイル

my $outfile = '';

$top->Entry(
  -textvariable => \$outfile
)->grid(-row => 4, -column => 1, -columnspan => 3, -sticky => 'nsew');

$top->Button(
  -text => '選択',
  -command => sub {
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
  }
)->grid(-row => 4, -column => 4, -sticky => 'ew');

# 線の透過率

$top->Spinbox(
  -textvariable => \$param{opacity},
  -format => '%3.1f',
  -from => 0.0,
  -to => 1.0,
  -increment => 0.1
)->grid(-row => 6, -column => 1, -sticky => 'nsew');

# 線種

my $styles = [['GPX', 0], ['実線', 1], ['破線', 11], ['点線', 13]];

my $f1 = $top->Frame(
  -borderwidth => 2, -relief => 'sunken'
)->grid(-row => 7, -column => 1, -sticky => 'nsew');

foreach my $pair (@{$styles}) {
  $f1->Radiobutton(
    -text => $pair->[0],
    -value => $pair->[1],
    -variable => \$param{line_style}
  )->pack(-side => 'left');
}

# 線幅

my $sizes =  [['GPX', 0], [' 1pt', 1], [' 3pt',  3], [' 5pt',  5]];

my $f2 = $top->Frame(
  -borderwidth => 2, -relief => 'sunken'
)->grid(-row => 8, -column => 1, -sticky => 'nsew');

foreach my $pair (@{$sizes}) {
  $f2->Radiobutton(
    -text => $pair->[0],
    -value => $pair->[1],
    -variable => \$param{line_size}
  )->pack(-side => 'left');
}

# 許容誤差

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

# 軌跡点数

$top->Entry(
  -textvariable => \$n_point,
  -foreground => 'blue',
  -state => 'readonly'
)->grid(-row => 8, -column => 3, -sticky => 'nsew');

# 変換

$top->Button(-text => '変換', -command => sub {
  if ($gpxfiles->size == 0) {
    $top->messageBox(-type => 'ok', -icon => 'warning', -title => '警告',
      -message => 'GPXファイルが未設定'
    );
    return;
  }
  if ($outfile eq '') {
    $top->messageBox(-type => 'ok', -icon => 'warning', -title => '警告',
      -message => '出力ファイルが未設定',
    );
    return;
  }
  eval {
    my $gpx = read_gpxfiles($gpxfiles->get(0, 'end'));
    my $geojson = gpx2geojson($gpx);
    open(my $out, '>', $outfile) or die "Can't open $outfile: $!";
    print $out JSON->new->utf8(0)->encode($geojson), "\n";
    close($out);
  };
  if (my $msg = $@) {
    $top->messageBox(-type => 'ok', -icon => 'error', -title => 'エラー',
      -message => $msg
    );
  } else {
    $top->messageBox(-type => 'ok', -icon => 'info', -title => '成功',
      -message => "変換結果を${outfile}に出力しました"
    );
  }
})->grid(-row => 9, -column => 1);

# 終了

$top->Button(-text => '終了', -command => sub {
  save_param();
  $top->destroy();
})->grid(-row => 9, -column => 4);

MainLoop();

__END__
