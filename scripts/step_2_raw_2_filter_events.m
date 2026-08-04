%% step_2_raw_2_filter_events.m
% Purpose:
%   - Read dataset_list_prelim.xlsx
%   - Evaluate each row's event list against logical filters defined in
%     data/info_prelim/event_annotations/event_annotation_summary.csv (Filter_AND / Filter_OR / Filter_NOT)
%   - Append a new column 'event_missing' to dataset_list_prelim.xlsx:
%       ""        -> row passes filters (keep)
%       "missing" -> row fails filters (exclude downstream)
%
% Notes:
%   - Exact, case-sensitive matching of annotation names
%   - 'renaming_info_missing' == "missing" rows are skipped (left as "")
%   - Empty filter columns are ignored (i.e., no constraint)

log_command_window('start');
clear; clc;

%% Paths
baseDir = '/Users/lukebaxter/pipeline_paper/simple-oxford';
fileListPath = fullfile(baseDir, 'data_lists', 'dataset_list_prelim.xlsx');
mappingPath  = fullfile(baseDir, 'data', 'info_prelim', 'event_annotations', 'event_annotation_summary.csv');

%% Load dataset_list_prelim.xlsx
fprintf('Loading: %s\n', fileListPath);
% Preserve strings as strings (avoid silent cell/double conversions)
optsList = detectImportOptions(fileListPath, 'PreserveVariableNames', true);
% Make sure critical columns come in as string
forceStrCols = {'renaming_info_missing','event_annotations'};
for k = 1:numel(forceStrCols)
    if any(strcmpi(optsList.VariableNames, forceStrCols{k}))
        optsList = setvaropts(optsList, forceStrCols{k}, 'Type', 'string');
    end
end
T = readtable(fileListPath, optsList);

% Ensure required columns exist
requiredCols = {'renaming_info_missing','event_annotations'};
missingCols = setdiff(requiredCols, T.Properties.VariableNames);
if ~isempty(missingCols)
    error('Missing required columns in dataset_list_prelim.xlsx: %s', strjoin(missingCols, ', '));
end

% Create/initialize the output column (if it already exists, we will overwrite it)
T.event_missing = strings(height(T), 1);

%% Load event_annotation_summary.csv
fprintf('Loading: %s\n', mappingPath);
optsMap = detectImportOptions(mappingPath, 'PreserveVariableNames', true, 'TextType', 'string');

% Ensure expected columns exist and read as string
expectedMapCols = {'Annotation','Filter_AND','Filter_OR','Filter_NOT'};
for k = 1:numel(expectedMapCols)
    if ~any(strcmpi(optsMap.VariableNames, expectedMapCols{k}))
        error('Missing required column in mapping file: %s', expectedMapCols{k});
    end
    optsMap = setvaropts(optsMap, expectedMapCols{k}, 'Type', 'string');
end

M = readtable(mappingPath, optsMap);

M.Annotation = strtrim(M.Annotation);  % normalize whitespace just in case
M.Filter_AND = strtrim(M.Filter_AND);
M.Filter_OR  = strtrim(M.Filter_OR);
M.Filter_NOT = strtrim(M.Filter_NOT);

% Normalize filter flags to logicals (treat '1' as true, everything else blank/false)
toBool = @(x) (x == "1");  % exact "1" means selected; blanks or anything else are false

andMask = toBool(M.Filter_AND);
orMask  = toBool(M.Filter_OR);
notMask = toBool(M.Filter_NOT);

AND_set = M.Annotation(andMask);
OR_set  = M.Annotation(orMask);
NOT_set = M.Annotation(notMask);

fprintf('Active filters: AND=%d, OR=%d, NOT=%d\n', numel(AND_set), numel(OR_set), numel(NOT_set));
if all([isempty(M.Annotation(andMask)), isempty(M.Annotation(orMask)), isempty(M.Annotation(notMask))])
    fprintf('Note: No active filters (AND/OR/NOT all empty). All eligible rows will pass.\n');
end

%% Evaluate each row
N = height(T);
checked = 0;
flagged = 0;

for i = 1:N
    % Skip rows that were already invalid earlier in the pipeline
    if ~(T.renaming_info_missing(i) == "" || ismissing(T.renaming_info_missing(i)))
        % Leave event_missing as "" (we're not judging here)
        continue;
    end

    % Parse this row's event list (semicolon-separated)
    annStr = T.event_annotations(i);
    if ismissing(annStr) || annStr == ""
        thisSet = string([]);   % no events in this row
    else
        % Split the semicolon-separated string, trim spaces, cast to string, dedupe
        thisSet = unique(string(strtrim(split(string(annStr), ';'))));
        % Remove empty tokens if any slipped through (drop empty tokens and <missing>)
        thisSet = thisSet( thisSet ~= "" & ~ismissing(thisSet) );
    end

    % Evaluate filters
    pass = true;

    % AND: all must be present (if AND_set non-empty)
    if ~isempty(AND_set)
        if ~all( ismember(AND_set, thisSet) )
            pass = false;
        end
    end

    % OR: at least one must be present (if OR_set non-empty)
    if pass && ~isempty(OR_set)

        % Enforce rule: OR_set must have at least 2 entries
        if isscalar(OR_set)
            error(['Invalid Filter_OR: only one annotation ("%s") is marked. ', ...
                'You must mark at least two annotations for an OR rule, or leave all blank.'], OR_set);
        end

        % Apply OR filter logic
        if ~any( ismember(OR_set, thisSet) )
            pass = false;
        end
    end

    % NOT: none may be present (if NOT_set non-empty)
    if pass && ~isempty(NOT_set)
        if any( ismember(NOT_set, thisSet) )
            pass = false;
        end
    end

    % Write result
    checked = checked + 1;
    if ~pass
        T.event_missing(i) = "missing";
        flagged = flagged + 1;
    else
        T.event_missing(i) = "";  % explicitly blank
    end
end

%% Save table (overwrite)
writetable(T, fileListPath);
fprintf('Done. Checked %d rows; flagged %d rows as event_missing.\n', checked, flagged);

log_command_window('stop');
