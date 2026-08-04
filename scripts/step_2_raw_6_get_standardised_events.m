%% step_2_raw_6_get_standardised_events.m
% Purpose:
%   - Read data_lists/dataset_list_prelim.xlsx
%   - For each INCLUDED dataset (excluded_datasets == ""), load the .set file in data/raw/...
%   - Extract all values from EEG.event.type
%   - Write three outputs:
%       1) Append a new column 'event_types' to dataset_list_prelim.xlsx (unique types; alphabetically sorted; semicolon-joined)
%       2) For each .set, write data/info_prelim/event_types/<stem>_event_types.csv with one type per row (duplicates kept; no header)
%       3) Write data/info_prelim/event_types/event_type_summary.csv with:
%            Type, TotalOccurrences, FilesContainingType
%
% Decisions:
%   - Include ALL event types exactly as found (e.g., 'boundary', 'NA'); drop truly empty strings if any slip through
%   - If a .set is missing/unreadable -> ERROR and STOP
%   - If a .set has zero events -> per-file CSV is empty; spreadsheet cell left blank
%   - 'event_types' values are unique types sorted alphabetically and joined with '; '
%
% Dependencies:
%   - EEGLAB on path (pop_loadset, eeg_checkset)
%
% Notes:
%   - path_reformatted is a RELATIVE path beginning with 'data/...'
%   - EEGfile_reformatted is the filename of the .set
%   - Only process rows where excluded_datasets == "" (treat <missing> as empty)

log_command_window('start');
clear; clc;

%% 0) Setup paths
root          = "/Users/lukebaxter/pipeline_paper/simple-oxford";
fileListPath  = root + "/data_lists/dataset_list_prelim.xlsx";
eventsFolder  = root + "/data/info_prelim/event_types";

% Ensure output folder exists
if ~exist(eventsFolder, 'dir')
    ok = mkdir(eventsFolder);
    if ~ok
        error("Failed to create events output folder: %s", eventsFolder);
    end
end

% Ensure EEGLAB is available; launch EEGLAB
assert(exist('eeglab','file') == 2 || exist('pop_loadset','file') == 2, ...
    "EEGLAB (eeglab/pop_loadset) not found on path.");
if exist('eeglab','file') == 2
    eeglab;
end

%% 1) Load spreadsheet & validate columns
fprintf("Loading EEG file list: %s\n", fileListPath);
opts = detectImportOptions(fileListPath, 'TextType','string', 'VariableNamingRule','preserve');
T    = readtable(fileListPath, opts);

reqCols = ["excluded_datasets","path_reformatted","EEGfile_reformatted"];
missingReq = setdiff(reqCols, string(T.Properties.VariableNames));
assert(isempty(missingReq), "Missing required columns in dataset_list_prelim.xlsx: %s", strjoin(missingReq, ", "));

% Normalize key columns to string & treat <missing> as empty
for c = reqCols
    T.(c) = string(T.(c));
    T.(c)(ismissing(T.(c))) = "";
end

% Prepare/overwrite the output column
N = height(T);
T.event_types = strings(N, 1);

%% 2) Select rows to process (INCLUDED rows only)
excl = string(T.excluded_datasets);
excl(ismissing(excl)) = "";
includedMask = (strlength(strtrim(excl)) == 0);

idxIncluded = find(includedMask);
if isempty(idxIncluded)
    fprintf("No included rows found (excluded_datasets != \"\"). Nothing to do.\n");
    % Still save the added empty column for completeness
    writetable(T, fileListPath);
    return;
end

%% 3) Global accumulators for the summary CSV
% totalCount: total occurrences across all files (duplicates counted)
% filesCount: number of files containing at least one of the type
totalCount = containers.Map('KeyType','char','ValueType','double');
filesCount = containers.Map('KeyType','char','ValueType','double');

processed = 0;
globalEventTotal = 0;

