%% step_8_gen_2_sample_details.m
%
% Create the participant-level source values and save/display the source table
% used to prepare Supplementary Table 3 (Petal dataset characteristics).
%
% After the script finishes, these two tables remain in the MATLAB
% workspace:
%   - participantDetailsTable: the participant-level source values
%   - supplementaryTable1: the source table for the manuscript
%
% Inputs:
%   1) data_lists/dataset_list.csv
%      Required canonical columns:
%         - subjectID, sessionID, runID, path_raw, EEGfile_raw
%      The optional replacement-ID route additionally supplies the complete
%      five-column *_orig mapping created by Step 2.10.
%
%   2) data_lists/medscinet_export_petal.xlsx
%      Required columns:
%         - RECD - Research project
%         - RECD - Participant number
%         - BIRTH - Gender
%         - BIRTH - Gestation at birth (w)
%         - BIRTH - Gestation at birth (d)
%         - BIRTH - Birth weight
%         - TESTOD - Gestational age at test occasion - w
%         - TESTOD - Gestational age at test occasion - d
%         - TESTOD - Relevant interventions during test occasion
%         - Stimulus/Clinical Procedure 2: PIPP-R 2022 1: PIPPR -
%           Behavioural State
%
% Matching rule:
%   MedSciNet source ID = (RECD - Research project, with "OX" changed to
%   "Ox") + (RECD - Participant number). With an original registry this is
%   matched directly. With a mapped registry it is translated through the
%   private participant map and only replacement subjectID is retained in
%   participantDetailsTable. Mapped mode requires exactly one complete source
%   row for each admitted participant and ignores malformed or duplicated
%   source-only identifier rows.
%
% Output:
%   data/results/supplementary_table_1_petal_dataset_characteristics.csv
%   The CSV is UTF-8 with a byte-order mark for reliable direct opening in
%   Microsoft Excel. Subgroup labels use an en dash rather than a leading
%   ASCII hyphen-minus.
%
% The table describes every participant in dataset_list.csv. Percentages
% therefore use that full participant count as their denominator.

log_command_window('start');
clear; clc;

%% Paths
baseDir = '/Users/lukebaxter/Developer/simple-eeg/simple-oxford';
functionsDir = fullfile(baseDir, 'functions');
addpath(functionsDir, '-begin');
clear load_dataset_identity_registry construct_medscinet_subject_ids
rehash path
local_assert_helper_paths(functionsDir, { ...
    'load_dataset_identity_registry', ...
    'construct_medscinet_subject_ids'});

datasetInPath = fullfile(baseDir, 'data_lists', 'dataset_list.csv');
medInPath = fullfile(baseDir, 'data_lists', ...
    'medscinet_export_petal.xlsx');
resultsDir = fullfile(baseDir, 'data', 'results');
tableOutPath = fullfile(resultsDir, ...
    'supplementary_table_1_petal_dataset_characteristics.csv');

%% Check input files exist
if ~isfile(datasetInPath)
    error('Input file not found: %s', datasetInPath);
end

if ~isfile(medInPath)
    error('Input file not found: %s', medInPath);
end

%% Read the dataset registry and establish the participant identity bridge
identity = load_dataset_identity_registry(datasetInPath);
identityMode = identity.mode;
participantMap = identity.participant_map;
participantMap = sortrows(participantMap, 'subjectID');
cohortSourceID = participantMap.sourceSubjectID;
cohortSubjectID = participantMap.subjectID;

%% Read medscinet_export_petal.xlsx
medOpts = detectImportOptions(medInPath, 'PreserveVariableNames', true);

medStringVars = { ...
    'RECD - Research project', ...
    'RECD - Participant number', ...
    'BIRTH - Gender', ...
    'TESTOD - Relevant interventions during test occasion', ...
    ['Stimulus/Clinical Procedure 2: PIPP-R 2022 1: PIPPR - ' ...
        'Behavioural State']};

medStringVarsPresent = intersect(medStringVars, ...
    medOpts.VariableNames, 'stable');
if ~isempty(medStringVarsPresent)
    medOpts = setvartype(medOpts, medStringVarsPresent, 'string');
end
medTbl = readtable(medInPath, medOpts);

%% Validate required MedSciNet columns
colArm = 'TESTOD - Relevant interventions during test occasion';
colSleep = [ ...
    'Stimulus/Clinical Procedure 2: PIPP-R 2022 1: PIPPR - ' ...
    'Behavioural State'];
requiredMedVars = { ...
    'RECD - Research project', ...
    'RECD - Participant number', ...
    'BIRTH - Gender', ...
    'BIRTH - Gestation at birth (w)', ...
    'BIRTH - Gestation at birth (d)', ...
    'BIRTH - Birth weight', ...
    'TESTOD - Gestational age at test occasion - w', ...
    'TESTOD - Gestational age at test occasion - d', ...
    colArm, ...
    colSleep};

