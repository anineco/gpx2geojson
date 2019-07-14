@echo off
setlocal
rem cpan Tk
rem cpan PAR::Packer
pp --gui -M XML::SAX::Expat -o gpx2geojson.exe gpx2geojson.pl
