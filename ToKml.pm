package ToKML;
use strict;
use warnings;
use utf8;

my %using;

sub get_point_placemark {
  my $pt = shift; # wpt or rtept
  my $icon = Extensions::icon($pt);
  my $id = 'N' . $icon;
  $using{$id} = IconLut::IconUrl($icon);
  my $p = {};
  $p->{name}[0] = $pt->{name}[0];
  $p->{styleUrl}[0] = '#' . $id;
  $p->{Point}[0]->{coordinates}[0] = sprintf('%.6f,%.6f', $pt->{lon}, $pt->{lat});
  my $html = '';
  if ($pt->{cmt}[0]) {
    foreach (split /,/, $pt->{cmt}[0]) {
      my ($key, $value) = split /=/;
      if ($key !~ /^[[:blank:]]*$/) { # using POSIX character class
        $html .= '<tr><td>' . $key . '</td><td>' . $value . '</td></tr>';
      }
    }
    if ($html) {
      $p->{description}[0] = '<table>' . $html . '</table>'; # will be HTML-escaped on output
    }
  }
  return $p;
}

my $id = 0;

sub get_linestring_style {
  my $t = shift; # trk or rte
  my $a = sprintf('%02x', $main::param{opacity} * 255);
  my $s = {};
  $s->{id} = sprintf('id%05d', ++$id);
  $s->{LineStyle}[0]->{color}[0] = $a . Extensions::line_color($t);
  $s->{LineStyle}[0]->{width}[0] = $main::param{line_size}  || Extensions::line_size($t);
  return $s;
}

sub get_linestring_placemark {
  my ($segment, $tag, $style, $name) = @_; # trkseg or rte
  my $p = {};
  $p->{name}[0] = $name;
  $p->{styleUrl}[0] = '#' . $style->{id};
  $p->{LineString}[0]->{coordinates}[0] = join("\n", map { sprintf('%.6f,%.6f', $_->{lon}, $_->{lat}) } @{$segment->{$tag}});
  return $p;
}

sub convert {
  my $gpx = shift;
  my $kml = {};
  $kml->{kml}[0]->{xmlns} = 'http://www.opengis.net/kml/2.2';
  $kml->{kml}[0]->{Document}[0]->{name}[0] = $main::param{title};
  my $placemark = $kml->{kml}[0]->{Document}[0]->{Placemark} = [];
  my $style = $kml->{kml}[0]->{Document}[0]->{Style} = [];

  # Waypoint
  foreach my $wpt (@{$gpx->{gpx}[0]->{wpt}}) {
    push @{$placemark}, get_point_placemark($wpt);
  }

  # Route
  foreach my $rte (@{$gpx->{gpx}[0]->{rte}}) {
    foreach my $rtept (@{$rte->{rtept}}) {
      next if (Extensions::icon($rtept) eq '903001'); # skip blank icon
      push @{$placemark}, get_point_placemark($rtept);
    }
    my $s = get_linestring_style($rte);
    push @{$style}, $s;
    push @{$placemark}, get_linestring_placemark($rte, 'rtept', $s, $rte->{name}[0]);
  }

  foreach my $id (keys %using) {
    my $s = {};
    $s->{id} = $id;
    $s->{IconStyle}[0]->{scale}[0] = 1;
    $s->{IconStyle}[0]->{Icon}[0]->{href}[0] = $using{$id};
    $s->{IconStyle}[0]->{hotSpot} = { x => 0.5, y => 0.5, xunits => 'fraction', yunits => 'fraction' }; # ext. of KMP
    push @{$style}, $s;
  }

  # Track
  foreach my $trk (@{$gpx->{gpx}[0]->{trk}}) {
    my $s = get_linestring_style($trk);
    push @{$style}, $s;
    foreach my $trkseg (@{$trk->{trkseg}}) {
      push @{$placemark}, get_linestring_placemark($trkseg, 'trkpt', $s, $trk->{name}[0]);
    }
  }
  return $kml;
}

1;