missingMedVars = setdiff(requiredMedVars, medTbl.Properties.VariableNames);
if ~isempty(missingMedVars)
    error('Missing required column(s) in medscinet_export_petal.xlsx: %s', ...
        strjoin(missingMedVars, ', '));
end

%% Resolve exactly one source row per admitted participant
projectComponent = local_clean_text( ...
    medTbl.('RECD - Research project'));
participantComponent = local_clean_text( ...
    medTbl.('RECD - Participant number'));

if identityMode == "original"
    % Preserve strict whole-source validation in the original route.
    medSubjectID = construct_medscinet_subject_ids( ...
        projectComponent, participantComponent);
    nonMissingIDMask = medSubjectID ~= "";
    idsToCheck = medSubjectID(nonMissingIDMask);
    [~, ~, groupIdx] = unique(idsToCheck);
    dupCounts = accumarray(groupIdx, 1);
    duplicateGroups = find(dupCounts > 1);
    if ~isempty(duplicateGroups)
        nonMissingRows = find(nonMissingIDMask);
        duplicateSourceRows = nonMissingRows( ...
            ismember(groupIdx, duplicateGroups));
        error('SimpleOxford:SampleDetails:DuplicateSourceID', ...
            ['The MedSciNet source workbook contains %d duplicated ' ...
             'participant ID group(s); first affected source row: %d.'], ...
            numel(duplicateGroups), duplicateSourceRows(1));
    end
    [isMatched, medLoc] = ismember(cohortSourceID, medSubjectID);
else
    % In mapped mode, malformed or duplicated source-only rows are outside
    % the admitted master cohort. Build IDs only for complete component pairs
    % and require exactly one such row for every admitted original ID.
    completeSourceRows = projectComponent ~= "" & participantComponent ~= "";
    completeRowNumbers = find(completeSourceRows);
    completeSourceIDs = construct_medscinet_subject_ids( ...
        projectComponent(completeSourceRows), ...
        participantComponent(completeSourceRows));
    [uniqueSourceIDs, ~, sourceGroups] = unique( ...
        completeSourceIDs, 'stable');
    sourceCounts = accumarray(sourceGroups, 1);
    duplicatedSourceIDs = uniqueSourceIDs(sourceCounts > 1);
    duplicatedMapRows = find(ismember( ...
        cohortSourceID, duplicatedSourceIDs));
    if ~isempty(duplicatedMapRows)
        error('SimpleOxford:SampleDetails:DuplicateAdmittedSourceID', ...
            ['An admitted participant has multiple MedSciNet rows; first ' ...
             'affected participant-map row: %d.'], duplicatedMapRows(1));
    end
    [isMatched, completeLocations] = ismember( ...
        cohortSourceID, completeSourceIDs);
    medLoc = zeros(numel(cohortSourceID), 1);
    medLoc(isMatched) = completeRowNumbers(completeLocations(isMatched));
end
if any(~isMatched)
    firstMissing = find(~isMatched, 1, 'first');
    error('SimpleOxford:SampleDetails:MissingSourceMatch', ...
        ['No matching MedSciNet row was found for %d admitted ' ...
         'participant(s); first affected participant-map row: %d.'], ...
        sum(~isMatched), firstMissing);
end

%% Convert and derive participant characteristics
% Restrict all clinical-field validation and recoding to the admitted
% participant rows. MedSciNet-only rows are deliberately outside this table.
selectedMedTbl = medTbl(medLoc, :);
gaBirthW = local_to_numeric( ...
    selectedMedTbl.('BIRTH - Gestation at birth (w)'));
gaBirthD = local_to_numeric( ...
    selectedMedTbl.('BIRTH - Gestation at birth (d)'));
birthWt = local_to_numeric(selectedMedTbl.('BIRTH - Birth weight'));
pmaStudyW = local_to_numeric( ...
    selectedMedTbl.('TESTOD - Gestational age at test occasion - w'));
pmaStudyD = local_to_numeric( ...
    selectedMedTbl.('TESTOD - Gestational age at test occasion - d'));

ageGaBirthWeeks = gaBirthW + (gaBirthD ./ 7);
agePmaStudyWeeks = pmaStudyW + (pmaStudyD ./ 7);
agePnaStudyDays = (agePmaStudyWeeks - ageGaBirthWeeks) .* 7;

sex = local_clean_text(selectedMedTbl.('BIRTH - Gender'));
trialArm = local_recode_trial_arm(selectedMedTbl.(colArm));
sleepState = local_recode_sleep_state(selectedMedTbl.(colSleep));

