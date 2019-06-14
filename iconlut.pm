package iconlut;
use strict;
use warnings;
sub iconUrl {
  my $icon = shift; # kashmir3d:icon
  return "https://map.jpn.org/icon/$icon.png";
}
sub iconSize {
  my $icon = shift; # kashmir3d:icon
  return [24, 24];
}
sub iconAnchor {
  my $icon = shift; # kashmir3d:icon
  return [12, 12];
}
1;
