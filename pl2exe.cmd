@echo off
setlocal
rem cpan Tk
rem cpan PAR::Packer
pp --gui -M XML::SAX::ExpatXS -l libexpat-1_.dll -o gpx2geojson.exe gpx2geojson.pl
