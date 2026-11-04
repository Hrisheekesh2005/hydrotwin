# HydroTwin Pro - Real GIS downloader for Windows PowerShell
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "Downloading Kerala OSM extract..."
Invoke-WebRequest `
  -Uri "https://download.openstreetmap.fr/extracts/asia/india/kerala-latest.osm.pbf" `
  -OutFile (Join-Path $here "kerala-latest.osm.pbf")

Write-Host "Downloading KSDMA/GSI Wayanad landslide susceptibility shapefile package..."
Invoke-WebRequest `
  -Uri "https://sdma.kerala.gov.in/wp-content/uploads/2025/08/Wayanad.zip" `
  -OutFile (Join-Path $here "Wayanad_KSDMA_GSI_2022.zip")

Write-Host "Downloads complete."
Write-Host "Next: unzip Wayanad_KSDMA_GSI_2022.zip and import the Wayanad shapefile into QGIS."
