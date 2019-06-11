@echo off
setlocal
pp --gui -M XML::SAX::Expat -X iconlut -o gpx2geojson.exe gpx2geojson.pl
