@echo off
rem strawberry-perl-5.30.3.1-64bit
rem cpan Tk
rem cpan PAR::Packer
pp --gui -M XML::LibXML::SAX -M XML::SAX::Expat -M XML::Parser::Expat -l libexpat-1__.dll -o gpx2geojson.exe gpx2geojson.pl
