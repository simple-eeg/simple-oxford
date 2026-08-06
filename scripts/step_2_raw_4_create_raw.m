%% step_2_raw_4_create_raw.m
% Purpose:
%   - Drive conversions from data_lists/dataset_list_prelim.xlsx (one row per dataset)
%   - Process rows not marked "excluded" (case-insensitive) when format is recognised
%   - Build EEGLAB EEG structs via helper functions:
%       * XDF:   functions/convert_xdf_to_eeg.m
%       * Curry: functions/convert_curry_to_eeg.m
%   - Save .set to data/raw/... (mirrors data/source/...)
%   - Apply annotation->Type mapping (empty/missing -> 'NA') inside helpers
%   - Hygiene: trim whitespace in mapping, fail if Type column is entirely empty

log_command_window('start');
clear; clc;

%% 0) Setup
root = "/Users/lukebaxter/Developer/simple-eeg/simple-oxford";
eegListXlsx = root + "/data_lists/dataset_list_prelim.xlsx";
mapCsv      = root + "/data/info_prelim/event_annotations/event_annotation_summary.csv";

% Add functions folder to MATLAB path
functionsFolder = fullfile(char(root), 'functions');
addpath(functionsFolder);

% Check EEGLAB is available
assert(exist('eeglab','file') == 2, "EEGLAB not found on path.");
eeglab;

%% 1) Load mapping Annotation -> Type (trim + hard-empty-Type check)
mapOpts = detectImportOptions(mapCsv, 'TextType','string', 'VariableNamingRule','preserve');
mapTbl  = readtable(mapCsv, mapOpts);

% Expect columns: Annotation, Type
assert(all(ismember(["Annotation","Type"], string(mapTbl.Properties.VariableNames))), ...
    "Mapping file must contain columns: Annotation, Type.");

% Coerce to string; treat <missing> as empty; trim whitespace
annCol  = string(mapTbl.Annotation); annCol(ismissing(annCol))   = "";
typeCol = string(mapTbl.Type);      typeCol(ismissing(typeCol)) = "";
annCol  = strtrim(annCol);
typeCol = strtrim(typeCol);

% Hard error if the entire Type column is empty after trimming
if all(strlength(typeCol) == 0)
    error("event_annotation_summary.csv: 'Type' column is entirely empty after trimming. Populate at least one Type and retry.");
end

% Build containers.Map (keys: non-empty Annotation; values may be empty)
validIdx = strlength(annCol) > 0;
annotationToType = containers.Map( ...
    cellstr(annCol(validIdx)), ...
    cellstr(typeCol(validIdx)) ...
    );

%% 2) Load spreadsheet of datasets (format-agnostic handling)
opts = detectImportOptions(eegListXlsx, 'TextType','string', 'VariableNamingRule','preserve');
T    = readtable(eegListXlsx, opts);

% Required columns
reqCols = ["format","excluded_datasets","path_renamed","path_reformatted", ...
    "EEGfile_renamed","EEGfile_reformatted", ...
    "events_csv_renamed", ...               % XDF
    "dap_renamed","rs3_renamed","ceo_renamed","cef_renamed", ... % Curry 7
    "cdt_dpa_renamed","cdt_ceo_renamed","cdt_cef_renamed"];      % Curry 8

missingReq = setdiff(reqCols, string(T.Properties.VariableNames));
assert(isempty(missingReq), "Missing required columns in dataset_list_prelim.xlsx: %s", strjoin(missingReq, ", "));

% Ensure all relevant columns are string and replace <missing> -> ""
for c = reqCols
    T.(c) = string(T.(c));
    T.(c)(ismissing(T.(c))) = "";
end
% Normalize core columns explicitly
T.format              = string(T.format);
T.excluded_datasets   = string(T.excluded_datasets);
T.path_renamed        = string(T.path_renamed);
T.path_reformatted    = string(T.path_reformatted);
T.EEGfile_renamed     = string(T.EEGfile_renamed);
T.EEGfile_reformatted = string(T.EEGfile_reformatted);

% Exclusions: skip when equals "excluded" (case-insensitive)
excl = T.excluded_datasets; excl(ismissing(excl)) = ""; excl = strtrim(excl);
T = T(~strcmpi(excl, "excluded"), :);
N = height(T);
if N == 0
    fprintf("No rows to process (nothing included). Nothing to do.\n");
    log_command_window('stop');
    return;
end

