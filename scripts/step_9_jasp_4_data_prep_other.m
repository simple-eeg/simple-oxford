%% step_9_jasp_4_data_prep_other.m
% Purpose
%   - Read the admitted participant identity route from:
%       data_lists/dataset_list.csv
%   - Read upstream MedSciNet export:
%       data_lists/medscinet_export_petal.xlsx
%   - Derive subjectID from:
%       RECD - Research project + RECD - Participant number
%       with project casing normalised ("OX" -> "Ox").
%   - Extract and recode:
%       • trial arm
%       • HL sleep state prior to heel lance
%   - Allow missing trial arm / sleep state (leave blank). Original mode
%     validates every source identifier strictly. Mapped mode requires exactly
%     one complete source row per admitted original ID and ignores malformed or
%     duplicated source-only identifiers.
%   - Hard-error on unexpected non-empty trial-arm or sleep-state values within
%     the route cohort.
%   - Create data/results/ if missing, and write:
%       data/results/jasp_data_other.csv
%   - With an original registry, retain every valid MedSciNet participant.
%   - With a mapped registry, emit only admitted registry participants and
%     translate source IDs to canonical replacement subjectID values.
%   - Output rows sorted by subjectID; columns in exact order specified below.
%
% Output schema (columns in this exact order)
%   subjectID
%   trial_arm
%   HL_sleep_state
%
% Trial arm source + mapping
%   Source column:
%     TESTOD - Relevant interventions during test occasion
%   Allowed non-empty values (after trimming leading/trailing whitespace):
%     "Post-procedural parent stroking" -> Control
%     "Pre-procedural parent stroking"  -> Intervention
%   Missing/empty -> leave blank.
%   Any other non-empty value -> hard error.
%
% HL sleep state source + mapping
%   Source column (exact; do not use the "- Unknown" column):
%     Stimulus/Clinical Procedure 2: PIPP-R 2022 1: PIPPR - Behavioural State
%   After trimming leading/trailing whitespace:
%     Must start with one of:
%       "Active and asleep"  -> Asleep
%       "Quiet and asleep"   -> Asleep
%       "Active and awake"   -> Awake
%       "Quiet and awake"    -> Awake
%   Missing/empty -> leave blank.
%   Any non-empty value not starting with one of the four prefixes -> hard error.

log_command_window('start');
clear; clc;

%% 0) User config: paths and exact column headers
baseDir = '/Users/lukebaxter/Developer/simple-eeg/simple-oxford';
functionsDir = fullfile(baseDir, 'functions');
addpath(functionsDir, '-begin');
clear load_dataset_identity_registry construct_medscinet_subject_ids
rehash path
local_assert_helper_paths(functionsDir, { ...
    'load_dataset_identity_registry', ...
    'construct_medscinet_subject_ids'});

datasetCsv = fullfile(baseDir, 'data_lists', 'dataset_list.csv');
inXlsx = fullfile(baseDir, 'data_lists', 'medscinet_export_petal.xlsx');

outDir = fullfile(baseDir, 'data', 'results');
outCsv = fullfile(outDir, 'jasp_data_other.csv');

COL_PROJECT     = 'RECD - Research project';
COL_PARTICIPANT = 'RECD - Participant number';

COL_ARM = 'TESTOD - Relevant interventions during test occasion';

COL_SLEEP = 'Stimulus/Clinical Procedure 2: PIPP-R 2022 1: PIPPR - Behavioural State';
% Do NOT use:
%   'Stimulus/Clinical Procedure 2: PIPP-R 2022 1: PIPPR - Behavioural State - Unknown'

OUT_COLS = { ...
    'subjectID', ...
    'trial_arm', ...
    'HL_sleep_state' ...
    };

ARM_CONTROL_SRC      = "Post-procedural parent stroking";
ARM_INTERVENTION_SRC = "Pre-procedural parent stroking";

%% 1) Read and validate the admitted participant identity route
if ~isfile(datasetCsv)
    error('Input file not found: %s', datasetCsv);
end
identity = load_dataset_identity_registry(datasetCsv);
identityMode = identity.mode;

%% 2) Read MedSciNet spreadsheet and validate required columns
if ~isfile(inXlsx)
    error('Input file not found: %s', inXlsx);
end

sourceOptions = detectImportOptions(inXlsx, ...
    'PreserveVariableNames', true);