%% Build the participant-level workspace table
participantDetailsTable = table();
participantDetailsTable.subjectID = cohortSubjectID;
participantDetailsTable.age_ga_birth_weeks = ageGaBirthWeeks;
participantDetailsTable.age_pma_study_weeks = agePmaStudyWeeks;
participantDetailsTable.age_pna_study_days = agePnaStudyDays;
participantDetailsTable.birthweight_grams = birthWt;
participantDetailsTable.sex = sex;
participantDetailsTable.trial_arm = trialArm;
participantDetailsTable.HL_sleep_state = sleepState;
participantDetailsTable = sortrows(participantDetailsTable, 'subjectID');

%% Fail closed if the manuscript-summary denominator would be ambiguous
if height(participantDetailsTable) == 0 || ...
        any(participantDetailsTable.subjectID == "") || ...
        any(~isfinite(participantDetailsTable.age_ga_birth_weeks)) || ...
        any(~isfinite(participantDetailsTable.age_pma_study_weeks)) || ...
        any(~isfinite(participantDetailsTable.age_pna_study_days)) || ...
        any(~isfinite(participantDetailsTable.birthweight_grams)) || ...
        any(participantDetailsTable.sex == "") || ...
        any(participantDetailsTable.trial_arm == "") || ...
        any(participantDetailsTable.HL_sleep_state == "")
    error('SimpleOxford:SampleDetails:IncompleteData', ...
        ['Supplementary Table 3 requires complete participant-level ' ...
        'values for every displayed characteristic.']);
end

local_require_categories(participantDetailsTable.sex, ...
    ["Female", "Male"], 'sex');
local_require_categories(participantDetailsTable.trial_arm, ...
    ["Intervention", "Control"], 'trial_arm');
local_require_categories(participantDetailsTable.HL_sleep_state, ...
    ["Asleep", "Awake"], 'HL_sleep_state');

%% Calculate the exact manuscript summaries
n = height(participantDetailsTable);
[gaMedian, gaIQR] = local_median_iqr( ...
    participantDetailsTable.age_ga_birth_weeks);
[pmaMedian, pmaIQR] = local_median_iqr( ...
    participantDetailsTable.age_pma_study_weeks);
[pnaMedian, pnaIQR] = local_median_iqr( ...
    participantDetailsTable.age_pna_study_days);
[birthweightMedian, birthweightIQR] = local_median_iqr( ...
    participantDetailsTable.birthweight_grams);

Characteristic = [ ...
    "Sample size"; ...
    "Age"; ...
    "– Gestational age at birth (weeks)"; ...
    "– Postmenstrual age at time of study (weeks)"; ...
    "– Postnatal age at time of study (days)"; ...
    "Birthweight (g)"; ...
    "Sex"; ...
    "– Female"; ...
    "– Male"; ...
    "Trial arm"; ...
    "– Intervention"; ...
    "– Control"; ...
    "Sleep state pre-heel lance"; ...
    "– Asleep"; ...
    "– Awake"];

Value = [ ...
    string(n); ...
    ""; ...
    string(sprintf('%.1f (%.1f)', gaMedian, gaIQR)); ...
    string(sprintf('%.1f (%.1f)', pmaMedian, pmaIQR)); ...
    string(sprintf('%.1f (%.1f)', pnaMedian, pnaIQR)); ...
    string(sprintf('%.0f (%.1f)', ...
        birthweightMedian, birthweightIQR)); ...
    ""; ...
    local_count_percent(participantDetailsTable.sex, "Female", n); ...
    local_count_percent(participantDetailsTable.sex, "Male", n); ...
    ""; ...
    local_count_percent( ...
        participantDetailsTable.trial_arm, "Intervention", n); ...
    local_count_percent( ...
        participantDetailsTable.trial_arm, "Control", n); ...
    ""; ...
    local_count_percent( ...
        participantDetailsTable.HL_sleep_state, "Asleep", n); ...
    local_count_percent( ...
        participantDetailsTable.HL_sleep_state, "Awake", n)];

supplementaryTable1 = table(Characteristic, Value);

fprintf(['\nSupplementary Table 3. Petal dataset characteristics. ' ...
    'Values are median (IQR) or n (%%).\n\n']);
disp(supplementaryTable1);
fprintf('Identity route: %s (%d admitted participants).\n', ...
    identityMode, height(participantDetailsTable));

%% Create the results folder and save the validated manuscript table
if ~isfolder(resultsDir)
    [ok, message] = mkdir(resultsDir);
    if ~ok
        error('Failed to create results directory %s: %s', ...
            resultsDir, message);
    end
