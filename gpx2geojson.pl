#!/usr/bin/env perl
# gpx2geojson.pl
# Script for merging kashmir3d-generated GPX files and converting into GeoJSON file
# Copyright (c) 2019 anineco@nifty.com
# Released under the MIT license
# https://opensource.org/licenses/mit-license.php

use strict;
use warnings;
use utf8;
use open ':utf8';
use open ':std';
use XML::Simple;
use FileHandle;
use IPC::Open2;
use JSON;
# include iconlut.pm
#use FindBin qw($Bin);
#use lib "$Bin";
#use iconlut;

if (@ARGV == 0) {
  die "Usage: gpx2geojson.pl gpxfiles\n";
}

my $parser = XML::Simple->new(
  forcearray => ['trk','trkseg','trkpt','wte','rte','rtept'],
  keyattr => []
);

my $gpx = { wpt => [], rte => [], trk => [] };

foreach my $arg (@ARGV) {
  my $xml = $parser->XMLin($arg);
# merge GPX files
  foreach my $tag ('wpt', 'rte', 'trk') {
    my $i = $#{$gpx->{$tag}} + 1;
    my $j = 0;
    my $n = $#{$xml->{$tag}};
    while ($j <= $n) {
      $gpx->{$tag}[$i++] = $xml->{$tag}[$j++];
    }
  }
}

sub pointFeature {
  my $p = $_[0];
  my $q = {
    type => 'Feature',
    properties => {
      name => $p->{name},
      _iconUrl => "https://map.jpn.org/icon/$p->{extensions}->{'kashmir3d:icon'}.png",
#     _iconUrl => $iconlut::iconlut{$p->{extensions}->{'kashmir3d:icon'}},
      _iconSize => [24,24],
      _iconAnchor => [12,12]
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

my $dash = {
  11 => [4,2],
  12 => [6,2],
  13 => [1,2],
  14 => [1,2,5,2],
  15 => [1,2,1,2,6,2]
};

sub getProperties {
  my $p = $_[0];
  my $c = $p->{extensions}->{'kashmir3d:line_color'};
# my $w = 0 + $p->{extensions}->{'kashmir3d:line_size'};
  my $w = 3;
  my $q = {
    _color => '#' . substr($c,4,2) . substr($c,2,2) . substr($c,0,2),
    _weight => $w,
    _opacity => 0.5
  };
# my $s = $dash->{$p->{extensions}->{'kashmir3d:line_style'}};
  my $s = $dash->{13};
  if ($s) {
    $q->{_dashArray} = join(',', map { ($_ * $w) . '' } @{$s});
  }
  return $q;
}

sub lineStringFeature {
  my ($p, $tag, $properties) = @_;
  my $q = {
    type => 'Feature',
    properties => $properties,
    geometry => {
      type => 'LineString',
      coordinates => []
    }
  };
  if ($tag eq 'rtept') {
    my $i = 0;
    foreach my $rtept (@{$p->{rtept}}) {
      @{$q->{geometry}->{coordinates}[$i++]} = (0+$rtept->{lon}, 0+$rtept->{lat});
    }
    return $q;
  }
# decimate track points in a segment by using gpsbabel. maximum allowable error = 0.005km.
  open2(*IN, *OUT, "gpsbabel -t -i gpx -f - -x simplify,error=0.005k -o gpx -F -");
  print OUT "<gpx><trk><trkseg>\n";
  foreach my $trkpt (@{$p->{trkpt}}) {
    print OUT qq!<trkpt lat="$trkpt->{lat}" lon="$trkpt->{lon}"/>\n!;
  }
  print OUT "</trkseg></trk></gpx>\n";
  close(OUT);

  my $i = 0;
  while (<IN>) {
    next if (!/<trkpt/);
    m%<trkpt lat="(.*)" lon="(.*)"/>%;
    @{$q->{geometry}->{coordinates}[$i++]} = (0+sprintf("%.6f",$2), 0+sprintf("%.6f",$1));
  }
  close(IN);
  return $q;
}

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

#print JSON->new->pretty->encode($q);
print JSON->new->utf8(0)->encode($q), "\n";

# end of gpx2geojson.pl
