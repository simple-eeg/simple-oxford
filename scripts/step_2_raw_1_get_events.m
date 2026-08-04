%% step_2_raw_1_get_events.m
% This script extracts annotations from EEG event files (Curry 7/8 or XDF)
% for each dataset listed in dataset_list_prelim.xlsx. It:
%   - Saves a per-file list of annotations (including duplicates)
%   - Updates dataset_list_prelim.xlsx with a new 'event_annotations' column
%   - Generates a summary CSV of unique annotations across all datasets
%
% Dependencies:
%   - read_events_from_curry_cef.m
%   - read_annotations_from_xdf_csv.m
%   - dataset_list_prelim.xlsx (must contain required metadata columns)
%
% NOTE: Outputs go to data/info_prelim/event_annotations.
%       Downstream scripts that read the mapping CSV will need their paths
%       updated later (we'll handle that at the end of step 2).

log_command_window('start');
clear; clc;

%% Setup

% Define base directory (hardcoded for this project)
baseDir = '/Users/lukebaxter/pipeline_paper/simple-oxford';

% Add functions folder to MATLAB path
functionsFolder = fullfile(baseDir, 'functions');
addpath(functionsFolder);

% Define paths
dataListPath = fullfile(baseDir, 'data_lists', 'dataset_list_prelim.xlsx');

% Write all event CSVs to data/info_prelim/event_annotations
eventsFolder = fullfile(baseDir, 'data', 'info_prelim', 'event_annotations');
if ~exist(eventsFolder, 'dir')
    mkdir(eventsFolder);
end

summaryOutPath = fullfile(eventsFolder, 'event_annotation_summary.csv');

%% Load dataset_list_prelim
fprintf('Loading EEG file list...\n');
opts = detectImportOptions(dataListPath);
tbl = readtable(dataListPath, opts);

% Ensure required columns exist
requiredCols = {'format', 'path_renamed', 'renaming_info_missing', ...
    'cef_renamed', 'cdt_cef_renamed', 'events_csv_renamed'};
missingCols = setdiff(requiredCols, tbl.Properties.VariableNames);
if ~isempty(missingCols)
    error('Missing required columns in dataset_list_prelim.xlsx: %s', strjoin(missingCols, ', '));
end

% Initialize annotation summary map and result column
allAnnotations = {};                    % aggregated (cellstr) across files
eventAnnotationsCol = strings(height(tbl), 1); % semicolon-joined unique annotations per row

%% Loop through each row
for i = 1:height(tbl)
    % Skip rows marked as 'missing'
    if strcmpi(tbl.renaming_info_missing{i}, 'missing')
        continue;
    end

    % Get EEG format and relevant info
    eegFormat   = tbl.format{i};
    eegFolderRel = tbl.path_renamed{i};
    eegFolder    = fullfile(baseDir, eegFolderRel);

    switch eegFormat
        case 'Curry 7'
            eventFileName = tbl.cef_renamed{i};
            eventFilePath = fullfile(eegFolder, eventFileName);
            [~, ~, annotations] = read_events_from_curry_cef(eventFilePath);

        case 'Curry 8'
            eventFileName = tbl.cdt_cef_renamed{i};
            eventFilePath = fullfile(eegFolder, eventFileName);
            [~, ~, annotations] = read_events_from_curry_cef(eventFilePath);

        case 'XDF'
            eventFileName = tbl.events_csv_renamed{i};
            eventFilePath = fullfile(eegFolder, eventFileName);
            annotations = read_annotations_from_xdf_csv(eventFilePath);

        otherwise
            warning('Unknown EEG format "%s" at row %d. Skipping.', eegFormat, i);
            continue;
    end

    % Normalize type & drop empty annotations before any downstream use
    % - cast to string column
    % - drop entries with zero length after trimming
    ann = string(annotations(:));
    ann = strtrim(ann);
    ann = ann(strlength(ann) > 0);

    % Save full annotation list (including duplicates) after empty-filtering
    % Determine correct name stem for saving annotations
    switch eegFormat
        case 'Curry 7'
            nameStem = erase(eventFileName, '_eeg.cef');
        case 'Curry 8'
            nameStem = erase(eventFileName, '_eeg.cdt.cef');
        case 'XDF'
            nameStem = erase(eventFileName, '_events.csv');
    end
    outFile = fullfile(eventsFolder, [nameStem '_eeg_event_annotations.csv']);
    writecell(cellstr(ann), outFile);

    % Extract unique annotations for the spreadsheet (still exclude empties)
    uniqueAnnots = unique(ann);
    eventAnnotationsCol(i) = strjoin(uniqueAnnots, '; ');

    % Append to full list for summary
    allAnnotations = [allAnnotations; cellstr(ann)]; %#ok<AGROW>
end

%% Write updated dataset_list_prelim.xlsx
fprintf('Updating dataset_list_prelim.xlsx with annotation summaries...\n');
tbl.event_annotations = eventAnnotationsCol;
tbl.latency_correct = strings(height(tbl),1); % new blank column for latency correction flags
writetable(tbl, dataListPath);

%% Generate summary: event_annotation_summary.csv
fprintf('Generating annotation summary table...\n');

% allAnnotations is a cell array (one row per instance across all files), already empty-filtered
[uniqueAnnotations, ~, idx] = unique(allAnnotations);
counts = accumarray(idx, 1);

summaryTbl = table;
summaryTbl.Annotation = uniqueAnnotations;
summaryTbl.TotalOccurrences = counts;
summaryTbl.FilesContainingEvent = zeros(size(uniqueAnnotations));

for j = 1:numel(uniqueAnnotations)
    currentAnnot = uniqueAnnotations{j};             % char
    matches = false(height(tbl), 1);                 % file-level presence flags

    for i = 1:height(tbl)
        if strlength(eventAnnotationsCol(i)) == 0
            continue;  % Skip empty rows
        end

        % Split the semicolon-separated annotations into a cell array (trimmed)
        annotationsInRow = strtrim(split(eventAnnotationsCol(i), ';'));

        % Check for exact match (string vs char is OK in strcmp; MATLAB converts char)
        if any(strcmp(annotationsInRow, currentAnnot))
            matches(i) = true;
        end
    end

    % Count how many files contain this exact annotation at least once
    summaryTbl.FilesContainingEvent(j) = sum(matches);
end

% Add user-editable fields
summaryTbl.Type        = repmat("", height(summaryTbl), 1);    % User-defined label for EEG.event.type
summaryTbl.Filter_AND  = repmat("", height(summaryTbl), 1);    % Annotations that must all be present
summaryTbl.Filter_OR   = repmat("", height(summaryTbl), 1);    % At least one of these must be present
summaryTbl.Filter_NOT  = repmat("", height(summaryTbl), 1);    % None of these must be present
summaryTbl.LatencyCorrect = repmat("", height(summaryTbl), 1); % Blank column for user-defined flags for latency correction

% Write summary CSV to the NEW folder (data/source/events)
writetable(summaryTbl, summaryOutPath);

fprintf('Done.\n');

log_command_window('stop');
