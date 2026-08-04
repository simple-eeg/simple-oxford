%% step_8_jasp_5_data_prep_combine_all.m
% Purpose
%   - Read:
%       data/jasp/jasp_data_eeg.csv
%       data/jasp/jasp_data_other.csv
%   - Merge by subjectID using jasp_data_eeg.csv as the master subject list.
%   - Require (hard errors):
%       • subjectID exists in both inputs.
%       • subjectID is non-blank in both inputs (after trimming).
%       • subjectID is unique within each input.
%       • every EEG subject has a matching row in jasp_data_other.csv (1:1 match).
%   - Ignore any extra subjects present only in jasp_data_other.csv.
%   - Preserve column order:
%       • subjectID first
%       • then all EEG columns in the exact order from jasp_data_eeg.csv
%       • then all OTHER columns in the exact order from jasp_data_other.csv (excluding subjectID)
%   - Sort rows by subjectID before writing.
%   - Write:
%       data/jasp/jasp_data_all.csv

log_command_window('start');
clear; clc;

%% 0) User config: paths
baseDir = '/Users/lukebaxter/pipeline_paper/simple-oxford';

jaspDir = fullfile(baseDir, 'data', 'jasp');

eegCsv   = fullfile(jaspDir, 'jasp_data_eeg.csv');
otherCsv = fullfile(jaspDir, 'jasp_data_other.csv');
outCsv   = fullfile(jaspDir, 'jasp_data_all.csv');

%% 1) Validate inputs exist
assert(isfile(eegCsv),   'Input file not found: %s', eegCsv);
assert(isfile(otherCsv), 'Input file not found: %s', otherCsv);

%% 2) Read both CSVs (string-stable import; preserve leading zeros in subjectID)
opts_eeg = detectImportOptions(eegCsv, 'PreserveVariableNames', true, 'TextType', 'string');
if any(strcmp(opts_eeg.VariableNames, 'subjectID'))
    opts_eeg = setvaropts(opts_eeg, 'subjectID', 'Type', 'string');
end
Teeg = readtable(eegCsv, opts_eeg);

opts_other = detectImportOptions(otherCsv, 'PreserveVariableNames', true, 'TextType', 'string');
if any(strcmp(opts_other.VariableNames, 'subjectID'))
    opts_other = setvaropts(opts_other, 'subjectID', 'Type', 'string');
end
Tother = readtable(otherCsv, opts_other);

%% 3) Validate subjectID column integrity (both tables)
% Existence
assert(any(strcmp(Teeg.Properties.VariableNames, 'subjectID')),   'EEG table missing required column: subjectID');
assert(any(strcmp(Tother.Properties.VariableNames, 'subjectID')), 'OTHER table missing required column: subjectID');

% Normalise to trimmed string; treat missing as ""
Teeg.subjectID   = strtrim(string(Teeg.subjectID));
Tother.subjectID = strtrim(string(Tother.subjectID));

Teeg.subjectID(ismissing(Teeg.subjectID))     = "";
Tother.subjectID(ismissing(Tother.subjectID)) = "";

% Non-blank
if any(Teeg.subjectID == "")
    idx = find(Teeg.subjectID == "", 1, 'first');
    error('EEG table contains blank subjectID (after trimming) at row %d.', idx);
end
if any(Tother.subjectID == "")
    idx = find(Tother.subjectID == "", 1, 'first');
    error('OTHER table contains blank subjectID (after trimming) at row %d.', idx);
end

% Uniqueness within each table
if numel(unique(Teeg.subjectID)) ~= height(Teeg)
    error('EEG table subjectID values are not unique. Aborting.');
end
if numel(unique(Tother.subjectID)) ~= height(Tother)
    error('OTHER table subjectID values are not unique. Aborting.');
end

%% 4) Enforce EEG subjectIDs are all present in OTHER (OTHER may have extras)
missing_in_other = setdiff(Teeg.subjectID, Tother.subjectID);
if ~isempty(missing_in_other)
    error('SubjectID(s) present in EEG but missing in OTHER: %s', strjoin(cellstr(missing_in_other), ', '));
end

%% 5) Align rows (EEG as master) and combine columns
Teeg = sortrows(Teeg, 'subjectID');

% Map EEG IDs into OTHER rows
[tf, loc] = ismember(Teeg.subjectID, Tother.subjectID);
assert(all(tf), 'Internal: subjectID mapping failed after prior subset check.');

Tother_matched = Tother(loc, :);

% Append OTHER columns excluding subjectID, preserving OTHER column order
otherVars = Tother.Properties.VariableNames;
otherVars_noID = setdiff(otherVars, {'subjectID'}, 'stable');

Tout = [Teeg, Tother_matched(:, otherVars_noID)];

% Deterministic sort (explicit)
Tout = sortrows(Tout, 'subjectID');

%% 6) Write output
writetable(Tout, outCsv);

log_command_window('stop');