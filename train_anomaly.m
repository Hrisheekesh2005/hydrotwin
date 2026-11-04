% =========================================================================
% train_anomaly.m
% Sensor-health anomaly model for HydroTwin Pro
% =========================================================================

clc;
clear;
close all;

rng(7);  % Reproducible training

disp('Generating healthy sensor operating range...');

% Healthy water-level measurements expected by the prototype.
% This model is a SENSOR-VALIDITY failsafe, not a flood predictor.
healthy_min = 0.5;   % m
healthy_max = 5.5;   % m
training_data = healthy_min + ...
    (healthy_max - healthy_min) * rand(2000,1);

disp('Training Machine Learning sensor-health failsafe...');

% About 1% of healthy-training samples are allowed to define the anomaly
% boundary. The runtime code also has explicit physical/rate checks.
anomaly_model = iforest(training_data, 'Contamination', 0.01);

save('sensor_health_model.mat', ...
    'anomaly_model', 'healthy_min', 'healthy_max');

disp('SUCCESS: Sensor-health AI model saved!');