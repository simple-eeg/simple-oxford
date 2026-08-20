%% step_9_jasp_5_data_prep_combine_all.m
% Purpose
%   - Read:
%       data/results/jasp_data_eeg.csv
%       data/results/jasp_data_other.csv
%       data_lists/dataset_list.csv
%   - Merge by subjectID using jasp_data_eeg.csv as the master subject list.
%   - Require (hard errors):
%       • subjectID exists in both inputs.
%       • subjectID is non-blank in both inputs (after trimming).
%       • subjectID is unique within each input.
%       • every EEG subject has a matching row in jasp_data_other.csv (1:1 match).
%       • EEG subjects equal the admitted canonical registry participant set.
%       • mapped metadata subjects equal that same admitted set exactly.
%   - Ignore any extra subjects present only in jasp_data_other.csv.
%   - Preserve column order:
%       • subjectID first
%       • then all EEG columns in the exact order from jasp_data_eeg.csv
%       • then all OTHER columns in the exact order from jasp_data_other.csv (excluding subjectID)
%   - Sort rows by subjectID before writing.
%   - Write the provisional combined table:
%       data/results/jasp_data_all.csv
%   - Step 9.6 finalises this same path with the three analysis-membership
%     columns. Do not import it into JASP until Step 9.6 succeeds.

log_command_window('start');
clear; clc;

%% 0) User config: paths
baseDir = '/Users/lukebaxter/Developer/simple-eeg/simple-oxford';
functionsDir = fullfile(baseDir, 'functions');
addpath(functionsDir, '-begin');
clear load_dataset_identity_registry
rehash path
local_assert_helper_paths(functionsDir, ...
    {'load_dataset_identity_registry'});

resultsDir = fullfile(baseDir, 'data', 'results');

eegCsv   = fullfile(resultsDir, 'jasp_data_eeg.csv');
otherCsv = fullfile(resultsDir, 'jasp_data_other.csv');
outCsv   = fullfile(resultsDir, 'jasp_data_all.csv');
datasetCsv = fullfile(baseDir, 'data_lists', 'dataset_list.csv');

%% 1) Validate inputs exist
assert(isfile(eegCsv),   'Input file not found: %s', eegCsv);
assert(isfile(otherCsv), 'Input file not found: %s', otherCsv);
assert(isfile(datasetCsv), 'Input file not found: %s', datasetCsv);

identity = load_dataset_identity_registry(datasetCsv);
identityMode = identity.mode;
canonicalRegistryIDs = sort(identity.canonical_subject_ids);

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

%% 4) Validate both inputs against the current registry identity route
eegIDs = sort(Teeg.subjectID);
if ~isequal(eegIDs, canonicalRegistryIDs)
    error('SimpleOxford:JaspCombineAll:EEGRegistryMismatch', ...
        ['The EEG intermediate does not contain exactly the admitted ' ...
         'canonical registry participant set.']);
end

otherIDs = sort(Tother.subjectID);
if identityMode == "mapped" && ...
        ~isequal(otherIDs, canonicalRegistryIDs)
    error('SimpleOxford:JaspCombineAll:MetadataRegistryMismatch', ...
        ['Mapped metadata must contain exactly the admitted canonical ' ...
         'registry participant set.']);
end

%% 5) Enforce EEG subjectIDs are all present in OTHER (original mode may have extras)
missing_in_other = setdiff(Teeg.subjectID, Tother.subjectID);
if ~isempty(missing_in_other)
    error('SimpleOxford:JaspCombineAll:MissingMetadata', ...
        'Metadata are missing for %d admitted EEG participant(s).', ...
        numel(missing_in_other));
end

%% 6) Align rows (EEG as master) and combine columns
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

%% 7) Write and verify the provisional output
local_write_verified_csv(Tout, outCsv);
fprintf('Wrote Step 9.5 provisional table: %s (%d rows x %d columns)\n', ...
    outCsv, height(Tout), width(Tout));
fprintf('Identity route: %s (%d admitted participants).\n', ...
    identityMode, height(Tout));

clear identity canonicalRegistryIDs;

log_command_window('stop');

%% Local functions
function local_write_verified_csv(expected, finalPath)
candidatePath = [tempname(fileparts(finalPath)) '.csv'];
candidateCleanup = onCleanup(@() local_delete_candidate(candidatePath));
writetable(expected, candidatePath);
local_verify_csv(candidatePath, expected);
local_atomic_promote(candidatePath, finalPath);
end

function local_verify_csv(csvPath, expected)
options = detectImportOptions(csvPath, ...
    'PreserveVariableNames', true, 'TextType', 'string');
if ~any(strcmp(options.VariableNames, 'subjectID'))
    error('SimpleOxford:JaspCombineAll:OutputVerification', ...
        'Candidate Step 9.5 CSV is missing subjectID.');
end
options = setvartype(options, 'subjectID', 'string');
observed = readtable(csvPath, options);
if ~local_csv_tables_equal(observed, expected)
    error('SimpleOxford:JaspCombineAll:OutputVerification', ...
        ['Candidate Step 9.5 CSV did not preserve its exact schema, ' ...
         'values, and textual subjectID values.']);
end
end

function tf = local_csv_tables_equal(observed, expected)
if ~isequal(observed.Properties.VariableNames, ...
        expected.Properties.VariableNames)
    tf = false;
    return;
end
for variableIndex = 1:width(expected)
    variableName = expected.Properties.VariableNames{variableIndex};
    if isstring(expected.(variableName))
        expected.(variableName)(ismissing(expected.(variableName))) = "";
        observed.(variableName) = string(observed.(variableName));
        observed.(variableName)(ismissing(observed.(variableName))) = "";
    end
end
tf = isequaln(observed, expected);
end

function local_atomic_promote(candidatePath, finalPath)
sourcePath = java.io.File(candidatePath).toPath();
destinationPath = java.io.File(finalPath).toPath();
moveOptions = javaArray('java.nio.file.CopyOption', 2);
moveOptions(1) = java.nio.file.StandardCopyOption.ATOMIC_MOVE;
moveOptions(2) = java.nio.file.StandardCopyOption.REPLACE_EXISTING;
try
    java.nio.file.Files.move(sourcePath, destinationPath, moveOptions);
catch
    error('SimpleOxford:JaspCombineAll:OutputPromotion', ...
        'The verified Step 9.5 CSV could not be promoted atomically.');
end
end

function local_delete_candidate(candidatePath)
if isfile(candidatePath)
    delete(candidatePath);
end
end

function local_assert_helper_paths(functionsDir, helperNames)
for helperIndex = 1:numel(helperNames)
    helperName = helperNames{helperIndex};
    expectedPath = char(java.io.File(fullfile( ...
        functionsDir, [helperName '.m'])).getCanonicalPath());
    resolvedPath = which(helperName);
    if isempty(resolvedPath)
        error('SimpleOxford:JaspCombineAll:MissingHelper', ...
            'Required repository helper is unavailable: %s', helperName);
    end
    resolvedPath = char(java.io.File(resolvedPath).getCanonicalPath());
    if ~strcmp(resolvedPath, expectedPath)
        error('SimpleOxford:JaspCombineAll:WrongHelper', ...
            ['Required helper %s must resolve to this checkout. Expected ' ...
             '%s, resolved %s.'], helperName, expectedPath, resolvedPath);
    end
end
end
