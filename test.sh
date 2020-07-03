#!/bin/sh
rm -f docs/{180701,200411}/{no-decim,decimate}.*

./gpx2geojson.pl          -f gpx test/180701/{trk,wpt,rte}.gpx > docs/180701/no-decim.gpx
./gpx2geojson.pl -x 0.005 -f gpx test/180701/{trk,wpt,rte}.gpx > docs/180701/decimate.gpx
./gpx2geojson.pl -x 0.005 -f kml test/180701/{trk,wpt,rte}.gpx | sed -e 's/^ *//' > docs/180701/decimate.kml
./gpx2geojson.pl -x 0.005        test/180701/{trk,wpt,rte}.gpx > docs/180701/decimate.geojson
#
./gpx2geojson.pl          -f gpx test/200411/{trk,wpt}.gpx     > docs/200411/no-decim.gpx
./gpx2geojson.pl -x 0.005 -f gpx test/200411/{trk,wpt}.gpx     > docs/200411/decimate.gpx
./gpx2geojson.pl -x 0.005 -f kml test/200411/{trk,wpt}.gpx     | sed -e 's/^ *//' > docs/200411/decimate.kml
./gpx2geojson.pl -x 0.005        test/200411/{trk,wpt}.gpx     > docs/200411/decimate.geojson