end
writetable(supplementaryTable1, tableOutPath, 'Encoding', 'UTF-8');
local_add_utf8_bom(tableOutPath);
fprintf('Saved Supplementary Table 3: %s\n', tableOutPath);

% Keep the documented manuscript tables while dropping private source-ID
% working variables from the successful base workspace.
clear identity participantMap cohortSourceID medSubjectID medTbl selectedMedTbl medOpts ...
    medStringVars medStringVarsPresent nonMissingIDMask idsToCheck ...
    groupIdx dupCounts duplicateGroups duplicateSourceRows ...
    nonMissingRows ...
    isMatched medLoc projectComponent participantComponent ...
    completeSourceRows completeRowNumbers completeSourceIDs ...
    uniqueSourceIDs sourceGroups sourceCounts duplicatedSourceIDs ...
    duplicatedMapRows completeLocations;

log_command_window('stop');

%% Local functions
function x = local_clean_text(x)
if iscell(x)
    x = string(x);
elseif ischar(x)
    x = string(cellstr(x));
elseif ~isstring(x)
    x = string(x);
end
x = strtrim(x);
x(ismissing(x)) = "";
end

function x = local_to_numeric(x)
if isnumeric(x)
    x = double(x);
    return;
end
if iscell(x)
    x = string(x);
elseif ischar(x)
    x = string(cellstr(x));
elseif ~isstring(x)
    x = string(x);
end
x = strtrim(x);
x(ismissing(x)) = "";
x = strrep(x, ",", "");
x = double(str2double(x));
end

function values = local_recode_trial_arm(values)
values = local_clean_text(values);
controlSource = "Post-procedural parent stroking";
interventionSource = "Pre-procedural parent stroking";
for i = 1:numel(values)
    if values(i) == ""
        continue;
    elseif values(i) == controlSource
        values(i) = "Control";
    elseif values(i) == interventionSource
        values(i) = "Intervention";
    else
        error('SimpleOxford:SampleDetails:UnexpectedCategory', ...
            'Unexpected trial-arm category at admitted participant row %d.', i);
    end
end
end

function values = local_recode_sleep_state(values)
values = local_clean_text(values);
for i = 1:numel(values)
    if values(i) == ""
        continue;
    elseif startsWith(values(i), "Active and asleep") || ...
            startsWith(values(i), "Quiet and asleep")
        values(i) = "Asleep";
    elseif startsWith(values(i), "Active and awake") || ...
            startsWith(values(i), "Quiet and awake")
        values(i) = "Awake";
    else
        error('SimpleOxford:SampleDetails:UnexpectedCategory', ...
            ['Unexpected heel-lance sleep-state category at admitted ' ...
             'participant row %d.'], i);
    end
end
end

function local_require_categories(values, allowed, fieldName)
unexpected = ~ismember(values, allowed);
if any(unexpected)
    firstRow = find(unexpected, 1, 'first');
    error('SimpleOxford:SampleDetails:UnexpectedCategory', ...
        'Unexpected %s category at admitted participant row %d.', ...
        fieldName, firstRow);
end
end

function [centre, spread] = local_median_iqr(values)
values = sort(double(values(:)));
centre = median(values);
q1 = local_type7_quantile(values, 0.25);
q3 = local_type7_quantile(values, 0.75);
spread = q3 - q1;
end

function value = local_type7_quantile(values, probability)
position = 1 + (numel(values) - 1) * probability;
lowerIndex = floor(position);
upperIndex = ceil(position);
fraction = position - lowerIndex;
value = values(lowerIndex) + ...
    fraction * (values(upperIndex) - values(lowerIndex));
end

function value = local_count_percent(values, target, denominator)
count = sum(values == target);
value = string(sprintf('%d (%.1f%%)', ...
    count, 100 * count / denominator));
end

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

function local_assert_helper_paths(functionsDir, helperNames)
for helperIndex = 1:numel(helperNames)
    helperName = helperNames{helperIndex};
    expectedPath = char(java.io.File(fullfile( ...
        functionsDir, [helperName '.m'])).getCanonicalPath());
    resolvedPath = which(helperName);
    if isempty(resolvedPath)
        error('SimpleOxford:SampleDetails:MissingHelper', ...
            'Required repository helper is unavailable: %s', helperName);
    end
    resolvedPath = char(java.io.File(resolvedPath).getCanonicalPath());
    if ~strcmp(resolvedPath, expectedPath)
        error('SimpleOxford:SampleDetails:WrongHelper', ...
            ['Required helper %s must resolve to this checkout. Expected ' ...
             '%s, resolved %s.'], helperName, expectedPath, resolvedPath);
    end
end
end
