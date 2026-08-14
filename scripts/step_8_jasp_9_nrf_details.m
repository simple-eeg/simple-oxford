%% step_8_jasp_9_nrf_details.m
% Read-only inspection script for three EEG NRF templates.
%
% This script:
% - loads three existing NRF .mat files,
% - verifies expected contents,
% - plots each NRF in its own subplot on a common fake EEG epoch axis,
% - creates a compact MATLAB summary table,
% - saves nothing, and modifies nothing on disk.
%
% Assumptions for each .mat file:
% - contains variable 'NRF' (numeric vector)
% - contains variable 'fs'  (numeric scalar sampling rate)
%
% Notes:
% - L2 normalisation is used to make each NRF unitless for visual comparison.
% - User-defined display scaling is applied after L2 normalisation.
% - Optional smoothing affects only peak-latency estimation.
% - Plotting uses EEG convention with positive values down.

log_command_window('start');
clear; clc; close all;

%% ------------------------------------------------------------------------
% USER CONFIG
% -------------------------------------------------------------------------

baseDir = '/Users/lukebaxter/Developer/simple-eeg/simple-oxford';
functionsDir = fullfile(baseDir, 'functions');
addpath(functionsDir, '-begin');
clear NRFUtils;
rehash toolboxcache;

expectedNRFUtilsFile = char(java.io.File( ...
    fullfile(functionsDir, 'NRFUtils.m')).getCanonicalPath());
resolvedNRFUtilsFile = which('NRFUtils');
if isempty(resolvedNRFUtilsFile)
    error('SIMPLE:LocalHelperUnresolved', ...
        'Required local helper did not resolve: NRFUtils');
end
resolvedNRFUtilsFile = char(java.io.File( ...
    resolvedNRFUtilsFile).getCanonicalPath());
if ~strcmp(resolvedNRFUtilsFile, expectedNRFUtilsFile)
    error('SIMPLE:LocalHelperShadowed', ...
        ['NRFUtils resolved outside this repository. Expected %s; ' ...
         'resolved %s.'], expectedNRFUtilsFile, resolvedNRFUtilsFile);
end

% =========================================================================
% A. File and NRF identity settings
% =========================================================================
earlyNRFName    = 'early_NRF_500Hz';
noxiousNRFName  = 'noxious_NRF_500Hz';
pretermNRFName  = 'noxious_preterm_NRF_500Hz';
nrfDisplayNames = {'Early', 'Noxious', 'Noxious preterm'};

% =========================================================================
% B. Projection and display-scaling settings
% =========================================================================
earlyStartMs    = 100;
noxiousStartMs  = 400;
pretermStartMs  = 0;

earlyScale      = 1;
noxiousScale    = 1;
pretermScale    = 1;

% =========================================================================
% C. Epoch-support and axis settings
% =========================================================================
fsExpected      = 500;
supportStartMs  = 0;
supportEndMs    = 1200;
visibleXLimMs   = [0 1000];
invertYAxis     = true;

% =========================================================================
% D. Plot appearance settings
% =========================================================================
earlyColor      = [0 0.4470 0.7410];
noxiousColor    = [0 0.4470 0.7410];
pretermColor    = [0 0.4470 0.7410];
zeroLineColor   = [0.4 0.4 0.4];
zeroLineStyle   = '--';
nrfLineWidth    = 2;
zeroLineWidth   = 1;

% =========================================================================
% E. Peak-detection settings
% =========================================================================
usePeakSmoothing        = false;
peakSmoothingMethod     = 'gaussian';
peakSmoothingWidthSamps = 5;

% =========================================================================
% F. Table metadata settings
% =========================================================================
earlyN              = 54;
noxiousN            = 18;
pretermN            = 30;

earlyPMAMin         = 36.6;
earlyPMAMax         = 42.6;
noxiousPMAMin       = 37.1;
noxiousPMAMax       = 42.7;
pretermPMAMin       = 30.0;
pretermPMAMax       = 33.6;

earlyProcedure      = 'heel lance';
noxiousProcedure    = 'heel lance';
pretermProcedure    = 'heel lance';

earlyPublication    = 'Cobo 2022';
noxiousPublication  = 'Hartley 2017';
pretermPublication  = 'van der Vaart 2022';