sourceStringColumns = {COL_PROJECT, COL_PARTICIPANT, COL_ARM, COL_SLEEP};
presentStringColumns = intersect(sourceStringColumns, ...
    sourceOptions.VariableNames, 'stable');
if ~isempty(presentStringColumns)
    sourceOptions = setvartype(sourceOptions, ...
        presentStringColumns, 'string');
end
T = readtable(inXlsx, sourceOptions);

needCols = {COL_PROJECT, COL_PARTICIPANT, COL_ARM, COL_SLEEP};
missing = setdiff(needCols, T.Properties.VariableNames);
if ~isempty(missing)
    error('Missing required columns in medscinet_export_petal.xlsx: %s', strjoin(missing, ', '));
end

%% 3) Extract and normalise source columns
project_raw = local_clean_text(T.(COL_PROJECT));
participant_raw = local_clean_text(T.(COL_PARTICIPANT));
arm_raw = local_clean_text(T.(COL_ARM));
sleep_raw = local_clean_text(T.(COL_SLEEP));

%% 4) Resolve the route cohort and canonical identity
sourceOnlyCount = 0;
if identityMode == "original"
    % Preserve strict whole-source validation in the original route.
    sourceSubjectID = construct_medscinet_subject_ids( ...
        project_raw, participant_raw);
    bad_sid = (sourceSubjectID == "");
    if any(bad_sid)
        idx = find(bad_sid, 1, 'first');
        error('SimpleOxford:JaspOther:BlankSourceID', ...
            ['Blank participant ID generated at source row %d. Check ' ...
             'columns "%s" and "%s" for missing values.'], ...
            idx, COL_PROJECT, COL_PARTICIPANT);
    end
    [~, ~, ic] = unique(sourceSubjectID, 'stable');
    counts = accumarray(ic, 1);
    duplicateGroups = find(counts > 1);
    if ~isempty(duplicateGroups)
        duplicateRows = find(ismember(ic, duplicateGroups));
        error('SimpleOxford:JaspOther:DuplicateSourceID', ...
            ['The MedSciNet source workbook contains %d duplicated ' ...
             'participant ID group(s); first affected source row: %d.'], ...
            numel(duplicateGroups), duplicateRows(1));
    end
    subjectID = sourceSubjectID;
    sourceLocation = (1:numel(sourceSubjectID))';
else
    participantMap = identity.participant_map;
    completeSourceRows = project_raw ~= "" & participant_raw ~= "";
    completeRowNumbers = find(completeSourceRows);
    completeSourceIDs = construct_medscinet_subject_ids( ...
        project_raw(completeSourceRows), ...
        participant_raw(completeSourceRows));
    [uniqueSourceIDs, ~, sourceGroups] = unique( ...
        completeSourceIDs, 'stable');
    sourceCounts = accumarray(sourceGroups, 1);
    duplicatedSourceIDs = uniqueSourceIDs(sourceCounts > 1);
    duplicatedMapRows = find(ismember( ...
        participantMap.sourceSubjectID, duplicatedSourceIDs));
    if ~isempty(duplicatedMapRows)
        error('SimpleOxford:JaspOther:DuplicateAdmittedSourceID', ...
            ['An admitted participant has multiple MedSciNet rows; first ' ...
             'affected participant-map row: %d.'], duplicatedMapRows(1));
    end
    [isMatched, completeLocations] = ismember( ...
        participantMap.sourceSubjectID, completeSourceIDs);
    if any(~isMatched)
        firstMissing = find(~isMatched, 1, 'first');
        error('SimpleOxford:JaspOther:MissingSourceMatch', ...
            ['No MedSciNet row was found for %d admitted participant(s); ' ...
             'first affected participant-map row: %d.'], ...
            sum(~isMatched), firstMissing);
    end
    sourceLocation = completeRowNumbers(completeLocations);
    subjectID = participantMap.subjectID;
    sourceOnlyIDs = unique(completeSourceIDs( ...
        ~ismember(completeSourceIDs, participantMap.sourceSubjectID)), ...
        'stable');
    sourceOnlyCount = numel(sourceOnlyIDs);
end

% Source-only MedSciNet rows are deliberately outside mapped Step 9.4.
% Validate and recode only the rows selected by the active identity route.
arm_raw = arm_raw(sourceLocation);
sleep_raw = sleep_raw(sourceLocation);