%% 4) Process each included row
for k = 1:numel(idxIncluded)
    i = idxIncluded(k);

    relDir  = T.path_reformatted(i);
    setName = T.EEGfile_reformatted(i);

    % Validate presence of values
    if strlength(relDir) == 0
        error("Row %d: path_reformatted is empty for an included dataset.", i);
    end
    if strlength(setName) == 0
        error("Row %d: EEGfile_reformatted is empty for an included dataset.", i);
    end

    % Build absolute paths
    absDir = fullfile(char(root), char(relDir));
    absSet = fullfile(absDir, char(setName));

    if ~isfile(absSet)
        error("Row %d: Missing .set file: %s", i, absSet);
    end

    % Load dataset
    try
        EEG = pop_loadset('filename', char(setName), 'filepath', absDir);
        EEG = eeg_checkset(EEG);
    catch ME
        error("Row %d: Failed to load .set file (%s). Error: %s", i, absSet, ME.message);
    end

    % Extract event types
    types = strings(0,1);
    if isfield(EEG, 'event') && ~isempty(EEG.event)
        % Collect raw types (can be char/num/mixed); normalize to string and trim
        raw = cell(1, numel(EEG.event));
        for e = 1:numel(EEG.event)
            raw{e} = EEG.event(e).type;
        end
        types = strings(numel(raw), 1);
        for e = 1:numel(raw)
            % string(...) handles numeric/char; ensure scalar string
            types(e) = strtrim(string(raw{e}));
        end
        % Drop truly empty strings if any slipped through
        types = types(strlength(types) > 0);
    end

    % ---- 4a) Write per-file CSV with duplicates kept (no header) ----
    [~, stem, ext] = fileparts(char(setName)); %#ok<ASGLU>
    outCsv = fullfile(eventsFolder, [stem '_event_types.csv']);

    if isempty(types)
        % Create an empty file explicitly
        fid = fopen(outCsv, 'w'); fclose(fid);
    else
        % One type per line
        writecell(cellstr(types), outCsv);
    end

    % ---- 4b) Update spreadsheet column with unique, alphabetically sorted list ----
    if ~isempty(types)
        uniqTypes = unique(types);                 % dedupe
        uniqTypes = sort(uniqTypes);               % alphabetical
        T.event_types(i) = strjoin(uniqTypes, '; ');
    else
        T.event_types(i) = "";                     % leave blank
    end

    % ---- 4c) Update global accumulators ----
    % TotalOccurrences: count duplicates
    for e = 1:numel(types)
        key = char(types(e));
        if isKey(totalCount, key)
            totalCount(key) = totalCount(key) + 1;
        else
            totalCount(key) = 1;
        end
    end

    % FilesContainingType: count once per file
    if ~isempty(types)
        fileUniques = unique(types);
        for e = 1:numel(fileUniques)
            key = char(fileUniques(e));
            if isKey(filesCount, key)
                filesCount(key) = filesCount(key) + 1;
            else
                filesCount(key) = 1;
            end
        end
    end

    processed = processed + 1;
    globalEventTotal = globalEventTotal + numel(types);

    fprintf("Processed %d/%d | %s  (events: %d)\n", processed, numel(idxIncluded), stem, numel(types));
end

%% 5) Save updated spreadsheet with the new 'event_types' column
writetable(T, fileListPath);
fprintf("Updated dataset_list_prelim.xlsx with 'event_types'.\n");

%% 6) Build & save global summary CSV: event_type_summary.csv
allKeys = [keys(totalCount), keys(filesCount)];
if isempty(allKeys)
    % No events found anywhere → write an empty summary with headers
    Type = strings(0,1); TotalOccurrences = zeros(0,1); FilesContainingType = zeros(0,1); %#ok<NASGU>
    summaryTbl = table(Type, TotalOccurrences, FilesContainingType);
else
    allKeys = unique(allKeys);               % cellstr of unique type names
    Type = string(allKeys(:));               % column vector of types (as strings)
    TotalOccurrences = zeros(numel(allKeys), 1);
    FilesContainingType = zeros(numel(allKeys), 1);

    for j = 1:numel(allKeys)
        key = allKeys{j};
        if isKey(totalCount, key),        TotalOccurrences(j)   = totalCount(key);       end
        if isKey(filesCount, key),        FilesContainingType(j) = filesCount(key);      end
    end

    % Sort summary alphabetically by Type
    [Type, sortIdx] = sort(Type);
    TotalOccurrences   = TotalOccurrences(sortIdx);
    FilesContainingType = FilesContainingType(sortIdx);

    summaryTbl = table(Type, TotalOccurrences, FilesContainingType);
end

summaryPath = fullfile(eventsFolder, "event_type_summary.csv");
writetable(summaryTbl, summaryPath);

%% 7) Wrap-up logs
fprintf("Done.\n");
fprintf("  Files processed       : %d\n", processed);
fprintf("  Total events (all files): %d\n", globalEventTotal);
if exist(summaryPath, 'file')
    fprintf("  Summary written to    : %s\n", summaryPath);
end

log_command_window('stop');