%% ------------------------------------------------------------------------
% INITIALISE DERIVED SUPPORT STRUCTURES
% -------------------------------------------------------------------------
sampleIntervalMs = 1000 / fsExpected;
supportTimeMs    = supportStartMs:sampleIntervalMs:supportEndMs;
nSupportSamples  = numel(supportTimeMs);

templateReferences = {earlyNRFName, noxiousNRFName, pretermNRFName};
logicalNRFNames = cell(size(templateReferences));
canonicalNRFFiles = cell(size(templateReferences));
for i = 1:numel(templateReferences)
    [logicalNRFNames{i}, canonicalNRFFiles{i}] = ...
        NRFUtils.resolveTemplateFile(templateReferences{i}, baseDir);
end

startMs   = [earlyStartMs, noxiousStartMs, pretermStartMs];
scales    = [earlyScale, noxiousScale, pretermScale];
colors    = {earlyColor, noxiousColor, pretermColor};

metaN = [earlyN, noxiousN, pretermN];
metaPMAMin = [earlyPMAMin, noxiousPMAMin, pretermPMAMin];
metaPMAMax = [earlyPMAMax, noxiousPMAMax, pretermPMAMax];
metaProcedure = {earlyProcedure, noxiousProcedure, pretermProcedure};
metaPublication = {earlyPublication, noxiousPublication, pretermPublication};

%% ------------------------------------------------------------------------
% PREALLOCATE OUTPUT CONTAINERS
% -------------------------------------------------------------------------
nNRF = numel(logicalNRFNames);

rawNRFs          = cell(1, nNRF);
loadedFs         = nan(1, nNRF);
normNRFs         = cell(1, nNRF);
scaledNRFs       = cell(1, nNRF);
projectedNRFs    = cell(1, nNRF);

durationsMs      = nan(1, nNRF);
polarityLabels   = cell(1, nNRF);
peakLatencyMs    = nan(1, nNRF);

%% ------------------------------------------------------------------------
% LOOP OVER THE THREE NRF FILES
% -------------------------------------------------------------------------
for i = 1:nNRF
    thisPath = canonicalNRFFiles{i};

    if ~isfile(thisPath)
        error('File not found: %s', thisPath);
    end

    S = load(thisPath);

    if ~isfield(S, 'NRF')
        error('Missing variable ''NRF'' in file: %s', thisPath);
    end
    if ~isfield(S, 'fs')
        error('Missing variable ''fs'' in file: %s', thisPath);
    end

    if ~(isnumeric(S.fs) && isscalar(S.fs) && isfinite(S.fs))
        error('Variable ''fs'' must be a finite numeric scalar in file: %s', thisPath);
    end
    if S.fs ~= fsExpected
        error('Unexpected fs in file %s. Expected %g, found %g.', thisPath, fsExpected, S.fs);
    end

    if ~(isnumeric(S.NRF) && isvector(S.NRF) && ~isempty(S.NRF) && all(isfinite(S.NRF)))
        error('Variable ''NRF'' must be a non-empty finite numeric vector in file: %s', thisPath);
    end

    thisNRF = S.NRF(:);
    thisFs  = S.fs;

    rawNRFs{i}  = thisNRF;
    loadedFs(i) = thisFs;

    nSamples = numel(thisNRF);
    durationsMs(i) = (nSamples - 1) * 1000 / thisFs;

    thisL2 = norm(thisNRF, 2);
    if ~(isfinite(thisL2) && thisL2 > 0)
        error('Invalid L2 norm for NRF in file: %s', thisPath);
    end

    thisNormNRF   = thisNRF / thisL2;
    thisScaledNRF = thisNormNRF * scales(i);

    normNRFs{i}   = thisNormNRF;
    scaledNRFs{i} = thisScaledNRF;

    withinTimeMs = (0:nSamples-1)' * (1000 / thisFs);
    epochTimeMs  = startMs(i) + withinTimeMs;

    projectedVec = nan(nSupportSamples, 1);

    roundedEpochTime = round(epochTimeMs, 10);
    roundedSupport   = round(supportTimeMs(:), 10);

    [isMember, idxSupport] = ismember(roundedEpochTime, roundedSupport);
    projectedVec(idxSupport(isMember)) = thisScaledNRF(isMember);

    projectedNRFs{i} = projectedVec;

    % Peak detection relative to the first sample only.
    % This affects peak latency and polarity.
    shiftedNRF = thisNRF - thisNRF(1);

    % Optional smoothing for peak-location detection only
    peakDetectVec = shiftedNRF;
    if usePeakSmoothing
        if ~(isscalar(peakSmoothingWidthSamps) && isnumeric(peakSmoothingWidthSamps) && ...
                isfinite(peakSmoothingWidthSamps) && peakSmoothingWidthSamps >= 1 && ...
                mod(peakSmoothingWidthSamps, 1) == 0)
            error('peakSmoothingWidthSamps must be a positive integer.');
        end
        peakDetectVec = smoothdata(peakDetectVec, 1, peakSmoothingMethod, peakSmoothingWidthSamps);
    end

    [~, peakIdxDetect] = max(abs(peakDetectVec));
    peakLatencyMs(i) = startMs(i) + (peakIdxDetect - 1) * (1000 / thisFs);

    % Polarity taken from the raw unsmoothed shifted NRF at the same peak
    dominantValueRaw = shiftedNRF(peakIdxDetect);

    if dominantValueRaw > 0
        polarityLabels{i} = 'Positive';
    elseif dominantValueRaw < 0
        polarityLabels{i} = 'Negative';
    else
        polarityLabels{i} = 'Flat/unclear';
    end
