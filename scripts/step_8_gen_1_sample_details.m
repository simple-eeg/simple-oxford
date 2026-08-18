%% step_8_gen_1_sample_details.m
%
% Create the participant-level source table and save/display:
%   Supplementary Table 1. Petal dataset characteristics.
%
% After the script finishes, these two tables remain in the MATLAB
% workspace:
%   - participantDetailsTable: the participant-level source values
%   - supplementaryTable1: the formatted manuscript table
%
% Inputs:
%   1) data_lists/dataset_list.csv
%      Required column:
%         - subjectID
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
%   subjectID = (RECD - Research project, with uppercase X changed to
%   lowercase x) + (RECD - Participant number)
%
% Output:
%   data/results/supplementary_table_1_petal_dataset_characteristics.csv
%
% The table describes every participant in dataset_list.csv. Percentages
% therefore use that full participant count as their denominator.

log_command_window('start');
clear; clc;

%% Paths
baseDir = '/Users/lukebaxter/Developer/simple-eeg/simple-oxford';

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

%% Read the dataset registry and establish the participant master
datasetOpts = detectImportOptions(datasetInPath, ...
    'PreserveVariableNames', true);
if any(strcmp(datasetOpts.VariableNames, 'subjectID'))
    datasetOpts = setvartype(datasetOpts, 'subjectID', 'string');
end
datasetTbl = readtable(datasetInPath, datasetOpts);

if ~any(strcmp(datasetTbl.Properties.VariableNames, 'subjectID'))
    error('Missing required column in dataset_list.csv: subjectID');
end

cohortSubjectID = local_clean_text(datasetTbl.subjectID);
if isempty(cohortSubjectID) || any(cohortSubjectID == "")
    error('SimpleOxford:SampleDetails:InvalidDatasetList', ...
        'dataset_list.csv must contain nonblank subjectID values.');
end
if numel(unique(cohortSubjectID)) ~= numel(cohortSubjectID)
    error('SimpleOxford:SampleDetails:InvalidDatasetList', ...
        'dataset_list.csv subjectID values must be unique.');
end
cohortSubjectID = sort(cohortSubjectID);

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

%% Construct MedSciNet subjectID
proj = local_clean_text(medTbl.('RECD - Research project'));
part = local_clean_text(medTbl.('RECD - Participant number'));
proj = replace(proj, "X", "x");
medSubjectID = local_clean_text(proj + part);

nonMissingIDMask = medSubjectID ~= "";
idsToCheck = medSubjectID(nonMissingIDMask);
[uniqueIDs, ~, groupIdx] = unique(idsToCheck);
dupCounts = accumarray(groupIdx, 1);
dupIDs = uniqueIDs(dupCounts > 1);
if ~isempty(dupIDs)
    error(['Duplicate constructed subjectID(s) found in ' ...
        'medscinet_export_petal.xlsx: %s'], ...
        strjoin(cellstr(dupIDs), ', '));
end

%% Match the registry cohort to MedSciNet
[isMatched, medLoc] = ismember(cohortSubjectID, medSubjectID);
if any(~isMatched)
    unmatchedIDs = cohortSubjectID(~isMatched);
    error('No matching MedSciNet row found for subjectID(s): %s', ...
        strjoin(cellstr(unmatchedIDs), ', '));
end

%% Convert and derive participant characteristics
gaBirthW = local_to_numeric( ...
    medTbl.('BIRTH - Gestation at birth (w)'));
gaBirthD = local_to_numeric( ...
    medTbl.('BIRTH - Gestation at birth (d)'));
birthWt = local_to_numeric(medTbl.('BIRTH - Birth weight'));
pmaStudyW = local_to_numeric( ...
    medTbl.('TESTOD - Gestational age at test occasion - w'));
pmaStudyD = local_to_numeric( ...
    medTbl.('TESTOD - Gestational age at test occasion - d'));

ageGaBirthWeeks = gaBirthW + (gaBirthD ./ 7);
agePmaStudyWeeks = pmaStudyW + (pmaStudyD ./ 7);
agePnaStudyDays = (agePmaStudyWeeks - ageGaBirthWeeks) .* 7;

sex = local_clean_text(medTbl.('BIRTH - Gender'));
trialArm = local_recode_trial_arm(medTbl.(colArm));
sleepState = local_recode_sleep_state(medTbl.(colSleep));

%% Build the participant-level workspace table
participantDetailsTable = table();
participantDetailsTable.subjectID = cohortSubjectID;
participantDetailsTable.age_ga_birth_weeks = ageGaBirthWeeks(medLoc);
participantDetailsTable.age_pma_study_weeks = agePmaStudyWeeks(medLoc);
participantDetailsTable.age_pna_study_days = agePnaStudyDays(medLoc);
participantDetailsTable.birthweight_grams = birthWt(medLoc);
participantDetailsTable.sex = sex(medLoc);
participantDetailsTable.trial_arm = trialArm(medLoc);
participantDetailsTable.HL_sleep_state = sleepState(medLoc);
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
        ['Supplementary Table 1 requires complete participant-level ' ...
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
    "- Gestational age at birth (weeks)"; ...
    "- Postmenstrual age at time of study (weeks)"; ...
    "- Postnatal age at time of study (days)"; ...
    "Birthweight (g)"; ...
    "Sex"; ...
    "- Female"; ...
    "- Male"; ...
    "Trial arm"; ...
    "- Intervention"; ...
    "- Control"; ...
    "Sleep state pre-heel lance"; ...
    "- Asleep"; ...
    "- Awake"];

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

fprintf(['\nSupplementary Table 1. Petal dataset characteristics. ' ...
    'Values are median (IQR) or n (%%).\n\n']);
disp(supplementaryTable1);

%% Create the results folder and save the validated manuscript table
if ~isfolder(resultsDir)
    [ok, message] = mkdir(resultsDir);
    if ~ok
        error('Failed to create results directory %s: %s', ...
            resultsDir, message);
    end
end
writetable(supplementaryTable1, tableOutPath);
fprintf('Saved Supplementary Table 1: %s\n', tableOutPath);

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
            'Unexpected trial-arm source value: %s', values(i));
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
            'Unexpected heel-lance sleep-state source value: %s', ...
            values(i));
    end
end
end

function local_require_categories(values, allowed, fieldName)
unexpected = setdiff(unique(values), allowed);
if ~isempty(unexpected)
    error('SimpleOxford:SampleDetails:UnexpectedCategory', ...
        'Unexpected %s value(s): %s', fieldName, ...
        strjoin(cellstr(unexpected), ', '));
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
