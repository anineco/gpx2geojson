@echo off
rem strawberry-perl-5.30.3.1-64bit
rem cpan Tk
rem cpan PAR::Packer
rem https://github.com/lucasg/Dependencies
pp --gui -M XML::LibXML::SAX -l libxml2-2__.dll -l libiconv-2__.dll -l liblzma-5__.dll -l zlib1__.dll -o gpx2geojson.exe gpx2geojson.pl
