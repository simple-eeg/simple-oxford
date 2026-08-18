%% step_8_jasp_3_data_prep_eeg_combine.m
% Purpose
%   - Read:
%       data/results/jasp_data_eeg_qc.csv
%       data/results/jasp_data_eeg_nrf.csv
%   - Merge 1:1 by subjectID with strict validation:
%       • subjectID exists in both files
%       • subjectID is non-blank (after trimming) in both files
%       • subjectID is unique within each file
%       • the subjectID sets match exactly across the two files
%   - Preserve column order:
%       • subjectID first
%       • then all QC columns in the exact order from jasp_data_eeg_qc.csv
%       • then all NRF columns in the exact order from jasp_data_eeg_nrf.csv (excluding subjectID)
%   - Sort rows by subjectID before writing.
%   - Write:
%       data/results/jasp_data_eeg.csv

log_command_window('start');
clear; clc;

%% 0) User config: paths
baseDir = '/Users/lukebaxter/Developer/simple-eeg/simple-oxford';

resultsDir = fullfile(baseDir, 'data', 'results');

qcCsv  = fullfile(resultsDir, 'jasp_data_eeg_qc.csv');
nrfCsv = fullfile(resultsDir, 'jasp_data_eeg_nrf.csv');
outCsv = fullfile(resultsDir, 'jasp_data_eeg.csv');

%% 1) Validate inputs exist
assert(isfile(qcCsv),  'Input file not found: %s', qcCsv);
assert(isfile(nrfCsv), 'Input file not found: %s', nrfCsv);

%% 2) Read both CSVs (string-stable import; preserve leading zeros in subjectID)
opts_qc = detectImportOptions(qcCsv, 'PreserveVariableNames', true, 'TextType', 'string');
if any(strcmp(opts_qc.VariableNames, 'subjectID'))
    opts_qc = setvaropts(opts_qc, 'subjectID', 'Type', 'string');
end
Tqc = readtable(qcCsv, opts_qc);

opts_nrf = detectImportOptions(nrfCsv, 'PreserveVariableNames', true, 'TextType', 'string');
if any(strcmp(opts_nrf.VariableNames, 'subjectID'))
    opts_nrf = setvaropts(opts_nrf, 'subjectID', 'Type', 'string');
end
Tnrf = readtable(nrfCsv, opts_nrf);

%% 3) Validate subjectID column integrity (both tables)
% Existence
assert(any(strcmp(Tqc.Properties.VariableNames, 'subjectID')),  'QC table missing required column: subjectID');
assert(any(strcmp(Tnrf.Properties.VariableNames, 'subjectID')), 'NRF table missing required column: subjectID');

% Normalise to trimmed string; treat missing as ""
Tqc.subjectID  = strtrim(string(Tqc.subjectID));
Tnrf.subjectID = strtrim(string(Tnrf.subjectID));

Tqc.subjectID(ismissing(Tqc.subjectID))   = "";
Tnrf.subjectID(ismissing(Tnrf.subjectID)) = "";

% Non-blank
if any(Tqc.subjectID == "")
    idx = find(Tqc.subjectID == "", 1, 'first');
    error('QC table contains blank subjectID (after trimming) at row %d.', idx);
end
if any(Tnrf.subjectID == "")
    idx = find(Tnrf.subjectID == "", 1, 'first');
    error('NRF table contains blank subjectID (after trimming) at row %d.', idx);
end

% Uniqueness within each table
if numel(unique(Tqc.subjectID)) ~= height(Tqc)
    error('QC table subjectID values are not unique. Aborting.');
end
if numel(unique(Tnrf.subjectID)) ~= height(Tnrf)
    error('NRF table subjectID values are not unique. Aborting.');
end

%% 4) Enforce 1:1 subject match between tables
ids_qc  = sort(Tqc.subjectID);
ids_nrf = sort(Tnrf.subjectID);

if numel(ids_qc) ~= numel(ids_nrf)
    error('Subject count mismatch: QC has %d rows, NRF has %d rows.', numel(ids_qc), numel(ids_nrf));
end

if ~all(ids_qc == ids_nrf)
    missing_in_nrf = setdiff(ids_qc, ids_nrf);
    missing_in_qc  = setdiff(ids_nrf, ids_qc);

    msg = "SubjectID mismatch between QC and NRF tables.";
    if ~isempty(missing_in_nrf)
        msg = msg + newline + "Present in QC but missing in NRF: " + strjoin(cellstr(missing_in_nrf), ', ');
    end
    if ~isempty(missing_in_qc)
        msg = msg + newline + "Present in NRF but missing in QC: " + strjoin(cellstr(missing_in_qc), ', ');
    end
    error('%s', msg);
end

%% 5) Align rows by subjectID (deterministic) and combine columns
Tqc  = sortrows(Tqc,  'subjectID');
Tnrf = sortrows(Tnrf, 'subjectID');

assert(all(Tqc.subjectID == Tnrf.subjectID), 'Internal alignment error: subjectID order mismatch after sorting.');

% Append NRF columns excluding subjectID, preserving NRF column order
nrfVars = Tnrf.Properties.VariableNames;
nrfVars_noID = setdiff(nrfVars, {'subjectID'}, 'stable');

Tout = [Tqc, Tnrf(:, nrfVars_noID)];

% Final deterministic sort (redundant but explicit)
Tout = sortrows(Tout, 'subjectID');

%% 6) Write output
writetable(Tout, outCsv);
fprintf('Wrote Step 8.3 intermediate: %s (%d rows x %d columns)\n', ...
    outCsv, height(Tout), width(Tout));

log_command_window('stop');
