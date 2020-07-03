#!/usr/bin/env perl

# gpx2geojson.pl
#
# GUI application for merging kashmir3d-generated multiple
# GPX files into a single file, decimating track points,
# and converting into a GeoJSON or KML file,
# both of which are specified in
# https://maps.gsi.go.jp/development/sakuzu_siyou.html
#
# Official website:
# https://github.com/anineco/gpx2geojson
#
# Copyright (c) 2019-2020 anineco@nifty.com
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
use Getopt::Std;
use Tk;
use constant IS_WIN32 => $^O eq 'MSWin32';
BEGIN {
  if (IS_WIN32) {
    require Win32::Process;
    Win32::Process->import();
  }
}
use Data::Dumper; # for debug only
{
  no warnings 'redefine';
  *Data::Dumper::qquote = sub { return shift; };
  $Data::Dumper::Useperl = 1;
}
use FindBin;
use lib $FindBin::Bin;
use Extensions;
use ToGeojson;
use ToKml;
require IconLut;
require Gpsbabel;

my $version = "1.0";

our %param = (
  line_style => 0,
  line_size => 0,
  opacity => 0.5,
  xt_state => 1,
  xt_error => 0.005, # allowable cross-track error in kilometer
  indir => '',
  outdir => '',
  outext => '.geojson',
  title => 'GPS Track Log'
);

my $dotfile = File::Spec->catfile(File::HomeDir->my_home, '.gpx2geojson');

