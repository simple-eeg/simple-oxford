%% step_8_jasp_7_sample_details.m
%
% Create a JASP-ready sample-details CSV containing subject-level
% demographic and baseline characteristics.
%
% Inputs:
%   1) data/jasp/jasp_data_all.csv
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
% Output:
%   data/jasp/jasp_sample_details.csv
%
% Output columns:
%   - subjectID
%   - age_ga_birth_weeks
%   - age_pma_study_weeks
%   - age_pna_study_days
%   - birthweight_grams
%   - sex
%   - trial_arm
%   - HL_sleep_state

log_command_window('start');
clear; clc;

%% Paths
baseDir = '/Users/lukebaxter/Developer/simple-eeg/simple-oxford';

jaspInPath = fullfile(baseDir, 'data', 'jasp', 'jasp_data_all.csv');
medInPath  = fullfile(baseDir, 'data_lists', 'medscinet_export_petal.xlsx');
outPath    = fullfile(baseDir, 'data', 'jasp', 'jasp_sample_details.csv');

%% Check input files exist
if ~isfile(jaspInPath)
    error('Input file not found: %s', jaspInPath);
end

if ~isfile(medInPath)
    error('Input file not found: %s', medInPath);
end

%% Read jasp_data_all.csv
jaspOpts = detectImportOptions(jaspInPath, 'PreserveVariableNames', true);
jaspVarsToReadAsString = {'subjectID', 'trial_arm', 'HL_sleep_state'};
jaspVarsPresent = intersect(jaspVarsToReadAsString, jaspOpts.VariableNames, 'stable');

if ~isempty(jaspVarsPresent)
    jaspOpts = setvartype(jaspOpts, jaspVarsPresent, 'string');
end

jaspTbl = readtable(jaspInPath, jaspOpts);

%% Validate required JASP columns
requiredJaspVars = {'subjectID', 'trial_arm', 'HL_sleep_state'};
missingJaspVars = setdiff(requiredJaspVars, jaspTbl.Properties.VariableNames);

if ~isempty(missingJaspVars)
    error('Missing required column(s) in jasp_data_all.csv: %s', strjoin(missingJaspVars, ', '));
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

medStringVarsPresent = intersect(medStringVars, medOpts.VariableNames, 'stable');

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
    error('Missing required column(s) in medscinet_export_petal.xlsx: %s', strjoin(missingMedVars, ', '));
end

%% Construct MedSciNet subjectID
proj = local_clean_text(medTbl.('RECD - Research project'));
part = local_clean_text(medTbl.('RECD - Participant number'));

proj = replace(proj, "X", "x");
medSubjectID = proj + part;
medSubjectID = local_clean_text(medSubjectID);

%% Check for duplicate constructed IDs in MedSciNet
nonMissingIDMask = medSubjectID ~= "";
idsToCheck = medSubjectID(nonMissingIDMask);

[uniqueIDs, ~, groupIdx] = unique(idsToCheck);
dupCounts = accumarray(groupIdx, 1);
dupIDs = uniqueIDs(dupCounts > 1);

if ~isempty(dupIDs)
    error('Duplicate constructed subjectID(s) found in medscinet_export_petal.xlsx: %s', ...
        strjoin(cellstr(dupIDs), ', '));
end

%% Clean/copy sex column
sex = local_clean_text(medTbl.('BIRTH - Gender'));

%% Convert numeric source columns
gaBirthW   = local_to_numeric(medTbl.('BIRTH - Gestation at birth (w)'));
gaBirthD   = local_to_numeric(medTbl.('BIRTH - Gestation at birth (d)'));
birthWt    = local_to_numeric(medTbl.('BIRTH - Birth weight'));
pmaStudyW  = local_to_numeric(medTbl.('TESTOD - Gestational age at test occasion - w'));
pmaStudyD  = local_to_numeric(medTbl.('TESTOD - Gestational age at test occasion - d'));

%% Derive age columns
age_ga_birth_weeks = gaBirthW + (gaBirthD ./ 7);
age_pma_study_weeks = pmaStudyW + (pmaStudyD ./ 7);
age_pna_study_days = (age_pma_study_weeks - age_ga_birth_weeks) .* 7;

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

%% Build final output table
outTbl = table();

outTbl.subjectID = jaspBase.subjectID;
outTbl.age_ga_birth_weeks = medLookup.age_ga_birth_weeks(medLoc);
outTbl.age_pma_study_weeks = medLookup.age_pma_study_weeks(medLoc);
outTbl.age_pna_study_days = medLookup.age_pna_study_days(medLoc);
outTbl.birthweight_grams = medLookup.birthweight_grams(medLoc);
outTbl.sex = medLookup.sex(medLoc);
outTbl.trial_arm = jaspBase.trial_arm;
outTbl.HL_sleep_state = jaspBase.HL_sleep_state;

%% Ensure text missing values are truly blank
outTbl.subjectID = local_clean_text(outTbl.subjectID);
outTbl.sex = local_clean_text(outTbl.sex);
outTbl.trial_arm = local_clean_text(outTbl.trial_arm);
outTbl.HL_sleep_state = local_clean_text(outTbl.HL_sleep_state);

%% Sort by subjectID
outTbl = sortrows(outTbl, 'subjectID');

%% Convert text columns to cell arrays so blanks write as empty CSV cells
outTbl.subjectID = cellstr(outTbl.subjectID);
outTbl.sex = cellstr(outTbl.sex);
outTbl.trial_arm = cellstr(outTbl.trial_arm);
outTbl.HL_sleep_state = cellstr(outTbl.HL_sleep_state);

%% Write output CSV
writetable(outTbl, outPath);

fprintf('Saved sample-details CSV:\n%s\n', outPath);
fprintf('Number of rows written: %d\n', height(outTbl));

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