%% 3) Iterate rows with progress printing
for r = 1:N
    fmt          = strtrim(T.format(r));   % preserve case
    srcRel       = T.path_renamed(r);
    dstRel       = T.path_reformatted(r);
    eegSrcName   = T.EEGfile_renamed(r);
    eegDstName   = T.EEGfile_reformatted(r);

    % Sidecars present in table (format-specific usage happens in switch)
    % XDF sidecar
    eventsCsvRel   = T.events_csv_renamed(r);
    % Curry 7 sidecars
    dapRel   = T.dap_renamed(r);
    rs3Rel   = T.rs3_renamed(r);
    ceoRel   = T.ceo_renamed(r);
    cefRel   = T.cef_renamed(r);
    % Curry 8 sidecars
    dpaRel   = T.cdt_dpa_renamed(r);
    c8ceoRel = T.cdt_ceo_renamed(r);
    c8cefRel = T.cdt_cef_renamed(r);

    % Progress label
    progLabel = char(eegSrcName);
    if strlength(progLabel) == 0, progLabel = char(srcRel); end

    % Absolute dirs
    srcDir = fullfile(char(root), char(srcRel));
    dstDir = fullfile(char(root), char(dstRel));

    % Ensure destination directory exists
    if ~isfolder(dstDir)
        mk = mkdir(dstDir);
        if ~mk, error("Failed to create destination folder: %s", dstDir); end
    end

    switch fmt
        case "XDF"
            fprintf("Row %d/%d | %s | XDF ...\n", r, N, progLabel);

            % Minimal checks in caller; helper will validate existence
            if strlength(eegSrcName) == 0
                error("Row %d: EEGfile_renamed is empty for XDF.", r);
            end
            if ~isfile(fullfile(srcDir, char(eegSrcName)))
                error("Missing XDF file: %s", fullfile(srcDir, char(eegSrcName)));
            end
            if strlength(eventsCsvRel) == 0
                error("Row %d: events_csv_renamed is empty for XDF.", r);
            end

            % Build sidecars with relative filename (helper resolves with srcDir)
            sidecars = struct();
            sidecars.events_csv = char(eventsCsvRel);

            % Build EEG
            [EEG, ok] = convert_xdf_to_eeg(srcDir, char(eegSrcName), sidecars, annotationToType);
            if ~ok
                error("XDF conversion failed for: %s", fullfile(srcDir, char(eegSrcName)));
            end

            % Essential integrity checks
            assert(~isempty(EEG.event), "Empty EEG.event after conversion (row %d).", r);
            assert(isfield(EEG, 'srate') && ~isempty(EEG.srate) && EEG.srate > 0, ...
                "Invalid sampling rate after conversion (row %d).", r);

            % Save .set
            pop_saveset(EEG, 'filename', char(eegDstName), 'filepath', dstDir, 'savemode', 'onefile');
            fprintf("Row %d/%d | %s | XDF → saved -> %s\n", r, N, progLabel, fullfile(dstDir, char(eegDstName)));

        case "Curry 7"
            fprintf("Row %d/%d | %s | Curry 7 ...\n", r, N, progLabel);

            sidecars = struct( ...
                'dap', char(dapRel), ...
                'rs3', char(rs3Rel), ...
                'cef', char(cefRel), ...
                'ceo', char(ceoRel) ...
                );

            if strlength(eegSrcName) == 0
                error("Row %d: EEGfile_renamed is empty for Curry 7.", r);
            end

            [EEG, ok] = convert_curry_to_eeg(srcDir, char(eegSrcName), sidecars, annotationToType, "Curry 7");
            if ~ok
                error("Curry 7 conversion failed for: %s", fullfile(srcDir, char(eegSrcName)));
            end

            assert(~isempty(EEG.event), "Empty EEG.event after conversion (row %d).", r);
            assert(isfield(EEG, 'srate') && ~isempty(EEG.srate) && EEG.srate > 0, ...
                "Invalid sampling rate after conversion (row %d).", r);

            pop_saveset(EEG, 'filename', char(eegDstName), 'filepath', dstDir, 'savemode', 'onefile');
            fprintf("Row %d/%d | %s | Curry 7 → saved -> %s\n", r, N, progLabel, fullfile(dstDir, char(eegDstName)));

        case "Curry 8"
            fprintf("Row %d/%d | %s | Curry 8 ...\n", r, N, progLabel);

            sidecars = struct( ...
                'cdt_dpa', char(dpaRel), ...
                'cdt_cef', char(c8cefRel), ...
                'cdt_ceo', char(c8ceoRel) ...
                );

            if strlength(eegSrcName) == 0
                error("Row %d: EEGfile_renamed is empty for Curry 8.", r);
            end

            [EEG, ok] = convert_curry_to_eeg(srcDir, char(eegSrcName), sidecars, annotationToType, "Curry 8");
            if ~ok
                error("Curry 8 conversion failed for: %s", fullfile(srcDir, char(eegSrcName)));
            end

            assert(~isempty(EEG.event), "Empty EEG.event after conversion (row %d).", r);
            assert(isfield(EEG, 'srate') && ~isempty(EEG.srate) && EEG.srate > 0, ...
                "Invalid sampling rate after conversion (row %d).", r);

            pop_saveset(EEG, 'filename', char(eegDstName), 'filepath', dstDir, 'savemode', 'onefile');
            fprintf("Row %d/%d | %s | Curry 8 → saved -> %s\n", r, N, progLabel, fullfile(dstDir, char(eegDstName)));

        otherwise
            error("Unknown format at row %d: %s", r, string(T.format(r)));
    end
end

fprintf("Completed conversions to .set in data/raw mirror.\n");

log_command_window('stop');
