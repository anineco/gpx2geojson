#!/usr/bin/env perl
# kml2geojson.pl
# Script for migrating gpx2jsgi-converted KML files separately to GeoJSON files
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
# include iconlut.pm
use FindBin qw($Bin);
use lib "$Bin";
require iconlut; # customize icon for waypoint

if (@ARGV == 0) {
  die "Usage: kml2geojson.pl kmlfiles\n";
}

sub dehtml {
  my $s = shift; # description
  $s =~ s%^<table><tr><td>%%;
  $s =~ s%</td></tr></table>$%%;
  $s =~ s%</td></tr><tr><td>%,%g;
  $s =~ s%</td><td>%=%g;
  return $s;
}

sub pointFeature {
  my ($p, $id, $style) = @_;
  my $icon = substr($id, 1); # delete the first character 'N'
  my ($lon,$lat,$alt) = split /,/, $p->{Point}->{coordinates};
  my $q = {
    type => 'Feature',
    properties => {
      name => $p->{name},
#     _iconUrl => $style->{IconStyle}->{Icon}->{href},
      _iconUrl => iconlut::iconUrl($icon),
      _iconSize => iconlut::iconSize($icon),
      _iconAnchor => iconlut::iconAnchor($icon)
    },
    geometry => {
      type => 'Point',
      coordinates => []
    }
  };
  @{$q->{geometry}->{coordinates}} = (0+$lon, 0+$lat);
  my $cmt = dehtml($p->{description} || '');
  if ($cmt) {
    foreach my $kv (split /,/, $cmt) {
      my ($k,$v) = split /=/, $kv;
      $q->{properties}->{$k} = $v;
    }
  }
  return $q;
}

sub lineStringFeature {
  my ($p, $id, $style) = @_;
  $style->{LineStyle}->{color} =~ /^(..)(..)(..)(..)$/;
  my $color = "#$4$3$2";
# my $opacity = hex($1) / 255.0;
  my $opacity = 0.5;
# my $w = 0 + $style->{LineStyle}->{width};
  my $w = 3;
  my $q = {
    type => 'Feature',
    properties => {
      _color => $color,
      _opacity => $opacity,
      _weight => $w,
      _dashArray => "3,6",
    },
    geometry => {
      type => 'LineString',
      coordinates => []
    }
  };
  my $i = 0;
  foreach my $x (split /\n/, $p->{LineString}->{coordinates}) {
    my ($lon,$lat,$alt) = split /,/, $x;
    @{$q->{geometry}->{coordinates}[$i++]} = (0+$lon, 0+$lat);
  }
  return $q;
}

sub kml2geojson {
  my $kml = shift;
  my $q = {
    type => 'FeatureCollection',
    features => []
  };
  my $n = 0;
  foreach my $folder (@{$kml->{Document}->{Folder}}) {
    foreach my $p (@{$folder->{Placemark}}) {
      my $id = substr($p->{styleUrl}, 1); # delete the first character '#'
      my $style = $kml->{Document}->{Style}->{$id};
      if ($p->{Point}) {
        $q->{features}[$n++] = pointFeature($p, $id, $style);
      } elsif ($p->{LineString}) {
        $q->{features}[$n++] = lineStringFeature($p, $id, $style);
      }
    }
  }
  return $q;
}

my $parser = XML::Simple->new(
  forcearray => ['Style','Folder','Placemark'],
  keyattr => ['id']
);
my $serializer = JSON->new();

foreach my $arg (@ARGV) {
  my $kml = $parser->XMLin($arg);
  my $geojson = kml2geojson($kml);
  my $outfile = $arg;
  $outfile =~ s/\.kml$/.geojson/;
  print STDERR "$arg -> $outfile\n";
  open(my $out, ">$outfile") or die "Can't open $outfile: $!";
  print $out $serializer->utf8(0)->encode($geojson), "\n";
  close($out);
}

# end of kml2geojson.pl
