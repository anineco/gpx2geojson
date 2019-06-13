#!/usr/bin/env perl
# gpx2geojson.pl
# GUI application for merging kashmir3d-generated GPX files
# and converting into GeoJSON file with style specified in
# https://github.com/gsi-cyberjapan/geojson-with-style-spec

# Official website:
# https://github.com/anineco/gpx2geojson

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
use IPC::Open2;
use Tk;
use constant {
  OS_MSWIN => $^O eq 'MSWin32',
  GPSBABEL => 'C:\Program Files (x86)\GPSBabel\gpsbabel.exe' # full path of executable file
};
BEGIN {
  if (OS_MSWIN) {
    require Win32::Process;
    Win32::Process->import();
  }
}
# include iconlut.pm
use FindBin qw($Bin);
use lib "$Bin";
require iconlut; # customize icon for waypoint

my $version = '0.9';

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
  open(my $in, "<$home/.gpx2geojson") or return;
  while (<$in>) {
    chomp;
    my ($k, $v) = split('=');
    if (exists($param{$k})) {
      $param{$k} = $v;
    }
  }
  close($in);
}

sub saveParam {
  open(my $out, ">$home/.gpx2geojson") or return;
  foreach (keys(%param)) {
    print $out "$_=$param{$_}\n";
  }
  close($out);
}

my $parser = XML::Simple->new(
  forcearray => ['trk','trkseg','trkpt','wte','rte','rtept'],
  keyattr => []
);

sub readGpxFiles {
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

sub pointFeature {
  my $p = $_[0]; # wpt or rtept
  my $icon = $p->{extensions}->{'kashmir3d:icon'};
  my $q = {
    type => 'Feature',
    properties => {
      name => $p->{name},
      _iconUrl => iconlut::iconUrl($icon),
      _iconSize => iconlut::iconSize($icon),
      _iconAnchor => iconlut::iconAnchor($icon)
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

my $n_point; # number of track points after conversion

sub writeTrkseg {
  my ($out, $p) = @_; # trkseg
  print $out "<gpx><trk><trkseg>\n";
  foreach my $trkpt (@{$p->{trkpt}}) {
    print $out qq!<trkpt lat="$trkpt->{lat}" lon="$trkpt->{lon}"/>\n!;
  }
  print $out "</trkseg></trk></gpx>\n";
}

sub readTrkseg {
  my ($in, $q) = @_; # 'LineString' feature
  my $i = 0;
  while (<$in>) {
    next if (!/<trkpt/);
    m%<trkpt lat="(.*)" lon="(.*)"/>%;
    @{$q->{geometry}->{coordinates}[$i++]} = (0+sprintf("%.6f",$2), 0+sprintf("%.6f",$1));
  }
  $n_point += $i;
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
  if ($tag eq 'rtept' or !$param{xt_state}) {
    foreach (@{$p->{$tag}}) {
      @{$q->{geometry}->{coordinates}[$i++]} = (0+$_->{lon}, 0+$_->{lat});
    }
    $n_point += $i;
    return $q;
  }
# decimate track points in a segment using gpsbabel
  if (0) {
    my $cmd = "gpsbabel -t -i gpx -f - -x simplify,error=$param{xt_error}k -o gpx -F -";
    open2(my $in, my $out, $cmd);
    writeTrkseg($out, $p);
    close($out);
    readTrkseg($in, $q);
    close($in);
  } else {
    my $tmp1 = tmpnam();
    my $tmp2 = tmpnam();
    my $cmd = "gpsbabel -t -i gpx -f $tmp1 -x simplify,error=$param{xt_error}k -o gpx -F $tmp2";
    open(my $out, '>', $tmp1);
    writeTrkseg($out, $p);
    close($out);

    if (OS_MSWIN) {
      # execute external program without opening unsightly window
      Win32::Process::Create(my $process, GPSBABEL, $cmd, 0, CREATE_NO_WINDOW, '.');
      $process->Wait(INFINITE);
    } else {
      system($cmd);
    }

    open(my $in, '<', $tmp2);
    readTrkseg($in, $q);
    close($in);
    unlink $tmp1, $tmp2;
  }
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

openParam();

# command line interface

if (@ARGV > 0) {
  my $gpx = readGpxFiles(@ARGV);
  my $geojson = gpx2geojson($gpx);
  print JSON->new->pretty->encode($geojson);
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
  foreach my $path (@{$ret}) {
    $gpxfiles->insert('end', $path);
    $param{indir} = dirname($path);
  }
})->grid(-row => 1, -column => 4, -sticky => 'ew');

$top->Button(-text => '除外', -command => sub {
  my $i = $gpxfiles->curselection;
  if ($i ne "") { $gpxfiles->delete($i); }
})->grid(-row => 2, -column => 4, -sticky => 'ew');

$top->Button(-text => 'クリア', -command => sub {
  $gpxfiles->delete(0, 'end');
})->grid(-row => 3, -column => 4, -sticky => 'ew');

my $outfile = '';

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
      -message => 'GPXファイルが未設定'
    );
    return;
  }
  if ($outfile eq '') {
    $top->messageBox(-type => 'ok', -icon => 'warning', -title => '警告',
      -message => '出力ファイルが未設定'
    );
    return;
  }
  my $gpx = readGpxFiles($gpxfiles->get(0, 'end'));
  my $geojson = gpx2geojson($gpx);
  my $ret = open(my $out, ">$outfile");
  print $out JSON->new->utf8(0)->encode($geojson), "\n";
  close($out);
  $top->messageBox(-type => 'ok',
    -title => $ret ? '成功' : '失敗',
    -message => $ret ? "変換結果を${outfile}に出力しました"
                     : "変換結果が${outfile}に出力できません"
  );
})->grid(-row => 9, -column => 1);

$top->Button(-text => '終了', -command => sub {
  saveParam();
  $top->destroy();
})->grid(-row => 9, -column => 4);

MainLoop();
__END__
