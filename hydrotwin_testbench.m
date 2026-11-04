% =========================================================================
% hydrotwin_testbench.m
% HydroTwin Pro - Scenario Testbench
% =========================================================================
% Edit SCENARIO_NAME below and run this file.
% The testbench writes hydrotwin_scenario.mat beside itself, verifies it,
% then runs main_hydrotwin.m from the same folder.
% =========================================================================

clc;
clear;
close all;

%% TESTBENCH LOCATION
TESTBENCH_FOLDER = fileparts(mfilename('fullpath'));
if isempty(TESTBENCH_FOLDER)
    TESTBENCH_FOLDER = pwd;
end
cd(TESTBENCH_FOLDER);

SCENARIO_FILE = fullfile(TESTBENCH_FOLDER,'hydrotwin_scenario.mat');
MAIN_FILE = fullfile(TESTBENCH_FOLDER,'main_hydrotwin.m');

%% SELECT SCENARIO
SCENARIO_NAME = "flood";

%% COMMON SETTINGS
total_steps = 300;
dt = 1;
time_vector = (0:total_steps-1)*dt;
rng(7);

%% CUSTOM SETTINGS
custom_base_level = 1.0;
custom_final_level = 4.6;
custom_rise_start = 80;
custom_rise_end = 140;
custom_rain_base = 8;
custom_rain_peak = 120;
custom_sensor_noise = 0.04;
custom_failure_start = 200;
custom_failure_end = 230;
custom_enable_failure = true;

%% INITIAL SCENARIO
scenario = struct();
scenario.name = "Uninitialized";
scenario.condition = "normal";
scenario.total_steps = total_steps;
scenario.dt = dt;
scenario.time_vector = time_vector;
scenario.water_level = ones(1,total_steps);
scenario.rainfall = 8*ones(1,total_steps);
scenario.sensor_failure = false(1,total_steps);
scenario.sensor_noise_std = 0.04;
scenario.sensor_failure_level = 0.03;
scenario.sensor_failure_noise_std = 0.01;

