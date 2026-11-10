%% step_8_gen_3_nrf_details.m
% Create and save:
%   Supplementary Table 6. NRF template-derivation and fitting details.
%   Supplementary Figure 13. NRF template visualisations.
%
% This script:
% - loads three existing NRF .mat files,
% - verifies their expected contents,
% - plots each NRF in its own subplot on a common fake EEG epoch axis,
% - creates a manuscript-shaped MATLAB summary table,
% - saves the table as UTF-8 CSV with a byte-order mark for reliable direct
%   opening in Microsoft Excel, and saves the figure as a vector PDF under
%   data/results.
%
% Assumptions for each .mat file:
% - contains variable 'NRF' (a non-empty, finite, real numeric vector)
% - contains variable 'fs'  (numeric scalar sampling rate)
%
% Notes:
% - Each curve shows the stored NRF samples at their projection times.
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

resultsDir = fullfile(baseDir, 'data', 'results');
tableOutPath = fullfile(resultsDir, ...
    'supplementary_table_4_nrf_template_derivation_and_fitting_details.csv');
figureOutPath = fullfile(resultsDir, ...
    'supplementary_figure_1_nrf_template_visualisations.pdf');

% =========================================================================
% A. File and NRF identity settings
% =========================================================================
earlyNRFName    = 'early_NRF_500Hz';
noxiousNRFName  = 'noxious_NRF_500Hz';
pretermNRFName  = 'noxious_preterm_NRF_500Hz';
nrfDisplayNames = {'Early', 'Noxious', 'Noxious preterm'};

% =========================================================================
% B. Projection and jitter settings
% =========================================================================
earlyStartMs    = 100;
noxiousStartMs  = 400;
pretermStartMs  = 0;

earlyJitterMs   = 100;
noxiousJitterMs = 100;
pretermJitterMs = 100;

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
pretermN            = 47;

earlyPMAMin         = 36.6;
earlyPMAMax         = 42.6;
noxiousPMAMin       = 37.1;
noxiousPMAMax       = 42.7;
pretermPMAMin       = 28.1;
pretermPMAMax       = 39.7;

earlyProcedure      = 'Heel lance';
noxiousProcedure    = 'Heel lance';
pretermProcedure    = 'Heel lance';

earlyPublication    = 'Cobo et al., 2022';
noxiousPublication  = 'Hartley et al., 2017';
pretermPublication  = 'van der Vaart et al., 2022';

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
jitterMs  = [earlyJitterMs, noxiousJitterMs, pretermJitterMs];
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

projectedNRFs    = cell(1, nNRF);

durationsMs      = nan(1, nNRF);
polarityLabels   = cell(1, nNRF);
peakLatencyMs    = nan(1, nNRF);

%% ------------------------------------------------------------------------
% LOAD AND VALIDATE THE THREE NRF FILES
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
        error(['Variable ''fs'' must be a finite numeric scalar in ' ...
            'file: %s'], thisPath);
    end
    if S.fs ~= fsExpected
        error('Unexpected fs in file %s. Expected %g, found %g.', ...
            thisPath, fsExpected, S.fs);
    end
    if ~(isnumeric(S.NRF) && isreal(S.NRF) && isvector(S.NRF) && ...
            ~isempty(S.NRF) && all(isfinite(S.NRF)))
        error(['Variable ''NRF'' must be a non-empty finite real numeric ' ...
            'vector in file: %s'], thisPath);
    end

    thisNRF = S.NRF(:);
    thisFs = S.fs;

    nSamples = numel(thisNRF);
    durationsMs(i) = (nSamples - 1) * 1000 / thisFs;

    withinTimeMs = (0:nSamples-1)' * (1000 / thisFs);
    epochTimeMs = startMs(i) + withinTimeMs;
    projectedVec = nan(nSupportSamples, 1);

    roundedEpochTime = round(epochTimeMs, 10);
    roundedSupport = round(supportTimeMs(:), 10);
    [isMember, idxSupport] = ismember(roundedEpochTime, roundedSupport);
    projectedVec(idxSupport(isMember)) = thisNRF(isMember);
    projectedNRFs{i} = projectedVec;

    % Table latency and polarity use deflection from the first template sample.
    shiftedNRF = thisNRF - thisNRF(1);
    peakDetectVec = shiftedNRF;
    if usePeakSmoothing
        if ~(isscalar(peakSmoothingWidthSamps) && ...
                isnumeric(peakSmoothingWidthSamps) && ...
                isfinite(peakSmoothingWidthSamps) && ...
                peakSmoothingWidthSamps >= 1 && ...
                mod(peakSmoothingWidthSamps, 1) == 0)
            error('peakSmoothingWidthSamps must be a positive integer.');
        end
        peakDetectVec = smoothdata(peakDetectVec, 1, ...
            peakSmoothingMethod, peakSmoothingWidthSamps);
    end

    [~, peakIdxDetect] = max(abs(peakDetectVec));
    peakLatencyMs(i) = startMs(i) + ...
        (peakIdxDetect - 1) * (1000 / thisFs);

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
% BUILD THE MANUSCRIPT-SHAPED SUMMARY TABLE
% -------------------------------------------------------------------------
Detail = [ ...
    "Publication"; ...
    "Clinical Procedure"; ...
    "PMA Range (weeks)"; ...
    "Sample size (n)"; ...
    "Deflection Polarity"; ...
    "NRF Start Latency (ms)"; ...
    "NRF Duration (ms)"; ...
    "NRF Peak Latency (ms)"; ...
    "Jitter allowance (ms)"];

