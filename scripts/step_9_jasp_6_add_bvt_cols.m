%% step_9_jasp_6_add_bvt_cols.m
% Purpose
%   - Read:  data/results/jasp_data_all.csv
%   - Read:  data_lists/dataset_list.csv
%   - Read:  data_lists/medscinet_export_petal_pub.xlsx
%   - Derive a publication source-ID list from the XLSX:
%       subjectID = (RECD - Research project, with "OX" -> "Ox") + (RECD - Participant number)
%       (trim leading/trailing whitespace only; preserve leading zeros)
%   - With a mapped registry, translate every publication source ID to the
%     canonical replacement subjectID before matching the final table.
%   - Add (or re-create) three columns at the end of jasp_data_all.csv:
%       HL_ER_nNRF_mag_Screening
%       HL_ER_nNRF_mag_pub
%       HL_ER_nNRF_mag_pub_Screening
%   - Overwrite data/results/jasp_data_all.csv in place
%   - This finalises the Step 9 JASP table. Rerun Step 9.6 after any rerun of
%     Step 9.5 before importing jasp_data_all.csv into JASP.
%
% Notes
%   - The pub XLSX defines the "pub cohort" subject list.
%   - Pub cohort subjects must exist in jasp_data_all.csv, and must have a non-missing HL_ER_nNRF_mag.
%   - Screening columns are text: "Included" or "Excluded".
%   - This script is intentionally strict (hard errors on unexpected conditions).

log_command_window('start');
clear; clc;

%% 0) User config: paths
baseDir = '/Users/lukebaxter/Developer/simple-eeg/simple-oxford';
functionsDir = fullfile(baseDir, 'functions');
addpath(functionsDir, '-begin');
clear load_dataset_identity_registry construct_medscinet_subject_ids
rehash path
local_assert_helper_paths(functionsDir, { ...
    'load_dataset_identity_registry', ...
    'construct_medscinet_subject_ids'});

resultsDir = fullfile(baseDir, 'data', 'results');
csvPath = fullfile(resultsDir, 'jasp_data_all.csv');

xlsPath = fullfile(baseDir, 'data_lists', 'medscinet_export_petal_pub.xlsx');
datasetCsv = fullfile(baseDir, 'data_lists', 'dataset_list.csv');

%% 1) Column names (preserve exact input headers)
COL_ID   = 'subjectID';
COL_MAG  = 'HL_ER_nNRF_mag';

COL_PROJECT     = 'RECD - Research project';
COL_PARTICIPANT = 'RECD - Participant number';

COL_SCR      = 'HL_ER_nNRF_mag_Screening';
COL_PUB_MAG  = 'HL_ER_nNRF_mag_pub';
COL_PUB_SCR  = 'HL_ER_nNRF_mag_pub_Screening';

%% 2) Read and validate the current registry identity route
assert(isfile(datasetCsv), 'Missing dataset registry: %s', datasetCsv);
identity = load_dataset_identity_registry(datasetCsv);
identityMode = identity.mode;
canonicalRegistryIDs = sort(identity.canonical_subject_ids);

%% 3) Read CSV with subjectID forced to text before import
assert(isfile(csvPath), 'Missing input CSV: %s', csvPath);

opts = detectImportOptions(csvPath, ...
    'PreserveVariableNames', true, 'TextType', 'string');
opts.VariableNamingRule = 'preserve';
if any(strcmp(opts.VariableNames, COL_ID))
    opts = setvartype(opts, COL_ID, 'string');
end
T = readtable(csvPath, opts);

% Validate required columns exist
assert(any(strcmp(T.Properties.VariableNames, COL_ID)),  'Missing required column in CSV: %s', COL_ID);
assert(any(strcmp(T.Properties.VariableNames, COL_MAG)), 'Missing required column in CSV: %s', COL_MAG);

