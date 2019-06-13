package iconlut;
use strict;
use warnings;
sub iconUrl {
  my $icon = $_[0]; # kashmir3d:icon
  return "https://map.jpn.org/icon/$icon.png";
}
sub iconSize {
  my $icon = $_[0]; # kashmir3d:icon
  return [24, 24];
}
sub iconAnchor {
  my $icon = $_[0]; # kashmir3d:icon
  return [12, 12];
}
1;
