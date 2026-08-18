%% step_9_gen_2_sample_details.m
%
% Create the participant-level source table and display:
%   Supplementary Table 1. Petal dataset characteristics.
%
% This is a general manuscript-output script. It does not write a CSV,
% figure, table, log or other scientific output file. After the script
% finishes, these two tables remain in the MATLAB workspace:
%   - participantDetailsTable: the participant-level source values
%   - supplementaryTable1: the formatted manuscript table
%
% Inputs:
%   1) data/results/jasp_data_all.csv
%      Required columns:
%         - subjectID
%         - trial_arm
%         - HL_sleep_state
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
%
% Matching rule:
%   subjectID = (RECD - Research project, with uppercase X changed to
%   lowercase x) + (RECD - Participant number)
%
% The table describes every participant in jasp_data_all.csv. Percentages
% therefore use that full participant count as their denominator.

clear; clc;

%% Paths
baseDir = '/Users/lukebaxter/Developer/simple-eeg/simple-oxford';

resultsInPath = fullfile(baseDir, 'data', 'results', 'jasp_data_all.csv');
medInPath  = fullfile(baseDir, 'data_lists', 'medscinet_export_petal.xlsx');

%% Check input files exist
if ~isfile(resultsInPath)
    error('Input file not found: %s', resultsInPath);
end

if ~isfile(medInPath)
    error('Input file not found: %s', medInPath);
end

%% Read jasp_data_all.csv
jaspOpts = detectImportOptions(resultsInPath, 'PreserveVariableNames', true);
jaspVarsToReadAsString = {'subjectID', 'trial_arm', 'HL_sleep_state'};
jaspVarsPresent = intersect(jaspVarsToReadAsString, ...
    jaspOpts.VariableNames, 'stable');

if ~isempty(jaspVarsPresent)
    jaspOpts = setvartype(jaspOpts, jaspVarsPresent, 'string');
end

jaspTbl = readtable(resultsInPath, jaspOpts);

%% Validate required JASP columns
requiredJaspVars = {'subjectID', 'trial_arm', 'HL_sleep_state'};
missingJaspVars = setdiff(requiredJaspVars, ...
    jaspTbl.Properties.VariableNames);

if ~isempty(missingJaspVars)
    error('Missing required column(s) in jasp_data_all.csv: %s', ...
        strjoin(missingJaspVars, ', '));
end

%% Keep and clean required JASP columns
jaspBase = jaspTbl(:, requiredJaspVars);

jaspBase.subjectID      = local_clean_text(jaspBase.subjectID);
jaspBase.trial_arm      = local_clean_text(jaspBase.trial_arm);
jaspBase.HL_sleep_state = local_clean_text(jaspBase.HL_sleep_state);

%% Read medscinet_export_petal.xlsx
medOpts = detectImportOptions(medInPath, 'PreserveVariableNames', true);

medStringVars = { ...
    'RECD - Research project', ...
    'RECD - Participant number', ...
    'BIRTH - Gender'};

medStringVarsPresent = intersect(medStringVars, ...
    medOpts.VariableNames, 'stable');

if ~isempty(medStringVarsPresent)
    medOpts = setvartype(medOpts, medStringVarsPresent, 'string');
end

medTbl = readtable(medInPath, medOpts);

%% Validate required MedSciNet columns
requiredMedVars = { ...
    'RECD - Research project', ...
    'RECD - Participant number', ...
    'BIRTH - Gender', ...
    'BIRTH - Gestation at birth (w)', ...
    'BIRTH - Gestation at birth (d)', ...
    'BIRTH - Birth weight', ...
    'TESTOD - Gestational age at test occasion - w', ...
    'TESTOD - Gestational age at test occasion - d'};

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

%% Check for duplicate constructed IDs in MedSciNet
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

%% Clean/copy sex column
sex = local_clean_text(medTbl.('BIRTH - Gender'));

%% Convert numeric source columns
gaBirthW  = local_to_numeric( ...
    medTbl.('BIRTH - Gestation at birth (w)'));
gaBirthD  = local_to_numeric( ...
    medTbl.('BIRTH - Gestation at birth (d)'));
birthWt   = local_to_numeric(medTbl.('BIRTH - Birth weight'));
pmaStudyW = local_to_numeric( ...
    medTbl.('TESTOD - Gestational age at test occasion - w'));
pmaStudyD = local_to_numeric( ...
    medTbl.('TESTOD - Gestational age at test occasion - d'));

%% Derive age columns
age_ga_birth_weeks = gaBirthW + (gaBirthD ./ 7);
age_pma_study_weeks = pmaStudyW + (pmaStudyD ./ 7);
age_pna_study_days = ...
    (age_pma_study_weeks - age_ga_birth_weeks) .* 7;

%% Create reduced MedSciNet lookup table
medLookup = table();
medLookup.subjectID = medSubjectID;
medLookup.age_ga_birth_weeks = age_ga_birth_weeks;
medLookup.age_pma_study_weeks = age_pma_study_weeks;
medLookup.age_pna_study_days = age_pna_study_days;
medLookup.birthweight_grams = birthWt;
medLookup.sex = sex;

%% Match JASP rows to MedSciNet rows
[isMatched, medLoc] = ismember(jaspBase.subjectID, medLookup.subjectID);

if any(~isMatched)
    unmatchedIDs = unique(jaspBase.subjectID(~isMatched));
    error('No matching MedSciNet row found for subjectID(s): %s', ...
        strjoin(cellstr(unmatchedIDs), ', '));
end

%% Build the participant-level workspace table
participantDetailsTable = table();

participantDetailsTable.subjectID = jaspBase.subjectID;
participantDetailsTable.age_ga_birth_weeks = ...
    medLookup.age_ga_birth_weeks(medLoc);
participantDetailsTable.age_pma_study_weeks = ...
    medLookup.age_pma_study_weeks(medLoc);
participantDetailsTable.age_pna_study_days = ...
    medLookup.age_pna_study_days(medLoc);
participantDetailsTable.birthweight_grams = ...
    medLookup.birthweight_grams(medLoc);
participantDetailsTable.sex = medLookup.sex(medLoc);
participantDetailsTable.trial_arm = jaspBase.trial_arm;
participantDetailsTable.HL_sleep_state = jaspBase.HL_sleep_state;

%% Clean text and sort by subjectID
participantDetailsTable.subjectID = ...
    local_clean_text(participantDetailsTable.subjectID);
participantDetailsTable.sex = ...
    local_clean_text(participantDetailsTable.sex);
participantDetailsTable.trial_arm = ...
    local_clean_text(participantDetailsTable.trial_arm);
participantDetailsTable.HL_sleep_state = ...
    local_clean_text(participantDetailsTable.HL_sleep_state);
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
    "Gestational age at birth (weeks)"; ...
    "Postmenstrual age at time of study (weeks)"; ...
    "Postnatal age at time of study (days)"; ...
    "Birthweight (g)"; ...
    "Sex"; ...
    "Female"; ...
    "Male"; ...
    "Trial arm"; ...
    "Intervention"; ...
    "Control"; ...
    "Sleep state pre-heel lance"; ...
    "Asleep"; ...
    "Awake"];

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