%% 7) Recode trial arm (allow missing; hard error on unexpected non-empty values)
n = numel(subjectID);
trial_arm = strings(n,1);

for i = 1:n
    a = arm_raw(i);

    if a == ""
        trial_arm(i) = "";
        continue
    end

    if a == ARM_CONTROL_SRC
        trial_arm(i) = "Control";
    elseif a == ARM_INTERVENTION_SRC
        trial_arm(i) = "Intervention";
    else
        error('SimpleOxford:JaspOther:UnexpectedTrialArm', ...
            'Unexpected trial-arm category in "%s" at selected row %d.', ...
            COL_ARM, i);
    end
end

%% 8) Recode HL sleep state (allow missing; hard error on unexpected non-empty values)
HL_sleep_state = strings(n,1);

for i = 1:n
    s = sleep_raw(i);

    if s == ""
        HL_sleep_state(i) = "";
        continue
    end

    if startsWith(s, "Active and asleep")
        HL_sleep_state(i) = "Asleep";
    elseif startsWith(s, "Quiet and asleep")
        HL_sleep_state(i) = "Asleep";
    elseif startsWith(s, "Active and awake")
        HL_sleep_state(i) = "Awake";
    elseif startsWith(s, "Quiet and awake")
        HL_sleep_state(i) = "Awake";
    else
        error('SimpleOxford:JaspOther:UnexpectedSleepState', ...
            'Unexpected sleep-state category in "%s" at selected row %d.', ...
            COL_SLEEP, i);
    end
end

%% 9) Assemble output table (fixed column order) and sort by subjectID
Tout = table(subjectID, trial_arm, HL_sleep_state);
Tout.Properties.VariableNames = OUT_COLS;

Tout = sortrows(Tout, 'subjectID');

%% 10) Create the results directory and write the fully validated CSV
if ~exist(outDir, 'dir')
    ok = mkdir(outDir);
    if ~ok
        error('Failed to create output directory: %s', outDir);
    end
end
local_write_verified_csv(Tout, outCsv);
fprintf('Wrote Step 9.4 intermediate: %s (%d rows x %d columns)\n', ...
    outCsv, height(Tout), width(Tout));
if identityMode == "mapped"
    fprintf(['Identity route: mapped (%d admitted participants; %d ' ...
        'source-only participant(s) omitted).\n'], ...
        height(Tout), sourceOnlyCount);
else
    fprintf('Identity route: original (%d source participants retained).\n', ...
        height(Tout));
end

clear identity participantMap T sourceSubjectID sourceOptions ...
    sourceStringColumns presentStringColumns ic counts duplicateGroups ...
    duplicateRows isMatched sourceLocation project_raw participant_raw ...
    completeSourceRows completeRowNumbers completeSourceIDs ...
    uniqueSourceIDs sourceGroups sourceCounts duplicatedSourceIDs ...
    duplicatedMapRows completeLocations sourceOnlyIDs;

log_command_window('stop');

%% Local functions
function values = local_clean_text(values)
values = string(values);
values = values(:);
values(ismissing(values)) = "";
values = strtrim(values);
end

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
    error('SimpleOxford:JaspOther:OutputVerification', ...
        'Candidate Step 9.4 CSV is missing subjectID.');
end
options = setvartype(options, 'subjectID', 'string');
observed = readtable(csvPath, options);
if ~local_csv_tables_equal(observed, expected)
    error('SimpleOxford:JaspOther:OutputVerification', ...
        ['Candidate Step 9.4 CSV did not preserve its exact schema, ' ...
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
    error('SimpleOxford:JaspOther:OutputPromotion', ...
        'The verified Step 9.4 CSV could not be promoted atomically.');
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
        error('SimpleOxford:JaspOther:MissingHelper', ...
            'Required repository helper is unavailable: %s', helperName);
    end
    resolvedPath = char(java.io.File(resolvedPath).getCanonicalPath());
    if ~strcmp(resolvedPath, expectedPath)
        error('SimpleOxford:JaspOther:WrongHelper', ...
            ['Required helper %s must resolve to this checkout. Expected ' ...
             '%s, resolved %s.'], helperName, expectedPath, resolvedPath);
    end
end
end
