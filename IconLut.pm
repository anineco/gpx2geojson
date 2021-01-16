package IconLut;
use strict;
use warnings;
use utf8;
sub IconUrl {
  my $icon = shift; # kashmir3d:icon
  return 'https://map.jpn.org/icon/' . $icon . '.png';
}
sub IconSize {
  my $icon = shift; # kashmir3d:icon
  return [24, 24];
}
sub IconAnchor {
  my $icon = shift; # kashmir3d:icon
  return [12, 12];
}
1;
