% =========================================================================
% HydroTwin Pro
% Physics-Informed Flood Routing + Sensor Health + GSI GIS Evacuation
% Dashboard
%
% LOCATION:
%   Mundakkai - Chooralmala - Meppadi sector, Wayanad, Kerala
%
% REAL GIS USED:
%   1) OSM roads extracted in QGIS:
%      C:\HydroTwin_Project\Wayanad_Roads_Raw.gpkg
%
%   2) GSI landslide susceptibility shapefile:
%      C:\HydroTwin_Project\KSDMA_GSI\Wayanad\Wayanad_GSI_LS.shp
%
%   3) Existing evacuation_nodes.csv / evacuation_edges.csv
%
% IMPORTANT:
%   GSI is a STATIC landslide-susceptibility layer:
%       High / Moderate / Low
%
%   It is NOT the observed 2024 landslide footprint.
%
%   The dynamic component is the simulated water-level state, estimated
%   using a physics-informed 2-state Kalman filter. The GSI class and
%   current water-level state are combined to produce hazard-weighted
%   evacuation routing.
% =========================================================================

clc;
clear;
close all;

fprintf('\n============================================================\n');
fprintf(' HydroTwin Pro - Wayanad Digital Twin\n');
fprintf('============================================================\n\n');

%% ========================================================================
% 1. GLOBAL SETTINGS
% =========================================================================

total_steps = 300;              % simulation duration in minutes
dt = 1;                         % sampling interval in minutes

% Water-level thresholds
NORMAL_LEVEL       = 2.5;
WARNING_LEVEL      = 3.0;
CRITICAL_LEVEL     = 4.0;
ROUTING_RISK_LEVEL = 3.0;

% -------------------------------------------------------------------------
% DEMO SCENARIO CONTROL
% -------------------------------------------------------------------------
% "random50" = 50% chance of spawning in a GSI High zone and 50% in Low.
% "high"    = force a dangerous starting location for the judge demo.
% "low"     = force a low-susceptibility starting location.
SPAWN_MODE = "random50";

% -------------------------------------------------------------------------
% SECOND PERSON / ROUTING TEST
% -------------------------------------------------------------------------
% Keep this ON for the judge/demo view. The second person is deliberately
% placed on a real road inside Moderate GSI susceptibility (High is used
% as a fallback if no Moderate road point is available). This lets you
% verify the evacuation branch while the primary person can remain Low-GSI.
SHOW_TEST_PERSON = true;
TEST_PERSON_TARGET_CLASS = "Moderate";

% Map limits
MAP_LAT_LIMIT = [11.47 11.57];
MAP_LON_LIMIT = [76.12 76.20];

% -------------------------------------------------------------------------
% REAL GIS FILES
% -------------------------------------------------------------------------

ROAD_FILE = "C:\HydroTwin_Project\Wayanad_Roads_Raw.gpkg";

GSI_FILE = ...
    "C:\HydroTwin_Project\KSDMA_GSI\Wayanad\Wayanad_GSI_LS.shp";

% QGIS topology-cleaned routing network
ROUTING_FILE = "C:\HydroTwin_Project\Wayanad_RoadNetwork_FINAL.gpkg";
ROUTING_LAYER = "routing_edges";

% Existing routing files
NODE_FILE = "evacuation_nodes.csv";
EDGE_FILE = "evacuation_edges.csv";

% Optional files
MODEL_FILE = "sensor_health_model.mat";
SIMULINK_MODEL = "hydro_physics";

%% ========================================================================
% 2. SIMULATED WATER-LEVEL SENSOR
% =========================================================================

rng(7);

time_vector = (0:total_steps-1) * dt;

% Normal level
mock_data = ones(1,total_steps) * 1.0;

% Rising flood wave
rise_start = 80;
rise_end   = 140;

mock_data(rise_start:rise_end) = ...
    linspace(1.0,4.6,rise_end-rise_start+1);

% High-water period
mock_data(rise_end+1:end) = 4.6;

% Small measurement noise
mock_data = mock_data + 0.04*randn(1,total_steps);

% Simulated heavy-rainfall intensity (mm/hr) driving the scenario.
rainfall = ones(1,total_steps)*8;
rainfall(rise_start:rise_end) = ...
    linspace(8,120,rise_end-rise_start+1);
rainfall(rise_end+1:end) = 120;
rainfall = rainfall + 2*randn(1,total_steps);
rainfall = max(rainfall,0);

% Simulated sensor failure
sensor_failure_start = 200;
sensor_failure_end   = 230;

mock_data(sensor_failure_start:sensor_failure_end) = ...
    0.03 + 0.01*randn(1,...
    sensor_failure_end-sensor_failure_start+1);

%% ========================================================================
% 3. OPTIONAL SENSOR-HEALTH MODEL
% =========================================================================

use_ml_model = false;
anomaly_model = [];

if isfile(MODEL_FILE)

    try

        S = load(MODEL_FILE);

        if isfield(S,"anomaly_model")

            anomaly_model = S.anomaly_model;
            use_ml_model = true;

            fprintf('[OK] Sensor health model loaded.\n');

        else

            fprintf('[WARNING] anomaly_model missing from MAT file.\n');

        end

    catch ME

        fprintf('[WARNING] Sensor model could not be loaded:\n%s\n',...
            ME.message);

    end

else

    fprintf('[INFO] ML sensor model not found. Statistical detection used.\n');

end

%% ========================================================================
% 4. SENSOR HEALTH HISTORY
% =========================================================================

health_score_history = nan(1,total_steps);
broken_history       = false(1,total_steps);

%% ========================================================================
% 5. PHYSICS-INFORMED 2-STATE KALMAN MODEL
% =========================================================================
%
% State:
%   x = [water level
%        level rate]
%
% Model:
%   level(k+1) = level(k) + rate(k)*dt
%   rate(k+1)  = 0.96*rate(k)
%
% This is a reduced-order digital-twin model suitable for a student
% prototype. It is not a full Saint-Venant hydraulic solver.
% =========================================================================

F = [1 dt;
     0 0.96];

H = [1 0];

Q = [0.015 0;
     0     0.010];

R = 0.20^2;

x_est = [1.0;
         0.0];

P = [1 0;
     0 1];

history_ekf = nan(1,total_steps);
history_rate = nan(1,total_steps);

%% ========================================================================
% 6. LOAD REAL GIS DATA
% =========================================================================

fprintf('\nLoading real GIS data...\n');

roads_loaded = false;
gsi_loaded   = false;

roads = [];
gsi   = [];

% -------------------------------------------------------------------------
% 6A. OSM ROAD DATA
% -------------------------------------------------------------------------

if isfile(ROAD_FILE)

    try

        roads = readgeotable(ROAD_FILE);

        roads_loaded = true;

        fprintf('[OK] OSM road GIS loaded.\n');
        fprintf('     Road features: %d\n',height(roads));

    catch ME

        fprintf('[ERROR] Could not load road GIS:\n%s\n',ME.message);

    end

else

    fprintf('[ERROR] Road file not found:\n%s\n',ROAD_FILE);

end

% -------------------------------------------------------------------------
% 6B. GSI LANDSLIDE SUSCEPTIBILITY
% -------------------------------------------------------------------------

if isfile(GSI_FILE)

    try

        % Let MATLAB read the CRS from the .prj file. The GSI shapefile
        % is projected, so forcing CoordinateSystemType="geographic"
        % incorrectly rejects the file.
        gsi = readgeotable(GSI_FILE);

        gsi_loaded = true;

        fprintf('[OK] GSI landslide susceptibility loaded.\n');
        fprintf('     GSI polygons: %d\n',height(gsi));

    catch ME

        fprintf('[ERROR] Could not load GSI shapefile:\n%s\n',ME.message);

    end

else

    fprintf('[ERROR] GSI file not found:\n%s\n',GSI_FILE);

end

%% ========================================================================
% 7. IDENTIFY GSI SUSCEPTIBILITY FIELD
% =========================================================================

if gsi_loaded
    n_gsi = height(gsi);
else
    n_gsi = 0;
end

gsi_class = strings(n_gsi,1);
gsi_field = "";