%% BUILD SCENARIO
switch lower(strtrim(string(SCENARIO_NAME)))

    case "normal"
        scenario.name = "Normal Conditions";
        scenario.condition = "normal";
        scenario.water_level = 1.0*ones(1,total_steps);
        scenario.rainfall = 8.0*ones(1,total_steps);

    case "flood"
        scenario.name = "Standard Flood";
        scenario.condition = "flood";

        rise_start = 80;
        rise_end = 140;

        scenario.water_level = 1.0*ones(1,total_steps);
        scenario.water_level(rise_start:rise_end) = ...
            linspace(1.0,4.6,rise_end-rise_start+1);
        scenario.water_level(rise_end+1:end) = 4.6;

        scenario.rainfall = 8.0*ones(1,total_steps);
        scenario.rainfall(rise_start:rise_end) = ...
            linspace(8.0,120.0,rise_end-rise_start+1);
        scenario.rainfall(rise_end+1:end) = 120.0;

        scenario.sensor_failure(200:230) = true;

    case "warning"
        scenario.name = "Warning-Level Flood";
        scenario.condition = "flood_warning";

        rise_start = 80;
        rise_end = 140;
        scenario.water_level = 1.0*ones(1,total_steps);
        scenario.water_level(rise_start:rise_end) = ...
            linspace(1.0,3.4,rise_end-rise_start+1);
        scenario.water_level(rise_end+1:end) = 3.4;

        scenario.rainfall = 8.0*ones(1,total_steps);
        scenario.rainfall(rise_start:rise_end) = ...
            linspace(8.0,90.0,rise_end-rise_start+1);
        scenario.rainfall(rise_end+1:end) = 90.0;

    case "extreme"
        scenario.name = "Extreme Flood";
        scenario.condition = "extreme_flood";

        rise_start = 50;
        rise_end = 100;
        scenario.water_level = 1.0*ones(1,total_steps);
        scenario.water_level(rise_start:rise_end) = ...
            linspace(1.0,5.2,rise_end-rise_start+1);
        scenario.water_level(rise_end+1:end) = 5.2;

        scenario.rainfall = 15.0*ones(1,total_steps);
        scenario.rainfall(rise_start:rise_end) = ...
            linspace(15.0,150.0,rise_end-rise_start+1);
        scenario.rainfall(rise_end+1:end) = 150.0;

    case "sensor_failure"
        scenario.name = "Normal Water + Sensor Failure";
        scenario.condition = "sensor_failure_test";
        scenario.water_level = 1.0*ones(1,total_steps);
        scenario.rainfall = 8.0*ones(1,total_steps);
        scenario.sensor_failure(200:230) = true;

    case "custom"
        scenario.name = "Custom User Scenario";
        scenario.condition = "custom";

        if custom_rise_start < 1 || custom_rise_end < custom_rise_start || ...
                custom_rise_end > total_steps
            error('HydroTwin_TestBench:BadRiseWindow', ...
                'Invalid custom rise window.');
        end

        scenario.water_level = custom_base_level*ones(1,total_steps);
        scenario.water_level(custom_rise_start:custom_rise_end) = ...
            linspace(custom_base_level,custom_final_level, ...
            custom_rise_end-custom_rise_start+1);
        scenario.water_level(custom_rise_end+1:end) = custom_final_level;

        scenario.rainfall = custom_rain_base*ones(1,total_steps);
        scenario.rainfall(custom_rise_start:custom_rise_end) = ...
            linspace(custom_rain_base,custom_rain_peak, ...
            custom_rise_end-custom_rise_start+1);
        scenario.rainfall(custom_rise_end+1:end) = custom_rain_peak;

        scenario.sensor_noise_std = custom_sensor_noise;

        if custom_enable_failure
            if custom_failure_start < 1 || custom_failure_end < custom_failure_start || ...
                    custom_failure_end > total_steps
                error('HydroTwin_TestBench:BadFailureWindow', ...
                    'Invalid custom sensor-failure window.');
            end
            scenario.sensor_failure(custom_failure_start:custom_failure_end) = true;
        end

    otherwise
        error('HydroTwin_TestBench:UnknownScenario', ...
            'Unknown SCENARIO_NAME: %s',SCENARIO_NAME);
end

%% DELETE ANY OLD SCENARIO FILE
if isfile(SCENARIO_FILE)
    delete(SCENARIO_FILE);
end

%% SAVE FRESH SCENARIO
save(SCENARIO_FILE,'scenario','-v7');

%% VERIFY THE FILE WE JUST SAVED
S = load(SCENARIO_FILE,'scenario');
required = {'name','condition','water_level','rainfall','sensor_failure'};
for i = 1:numel(required)
    if ~isfield(S.scenario,required{i})
        error('HydroTwin_TestBench:MissingField', ...
            'Freshly saved scenario is missing field: %s',required{i});
    end
end

fprintf('\n============================================================\n');
fprintf(' HYDROTWIN TESTBENCH\n');
fprintf('============================================================\n');
fprintf('Testbench folder : %s\n',TESTBENCH_FOLDER);
fprintf('Scenario         : %s\n',string(scenario.name));
fprintf('Condition        : %s\n',string(scenario.condition));
fprintf('Peak water       : %.2f m\n',max(scenario.water_level));
fprintf('Peak rainfall    : %.1f mm/hr\n',max(scenario.rainfall));
fprintf('Sensor failures  : %d samples\n',sum(scenario.sensor_failure));
fprintf('Scenario file    : %s\n',SCENARIO_FILE);
fprintf('Scenario check   : PASSED\n');
fprintf('============================================================\n\n');

%% RUN MAIN FROM THE SAME FOLDER
if ~isfile(MAIN_FILE)
    error('HydroTwin_TestBench:MainMissing', ...
        'main_hydrotwin.m was not found in %s',TESTBENCH_FOLDER);
end

fprintf('[OK] Running main_hydrotwin.m from the same folder...\n\n');
run(MAIN_FILE);