end

%% ------------------------------------------------------------------------
% CREATE ZERO-LINE VECTOR
% -------------------------------------------------------------------------
zeroLineVec = zeros(size(supportTimeMs));

%% ------------------------------------------------------------------------
% BUILD SUMMARY TABLE CONTENT
% -------------------------------------------------------------------------
rowNames = { ...
    'ConstructionPublication', ...
    'ConstructionProcedure', ...
    'ConstructionPMARange', ...
    'ConstructionSample', ...
    'PeakLatency', ...
    'DeflectionPolarity', ...
    'Duration'};

tableValues = strings(numel(rowNames), nNRF);

for i = 1:nNRF
    tableValues(1, i) = string(metaPublication{i});
    tableValues(2, i) = string(metaProcedure{i});
    tableValues(3, i) = sprintf('%.1f to %.1f weeks', metaPMAMin(i), metaPMAMax(i));
    tableValues(4, i) = sprintf('n = %d', metaN(i));
    tableValues(5, i) = sprintf('%g ms', peakLatencyMs(i));
    tableValues(6, i) = string(polarityLabels{i});
    tableValues(7, i) = sprintf('%g ms', durationsMs(i));
end

nrfSummaryTable = table( ...
    tableValues(:,1), ...
    tableValues(:,2), ...
    tableValues(:,3), ...
    'VariableNames', {'Early', 'Noxious', 'NoxiousPreterm'}, ...
    'RowNames', rowNames);

%% ------------------------------------------------------------------------
% CREATE FIGURE
% -------------------------------------------------------------------------
figure('Name', 'NRF details', 'Color', 'w');

for i = 1:nNRF
    subplot(3, 1, i);
    hold on;

    plot(supportTimeMs, zeroLineVec, ...
        'Color', zeroLineColor, ...
        'LineStyle', zeroLineStyle, ...
        'LineWidth', zeroLineWidth, ...
        'HandleVisibility', 'off');

    plot(supportTimeMs, projectedNRFs{i}, ...
        'Color', colors{i}, ...
        'LineWidth', nrfLineWidth, ...
        'DisplayName', nrfDisplayNames{i});

    xlim(visibleXLimMs);
    xlabel('Time (ms)');
    ylabel('Unitless amplitude');
    legend('Location', 'northeast');
    set(gca, 'TickDir', 'out');
    box off;

    if invertYAxis
        set(gca, 'YDir', 'reverse');
    end

    hold off;
end

%% ------------------------------------------------------------------------
% DISPLAY TABLE
% -------------------------------------------------------------------------
disp(' ');
disp('NRF summary table:');
disp(nrfSummaryTable);

log_command_window('stop');
