#!/bin/sh

for ymd in 180701 200411; do
  rm -f docs/$ymd/{no-decim,decimate,decimate-bing}.*
  ./gpx2geojson.pl          -f gpx test/$ymd/*.gpx > docs/$ymd/no-decim.gpx
  ./gpx2geojson.pl -x 0.005 -f gpx test/$ymd/*.gpx > docs/$ymd/decimate.gpx
  ./gpx2geojson.pl -x 0.005 -f kml test/$ymd/*.gpx > docs/$ymd/decimate.kml
  ./gpx2geojson.pl -x 0.005        test/$ymd/*.gpx > docs/$ymd/decimate.geojson
  xsltproc bingkml.xsl docs/$ymd/decimate.kml > docs/$ymd/decimate-bing.kml
done