tableValues = strings(numel(Detail), nNRF);
for i = 1:nNRF
    tableValues(1, i) = string(metaPublication{i});
    tableValues(2, i) = string(metaProcedure{i});
    tableValues(3, i) = sprintf('%.1f – %.1f', ...
        metaPMAMin(i), metaPMAMax(i));
    tableValues(4, i) = sprintf('%d', metaN(i));
    tableValues(5, i) = string(polarityLabels{i});
    tableValues(6, i) = sprintf('%g', startMs(i));
    tableValues(7, i) = sprintf('%g', durationsMs(i));
    tableValues(8, i) = sprintf('%g', peakLatencyMs(i));
    tableValues(9, i) = sprintf('±%g', jitterMs(i));
end

supplementaryTable4 = table( ...
    Detail, ...
    tableValues(:, 1), ...
    tableValues(:, 2), ...
    tableValues(:, 3), ...
    'VariableNames', { ...
        'Detail', ...
        'Early NRF', ...
        'Later Noxious NRF', ...
        'Preterm Noxious NRF'});

%% ------------------------------------------------------------------------
% CREATE FIGURE
% -------------------------------------------------------------------------
zeroLineVec = zeros(size(supportTimeMs));
nrfFigure = figure( ...
    'Name', 'NRF details', ...
    'Color', 'w', ...
    'Units', 'centimeters', ...
    'Position', [2 2 15.92 10.13]);

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

disp(' ');
disp(['Supplementary Table 6. NRF template-derivation and ' ...
    'fitting details.']);
disp(supplementaryTable4);

%% ------------------------------------------------------------------------
% CREATE RESULTS FOLDER AND SAVE VALIDATED OUTPUTS
% -------------------------------------------------------------------------
if ~isfolder(resultsDir)
    [ok, message] = mkdir(resultsDir);
    if ~ok
        error('Failed to create results directory %s: %s', ...
            resultsDir, message);
    end
end

writetable(supplementaryTable4, tableOutPath, 'Encoding', 'UTF-8');
local_add_utf8_bom(tableOutPath);
drawnow;
exportgraphics(nrfFigure, figureOutPath, 'ContentType', 'vector');

fprintf('Saved Supplementary Table 6: %s\n', tableOutPath);
fprintf('Saved Supplementary Figure 13: %s\n', figureOutPath);

log_command_window('stop');

function local_add_utf8_bom(filePath)
[fid, message] = fopen(filePath, 'rb');
if fid < 0
    error('SimpleOxford:ExcelCsv:OpenFailed', ...
        'Could not read CSV for Excel encoding: %s', message);
end
readerCleanup = onCleanup(@() fclose(fid));
bytes = fread(fid, Inf, '*uint8');
clear readerCleanup;

utf8Bom = uint8([239; 187; 191]);
if numel(bytes) >= 3 && isequal(bytes(1:3), utf8Bom)
    return;
end

[fid, message] = fopen(filePath, 'wb');
if fid < 0
    error('SimpleOxford:ExcelCsv:OpenFailed', ...
        'Could not rewrite CSV for Excel encoding: %s', message);
end
writerCleanup = onCleanup(@() fclose(fid));
nWritten = fwrite(fid, [utf8Bom; bytes], 'uint8');
if nWritten ~= numel(bytes) + numel(utf8Bom)
    error('SimpleOxford:ExcelCsv:WriteFailed', ...
        'Could not write the complete Excel-compatible UTF-8 CSV.');
end
clear writerCleanup;
end
