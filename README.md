# 🌊 HydroTwin Pro – GIS-Integrated Flood Risk Monitoring & Evacuation Decision Support System

<p align="center">
  <b>🏆 1st Place – MATRIX 2026 Hackathon</b><br>
  Government Engineering College, Thrissur | In association with MathWorks
</p>

<p align="center">
  <i>Shortlisted among the Top 12 teams from 300+ registrations.</i>
</p>

---

## 📌 Project Overview

**HydroTwin Pro** is a student-scale, reduced-order digital twin designed for flood-risk monitoring and evacuation decision support in the **Mundakkai–Chooralmala–Meppadi region of Wayanad, Kerala**.

The system integrates sensor-based water-level estimation, sensor-health assessment, real-world geospatial datasets, landslide susceptibility information and hazard-aware evacuation network analysis.

Rather than simply monitoring water levels, HydroTwin Pro explores how uncertain sensor measurements and geographical information can be transformed into meaningful, risk-aware decision support for disaster preparedness.

## 🏆 Achievement – MATRIX 2026

<badge>🥇 1st Place</badge>

- Secured **1st Place at MATRIX 2026**, conducted at Government Engineering College, Thrissur, in association with MathWorks as part of IDEATOR GECT.
- Shortlisted among the **Top 12 teams from over 300 registrations**.
- Presented HydroTwin Pro as an engineering-based approach to flood-risk monitoring and evacuation decision support.
- Demonstrated MATLAB-based simulation and Simulink validation.

---

## ⚙️ Key Features

### 1. Water-Level Estimation Using Kalman Filtering
- Implements a two-state Kalman filter.
- Estimates water level and water-level rate.
- Processes sensor measurements while accounting for uncertainty.

### 2. Sensor Health Assessment
- Evaluates sensor health and reliability.
- Supports fault-tolerant estimation.
- Explores system behaviour under unreliable sensor conditions.

### 3. Real-World GIS Integration
- Integrates OpenStreetMap road-network data.
- Uses Geological Survey of India (GSI) landslide susceptibility information.
- Incorporates geospatial reference points and hazard-event information.
- Supports spatial data processing and visualization through GIS tools.

### 4. Hazard-Weighted Evacuation Analysis
- Represents evacuation locations using network nodes and edges.
- Explores hazard-aware route assessment.
- Supports the integration of real road-network information.
- Provides a foundation for safer evacuation decision support.

### 5. Digital Twin Modelling
- Develops a reduced-order representation of the selected geographical region.
- Combines sensor estimation, geographical information and infrastructure status.
- Uses MATLAB simulation and Simulink validation.

---

## 🛠️ Technology Stack

| Category | Technologies |
|---|---|
| Programming & Modelling | MATLAB |
| Simulation & Validation | Simulink |
| Geospatial Analysis | QGIS, GIS |
| Road Network Data | OpenStreetMap |
| Landslide Data | Geological Survey of India (GSI) |
| Hazard Information | KSDMA, NRSC/ISRO |
| Estimation Algorithm | Two-State Kalman Filter |
| Data Formats | CSV, GeoJSON |
| Automation | PowerShell |

---

## 📂 Project Structure

```text
HydroTwin_Project/
│
├── KSDMA_GSI/                    # GSI/KSDMA GIS resources
├── resources/                    # Supporting resources
├── slprj/                        # MATLAB/Simulink generated files
│
├── main_hydrotwin.m              # Main HydroTwin workflow
├── buildfile.m                   # Build/support script
├── train_anomaly.m               # Anomaly detection model
├── sensor_health_model.*         # Sensor health assessment
├── hydrotwin_testbench.*         # Testbench and validation resources
│
├── data_sources.csv              # Dataset source references
├── live_data_sources.csv         # Live data source information
├── hazard_events.csv             # Hazard event information
├── hazard_zones.geojson          # Geospatial hazard reference points
├── evacuation_nodes.csv          # Evacuation network nodes
├── evacuation_edges.csv          # Candidate evacuation connections
├── infrastructure_status.csv     # Infrastructure status information
│
├── download_real_gis.ps1         # GIS data acquisition script
├── QGIS_PREPROCESSING.md         # GIS preprocessing documentation
├── HydroTwin_Project.*           # QGIS/project files
│
└── README.md
```

---

## 🗺️ GIS Data & Sources

HydroTwin Pro uses geographical datasets and publicly available information to represent the study region and support hazard analysis.

### 1. Road Network Data

**Source: OpenStreetMap (OSM)**

Recommended Kerala road-network dataset:

[Download Kerala OpenStreetMap PBF](https://download.openstreetmap.fr/extracts/asia/india/kerala-latest.osm.pbf)

This dataset provides road-network information that can be processed for geographical and evacuation-network analysis.

### 2. Landslide Susceptibility Data

**Source: Geological Survey of India (GSI) / Kerala State Disaster Management Authority (KSDMA)**

- [KSDMA Hazard Maps](https://sdma.kerala.gov.in/hazard-maps/)
- [GSI Wayanad Landslide Susceptibility Dataset](https://sdma.kerala.gov.in/wp-content/uploads/2025/08/Wayanad.zip)

The GSI dataset provides landslide susceptibility information for geographical risk assessment.

### 3. Historical Landslide Impact Information

**Source: NRSC / ISRO**

[Chooralmala Landslide Observed Impact Charter – 31 July 2024](https://bhuvan-app1.nrsc.gov.in/disaster/usrtasks/landslide/doc/Charter_1029_VAP_3_31july2024.pdf)

This resource provides observed impact information relating to the Chooralmala landslide.

### 4. Dataset Documentation

The repository includes:

- `data_sources.csv` – records dataset sources and references.
- `live_data_sources.csv` – documents live data source information.
- `QGIS_PREPROCESSING.md` – explains GIS preprocessing.
- `download_real_gis.ps1` – supports GIS data acquisition.

---

## ⚠️ Data Accuracy & Implementation Considerations

HydroTwin Pro emphasizes the importance of distinguishing between reference information, candidate data and verified geographical information.

### Hazard Geometry

The current `hazard_zones.geojson` contains reference POINTS rather than fabricated flood or landslide polygons.

This avoids presenting estimated or invented geographical boundaries as accurately mapped hazard zones.

For actual hazard geometry, the project identifies official GSI/KSDMA susceptibility datasets and NRSC/ISRO observed-impact products as relevant sources.

### Evacuation Network Accuracy

The current `evacuation_edges.csv` is marked:

`CANDIDATE_NOT_ROAD_ROUTING`

Its travel-time values are placeholders calculated using straight-line distances and an assumed speed of 30 km/h.

They must not be interpreted as verified road travel times or actual evacuation routes.

For real road-network routing, these candidate edges need to be replaced with network edges generated from actual OpenStreetMap road data, with appropriate road connectivity and hazard validation.

### Dynamic Bridge & Infrastructure Status

Infrastructure conditions can change over time.

For example, public records referenced during project development described controlled access through the Army Bailey bridge in 2025 and approval/award of a replacement bridge in 2026.

Therefore, bridge and road conditions should be treated as dynamic attributes rather than permanent fixed statuses.

The application should incorporate updated DDMA/PWD information or verified sensor inputs and suspend routes when infrastructure is reported unsafe.

---

## 🚀 Getting Started

### Prerequisites

- MATLAB
- Simulink
- QGIS
- PowerShell
- Required GIS datasets and supporting project resources

### 1. Clone the Repository

```bash
git clone https://github.com/YOUR_USERNAME/HydroTwin_Project.git
```

```bash
cd HydroTwin_Project
```

### 2. Open the Project in MATLAB

1. Launch MATLAB.
2. Open the HydroTwin project directory.
3. Set the project folder as the MATLAB Current Folder.
4. Verify that the required datasets and supporting files are available.

### 3. Execute the Main Workflow

```matlab
run('main_hydrotwin.m')
```

Supporting MATLAB scripts can be executed separately depending on their input requirements and the project workflow.

### 4. GIS Preprocessing

Refer to `QGIS_PREPROCESSING.md` for information about preparing the geographical datasets.

The `download_real_gis.ps1` script provides supporting functionality for obtaining GIS resources.

### 5. Open the QGIS Project

Open the HydroTwin QGIS project in QGIS.

If any layers are unavailable, update their data-source paths and verify that the required spatial datasets are present.

> Note: Exact MATLAB versions, toolbox requirements, input paths and execution dependencies should be verified against the actual project scripts.

---

## 🎯 Project Objectives

- Develop a reduced-order digital twin for localized flood-risk monitoring.
- Estimate water-level dynamics using Kalman filtering.
- Assess sensor reliability and support fault-tolerant estimation.
- Integrate real-world road networks and landslide susceptibility information.
- Explore hazard-weighted evacuation decision support.
- Improve the use of geographical and sensor information in disaster-preparedness workflows.

---

## 🔮 Future Scope

- Integration of live water-level and environmental sensor feeds.
- Real-time infrastructure and bridge-status updates.
- Improved sensor fault detection and estimation.
- Road-network-based evacuation route optimization.
- Integration of updated official hazard datasets.
- Extended digital twin validation using historical and real-world observations.

---

## 👥 Team & Contributions

**Project:** HydroTwin Pro

**Competition:** MATRIX 2026

**Team Members:**
- Jaisy Sunil
- Hrisheekesh Narayan P E
- Aardra S.V
- Mohammed Ameen

**Team Volunteer:** Gourikrishna TS

---

## 🙌 Acknowledgements

- Government Engineering College, Thrissur.
- MathWorks.
- IDEATOR GECT.
- Kerala State Disaster Management Authority (KSDMA).
- Geological Survey of India (GSI).
- National Remote Sensing Centre (NRSC), ISRO.
- OpenStreetMap contributors.

---

## ⚠️ Disclaimer

HydroTwin Pro is a student-scale engineering prototype developed for academic, research and demonstration purposes.

Its estimations, geographical representations and evacuation-network outputs should not be considered official disaster forecasts or verified emergency evacuation instructions.

Operational decisions must rely on current information and guidance from authorized disaster-management and government agencies.

---

<p align="center">
  <b>🌊 HydroTwin Pro</b><br>
  <i>Transforming Sensor Data and Geospatial Intelligence into Risk-Aware Decision Support.</i>
</p>

<p align="center">
  🏆 MATRIX 2026 – 1st Place
</p>