if gsi_loaded

    variable_names = string(gsi.Properties.VariableNames);

    fprintf('\nGSI attributes:\n');
    disp(variable_names');

    % Search all non-geometry columns for High / Moderate / Low.
    for v = 1:width(gsi)

        try

            values = string(gsi{:,v});

            test_values = lower(strtrim(values));

            class_hits = ...
                contains(test_values,"high") | ...
                contains(test_values,"moderate") | ...
                contains(test_values,"low");

            if any(class_hits)

                gsi_class = values;
                gsi_field = variable_names(v);

                fprintf('[OK] GSI susceptibility field: %s\n',gsi_field);

                break

            end

        catch

            % Ignore geometry / unsupported variables.

        end

    end

    if gsi_field == ""

        fprintf('[WARNING] Could not automatically identify GSI class field.\n');
        fprintf('[WARNING] GSI polygons will still be displayed, but node\n');
        fprintf('          hazard classification will default to Low.\n');

        gsi_class(:) = "Low";

    end

    fprintf('\nGSI susceptibility summary:\n');
    fprintf('  High     : %d polygons\n',...
        sum(contains(lower(gsi_class),"high")));

    fprintf('  Moderate : %d polygons\n',...
        sum(contains(lower(gsi_class),"moderate")));

    fprintf('  Low      : %d polygons\n',...
        sum(contains(lower(gsi_class),"low")));

end

%% ========================================================================
% 8. LOAD EVACUATION NETWORK
% =========================================================================

real_network_loaded = false;

if isfile(NODE_FILE) && isfile(EDGE_FILE)

    try

        node_table = readtable(NODE_FILE);
        edge_table = readtable(EDGE_FILE);

        required_node_fields = ...
            ["ID","Name","Latitude","Longitude","Type"];

        required_edge_fields = ...
            ["From","To","TravelTimeMin"];

        if all(ismember(required_node_fields,...
                string(node_table.Properties.VariableNames))) && ...
           all(ismember(required_edge_fields,...
                string(edge_table.Properties.VariableNames)))

            real_network_loaded = true;

            fprintf('[OK] Existing evacuation routing network loaded.\n');
            fprintf('     Nodes: %d\n',height(node_table));
            fprintf('     Edges: %d\n',height(edge_table));

        else

            fprintf('[WARNING] Routing CSV headers are incorrect.\n');

        end

    catch ME

        fprintf('[WARNING] Could not load routing network:\n%s\n',...
            ME.message);

    end

else

    fprintf('[INFO] Routing CSV files not found. Demo network used.\n');

end

%% ========================================================================
% 9. FALLBACK NETWORK
% =========================================================================

if ~real_network_loaded

    node_table = table( ...
        [1;2;3;4], ...
        ["Mundakkai";...
         "Chooralmala";...
         "Estate Ridge";...
         "Meppadi CHC"], ...
        [11.4950;11.5035;11.5200;11.5513], ...
        [76.1830;76.1738;76.1550;76.1368], ...
        ["Origin";"Danger";"Alternative";"Safe"], ...
        'VariableNames',...
        {'ID','Name','Latitude','Longitude','Type'});

    edge_table = table( ...
        [1;1;2;3], ...
        [2;3;4;4], ...
        [5;15;12;12], ...
        'VariableNames',...
        {'From','To','TravelTimeMin'});

end

%% ========================================================================
% 10. LOAD QGIS TOPOLOGICAL ROAD NETWORK FOR NAVIGATION ROUTING
% =========================================================================
% The visible map still uses Wayanad_Roads_Raw.gpkg.
% This separate QGIS-generated network is used only to calculate the
% optimum road path. It was reprojected to EPSG:32643, snapped, repaired,
% and split at intersections in QGIS.

routing_loaded = false;
routing = [];
routing_graph = [];
routing_proj = [];
routing_xy = zeros(0,2);
routing_edge_geom = zeros(0,1);

if isfile(ROUTING_FILE)
    try
        routing = readgeotable(ROUTING_FILE,...
            'Layer',ROUTING_LAYER,...
            'CoordinateSystemType','planar');

        routing_proj = projcrs(32643);

        [routing_graph,routing_xy,routing_edge_geom] = ...
            buildQGISRoutingGraph(routing,0.05);

        routing_loaded = numnodes(routing_graph) >= 2 && ...
                         numedges(routing_graph) >= 1;

        fprintf('[OK] Topology-clean OSM routing network loaded.\n');
        fprintf('     Routing layer : %s\n',ROUTING_LAYER);
        fprintf('     Routing segments: %d\n',height(routing));
        fprintf('[OK] OSM routing graph built: %d vertices, %d road links.\n',...
            numnodes(routing_graph),numedges(routing_graph));

    catch ME
        fprintf('[WARNING] Could not load/build QGIS routing network:\n%s\n',ME.message);
        routing_loaded = false;
    end
else
    fprintf('[WARNING] QGIS routing file not found: %s\n',ROUTING_FILE);
end

%% ========================================================================
% 10A. CLASSIFY QGIS ROUTING LINKS USING GSI
% =========================================================================
% The QGIS routing graph is the ONLY graph used for evacuation routing.
% Each road link receives the highest landslide-susceptibility class touched
% by sampled points along its real road geometry.

routing_edge_gsi_class = strings(0,1);
routing_edge_gsi_factor = zeros(0,1);

if routing_loaded

    routing_edge_gsi_class = repmat("Unknown",numedges(routing_graph),1);
    routing_edge_gsi_factor = ones(numedges(routing_graph),1);

    if gsi_loaded && gsi_field ~= ""
        fprintf('\n============================================================\n');
        fprintf(' QGIS ROAD-LINK GSI CLASSIFICATION\n');
        fprintf('============================================================\n');

        for e = 1:numedges(routing_graph)
            rid = routing_edge_geom(e);
            if rid >= 1 && rid <= height(routing)
                routing_edge_gsi_class(e) = ...
                    classifyRoutingEdgeGSI(routing.Shape(rid),gsi,gsi_class);
            end
        end
    end

    routing_edge_gsi_factor(strcmpi(routing_edge_gsi_class,"Low")) = 1.0;
    routing_edge_gsi_factor(strcmpi(routing_edge_gsi_class,"Moderate")) = 2.5;
    routing_edge_gsi_factor(strcmpi(routing_edge_gsi_class,"High")) = 6.0;
    routing_edge_gsi_factor(strcmpi(routing_edge_gsi_class,"Unknown")) = 1.0;

    fprintf('[OK] QGIS road-link susceptibility assigned.\n');
    fprintf('     High links    : %d\n',sum(strcmpi(routing_edge_gsi_class,"High")));
    fprintf('     Moderate links: %d\n',sum(strcmpi(routing_edge_gsi_class,"Moderate")));
    fprintf('     Low links     : %d\n',sum(strcmpi(routing_edge_gsi_class,"Low")));
    fprintf('     Unknown links : %d\n',sum(strcmpi(routing_edge_gsi_class,"Unknown")));
end

%% ========================================================================
% 11. REFERENCE EVACUATION DATA
% =========================================================================
% evacuation_nodes.csv / evacuation_edges.csv are retained as reference
% metadata only. The actual evacuation route is always calculated on the
% QGIS topology-cleaned OSM road graph above.

num_nodes = height(node_table);

%% ========================================================================
% 11. CLASSIFY EVACUATION NODES USING GSI
% =========================================================================

node_hazard_class = repmat("Unknown",num_nodes,1);

if gsi_loaded && gsi_field ~= ""

    for n = 1:num_nodes

        node_lat = node_table.Latitude(n);
        node_lon = node_table.Longitude(n);

        node_hazard_class(n) = ...
            classifyGSIpoint( ...
            node_lat,...
            node_lon,...
            gsi,...
            gsi_class);

    end

end

fprintf('\n============================================================\n');
fprintf(' EVACUATION NODE SUSCEPTIBILITY\n');
fprintf('============================================================\n');

for n = 1:num_nodes

    fprintf('  %-25s : %s\n',...
        string(node_table.Name(n)),...
        node_hazard_class(n));

end

%% ========================================================================
% 12. INITIAL MAP PLACEHOLDERS
% =========================================================================
% These are temporary values used only while the UI is being constructed.
% The actual random spawn and safest destination are selected immediately
% before the simulation loop.
origin_index = 1;
safe_index = num_nodes;
gps_lat = node_table.Latitude(origin_index);
gps_lon = node_table.Longitude(origin_index);

%% ========================================================================
% 13. MAIN COMMAND-CENTER FIGURE
% =========================================================================

fig = uifigure( ...
    'Name','HydroTwin Pro - Wayanad Command Center',...
    'Position',[20 40 1500 850]);

% IMPORTANT: maximize the command center so the geographic map is not
% pushed outside the visible screen by Windows display scaling/DPI.
fig.WindowState = 'maximized';

fig.Color = [0.08 0.08 0.10];

%% ------------------------------------------------------------------------
% Header
% -------------------------------------------------------------------------

lblStatus = uilabel(fig,...
    'Position',[25 725 900 35],...
    'FontSize',21,...
    'FontWeight','bold',...
    'FontColor',[0 1 0],...
    'Text','SYSTEM NORMAL: Physics + Sensor Fusion');

lblLeadTime = uilabel(fig,...
    'Position',[25 690 900 28],...
    'FontSize',15,...
    'FontWeight','bold',...
    'FontColor',[1 1 1],...
    'Text','Time to Critical: -- | Actionable Lead Time: --');

lblSensor = uilabel(fig,...
    'Position',[950 725 270 28],...
    'FontSize',13,...
    'FontWeight','bold',...
    'FontColor',[0 1 0],...
    'HorizontalAlignment','right',...
    'Text','SENSOR: HEALTHY');

lblScenario = uilabel(fig,...
    'Position',[25 660 700 25],...
    'FontSize',12,...
    'FontWeight','bold',...
    'FontColor',[0 1 1],...
    'Text','SCENARIO: Initializing...');

lblRoute = uilabel(fig,...
    'Position',[750 75 500 25],...
    'FontSize',12,...
    'FontWeight','bold',...
    'FontColor',[0 1 0],...
    'Text','ROUTE: STANDBY');

%% ========================================================================
% 13. WATER LEVEL TIME SERIES
% =========================================================================

ax1 = uiaxes(fig,...
    'Position',[20 310 710 350]);

ax1.Color = [0.02 0.02 0.025];
ax1.XColor = [1 1 1];
ax1.YColor = [1 1 1];

hold(ax1,'on');
grid(ax1,'on');

title(ax1,...
    'Water Level: Raw Sensor vs Physics-Informed Kalman Estimate',...
    'Color',[1 1 1]);

xlabel(ax1,'Time (min)');
ylabel(ax1,'Water Level (m)');

xlim(ax1,[0 total_steps]);
ylim(ax1,[0 6]);

p_sensor = plot(ax1,...
    NaN,NaN,...
    'r.',...
    'MarkerSize',9,...
    'DisplayName','Raw Sensor');

p_ekf = plot(ax1,...
    NaN,NaN,...
    'g-',...
    'LineWidth',2.2,...
    'DisplayName','Kalman Estimate');

yline(ax1,...
    WARNING_LEVEL,...
    '--',...
    'Warning Threshold');

yline(ax1,...
    CRITICAL_LEVEL,...
    '--',...
    'Critical Threshold');

legend(ax1,...
    [p_sensor p_ekf],...
    'Location','northwest',...
    'TextColor',[1 1 1],...
    'Color','none');

%% ========================================================================
% 14. CLEAN GTA-STYLE EVACUATION MAP
% =========================================================================
% The map is intentionally minimal:
%   - muted real OSM roads as context
%   - NO dense GSI color fills
%   - NO labels for every evacuation node
%   - YOU ARE HERE
%   - nearest safe destination
%   - one highlighted road route between them
% The GSI layer is still used for hazard classification/routing logic.

ax2 = uiaxes(fig,...
    'Position',[750 300 500 360]);

ax2.Color = [0.055 0.06 0.07];
ax2.XColor = [0.75 0.78 0.82];
ax2.YColor = [0.75 0.78 0.82];
ax2.Box = 'on';
ax2.FontSize = 9;
ax2.Toolbar.Visible = 'off';

hold(ax2,'on');
grid(ax2,'off');

xlabel(ax2,'');
ylabel(ax2,'');
xticks(ax2,[]);
yticks(ax2,[]);
title(ax2,'EVACUATION ROUTE  |  REAL OSM ROADS',...
    'Color',[1 1 1], 'FontWeight','bold');

%% ========================================================================
% 15. BUILD REAL OSM ROAD GRAPH
% =========================================================================
% This is the key change: evacuation geometry is now generated from the
% actual OSM road network rather than selecting a nearby road for each
% evacuation-graph edge.

osm_ready = false;
osmGraph = graph();
osm_node_lat = [];
osm_node_lon = [];
osm_edge_part = [];
osm_parts_lat = {};
osm_parts_lon = {};
osm_route_handles = gobjects(0);

if roads_loaded
    try
        [osmGraph,osm_node_lat,osm_node_lon,osm_edge_part,...
            osm_parts_lat,osm_parts_lon] = buildOSMRoadGraph(roads);
        osm_ready = numnodes(osmGraph) >= 2 && numedges(osmGraph) >= 1;

        if osm_ready
            fprintf('[OK] OSM road graph built: %d junction/road nodes, %d road links.\n',...
                numnodes(osmGraph),numedges(osmGraph));
        else
            fprintf('[WARNING] OSM road graph could not be built.\n');
        end
    catch ME
        fprintf('[WARNING] OSM road graph build failed:\n%s\n',ME.message);
    end
end

%% ========================================================================
% 16. DRAW ONLY MUTED ROAD CONTEXT
% =========================================================================
% Do not draw the GSI polygons or all evacuation-node labels here.
% They are decision layers, not visual clutter.

hRoads = gobjects(0);
road_plot_count = 0;

if osm_ready
    try
        for rr = 1:numel(osm_parts_lat)
            la = osm_parts_lat{rr};
            lo = osm_parts_lon{rr};
            good = isfinite(la) & isfinite(lo);
            if nnz(good) >= 2
                h = plot(ax2,lo(good),la(good),...
                    '-', 'Color',[0.62 0.66 0.70], 'LineWidth',0.55);
                hRoads(end+1,1) = h; %#ok<AGROW>
                road_plot_count = road_plot_count + 1;
            end
        end
        fprintf('[OK] OSM road context displayed: %d road segments.\n',road_plot_count);
    catch ME
        fprintf('[WARNING] Road context display failed:\n%s\n',ME.message);
    end
end

% Keep all named locations visible as small contextual place labels.
% These labels are intentionally subtle so the existing road/map styling
% remains unchanged while the map feels like a real operational map.
node_lat = node_table.Latitude;
node_lon = node_table.Longitude;

place_labels = gobjects(numel(node_lat),1);
label_dlat = 0.00045;
label_dlon = 0.00045;

for n = 1:numel(node_lat)
    place_labels(n) = text(ax2,...
        node_lon(n) + label_dlon,...
        node_lat(n) + label_dlat,...
        string(node_table.Name(n)),...
        'Color',[0.78 0.80 0.84],...
        'FontSize',7,...
        'FontWeight','normal',...
        'HorizontalAlignment','left',...
        'VerticalAlignment','bottom',...
        'Clipping','on',...
        'Interpreter','none');
end

%% ========================================================================
% 17. ACTIVE OSM EVACUATION ROUTE
% =========================================================================

hRouteGlow = gobjects(0);
hRouteCore = gobjects(0);
roadRouteReady = false;

% Second-person demonstration route handles.
hTestRouteGlow = gobjects(0);
hTestRouteCore = gobjects(0);
testRoadRouteReady = false;

%% ========================================================================
% 18. INITIAL MAP VIEW
% =========================================================================
% Zoom tightly around the user and initial safe candidate, like a game map.

initial_lat = [node_table.Latitude(origin_index); node_table.Latitude(safe_index)];
initial_lon = [node_table.Longitude(origin_index); node_table.Longitude(safe_index)];
setCleanMapView(ax2,initial_lat,initial_lon);

%% ========================================================================
% 19. USER + SAFE DESTINATION MARKERS
% =========================================================================

gps_lat = node_table.Latitude(origin_index);
gps_lon = node_table.Longitude(origin_index);

gps_marker = plot(ax2,gps_lon,gps_lat,'o',...
    'MarkerSize',10,...
    'MarkerFaceColor',[0 1 1],...
    'MarkerEdgeColor',[1 1 1],...
    'LineWidth',1.8);

gps_label = text(ax2,gps_lon,gps_lat,...
    '  YOU',...
    'Color',[0 1 1],...
    'FontSize',10,...
    'FontWeight','bold',...
    'Clipping','on');

destination_marker = plot(ax2,...
    node_table.Longitude(safe_index),...
    node_table.Latitude(safe_index),...
    'p',...
    'MarkerSize',11,...
    'MarkerFaceColor',[0.2 1 0.2],...
    'MarkerEdgeColor',[1 1 1],...
    'LineWidth',1.8);

destination_label = text(ax2,...
    node_table.Longitude(safe_index),...
    node_table.Latitude(safe_index),...
    '  SAFE',...
    'Color',[0.4 1 0.4],...
    'FontSize',10,...
    'FontWeight','bold',...
    'Clipping','on');

% -------------------------------------------------------------------------
% Secondary test person: deliberately placed in Moderate/High terrain.
% These handles are hidden until the actual test-person position is ready.
% -------------------------------------------------------------------------
test_marker = plot(ax2,NaN,NaN,'o',...
    'MarkerSize',10,...
    'MarkerFaceColor',[1 0.55 0.05],...
    'MarkerEdgeColor',[1 1 1],...
    'LineWidth',1.8,...
    'Visible','off');

test_label = text(ax2,NaN,NaN,...
    '  TEST USER',...
    'Color',[1 0.65 0.1],...
    'FontSize',10,...
    'FontWeight','bold',...
    'Clipping','on',...
    'Visible','off');

test_destination_marker = plot(ax2,NaN,NaN,'p',...
    'MarkerSize',11,...
    'MarkerFaceColor',[0.3 1 0.3],...
    'MarkerEdgeColor',[1 1 1],...
    'LineWidth',1.8,...
    'Visible','off');

test_destination_label = text(ax2,NaN,NaN,...
    '  TEST SAFE',...
    'Color',[0.45 1 0.45],...
    'FontSize',9,...
    'FontWeight','bold',...
    'Clipping','on',...
    'Visible','off');

%% ========================================================================
% 20. ALERT PANEL
% =========================================================================

txtAlert = uitextarea(fig,...
    'Position',[750 105 500 145],...
    'FontSize',14,...
    'FontWeight','bold',...
    'FontColor',[1 0.3 0.3],...
    'BackgroundColor',[0.12 0.04 0.04],...
    'Value',{'CELL BROADCAST STANDBY...'});

%% ========================================================================
% 21. SYSTEM INFORMATION
% =========================================================================

lblDataSource = uilabel(fig,...
    'Position',[25 250 700 35],...
    'FontSize',12,...
    'FontColor',[0.8 0.8 0.8],...
    'Text','');

if roads_loaded && gsi_loaded && real_network_loaded

    lblDataSource.Text = ...
        'GIS STATUS: REAL OSM ROADS + GSI + TOPOLOGICAL ROUTING + LIVE EVACUATION PATH';

elseif roads_loaded && gsi_loaded

    lblDataSource.Text = ...
        'GIS STATUS: REAL OSM ROADS + GSI SUSCEPTIBILITY';

elseif roads_loaded

    lblDataSource.Text = ...
        'GIS STATUS: REAL OSM ROAD DATA';

else

    lblDataSource.Text = ...
        'GIS STATUS: GIS DATA INCOMPLETE';

end

%% ========================================================================
% 22. SIMULATION HISTORY
% =========================================================================

history_sensor = nan(1,total_steps);

%% ========================================================================
% 23. RANDOM USER SPAWN + VERIFIED SAFE DESTINATION SETUP
% =========================================================================
% Spawn in a real GSI polygon. A Low-susceptibility spawn does NOT trigger
% terrain-based evacuation. Moderate/High spawns evacuate to the nearest
% reachable designated SAFE_CANDIDATE/SHELTER that is Low by GSI.

type_text = lower(strtrim(string(node_table.Type)));

safe_mask = ...
    (contains(type_text,"safe_candidate") | contains(type_text,"shelter")) & ...
    strcmpi(node_hazard_class,"Low");

safe_candidates = find(safe_mask);

if isempty(safe_candidates)
    error('HydroTwin:NoVerifiedSafeCandidate', ...
        ['No designated SAFE_CANDIDATE/SHELTER is classified Low by GSI. ' ...
         'Refusing to invent a safe destination.']);
end

% Exactly the requested 50/50 behavior unless the demo is forced.
if strcmpi(SPAWN_MODE,"high")
    spawn_target_class = "High";
elseif strcmpi(SPAWN_MODE,"low")
    spawn_target_class = "Low";
else
    if rand < 0.50
        spawn_target_class = "High";
    else
        spawn_target_class = "Low";
    end
end

% Spawn on an actual QGIS routing road that lies inside the requested
% GSI class. This prevents the simulated user from appearing in an
% isolated part of a large GSI polygon where no mapped road exists.
[gps_lat,gps_lon,spawn_ok] = randomPointOnRoutingRoadInGSIClass( ...
    spawn_target_class,routing,routing_proj,gsi,gsi_class, ...
    MAP_LAT_LIMIT,MAP_LON_LIMIT);

if ~spawn_ok
    fallback_idx = find(strcmpi(node_hazard_class,spawn_target_class),1);

    if isempty(fallback_idx)
        error('HydroTwin:SpawnFailed', ...
            'Could not create a %s GSI spawn point.',spawn_target_class);
    end

    gps_lat = node_table.Latitude(fallback_idx);
    gps_lon = node_table.Longitude(fallback_idx);
    fprintf('[WARNING] Random GSI spawn failed; using a named fallback point.\n');
end

spawn_class = spawn_target_class;
needs_evacuation = strcmpi(spawn_class,"High") || ...
                   strcmpi(spawn_class,"Moderate");

scenario_name = sprintf('USER SPAWN: %s SUSCEPTIBILITY',upper(string(spawn_class)));
scenario_location = sprintf('Random point %.5f, %.5f',gps_lat,gps_lon);

% Select the nearest reachable verified safe destination by real QGIS road
% distance. This is only needed when evacuation is actually required.
safe_index = safe_candidates(1);
best_road_distance = Inf;

if needs_evacuation && routing_loaded
    routing_start = nearestRoutingVertex( ...
        gps_lat,gps_lon,routing_xy,routing_proj);

    for d = safe_candidates(:)'
        routing_goal = nearestRoutingVertex( ...
            node_table.Latitude(d),node_table.Longitude(d), ...
            routing_xy,routing_proj);

        try
            [~,road_distance] = shortestpath( ...
                routing_graph,routing_start,routing_goal);

            if isfinite(road_distance) && road_distance < best_road_distance
                best_road_distance = road_distance;
                safe_index = d;
            end
        catch
            % Candidate is unreachable from the current road graph.
        end
    end
end

if needs_evacuation
    if isfinite(best_road_distance)
        fprintf('[OK] Nearest reachable verified safe destination: %s (%.0f m).\n', ...
            string(node_table.Name(safe_index)),best_road_distance);
    else
        fprintf('[WARNING] No verified safe destination is reachable on the QGIS road graph.\n');
    end
else
    fprintf('[OK] Spawn is Low GSI susceptibility: no terrain-triggered evacuation.\n');
end

% -------------------------------------------------------------------------
% Prepare the second demonstration person.
% -------------------------------------------------------------------------
test_person_ready = false;
test_person_lat = NaN;
test_person_lon = NaN;
test_person_class = "Unknown";
test_safe_index = NaN;
test_best_road_distance = inf;

if SHOW_TEST_PERSON && routing_loaded && gsi_loaded

    [test_person_lat,test_person_lon,test_person_class,test_person_ready] = ...
        spawnRoutingTestPerson( ...
        TEST_PERSON_TARGET_CLASS,...
        routing,routing_proj,gsi,gsi_class,...
        MAP_LAT_LIMIT,MAP_LON_LIMIT);

    if test_person_ready

        safe_from_test = safe_candidates(:)';
        test_start = nearestRoutingVertex( ...
            test_person_lat,test_person_lon,...
            routing_xy,routing_proj);

        for d = safe_from_test

            test_goal = nearestRoutingVertex( ...
                node_table.Latitude(d),...
                node_table.Longitude(d),...
                routing_xy,routing_proj);

            try
                [~,test_dist] = shortestpath( ...
                    routing_graph,test_start,test_goal);

                if isfinite(test_dist) && test_dist < test_best_road_distance
                    test_best_road_distance = test_dist;
                    test_safe_index = d;
                end
            catch
                % Ignore unreachable safe candidates.
            end
        end

        if isfinite(test_safe_index)

            test_marker.XData = test_person_lon;
            test_marker.YData = test_person_lat;
            test_marker.Visible = 'on';

            test_label.Position = [test_person_lon,test_person_lat];
            test_label.Visible = 'on';

            test_destination_marker.XData = node_table.Longitude(test_safe_index);
            test_destination_marker.YData = node_table.Latitude(test_safe_index);
            test_destination_marker.Visible = 'on';

            test_destination_label.Position = [ ...
                node_table.Longitude(test_safe_index),...
                node_table.Latitude(test_safe_index)];
            test_destination_label.Visible = 'on';

            fprintf('[OK] TEST USER spawned on %s GSI road at %.5f, %.5f.\n',...
                test_person_class,test_person_lat,test_person_lon);
            fprintf('[OK] TEST USER nearest verified safe destination: %s (%.0f m).\n',...
                string(node_table.Name(test_safe_index)),test_best_road_distance);

        else

            fprintf('[WARNING] TEST USER has no reachable verified safe destination.\n');

        end

    else

        fprintf('[WARNING] Could not place TEST USER on a Moderate/High GSI road.\n');

    end
end

% Focus the map around both people and the relevant safe destinations.
map_lat = gps_lat;
map_lon = gps_lon;

if test_person_ready && isfinite(test_safe_index)
    map_lat = [map_lat;test_person_lat;node_table.Latitude(test_safe_index)];
    map_lon = [map_lon;test_person_lon;node_table.Longitude(test_safe_index)];
end

if needs_evacuation
    map_lat = [map_lat;node_table.Latitude(safe_index)];
    map_lon = [map_lon;node_table.Longitude(safe_index)];
end

setCleanMapView(ax2,map_lat,map_lon);

fprintf('\n============================================================\n');
fprintf(' DEMO SCENARIO\n');
fprintf('============================================================\n');
fprintf('Spawn location : %s\n',scenario_location);
fprintf('Spawn class    : %s\n',spawn_class);
fprintf('Destination    : ');
if needs_evacuation
    fprintf('%s\n',string(node_table.Name(safe_index)));
else
    fprintf('STAY / MONITOR OFFICIAL ALERTS\n');
end
fprintf('Spawn mode     : %s\n',SPAWN_MODE);

if test_person_ready && isfinite(test_safe_index)
    fprintf('TEST USER class : %s\n',test_person_class);
    fprintf('TEST USER route : %s -> %s\n',...
        sprintf('%.5f, %.5f',test_person_lat,test_person_lon),...
        string(node_table.Name(test_safe_index)));
end

%% ========================================================================
% 24. REAL-TIME DIGITAL-TWIN LOOP
% =========================================================================

fprintf('\nStarting digital-twin simulation...\n\n');

for k = 1:total_steps

    %% --------------------------------------------------------------------
    % STEP 1 - READ SENSOR
    % ---------------------------------------------------------------------

    z = mock_data(k);

    history_sensor(k) = z;

    %% --------------------------------------------------------------------
    % STEP 2 - SENSOR HEALTH
    % ---------------------------------------------------------------------

    ml_anomaly = false;
    ml_score = 0;

    if use_ml_model

        try

            [ml_anomaly,ml_score] = ...
                isanomaly(anomaly_model,z);

        catch

            ml_anomaly = false;
            ml_score = 0;

        end

    end

    physical_failure = ...
        z < 0.20 || ...
        z > 12.0;

    if k > 1

        rate_measurement = ...
            (z-history_sensor(k-1))/dt;

        unrealistic_rate = ...
            abs(rate_measurement) > 1.5;

    else

        unrealistic_rate = false;

    end

    sensor_broken = ...
        ml_anomaly || ...
        physical_failure || ...
        unrealistic_rate;

    broken_history(k) = sensor_broken;

    health_score_history(k) = max([...
        double(logical(ml_score)),...
        double(physical_failure),...
        double(unrealistic_rate)]);

    %% --------------------------------------------------------------------
    % STEP 3 - KALMAN PREDICTION
    % ---------------------------------------------------------------------

    x_pred = F*x_est;

    P_pred = F*P*F' + Q;

    %% --------------------------------------------------------------------
    % STEP 4 - SENSOR FUSION / FAILSAFE
    % ---------------------------------------------------------------------

    if sensor_broken

        % Model-only prediction
        x_est = x_pred;
        P = P_pred;

        lblSensor.Text = 'SENSOR: FAILED / MODEL MODE';
        lblSensor.FontColor = [1 0.7 0];

    else

        innovation = z-H*x_pred;

        innovation_cov = ...
            H*P_pred*H' + R;

        K = P_pred*H'/innovation_cov;

        x_est = ...
            x_pred + K*innovation;

        P = ...
            (eye(2)-K*H)*P_pred;

        lblSensor.Text = 'SENSOR: HEALTHY';
        lblSensor.FontColor = [0 1 0];

    end

    % Physical limits
    x_est(1) = max(x_est(1),0);

    x_est(2) = ...
        max(min(x_est(2),2),-2);

    history_ekf(k) = x_est(1);
    history_rate(k) = x_est(2);

    current_level = x_est(1);

    %% --------------------------------------------------------------------
    % STEP 5 - SYSTEM STATE
    % ---------------------------------------------------------------------

    if current_level < NORMAL_LEVEL

        system_state = "NORMAL";

        lblStatus.Text = ...
            'SYSTEM NORMAL: Physics + Sensor Fusion';

        lblStatus.FontColor = [0 1 0];

    elseif current_level < WARNING_LEVEL

        system_state = "WATCH";

        lblStatus.Text = ...
            'WATCH: WATER LEVEL RISING';

        lblStatus.FontColor = [1 1 0];

    elseif current_level < CRITICAL_LEVEL

        system_state = "WARNING";

        lblStatus.Text = ...
            'WARNING: EVACUATION ROUTING PREPARING';

        lblStatus.FontColor = [1 0.65 0];

    else

        system_state = "CRITICAL";

        lblStatus.Text = ...
            'CRITICAL: HAZARD-AWARE ROUTING ACTIVE';

        lblStatus.FontColor = [1 0.1 0.1];

    end

    %% --------------------------------------------------------------------
    % STEP 6 - GSI + DYNAMIC HYDRO ROUTING
    % ---------------------------------------------------------------------

    route_found = false;
    path_nodes = [];
    path_cost = NaN;

    test_route_found = false;
    test_path_nodes = [];
    test_path_cost = NaN;

    % Only the QGIS topology-cleaned road graph is used for evacuation.
    % Build the same hazard-weighted graph for both the primary user and
    % the second demonstration user.
    if routing_loaded && (needs_evacuation || test_person_ready)

        G_dynamic = routing_graph;
        base_road_m = routing_graph.Edges.Weight(:);

        hydro_factor = 1.0;
        if current_level >= WARNING_LEVEL
            hydro_factor = 1.5;
        end
        if current_level >= CRITICAL_LEVEL
            hydro_factor = 3.0;
        end

        % Rainfall increases the penalty on susceptible terrain without
        % changing the relative cost of Low/Unknown links unnecessarily.
        rain_factor = 1.0 + min(max(rainfall(k),0),120)/120;

        dynamic_factor = 1.0 + ...
            (routing_edge_gsi_factor - 1.0) * hydro_factor * rain_factor;

        G_dynamic.Edges.Weight = base_road_m .* dynamic_factor;

        %% ----------------------------------------------------------------
        % STEP 7A - PRIMARY USER ROUTE
        % -----------------------------------------------------------------

        if needs_evacuation

            try
                routing_start = nearestRoutingVertex( ...
                    gps_lat,gps_lon,routing_xy,routing_proj);

                routing_goal = nearestRoutingVertex( ...
                    node_table.Latitude(safe_index), ...
                    node_table.Longitude(safe_index), ...
                    routing_xy,routing_proj);

                [path_nodes,path_cost_m] = shortestpath( ...
                    G_dynamic,routing_start,routing_goal);

                if ~isempty(path_nodes) && isfinite(path_cost_m)
                    route_found = true;

                    [user_x,user_y] = projfwd( ...
                        routing_proj,gps_lat,gps_lon);
                    [safe_x,safe_y] = projfwd( ...
                        routing_proj,...
                        node_table.Latitude(safe_index),...
                        node_table.Longitude(safe_index));

                    pUser = routing_xy(routing_start,:);
                    pSafe = routing_xy(routing_goal,:);

                    connector_m = ...
                        hypot(user_x-pUser(1),user_y-pUser(2)) + ...
                        hypot(safe_x-pSafe(1),safe_y-pSafe(2));

                    path_cost = (path_cost_m + connector_m)/500;
                end

            catch ME
                if k == 1 || k == rise_start || k == rise_end
                    fprintf('[WARNING] Primary route calculation failed: %s\n',ME.message);
                end
            end

        end

        %% ----------------------------------------------------------------
        % STEP 7B - SECOND PERSON ROUTE
        % -----------------------------------------------------------------

        if test_person_ready && isfinite(test_safe_index)

            try
                test_start = nearestRoutingVertex( ...
                    test_person_lat,test_person_lon,...
                    routing_xy,routing_proj);

                test_goal = nearestRoutingVertex( ...
                    node_table.Latitude(test_safe_index),...
                    node_table.Longitude(test_safe_index),...
                    routing_xy,routing_proj);

                [test_path_nodes,test_path_cost_m] = shortestpath( ...
                    G_dynamic,test_start,test_goal);

                if ~isempty(test_path_nodes) && isfinite(test_path_cost_m)
                    test_route_found = true;

                    [test_x,test_y] = projfwd( ...
                        routing_proj,test_person_lat,test_person_lon);
                    [safe_x,safe_y] = projfwd( ...
                        routing_proj,...
                        node_table.Latitude(test_safe_index),...
                        node_table.Longitude(test_safe_index));

                    pTest = routing_xy(test_start,:);
                    pSafe = routing_xy(test_goal,:);

                    test_connector_m = ...
                        hypot(test_x-pTest(1),test_y-pTest(2)) + ...
                        hypot(safe_x-pSafe(1),safe_y-pSafe(2));

                    test_path_cost = ...
                        (test_path_cost_m + test_connector_m)/500;
                end

            catch ME
                if k == 1 || k == rise_start || k == rise_end
                    fprintf('[WARNING] TEST USER route calculation failed: %s\n',ME.message);
                end
            end
        end
    end

    %% --------------------------------------------------------------------
    % STEP 8 - USER GPS LOCATION
    % ---------------------------------------------------------------------

    % The user remains at the randomly spawned location while the digital
    % twin determines the evacuation response.
    gps_marker.XData = gps_lon;
    gps_marker.YData = gps_lat;
    gps_label.Position = [gps_lon gps_lat];

    if needs_evacuation
        destination_marker.XData = node_table.Longitude(safe_index);
        destination_marker.YData = node_table.Latitude(safe_index);
        destination_label.Position = [ ...
            node_table.Longitude(safe_index), ...
            node_table.Latitude(safe_index)];
    end

    %% --------------------------------------------------------------------
    % STEP 9 - DISPLAY ONLY THE OPTIMUM ROAD PATH
    % ---------------------------------------------------------------------

    if needs_evacuation && route_found && current_level >= WARNING_LEVEL

        [roadRouteReady,hRouteGlow,hRouteCore] = drawQGISNeonRoute( ...
            ax2,routing,routing_graph,routing_xy,routing_edge_geom,...
            routing_proj,path_nodes,gps_lat,gps_lon,...
            node_table.Latitude(safe_index),node_table.Longitude(safe_index));

        if roadRouteReady
            setCleanMapView(ax2,...
                [gps_lat;node_table.Latitude(safe_index)],...
                [gps_lon;node_table.Longitude(safe_index)]);
        end

        lblRoute.Text = sprintf(...
            'ROUTE: NEAREST SAFE EXIT -> %s | EST. %.1f min',...
            string(node_table.Name(safe_index)),path_cost);
        lblRoute.FontColor = [0 1 1];

    else

        if ~isempty(hRouteGlow)
            good = isgraphics(hRouteGlow);
            if any(good), set(hRouteGlow(good),'Visible','off'); end
        end
        if ~isempty(hRouteCore)
            good = isgraphics(hRouteCore);
            if any(good), set(hRouteCore(good),'Visible','off'); end
        end

        if needs_evacuation
            lblRoute.Text = 'ROUTE: STANDBY - WAITING FOR WARNING CONDITION';
        else
            lblRoute.Text = 'ROUTE: NO TERRAIN EVACUATION - MONITOR OFFICIAL ALERTS';
        end
        lblRoute.FontColor = [1 1 0];

    end

    if test_person_ready && isfinite(test_safe_index)
        if test_route_found && current_level >= WARNING_LEVEL
            if isempty(lblRoute.Text) || startsWith(string(lblRoute.Text),"ROUTE: NO")
                lblRoute.Text = sprintf(...
                    'ROUTE: TEST USER -> %s | EST. %.1f min',...
                    string(node_table.Name(test_safe_index)),test_path_cost);
            else
                lblRoute.Text = sprintf(...
                    'PRIMARY/TEST: %s | %.1f min / %.1f min',...
                    string(node_table.Name(test_safe_index)),...
                    path_cost,test_path_cost);
            end
            lblRoute.FontColor = [0 1 1];
        end
    end

    %% --------------------------------------------------------------------
    % STEP 9B - DISPLAY TEST USER EVACUATION ROUTE
    % ---------------------------------------------------------------------

    if test_person_ready && isfinite(test_safe_index) && ...
            test_route_found && current_level >= WARNING_LEVEL

        [testRoadReady,hTestRouteGlow,hTestRouteCore] = drawQGISNeonRoute( ...
            ax2,routing,routing_graph,routing_xy,routing_edge_geom,...
            routing_proj,test_path_nodes,...
            test_person_lat,test_person_lon,...
            node_table.Latitude(test_safe_index),...
            node_table.Longitude(test_safe_index));

        if testRoadReady
            testRoadRouteReady = true;
        end

    else

        if ~isempty(hTestRouteGlow)
            good = isgraphics(hTestRouteGlow);
            if any(good)
                set(hTestRouteGlow(good),'Visible','off');
            end
        end

        if ~isempty(hTestRouteCore)
            good = isgraphics(hTestRouteCore);
            if any(good)
                set(hTestRouteCore(good),'Visible','off');
            end
        end
    end

    %% --------------------------------------------------------------------
    % STEP 10 - TIME TO CRITICAL LEVEL
    % ---------------------------------------------------------------------

    predicted_arrival = NaN;

    if current_level < CRITICAL_LEVEL && x_est(2) > 0.001

        predicted_arrival = ...
            (CRITICAL_LEVEL-current_level)/x_est(2);

        predicted_arrival = ...
            min(max(predicted_arrival,0),120);

    elseif current_level >= CRITICAL_LEVEL

        predicted_arrival = 0;

    end

    if isfinite(predicted_arrival)

        actionable_lead_time = ...
            max(predicted_arrival-5,0);

    else

        actionable_lead_time = NaN;

    end

    %% --------------------------------------------------------------------
    % STEP 11 - ALERT MESSAGE
    % ---------------------------------------------------------------------

    if needs_evacuation
        primary_text = sprintf( ...
            'PRIMARY: %s -> %s',...
            upper(string(spawn_class)),...
            string(node_table.Name(safe_index)));
    else
        primary_text = 'PRIMARY: LOW GSI -> STAY / MONITOR';
    end

    if test_person_ready && isfinite(test_safe_index)
        test_text = sprintf( ...
            ' | TEST USER: %s -> %s',...
            upper(string(test_person_class)),...
            string(node_table.Name(test_safe_index)));
    else
        test_text = '';
    end

    lblScenario.Text = sprintf( ...
        '%s%s | RAINFALL: %.0f mm/hr',...
        primary_text,test_text,rainfall(k));

    if ~needs_evacuation

        if test_person_ready && isfinite(test_safe_index)
            test_summary = sprintf( ...
                'TEST USER: %s GSI -> %s', ...
                upper(string(test_person_class)),...
                upper(string(node_table.Name(test_safe_index))));
        else
            test_summary = 'TEST USER: Moderate/High spawn unavailable';
        end

        if current_level >= CRITICAL_LEVEL

            if test_route_found
                test_route_summary = sprintf( ...
                    'TEST ROUTE: %.1f min | EVACUATION ACTIVE',test_path_cost);
            else
                test_route_summary = ...
                    'TEST ROUTE: UNAVAILABLE IN QGIS ROAD GRAPH';
            end

            txtAlert.Value = { ...
                'CRITICAL FLOOD CONDITION'; ...
                sprintf('Estimated water level: %.2f m',current_level); ...
                'PRIMARY: LOW GSI - NO TERRAIN-TRIGGERED EVACUATION'; ...
                'PRIMARY ACTION: MONITOR OFFICIAL FLOOD / EMERGENCY ALERTS'; ...
                test_summary; ...
                test_route_summary};

            lblStatus.Text = 'CRITICAL FLOOD: TEST USER EVACUATION ACTIVE';
            lblStatus.FontColor = [1 0.5 0.1];

        elseif current_level >= WARNING_LEVEL

            txtAlert.Value = { ...
                'FLOOD / LANDSLIDE WARNING'; ...
                sprintf('Estimated water level: %.2f m',current_level); ...
                'PRIMARY: LOW GSI - STAY / MONITOR'; ...
                test_summary; ...
                sprintf('TEST ROUTE: %s', ...
                    ternaryText(test_route_found,...
                    'EVACUATION ACTIVE',...
                    'ROUTE UNAVAILABLE'))};

        else

            txtAlert.Value = { ...
                'CELL BROADCAST STANDBY...'; ...
                sprintf('Estimated water level: %.2f m',current_level); ...
                'PRIMARY: LOW GSI - STAY / MONITOR'; ...
                sprintf('TEST USER: %s GSI - WAITING FOR WARNING LEVEL', ...
                    upper(string(test_person_class)))};

        end

        lblLeadTime.Text = ...
            'Terrain action: STAY / MONITOR OFFICIAL ALERTS';

    elseif current_level >= CRITICAL_LEVEL

        if route_found
            route_message = sprintf( ...
                ['CRITICAL HAZARD CONDITION.\n' ...
                 'Estimated water level: %.2f m\n' ...
                 'Hazard-weighted route: %.1f min\n' ...
                 'Evacuate to verified Low-GSI destination: %s'], ...
                 current_level,path_cost,string(node_table.Name(safe_index)));
        else
            route_message = sprintf( ...
                ['CRITICAL HAZARD CONDITION.\n' ...
                 'NO SAFE ROUTE AVAILABLE IN QGIS ROAD GRAPH.\n' ...
                 'Verified destination: %s\n' ...
                 'Contact emergency coordination immediately.'], ...
                 string(node_table.Name(safe_index)));
        end

        txtAlert.Value = splitlines(route_message);
        lblLeadTime.Text = sprintf( ...
            'Time to Critical: NOW | Route Cost: %.1f min',path_cost);

    elseif current_level >= WARNING_LEVEL

        if route_found
            txtAlert.Value = { ...
                'FLOOD / LANDSLIDE WARNING'; ...
                sprintf('Estimated water level: %.2f m',current_level); ...
                sprintf('Rainfall intensity: %.0f mm/hr',rainfall(k)); ...
                sprintf('Evacuate to verified Low-GSI destination: %s', ...
                    string(node_table.Name(safe_index))); ...
                'GSI susceptibility-aware road routing ACTIVE.'};
        else
            txtAlert.Value = { ...
                'FLOOD / LANDSLIDE WARNING'; ...
                sprintf('Estimated water level: %.2f m',current_level); ...
                'No reachable safe road route is currently available.'; ...
                'Routing system continues monitoring the QGIS network.'};
        end

        if isfinite(predicted_arrival)
            lblLeadTime.Text = sprintf( ...
                'Time to Critical: %.1f min | Actionable Lead Time: %.1f min', ...
                predicted_arrival,actionable_lead_time);
        else
            lblLeadTime.Text = ...
                'Time to Critical: calculating | Evacuation: active';
        end

    else

        txtAlert.Value = { ...
            'CELL BROADCAST STANDBY...'; ...
            sprintf('Estimated water level: %.2f m',current_level); ...
            sprintf('GSI CLASS: %s',upper(string(spawn_class))); ...
            'Evacuation routing on standby until warning level.'};

        lblLeadTime.Text = ...
            'Time to Critical: -- | Evacuation: monitoring';

    end

    %% --------------------------------------------------------------------
    % STEP 12 - UPDATE WATER LEVEL PLOT
    % ---------------------------------------------------------------------

    p_sensor.XData = time_vector(1:k);
    p_sensor.YData = history_sensor(1:k);

    p_ekf.XData = time_vector(1:k);
    p_ekf.YData = history_ekf(1:k);

    %% --------------------------------------------------------------------
    % STEP 13 - UI REFRESH
    % ---------------------------------------------------------------------

    drawnow limitrate;

    pause(0.03);

end

fprintf('\nDigital-twin simulation complete.\n');

%% ========================================================================
% 25. SIMULATION SUMMARY
% =========================================================================

peak_sensor = max(history_sensor,[],'omitnan');
peak_estimate = max(history_ekf,[],'omitnan');

num_sensor_failures = sum(broken_history);

fprintf('\n============================================================\n');
fprintf(' SIMULATION SUMMARY\n');
fprintf('============================================================\n');

fprintf('Peak raw sensor level      : %.2f m\n',peak_sensor);
fprintf('Peak estimated water level : %.2f m\n',peak_estimate);
fprintf('Spawn scenario             : %s at %s\n',spawn_class,scenario_location);
if needs_evacuation
    fprintf('Final safe destination     : %s\n',string(node_table.Name(safe_index)));
else
    fprintf('Final safe destination     : NOT REQUIRED FOR LOW-GSI SPAWN\n');
end

fprintf('Sensor-failure detections  : %d\n',num_sensor_failures);

if roads_loaded
    fprintf('Road GIS                   : REAL OSM GIS DATA\n');
if routing_loaded, fprintf('OSM routing network        : QGIS TOPOLOGICAL GPKG\n'); end
else
    fprintf('Road GIS                   : NOT LOADED\n');
end

if gsi_loaded
    fprintf('GSI susceptibility         : REAL GSI DATA\n');
else
    fprintf('GSI susceptibility         : NOT LOADED\n');
end

if real_network_loaded
    fprintf('Evacuation graph           : EXISTING ROUTING CSV DATA\n');
else
    fprintf('Evacuation graph           : DEMO / FALLBACK\n');
end

%% ========================================================================
% 26. OPTIONAL SIMULINK VALIDATION
% =========================================================================

fprintf('\n============================================================\n');
fprintf(' SIMULINK VALIDATION\n');
fprintf('============================================================\n');

if isfile(SIMULINK_MODEL + ".slx") || ...
   isfile(SIMULINK_MODEL + ".mdl")

    try

        sim_time_vector = (0:total_steps-1)';

        sim_input = timeseries(...
            history_sensor',...
            sim_time_vector);

        assignin('base','sim_input',sim_input);

        fprintf('Running Simulink model: %s\n',SIMULINK_MODEL);

        simOut = sim(...
            SIMULINK_MODEL,...
            'SimulationMode','normal',...
            'SaveOutput','on',...
            'ExternalInput','sim_input',...
            'Solver','FixedStepDiscrete',...
            'FixedStep','1',...
            'StartTime','0',...
            'StopTime',num2str(total_steps-1));

        sim_data = [];
        sim_time = [];

        % Try yout
        if isprop(simOut,'yout') || isfield(simOut,'yout')

            try

                yout_data = simOut.yout;

                if isa(yout_data,...
                        'Simulink.SimulationData.Dataset')

                    if yout_data.numElements > 0

                        sim_element = ...
                            yout_data.getElement(1);

                        values = sim_element.Values;

                        sim_data = values.Data;
                        sim_time = values.Time;

                    end

                end

            catch

            end

        end

        if ~isempty(sim_data)

            sim_data = sim_data(:);
            sim_time = sim_time(:);

            valid = ...
                isfinite(sim_time) & ...
                isfinite(sim_data);

            sim_time = sim_time(valid);
            sim_data = sim_data(valid);

            if numel(sim_time) >= 2

                history_simulink = ...
                    interp1(...
                    sim_time,...
                    sim_data,...
                    sim_time_vector,...
                    'linear',...
                    'extrap');

                f2 = figure(...
                    'Name','HydroTwin Simulink Validation',...
                    'Color',[0.1 0.1 0.1]);

                ax3 = axes(f2);

                plot(ax3,...
                    time_vector,...
                    history_ekf,...
                    'LineWidth',2,...
                    'DisplayName','MATLAB Digital Twin');

                hold(ax3,'on');

                plot(ax3,...
                    sim_time_vector,...
                    history_simulink,...
                    '--',...
                    'LineWidth',1.8,...
                    'DisplayName','Simulink Model');

                grid(ax3,'on');

                title(ax3,...
                    'MATLAB vs Simulink Physics Validation',...
                    'Color',[1 1 1]);

                xlabel(ax3,'Time (min)');
                ylabel(ax3,'Water Level (m)');

                legend(ax3,'Location','best');

                lblStatus.Text = ...
                    'VERIFIED: Simulink Validation Complete';

                lblStatus.FontColor = [0 1 1];

                fprintf('[OK] Simulink output successfully validated.\n');

            else

                fprintf('[WARNING] Simulink returned insufficient output data.\n');

            end

        else

            fprintf('[WARNING] No usable yout signal found in Simulink output.\n');

        end

    catch ME

        fprintf('[WARNING] Simulink execution failed:\n');
        fprintf('%s\n',ME.message);

    end

else

    fprintf('[INFO] hydro_physics.slx not found. Validation skipped.\n');

end

%% ========================================================================
% 27. FINAL MESSAGE
% =========================================================================

drawnow;

fprintf('\n============================================================\n');
fprintf(' HydroTwin Pro finished successfully.\n');
fprintf('============================================================\n');


function [G,vertex_xy,graph_edge_geom] = buildQGISRoutingGraph(routing,tol_m)
%BUILDQGISROUTINGGRAPH Build a bidirectional graph from QGIS routing_edges.

n = height(routing);
endpoint_xy = nan(n,4);
edge_len = nan(n,1);
valid = false(n,1);

for i = 1:n
    try
        [x,y] = shapeToXY(routing.Shape(i));
        good = isfinite(x) & isfinite(y);
        x = x(good);
        y = y(good);

        if numel(x) >= 2
            endpoint_xy(i,:) = [x(1),y(1),x(end),y(end)];
            edge_len(i) = sum(hypot(diff(x),diff(y)),'omitnan');
            valid(i) = isfinite(edge_len(i)) && edge_len(i) > 0.1;
        end
    catch
        % Skip malformed geometry.
    end
end

ids = find(valid);
key_map = containers.Map('KeyType','char','ValueType','double');
vertex_xy = zeros(0,2);
U = zeros(numel(ids),1);
V = zeros(numel(ids),1);
W = zeros(numel(ids),1);
row_id = zeros(numel(ids),1);

for j = 1:numel(ids)
    i = ids(j);
    p1 = endpoint_xy(i,1:2);
    p2 = endpoint_xy(i,3:4);

    k1 = sprintf('%.2f_%.2f', ...
        round(p1(1)/tol_m)*tol_m,round(p1(2)/tol_m)*tol_m);
    k2 = sprintf('%.2f_%.2f', ...
        round(p2(1)/tol_m)*tol_m,round(p2(2)/tol_m)*tol_m);

    if ~isKey(key_map,k1)
        key_map(k1) = size(vertex_xy,1)+1;
        vertex_xy(end+1,:) = p1; %#ok<AGROW>
    end

    if ~isKey(key_map,k2)
        key_map(k2) = size(vertex_xy,1)+1;
        vertex_xy(end+1,:) = p2; %#ok<AGROW>
    end

    U(j) = key_map(k1);
    V(j) = key_map(k2);
    W(j) = edge_len(i);
    row_id(j) = i;
end

keep = U ~= V & isfinite(W) & W > 0;
U = U(keep);
V = V(keep);
W = W(keep);
row_id = row_id(keep);

a = min(U,V);
b = max(U,V);
[~,~,grp] = unique([a b],'rows');
ng = max(grp);

UU = zeros(ng,1);
VV = zeros(ng,1);
WW = inf(ng,1);
RR = zeros(ng,1);

for g = 1:ng
    idx = find(grp == g);
    [~,q] = min(W(idx));
    z = idx(q);
    UU(g) = U(z);
    VV(g) = V(z);
    WW(g) = W(z);
    RR(g) = row_id(z);
end

keep = isfinite(WW) & WW > 0;
UU = UU(keep);
VV = VV(keep);
WW = WW(keep);
RR = RR(keep);

G = graph(UU,VV,WW,size(vertex_xy,1));
graph_edge_geom = zeros(numedges(G),1);

for j = 1:numel(UU)
    e = findedge(G,UU(j),VV(j));
    if e > 0 && graph_edge_geom(e) == 0
        graph_edge_geom(e) = RR(j);
    end
end
end

function idx = nearestRoutingVertex(lat,lon,vertex_xy,proj)
if isempty(vertex_xy)
    idx = NaN;
    return
end
[x,y] = projfwd(proj,lat,lon);
d2 = (vertex_xy(:,1)-x).^2 + (vertex_xy(:,2)-y).^2;
[~,idx] = min(d2);
end

function [ok,hGlow,hCore] = drawQGISNeonRoute(ax,routing,G,vertex_xy,graph_edge_geom,proj,path_nodes,gps_lat,gps_lon,safe_lat,safe_lon)
% Draw the ordered path from the QGIS topology graph as actual road geometry.
% The dark underlay makes the chosen route visible over the muted road map.

ok = false; hGlow = gobjects(0); hCore = gobjects(0);
if numel(path_nodes) < 2
    return
end

routeLat = [];
routeLon = [];

for k = 1:numel(path_nodes)-1
    e = findedge(G,path_nodes(k),path_nodes(k+1));
    if e == 0
        e = findedge(G,path_nodes(k+1),path_nodes(k));
    end
    if e == 0 || e > numel(graph_edge_geom)
        return
    end

    rid = graph_edge_geom(e);
    if rid < 1 || rid > height(routing)
        return
    end

    [x,y] = shapeToXY(routing.Shape(rid));
    good = isfinite(x) & isfinite(y);
    x=x(good); y=y(good);
    if numel(x) < 2
        return
    end

    pu = vertex_xy(path_nodes(k),:);
    pv = vertex_xy(path_nodes(k+1),:);
    d1 = hypot(x(1)-pu(1),y(1)-pu(2)) + hypot(x(end)-pv(1),y(end)-pv(2));
    d2 = hypot(x(end)-pu(1),y(end)-pu(2)) + hypot(x(1)-pv(1),y(1)-pv(2));
    if d2 < d1
        x=flipud(x); y=flipud(y);
    end

    [la,lo] = projinv(proj,x,y);
    la=la(:); lo=lo(:);
    good=isfinite(la)&isfinite(lo);
    la=la(good); lo=lo(good);
    if numel(la)<2, return; end

    if ~isempty(routeLat)
        dA=hypot(lo(1)-routeLon(end),la(1)-routeLat(end));
        dB=hypot(lo(end)-routeLon(end),la(end)-routeLat(end));
        if dB < dA
            la=flipud(la); lo=flipud(lo);
        end
        if hypot(lo(1)-routeLon(end),la(1)-routeLat(end)) < 1e-8
            la=la(2:end); lo=lo(2:end);
        end
    end

    routeLat=[routeLat;la]; %#ok<AGROW>
    routeLon=[routeLon;lo]; %#ok<AGROW>
end

if numel(routeLat)<2
    return
end

% Add only the short connector from the simulated GPS point and to the safe
% destination; the long middle section is always the actual road geometry.
routeLat = [gps_lat; routeLat; safe_lat];
routeLon = [gps_lon; routeLon; safe_lon];

hDark = plot(ax,routeLon,routeLat,'-',...
    'Color',[0.01 0.02 0.025],...
    'LineWidth',9,...
    'Clipping','on',...
    'Tag','HydroTwinActiveRouteGlow');

hCyan = plot(ax,routeLon,routeLat,'-',...
    'Color',[0 1 1],...
    'LineWidth',4.8,...
    'Clipping','on',...
    'Tag','HydroTwinActiveRoute');

hAccent = plot(ax,routeLon,routeLat,'-',...
    'Color',[0.85 1 1],...
    'LineWidth',0.9,...
    'Clipping','on',...
    'Tag','HydroTwinActiveRouteAccent');

hGlow=[hDark;hAccent];
hCore=hCyan;
ok=true;
end

function [x,y] = shapeToXY(sh)
% Extract planar X/Y coordinates from a projected geospatial shape.
GT = table(sh,'VariableNames',{'Shape'});
T = geotable2table(GT,["X","Y"]);
x = T.X(1); y = T.Y(1);
if iscell(x), x=x{1}; end
if iscell(y), y=y{1}; end
x=x(:); y=y(:);
end

function [ok,hRoute,route_edge_idx] = plotActualOSMRoute(ax,G,node_lat,node_lon,edge_part,parts_lat,parts_lon,...
    start_lat,start_lon,end_lat,end_lon,old_handle)
% Route directly on the OSM road graph between user and safe destination.

ok = false;
hRoute = old_handle;
route_edge_idx = [];

if ~isempty(old_handle)
    good = isgraphics(old_handle);
    if any(good)
        delete(old_handle(good));
    end
end
% Remove any previous route glow lines from this axes.
old_route = findobj(ax,'Tag','HydroTwinActiveRouteGlow');
if ~isempty(old_route)
    delete(old_route);
end

try
    s = nearestOSMNode(start_lat,start_lon,node_lat,node_lon);
    t = nearestOSMNode(end_lat,end_lon,node_lat,node_lon);
    [p,~] = shortestpath(G,s,t);

    if isempty(p) || numel(p)<2
        return
    end

    route_edge_idx = zeros(numel(p)-1,1);
    for k = 1:numel(p)-1
        e = findedge(G,p(k),p(k+1));
        if e == 0
            e = findedge(G,p(k+1),p(k));
        end
        if e == 0
            return
        end
        route_edge_idx(k) = e;
    end

    % Draw each actual OSM road segment in the chosen path.
    new_handles = gobjects(numel(route_edge_idx),1);
    nh = 0;
    for k = 1:numel(route_edge_idx)
        part = edge_part(route_edge_idx(k));
        la = parts_lat{part};
        lo = parts_lon{part};
        good = isfinite(la) & isfinite(lo);
        if nnz(good) >= 2
            % Dark underlay makes the cyan route readable over every road.
            plot(ax,lo(good),la(good),...
                '-','Color',[0.0 0.15 0.18],'LineWidth',8.0,...
                'Clipping','on','HitTest','off','Tag','HydroTwinActiveRouteGlow');
            nh = nh+1;
            new_handles(nh) = plot(ax,lo(good),la(good),...
                '-','Color',[0 1 1],'LineWidth',4.2,...
                'Clipping','on');
        end
    end

    if nh > 0
        hRoute = new_handles(1:nh);
        ok = true;
    end
catch
    ok = false;
end
end


function idx = nearestOSMNode(lat,lon,node_lat,node_lon)
% Nearest road-network node in approximate meters.
clat = cosd(lat);
dx = (node_lon-lon).*clat*111320;
dy = (node_lat-lat)*111320;
[~,idx] = min(dx.^2 + dy.^2);
end


function [G,node_lat,node_lon,edge_part,parts_lat,parts_lon] = buildOSMRoadGraph(roads)
% Build a compact weighted graph from real OSM line geometries.
% Each road-part endpoint becomes a graph node; consecutive road parts are
% connected using the actual road length as the edge weight.

tol_m = 12;   % endpoint snapping tolerance
node_lat = zeros(0,1);
node_lon = zeros(0,1);
edge_s = zeros(0,1);
edge_t = zeros(0,1);
edge_w = zeros(0,1);
edge_part = zeros(0,1);
parts_lat = {};
parts_lon = {};

for r = 1:height(roads)
    try
        [la,lo] = shapeToLatLon(roads.Shape(r));
        parts = splitNaNParts(la,lo);
    catch
        continue
    end

    for q = 1:numel(parts)
        la = parts{q}(:,1);
        lo = parts{q}(:,2);
        good = isfinite(la) & isfinite(lo);
        la = la(good);
        lo = lo(good);
        if numel(la) < 2
            continue
        end

        a = findOrCreateRoadNode(la(1),lo(1),node_lat,node_lon,tol_m);
        if a > numel(node_lat)
            node_lat(a,1) = la(1);
            node_lon(a,1) = lo(1);
        end
        b = findOrCreateRoadNode(la(end),lo(end),node_lat,node_lon,tol_m);
        if b > numel(node_lat)
            node_lat(b,1) = la(end);
            node_lon(b,1) = lo(end);
        end

        part_id = numel(parts_lat)+1;
        parts_lat{part_id,1} = la;
        parts_lon{part_id,1} = lo;

        if a ~= b
            edge_s(end+1,1) = a; %#ok<AGROW>
            edge_t(end+1,1) = b; %#ok<AGROW>
            edge_w(end+1,1) = polylineLengthMeters(la,lo); %#ok<AGROW>
            edge_part(end+1,1) = part_id; %#ok<AGROW>
        end
    end
end

if isempty(edge_s)
    G = graph();
    return
end

% Remove accidental duplicate endpoint pairs while keeping the shortest.
pair_min = containers.Map('KeyType','char','ValueType','double');
keep = false(numel(edge_s),1);
for e = 1:numel(edge_s)
    a = min(edge_s(e),edge_t(e));
    b = max(edge_s(e),edge_t(e));
    key = sprintf('%d_%d',a,b);
    if ~isKey(pair_min,key)
        pair_min(key) = e;
        keep(e) = true;
    else
        old = pair_min(key);
        if edge_w(e) < edge_w(old)
            keep(old) = false;
            keep(e) = true;
            pair_min(key) = e;
        end
    end
end

edge_s = edge_s(keep);
edge_t = edge_t(keep);
edge_w = edge_w(keep);
edge_part = edge_part(keep);

G = graph(edge_s,edge_t,edge_w,numel(node_lat));
end


function idx = findOrCreateRoadNode(lat,lon,node_lat,node_lon,tol_m)
if isempty(node_lat)
    idx = 1;
    return
end
clat = cosd(lat);
dx = (node_lon-lon).*clat*111320;
dy = (node_lat-lat)*111320;
d2 = dx.^2 + dy.^2;
[best,bidx] = min(d2);
if best <= tol_m^2
    idx = bidx;
else
    idx = numel(node_lat)+1;
end
end


function d = polylineLengthMeters(lat,lon)
clat = cosd((lat(1:end-1)+lat(2:end))/2);
dx = (lon(2:end)-lon(1:end-1)).*clat*111320;
dy = (lat(2:end)-lat(1:end-1))*111320;
d = sum(hypot(dx,dy),'omitnan');
end


function parts = splitNaNParts(lat,lon)
lat = lat(:); lon = lon(:);
sep = ~(isfinite(lat) & isfinite(lon));
starts = [1; find(sep(1:end-1))+1];
ends = [find(sep)-1; numel(lat)];
parts = {};
for k = 1:min(numel(starts),numel(ends))
    if starts(k) <= ends(k)
        la = lat(starts(k):ends(k));
        lo = lon(starts(k):ends(k));
        if numel(la) >= 2
            parts{end+1,1} = [la lo]; %#ok<AGROW>
        end
    end
end
end


function setCleanMapView(ax,lat,lon)
% Tight viewport around current user/destination while retaining context.
lat = lat(isfinite(lat));
lon = lon(isfinite(lon));
if isempty(lat) || isempty(lon)
    return
end

lat0 = mean(lat);
lon0 = mean(lon);
spanLat = max(lat)-min(lat);
spanLon = max(lon)-min(lon);

% Minimum useful viewing window: about 1.2 km x 1.2 km.
minLat = 0.012;
minLon = 0.012/max(cosd(lat0),0.2);

spanLat = max(spanLat*2.8,minLat);
spanLon = max(spanLon*2.8,minLon);

xlim(ax,[lon0-spanLon/2,lon0+spanLon/2]);
ylim(ax,[lat0-spanLat/2,lat0+spanLat/2]);
end


%% ========================================================================
% LOCAL FUNCTIONS: GSI CLASSIFICATION + RANDOM GSI SPAWN
% =========================================================================
function class_name = classifyGSIpoint(lat,lon,gsi,gsi_class)
%CLASSIFYGSIPOINT Classify one latitude/longitude point using GSI polygons.

class_name = "Unknown";

if isempty(gsi)
    return
end

% Check High first, then Moderate, then Low.
for wanted = ["high","moderate","low"]
    for p = 1:height(gsi)
        if ~contains(lower(strtrim(string(gsi_class(p)))),wanted)
            continue
        end

        try
            sh = gsi.Shape(p);
            ctype = string(sh.CoordinateSystemType);

            if strcmpi(ctype,"geographic")
                q = geopointshape(lat,lon);
                try
                    if ~isempty(sh.GeographicCRS)
                        q.GeographicCRS = sh.GeographicCRS;
                    end
                catch
                end
            else
                proj = sh.ProjectedCRS;
                [x,y] = projfwd(proj,lat,lon);
                q = mappointshape(x,y);
                q.ProjectedCRS = proj;
            end

            if isinterior(sh,q)
                if wanted == "high"
                    class_name = "High";
                elseif wanted == "moderate"
                    class_name = "Moderate";
                else
                    class_name = "Low";
                end
                return
            end
        catch
            % Continue with the next polygon.
        end
    end
end
end

function class_name = classifyRoutingEdgeGSI(sh,gsi,gsi_class)
%CLASSIFYROUTINGEDGEGSI Classify a real QGIS road link.
% Samples several points along the link and returns the highest
% susceptibility class touched by the road geometry.

class_name = "Unknown";

if isempty(gsi) || isempty(sh)
    return
end

try
    [x,y] = shapeToXY(sh);
    good = isfinite(x) & isfinite(y);
    x = x(good);
    y = y(good);

    if numel(x) < 2
        return
    end

    % Sample the road every ~75 m (plus both endpoints) so a road crossing
    % a GSI boundary is not missed just because its endpoints are outside.
    cumulative_m = [0; cumsum(hypot(diff(x),diff(y)))];
    total_m = cumulative_m(end);
    n_samples = max(3,min(30,ceil(total_m/75)+1));
    sample_m = linspace(0,total_m,n_samples);
    sample_x = interp1(cumulative_m,x,sample_m,'linear','extrap');
    sample_y = interp1(cumulative_m,y,sample_m,'linear','extrap');

    sampled_classes = strings(numel(sample_m),1);
    proj = sh.ProjectedCRS;

    for q = 1:numel(sample_m)
        [lat,lon] = projinv(proj,sample_x(q),sample_y(q));
        sampled_classes(q) = classifyGSIpoint(lat,lon,gsi,gsi_class);
    end

    if any(strcmpi(sampled_classes,"High"))
        class_name = "High";
    elseif any(strcmpi(sampled_classes,"Moderate"))
        class_name = "Moderate";
    elseif any(strcmpi(sampled_classes,"Low"))
        class_name = "Low";
    else
        class_name = "Unknown";
    end
catch
    class_name = "Unknown";
end
end

function [lat,lon,ok] = randomPointOnRoutingRoadInGSIClass( ...
    wanted,routing,proj,gsi,gsi_class,lat_lim,lon_lim)
%RANDOMPOINTONROUTINGROADINGISICLASS
% Pick a random point on a real QGIS routing road whose location falls
% inside the requested GSI susceptibility class.
%
% This is deliberately road-constrained: GSI polygons can extend beyond
% the mapped road network, so sampling anywhere inside a polygon can place
% the simulated user in a visually disconnected/off-road area.

lat = NaN;
lon = NaN;
ok = false;

if isempty(routing) || isempty(gsi)
    return
end

wanted = lower(strtrim(string(wanted)));
num_edges = height(routing);

% Randomize edge order so repeated runs do not always select the same road.
edge_order = randperm(num_edges);

for ii = 1:num_edges
    row = edge_order(ii);

    try
        sh = routing.Shape(row);
        [x,y] = shapeToXY(sh);

        good = isfinite(x) & isfinite(y);
        x = x(good);
        y = y(good);

        if numel(x) < 2
            continue
        end

        cumulative_m = [0; cumsum(hypot(diff(x),diff(y)))];
        total_m = cumulative_m(end);

        if ~isfinite(total_m) || total_m <= 0
            continue
        end

        % Test several positions along this road segment.
        n_samples = max(5,min(20,ceil(total_m/100)+1));
        sample_m = linspace(0,total_m,n_samples);
        sample_x = interp1(cumulative_m,x,sample_m,'linear');
        sample_y = interp1(cumulative_m,y,sample_m,'linear');

        sample_order = randperm(numel(sample_m));

        for jj = sample_order
            [test_lat,test_lon] = projinv(proj,sample_x(jj),sample_y(jj));

            if ~isfinite(test_lat) || ~isfinite(test_lon)
                continue
            end

            if test_lat < lat_lim(1) || test_lat > lat_lim(2) || ...
               test_lon < lon_lim(1) || test_lon > lon_lim(2)
                continue
            end

            actual_class = lower(strtrim(string( ...
                classifyGSIpoint(test_lat,test_lon,gsi,gsi_class))));

            if strcmpi(actual_class,wanted)
                lat = test_lat;
                lon = test_lon;
                ok = true;
                return
            end
        end
    catch
        % Skip this road segment and continue searching.
    end
end
end

function [lat,lon,actual_class,ok] = spawnRoutingTestPerson( ...
    preferred_class,routing,proj,gsi,gsi_class,lat_lim,lon_lim)
%SPAWNROUTINGTESTPERSON
% Place the second demonstration person on a real routing road.
% Preferred class is Moderate; High is the fallback for robustness.

lat = NaN;
lon = NaN;
actual_class = "Unknown";
ok = false;

preferred_class = string(preferred_class);

[lat,lon,ok] = randomPointOnRoutingRoadInGSIClass( ...
    preferred_class,routing,proj,gsi,gsi_class,lat_lim,lon_lim);

if ok
    actual_class = preferred_class;
    return
end

% Moderate may have fewer road samples than the polygon itself. Try High.
fallback_class = "High";

[lat,lon,ok] = randomPointOnRoutingRoadInGSIClass( ...
    fallback_class,routing,proj,gsi,gsi_class,lat_lim,lon_lim);

if ok
    actual_class = fallback_class;
end
end

function out = ternaryText(condition,true_text,false_text)
%TERNARYTEXT Small text helper for UI strings.
if condition
    out = true_text;
else
    out = false_text;
end
end

function [lat,lon,ok] = randomPointInGSIClass(wanted,gsi,gsi_class,lat_lim,lon_lim)
%RANDOMPOINTINGSICLASS Generate a random point inside the requested GSI class.

lat = NaN;
lon = NaN;
ok = false;

if isempty(gsi)
    return
end

wanted = lower(strtrim(string(wanted)));

candidate_rows = find(contains(lower(strtrim(string(gsi_class))),wanted));

if isempty(candidate_rows)
    return
end

% Repeated random sampling avoids placing the user outside polygon holes or
% outside the requested map window.
for attempt = 1:5000
    row = candidate_rows(randi(numel(candidate_rows)));

    try
        sh = gsi.Shape(row);
        [shape_lat,shape_lon] = shapeToLatLon(sh);
        good = isfinite(shape_lat) & isfinite(shape_lon);

        shape_lat = shape_lat(good);
        shape_lon = shape_lon(good);

        if isempty(shape_lat)
            continue
        end

        lat_lo = max(min(shape_lat),lat_lim(1));
        lat_hi = min(max(shape_lat),lat_lim(2));
        lon_lo = max(min(shape_lon),lon_lim(1));
        lon_hi = min(max(shape_lon),lon_lim(2));

        if lat_lo >= lat_hi || lon_lo >= lon_hi
            continue
        end

        test_lat = lat_lo + rand*(lat_hi-lat_lo);
        test_lon = lon_lo + rand*(lon_hi-lon_lo);

        if strcmpi(classifyGSIpoint(test_lat,test_lon,gsi,gsi_class),wanted)
            lat = test_lat;
            lon = test_lon;
            ok = true;
            return
        end
    catch
        % Try another random polygon/sample.
    end
end
end

function [lat,lon] = shapeCenterLatLon(sh)
% Geographic center of a line shape.
[lat,lon] = shapeToLatLon(sh);
good = isfinite(lat) & isfinite(lon);
if any(good)
    lat = mean(lat(good));
    lon = mean(lon(good));
else
    lat = NaN;
    lon = NaN;
end
end


function [lat,lon] = shapeToLatLon(sh)
% Convert supported MATLAB geographic/projected line or polygon shapes
% into latitude/longitude arrays for the standard UI map axes.

lat = [];
lon = [];
ctype = string(sh.CoordinateSystemType);

if strcmpi(ctype,"geographic")
    GT = table(sh,'VariableNames',{'Shape'});
    T = geotable2table(GT,["Latitude","Longitude"]);
    lat = T.Latitude(1);
    lon = T.Longitude(1);
    if iscell(lat), lat = lat{1}; end
    if iscell(lon), lon = lon{1}; end
    lat = lat(:);
    lon = lon(:);
    return
end

% Planar/projected shape.
GT = table(sh,'VariableNames',{'Shape'});
T = geotable2table(GT,["X","Y"]);
x = T.X(1);
y = T.Y(1);
if iscell(x), x = x{1}; end
if iscell(y), y = y{1}; end
proj = sh.ProjectedCRS;

if iscell(x)
    lat = [];
    lon = [];
    for k = 1:numel(x)
        if isempty(x{k}), continue; end
        [latk,lonk] = projinv(proj,x{k},y{k});
        lat = [lat; latk(:); NaN]; %#ok<AGROW>
        lon = [lon; lonk(:); NaN]; %#ok<AGROW>
    end
else
    [lat,lon] = projinv(proj,x,y);
    lat = lat(:);
    lon = lon(:);
end

end

