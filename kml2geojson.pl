#!/usr/bin/env perl
# kml2geojson.pl
# Script for migrating gpx2jsgi-converted KML files separately to GeoJSON files
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
# use Data::Dumper;

if (@ARGV == 0) {
  die "Usage: kml2geojson.pl kmlfiles\n";
}

sub dehtml {
  my $s = $_[0];
  $s =~ s|^<table><tr><td>||;
  $s =~ s|</td></tr></table>$||;
  $s =~ s|</td></tr><tr><td>|,|g;
  $s =~ s|</td><td>|=|g;
  return $s;
}

sub pointFeature {
  my ($p, $id, $style) = @_;
# my $icon = substr($id, 1); # delete the first character 'N'
# my $href = "https://map.jpn.org/icon/$icon.png";
  my $href = $style->{IconStyle}->{Icon}->{href};
  my ($lon,$lat,$alt) = split /,/, $p->{Point}->{coordinates};
  my $q = {
    type => 'Feature',
    properties => {
      name => $p->{name},
      _iconUrl => $href,
      _iconSize => [24,24],
      _iconAnchor => [12,12]
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

my $parser = XML::Simple->new(
  forcearray => ['Style','Folder','Placemark'],
  keyattr => ['id']
);
my $json = JSON->new();

sub kml2geojson {
  my $kml = $_[0];
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

foreach my $arg (@ARGV) {
  my $kml = $parser->XMLin($arg);
  my $geojson = kml2geojson($kml);
  my $out = $arg;
  $out =~ s/\.kml$/.geojson/;
  print STDERR "$arg -> $out\n";
  open(my $fh, ">$out");
  print $fh $json->utf8(0)->encode($geojson), "\n";
  close($fh);
}

# end of kml2geojson.pl
