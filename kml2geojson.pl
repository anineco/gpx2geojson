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
# include iconlut.pm for customizing icon of waypoint
use FindBin;
use lib $FindBin::Bin;
require iconlut;

if (@ARGV == 0) {
  die "Usage: kml2geojson.pl kmlfiles\n";
}

sub set_properties {
  my ($feature, $description) = @_;
  if (!$description) { return; }
  my ($comma, $equal) = (',', '=');
  if ($description =~ s%^<table><tr><td>(.*)</td></tr></table>$%$1%) {
    $comma = '</td></tr><tr><td>';
    $equal = '</td><td>';
  }
  foreach (split /$comma/, $description) {
    my ($key, $value) = split /$equal/;
    $feature->{properties}->{$key} = $value;
  }
}

sub point_feature {
  my ($placemark, $style, $id) = @_;
  $id =~ m/^N([0-9]{6})$/;
  my $icon = $1;
  my ($lon,$lat,$alt) = split /,/, $placemark->{Point}->{coordinates};
  my $feature = {
    type => 'Feature',
    properties => {
      name => $placemark->{name},
#     _iconUrl => $style->{IconStyle}->{Icon}->{href},
      _iconUrl => iconlut::iconUrl($icon), # NOTE: reset based on iconlut.pm
      _iconSize => iconlut::iconSize($icon),
      _iconAnchor => iconlut::iconAnchor($icon)
    },
    geometry => {
      type => 'Point',
      coordinates => [0+$lon, 0+$lat]
    }
  };
  set_properties($feature, $placemark->{description});
  return $feature;
}

sub linestring_feature {
  my ($placemark, $style) = @_;
  $style->{LineStyle}->{color} =~ /^(..)(..)(..)(..)$/;
  my $color = "#$4$3$2";
# my $opacity = hex($1) / 255.0;
  my $opacity = 0.5; # NOTE: set proper value
# my $w = 0 + $style->{LineStyle}->{width};
  my $w = 3; # NOTE: set proper value
  my $feature = {
    type => 'Feature',
    properties => {
      _color => $color,
      _opacity => $opacity,
      _weight => $w,
      _dashArray => "3,6" # NOTE: set proper value
    },
    geometry => {
      type => 'LineString',
      coordinates => []
    }
  };
  my $i = 0;
  foreach (split /\n/, $placemark->{LineString}->{coordinates}) {
    my ($lon,$lat,$alt) = split /,/;
    @{$feature->{geometry}->{coordinates}[$i++]} = (0+$lon, 0+$lat);
  }
  return $feature;
}

sub kml2geojson {
  my $kml = shift;
  my $geojson = {
    type => 'FeatureCollection',
    features => []
  };
  my $n = 0;
  foreach my $folder (@{$kml->{Document}->{Folder}}) {
    foreach my $placemark (@{$folder->{Placemark}}) {
      my $id = substr($placemark->{styleUrl}, 1); # delete first character '#'
      my $style = $kml->{Document}->{Style}->{$id};
      if ($placemark->{Point}) {
        $geojson->{features}[$n++] = point_feature($placemark, $style, $id);
      } elsif ($placemark->{LineString}) {
        $geojson->{features}[$n++] = linestring_feature($placemark, $style);
      }
    }
  }
  return $geojson;
}

my $parser = XML::Simple->new(
  forcearray => ['Style','Folder','Placemark'],
  keyattr => ['id']
);
my $serializer = JSON->new();

foreach my $file (@ARGV) {
  my $kml = $parser->XMLin($file) or die "Can't parse $file: $!";
  my $geojson = kml2geojson($kml);
  (my $outfile = $file) =~ s/\.kml$/.geojson/;
  print STDERR "$file -> $outfile\n";
  open(my $out, '>', $outfile) or die "Can't open $outfile: $!";
  print $out $serializer->utf8(0)->encode($geojson), "\n";
  close($out);
}

__END__