sub open_param {
  open(my $in, '<', $dotfile) or return;
  while (<$in>) {
    chomp;
    my ($key, $value) = split '=';
    if (exists($param{$key})) {
      $param{$key} = $value;
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

my $xs = XML::Simple->new(
  ForceArray => 1,
  KeepRoot => 1,
  KeyAttr => [],
  XMLDecl => '<?xml version="1.0" encoding="UTF-8"?>'
);

sub read_gpxfiles {
  my @files = @_;
  my $file = shift @files;
  my $gpx = $xs->XMLin($file) or die "Can't parse $file: $!";
  foreach $file (@files) {
    my $xml = $xs->XMLin($file) or die "Can't parse $file: $!";
    foreach my $tag ('wpt', 'rte', 'trk') {
      my $i = $#{$gpx->{gpx}[0]->{$tag}} + 1;
      my $j = 0;
      my $n = $#{$xml->{gpx}[0]->{$tag}};
      while ($j <= $n) {
        $gpx->{gpx}[0]->{$tag}[$i++] = $xml->{gpx}[0]->{$tag}[$j++];
      }
    }
  }
  return $gpx;
}


# decimate track points in a segment using gpsbabel

my $n_point; # number of track points after conversion

sub decimate_trkseg {
  my $trkseg = shift;
  my $xml = {};
  $xml->{gpx}[0]->{trk}[0]->{trkseg}[0] = $trkseg;

  if (IS_WIN32) {
    my $tmp1 = tmpnam();
    my $tmp2 = tmpnam();
    open(my $out, '>', $tmp1);
    $xs->XMLout($xml, OutputFile => $out);
    close($out);
    my $cmd = "gpsbabel -t -i gpx -f $tmp1 -x simplify,error=$param{xt_error}k -o gpx -F $tmp2";

    # since system($cmd) opens annoying console window, call gpsbabel.exe directly
    my $exe = Gpsbabel::exe();
#   my $exe = 'C:\Program Files (x86)\GPSBabel\gpsbabel.exe';
    Win32::Process::Create(my $process, $exe, $cmd, 0, CREATE_NO_WINDOW, '.') or die "Can't execute $exe: $!";
    $process->Wait(INFINITE);

    $xml = $xs->XMLin($tmp2);
    unlink $tmp1, $tmp2;
  } else {
    my $cmd = "gpsbabel -t -i gpx -f - -x simplify,error=$param{xt_error}k -o gpx -F -";
    open2(my $in, my $out, $cmd);
    $xs->XMLout($xml, OutputFile => $out);
    close($out);
    $xml = $xs->XMLin($in);
    close($in);
  }
  $trkseg = $xml->{gpx}[0]->{trk}[0]->{trkseg}[0];
  $n_point += $#{$trkseg->{trkpt}} + 1;
  return $trkseg;
}

sub decimate_gpx {
  my $gpx = shift;

  foreach my $trk (@{$gpx->{gpx}[0]->{trk}}) {
    my $trkseg = $trk->{trkseg};
    for (my $i = 0; $i <= $#{$trkseg}; $i++) {
      $trkseg->[$i] = decimate_trkseg($trkseg->[$i]);
    }
  }
}

my $outfile = '';

sub convert {
  my $gpx = read_gpxfiles(@_);
  if ($param{xt_state}) {
    decimate_gpx($gpx);
  }
  open(my $out, '>'. $outfile) or die "Can't open $outfile: $!";
  if ($param{outext} eq '.gpx') {
    $xs->XMLout($gpx, OutputFile => $out);
  } elsif ($param{outext} eq '.kml') {
    my $kml = ToKML::convert($gpx);
    $xs->XMLout($kml, OutputFile => $out);
  } else {
    my $geojson = ToGeoJSON::convert($gpx);
    print $out JSON->new->utf8(0)->encode($geojson), "\n";
  }
  close($out);
}

# command line interface

if (@ARGV > 0) {
  my %opts = ( a => 0.5, s => 0, w => 0, x => 0, f => 'geojson' );
  getopts('a:s:w:x:f:h', \%opts);
  if ($opts{h}) {
    print STDERR <<EOS;
Usage: gpx2geojson gpxfiles...
Options:
  -a opacity      between 0 and 1
  -s line_style   0: use value specified in GPX file
  -w line_size    0: use value specified in GPX file
  -x xt_error     decimate track points. set cross-track error [km].
  -f format       output format (gpx, kml, geojson).
  -h              print this message.
EOS
    exit;
  }
  $outfile = '-';
  $param{opacity} = 0 + $opts{a};
  $param{line_size} = 0 + $opts{w};
  $param{line_style} = 0 + $opts{s};
  $param{xt_state} = $opts{x} > 0;
  $param{xt_error} = 0 + $opts{x};
  $param{outext} = '.' . $opts{f};
  convert(@ARGV);
  exit;
}

# graphical user interface

open_param();

my $top = MainWindow->new();
$top->optionAdd('*font', ['MS Gothic', 10]);
$top->title('GPX2GeoJSON');
$top->resizable(0, 0);
$top->Label(
  -text => "GPX→GeoJSONコンバータ Ver.$version"
)->grid(-row => 0, -column => 0, -columnspan => 5);

$top->Label(-text => 'GPXファイル' )->grid(-row => 1, -column => 0, -sticky => 'e');
$top->Label(-text => '出力形式'    )->grid(-row => 4, -column => 0, -sticky => 'e');
$top->Label(-text => '出力ファイル')->grid(-row => 5, -column => 0, -sticky => 'e');
$top->Label(-text => '変換設定'    )->grid(-row => 6, -column => 1, -sticky => 'ew');
$top->Label(-text => '線の透過率'  )->grid(-row => 7, -column => 0, -sticky => 'e');
$top->Label(-text => '線種'        )->grid(-row => 8, -column => 0, -sticky => 'e');
$top->Label(-text => '線幅'        )->grid(-row => 9, -column => 0, -sticky => 'e');
$top->Label(-text => '許容誤差[km]')->grid(-row => 7, -column => 2, -sticky => 'e');
$top->Label(-text => '変換結果情報')->grid(-row => 8, -column => 3, -sticky => 'w');
$top->Label(-text => '軌跡点数'    )->grid(-row => 9, -column => 2, -sticky => 'e');

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

# 出力形式

my $f0 = $top->Frame(
  -borderwidth => 2, -relief => 'sunken'
)->grid(-row => 4, -column => 1, -sticky => 'nsew');

my $formats = [['GPX', '.gpx'], ['KML', '.kml'], ['GeoJSON', '.geojson']];

foreach my $pair (@{$formats}) {
  $f0->Radiobutton(
    -text => $pair->[0],
    -value => $pair->[1],
    -variable => \$param{outext}
  )->pack(-side => 'left');
}

# 出力ファイル

$top->Entry(
  -textvariable => \$outfile
)->grid(-row => 5, -column => 1, -columnspan => 3, -sticky => 'nsew');

$top->Button(
  -text => '選択',
  -command => sub {
    my $ret = $top->getSaveFile(
      -filetypes => [['GPXファイル', '.gpx'], ['KMLファイル', '.kml'], ['GeoJSONファイル', '.geojson'], ['すべて', '*']],
      -initialdir => $param{outdir} || $param{indir},
      -initialfile => 'routemap' . $param{outext},
      -defaultextension => $param{outext}
    );
    if (defined $ret) {
      $outfile = $ret;
      $param{outdir} = dirname($ret);
    }
  }
)->grid(-row => 5, -column => 4, -sticky => 'ew');

# 線の透過率

$top->Spinbox(
  -textvariable => \$param{opacity},
  -format => '%3.1f',
  -from => 0.0,
  -to => 1.0,
  -increment => 0.1
)->grid(-row => 7, -column => 1, -sticky => 'nsew');

# 線種

my $f1 = $top->Frame(
  -borderwidth => 2, -relief => 'sunken'
)->grid(-row => 8, -column => 1, -sticky => 'nsew');

my $styles = [['GPX', 0], ['実線', 1], ['破線', 11], ['点線', 13]];

foreach my $pair (@{$styles}) {
  $f1->Radiobutton(
    -text => $pair->[0],
    -value => $pair->[1],
    -variable => \$param{line_style}
  )->pack(-side => 'left');
}

# 線幅

my $f2 = $top->Frame(
  -borderwidth => 2, -relief => 'sunken'
)->grid(-row => 9, -column => 1, -sticky => 'nsew');

my $sizes =  [['GPX', 0], [' 1pt', 1], [' 3pt',  3], [' 5pt',  5]];

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
)->grid(-row => 7, -column => 3, -sticky => 'nsew');

$top->Checkbutton(
  -text => '軌跡を間引く',
  -variable => \$param{xt_state},
  -command => sub {
    $xt_widget->configure(-state => $param{xt_state} ? 'normal' : 'disabled');
  }
)->grid(-row => 6, -column => 3, -sticky => 'w');

# 軌跡点数

$top->Entry(
  -textvariable => \$n_point,
  -foreground => 'blue',
  -state => 'readonly'
)->grid(-row => 9, -column => 3, -sticky => 'nsew');

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
    convert($gpxfiles->get(0, 'end'));
  };
  if (my $msg = $@) {
    $top->messageBox(-type => 'ok', -icon => 'error', -title => 'エラー',
      -message => $msg
    );
  } else {
    $top->messageBox(-type => 'ok', -icon => 'info', -title => '成功',
      -message => '変換結果を' . $outfile . 'に出力しました'
    );
  }
})->grid(-row => 10, -column => 1);

# 終了

$top->Button(-text => '終了', -command => sub {
  save_param();
  $top->destroy();
})->grid(-row => 10, -column => 4);

MainLoop();

__END__
