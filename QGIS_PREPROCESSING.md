# HydroTwin Pro — QGIS preprocessing workflow

1. Load kerala-latest.osm.pbf into QGIS.
2. Clip the road layer to the Meppadi / Mundakkai study area:
   approximately 11.47–11.57 N, 76.12–76.20 E.
3. Keep drivable road classes and preserve:
   highway, name, surface, bridge, maxspeed, access, oneway.
4. Import the Wayanad_KSDMA_GSI_2022 shapefile package.
5. Reproject layers only for analysis if needed; retain WGS84 EPSG:4326 for
   MATLAB geographic plotting.
6. Obtain/import the NRSC Chooralmala impact geometry from the official product.
   Do NOT recreate a hazard polygon by drawing a rectangle around a point.
7. Validate bridges and road closures against current DDMA/PWD orders before
   labeling any edge "open", "closed", or "safe".
8. Generate:
   meppadi_roads.geojson
   hazard_zones.geojson
   evacuation_nodes.csv
   evacuation_edges.csv
9. For road routing, build edges from the actual OSM road graph—not straight
   lines between localities. Compute travel time from road length and road
   class/speed, then apply dynamic hazard penalties.