% Normalise subjectID
T.(COL_ID) = strtrim(string(T.(COL_ID)));
T.(COL_ID)(ismissing(T.(COL_ID))) = "";

if any(T.(COL_ID) == "")
    idx = find(T.(COL_ID) == "", 1, 'first');
    error('Blank subjectID detected in CSV at row %d. Aborting.', idx);
end

% Ensure unique subjectID
if numel(unique(T.(COL_ID))) ~= height(T)
    error('CSV subjectID values are not unique. Aborting.');
end

csvID = T.(COL_ID);
sortedCsvIDs = sort(csvID);
if ~isequal(sortedCsvIDs, canonicalRegistryIDs)
    error('SimpleOxford:JaspFinalise:RegistryMismatch', ...
        ['The provisional Step 9.5 CSV does not contain exactly the ' ...
         'admitted canonical registry participant set.']);
end

%% 4) Read pub XLSX and build its source participant list
assert(isfile(xlsPath), 'Missing pub XLSX: %s', xlsPath);

optsX = detectImportOptions(xlsPath, 'PreserveVariableNames', true);
optsX.VariableNamingRule = 'preserve';
publicationStringColumns = intersect( ...
    {COL_PROJECT, COL_PARTICIPANT}, optsX.VariableNames, 'stable');
if ~isempty(publicationStringColumns)
    optsX = setvartype(optsX, publicationStringColumns, 'string');
end
X = readtable(xlsPath, optsX);

% Validate required XLSX columns exist
assert(any(strcmp(X.Properties.VariableNames, COL_PROJECT)),     'Missing required column in XLSX: %s', COL_PROJECT);
assert(any(strcmp(X.Properties.VariableNames, COL_PARTICIPANT)), 'Missing required column in XLSX: %s', COL_PARTICIPANT);

publicationSourceIDAll = construct_medscinet_subject_ids( ...
    X.(COL_PROJECT), X.(COL_PARTICIPANT));
publicationRows = find(publicationSourceIDAll ~= "");
publicationSourceID = publicationSourceIDAll(publicationRows);

if isempty(publicationSourceID)
    error('Derived pub subjectID list is empty. Check XLSX columns and contents.');
end

% Ensure unique pub IDs
if numel(unique(publicationSourceID)) ~= numel(publicationSourceID)
    error('SimpleOxford:JaspFinalise:DuplicatePublicationID', ...
        'The publication XLSX contains duplicated participant IDs.');
end

if identityMode == "mapped"
    participantMap = identity.participant_map;
    [isMapped, mapLocation] = ismember( ...
        publicationSourceID, participantMap.sourceSubjectID);
    if any(~isMapped)
        firstMissing = find(~isMapped, 1, 'first');
        error('SimpleOxford:JaspFinalise:MissingPublicationMapping', ...
            ['No registry mapping exists for %d publication participant(s); ' ...
             'first affected publication source row: %d.'], ...
            sum(~isMapped), publicationRows(firstMissing));
    end
    pubID = participantMap.subjectID(mapLocation);
else
    pubID = publicationSourceID;
end

if numel(unique(pubID)) ~= numel(pubID)
    error('SimpleOxford:JaspFinalise:DuplicateCanonicalPublicationID', ...
        'Publication IDs are not unique after registry translation.');
end

%% 5) Extract HL_ER_nNRF_mag and define missingness
magRaw = T.(COL_MAG);

if isnumeric(magRaw)
    mag = double(magRaw);
else
    magStr = string(magRaw);
    magStr = strtrim(magStr);
    magStr(ismissing(magStr) | magStr == "") = "NaN";
    mag = str2double(magStr);
end

isMagMissing = isnan(mag);

%% 6) Validate pub IDs exist in CSV and have non-missing mag
[tf_pub, loc_pub] = ismember(pubID, csvID);
if ~all(tf_pub)
    error('SimpleOxford:JaspFinalise:PublicationNotInCSV', ...
        'The final table is missing %d publication participant(s).', ...
        sum(~tf_pub));
