# HydroTwin Pro — Wayanad / Meppadi GIS Data Pack

Generated: 2026-09-09

## What is included

- evacuation_nodes.csv
- evacuation_edges.csv
- hazard_events.csv
- hazard_zones.geojson
- infrastructure_status.csv
- data_sources.csv
- live_data_sources.csv
- download_real_gis.ps1
- QGIS_PREPROCESSING.md

## Important accuracy note

This pack does NOT invent a landslide/flood polygon. `hazard_zones.geojson`
contains reference POINTS only, because a fabricated polygon would give a
false impression of positional accuracy.

For the actual hazard geometry, download the official KSDMA/GSI Wayanad
susceptibility dataset and use the NRSC/ISRO Chooralmala impact product.

## Real road data

The recommended road source is the current Kerala OpenStreetMap PBF:

https://download.openstreetmap.fr/extracts/asia/india/kerala-latest.osm.pbf

It is about 170 MB according to the source index and was updated 2026-09-07.

## Official hazard sources

KSDMA lists:
- GSI 2022 district landslide susceptibility shapefiles
- historic flood hazard probability rasters/maps
- district flood/landslide resources

KSDMA hazard-map index:
https://sdma.kerala.gov.in/hazard-maps/

The GSI Wayanad package:
https://sdma.kerala.gov.in/wp-content/uploads/2025/08/Wayanad.zip

NRSC/ISRO Chooralmala observed impact charter:
https://bhuvan-app1.nrsc.gov.in/disaster/usrtasks/landslide/doc/Charter_1029_VAP_3_31july2024.pdf

## Routing warning

`evacuation_edges.csv` is deliberately marked CANDIDATE_NOT_ROAD_ROUTING.
Its travel times are only a placeholder based on straight-line distance and
an assumed 30 km/h speed. Replace these with edges generated from the actual
OSM road network before claiming that the map provides real evacuation
routing.

## Current bridge status warning

Do not permanently set the Chooralmala bridge to "destroyed".
Current public records describe the Army Bailey bridge as providing controlled
access in 2025, while a replacement bridge was approved/awarded in 2026.
Your application should ingest current road/bridge status as a dynamic
attribute and suspend routes when DDMA/PWD information or real-time sensors
indicate they are unsafe.

## Sources used for the coordinate CSV

The point coordinates were taken from traceable public sources such as
OpenStreetMap-derived Mapcarta pages and Wikidata/Kerala references. The
source reference is stored in every row so you can audit each point.