end

isPubRow = false(height(T), 1);
isPubRow(loc_pub) = true;

% Pub rows must have non-missing mag
if any(isMagMissing & isPubRow)
    error('SimpleOxford:JaspFinalise:MissingPublicationMagnitude', ...
        '%d publication participant(s) have missing %s in the CSV.', ...
        sum(isMagMissing & isPubRow), COL_MAG);
end

%% 7) Drop existing script-owned columns (if present), then add/recreate
toDrop = {COL_SCR, COL_PUB_MAG, COL_PUB_SCR};
for i = 1:numel(toDrop)
    if any(strcmp(T.Properties.VariableNames, toDrop{i}))
        T(:, toDrop{i}) = [];
    end
end

% (1) Screening based on missing mag
scr = repmat("Included", height(T), 1);
scr(isMagMissing) = "Excluded";

% (2) Pub mag (copy mag for pub rows only)
pubMag = nan(height(T), 1);
pubMag(isPubRow) = mag(isPubRow);

% (3) Pub screening
pubScr = repmat("Excluded", height(T), 1);
pubScr(~isnan(pubMag)) = "Included";

T.(COL_SCR)     = scr;
T.(COL_PUB_MAG) = pubMag;
T.(COL_PUB_SCR) = pubScr;

%% 8) Write back to CSV and verify exact textual subject IDs
local_write_verified_csv(T, csvPath);

%% 9) Summary
fprintf('\nFinalised Step 9 JASP table: %s (%d rows x %d columns)\n', ...
    csvPath, height(T), width(T));
fprintf('  %s: Excluded %d / %d\n', COL_SCR, sum(scr == "Excluded"), height(T));
fprintf('  %s: Included %d / %d\n', COL_PUB_SCR, sum(pubScr == "Included"), height(T));
fprintf('Identity route: %s (%d admitted participants).\n', ...
    identityMode, height(T));

clear identity participantMap canonicalRegistryIDs publicationSourceIDAll ...
    publicationSourceID publicationRows publicationStringColumns X optsX ...
    isMapped mapLocation;

log_command_window('stop');

%% Local functions
function local_write_verified_csv(expected, finalPath)
candidatePath = [tempname(fileparts(finalPath)) '.csv'];
candidateCleanup = onCleanup(@() local_delete_candidate(candidatePath));
writetable(expected, candidatePath);
local_verify_final_csv(candidatePath, expected);
local_atomic_promote(candidatePath, finalPath);
end

function local_verify_final_csv(csvPath, expected)
options = detectImportOptions(csvPath, ...
    'PreserveVariableNames', true, 'TextType', 'string');
if ~any(strcmp(options.VariableNames, 'subjectID'))
    error('SimpleOxford:JaspFinalise:OutputVerification', ...
        'Candidate Step 9.6 CSV is missing subjectID.');
end
options = setvartype(options, 'subjectID', 'string');
observed = readtable(csvPath, options);
if ~local_csv_tables_equal(observed, expected)
    error('SimpleOxford:JaspFinalise:OutputVerification', ...
        ['Candidate Step 9.6 CSV did not preserve its exact row order, ' ...
         'schema, values, and textual subjectID values.']);
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
    error('SimpleOxford:JaspFinalise:OutputPromotion', ...
        'The verified Step 9.6 CSV could not be promoted atomically.');
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
        error('SimpleOxford:JaspFinalise:MissingHelper', ...
            'Required repository helper is unavailable: %s', helperName);
    end
    resolvedPath = char(java.io.File(resolvedPath).getCanonicalPath());
    if ~strcmp(resolvedPath, expectedPath)
        error('SimpleOxford:JaspFinalise:WrongHelper', ...
            ['Required helper %s must resolve to this checkout. Expected ' ...
             '%s, resolved %s.'], helperName, expectedPath, resolvedPath);
    end
end
end
