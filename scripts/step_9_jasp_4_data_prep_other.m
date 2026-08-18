%% step_9_jasp_4_data_prep_other.m
% Purpose
%   - Read upstream MedSciNet export:
%       data_lists/medscinet_export_petal.xlsx
%   - Derive subjectID from:
%       RECD - Research project + RECD - Participant number
%       with project casing normalised ("OX" -> "Ox").
%   - Extract and recode:
%       • trial arm
%       • HL sleep state prior to heel lance
%   - Allow missing trial arm / sleep state (leave blank), but hard-error on:
%       • blank/invalid subjectID,
%       • duplicate subjectID,
%       • unexpected non-empty values in the trial-arm or sleep-state source columns.
%   - Create data/results/ if missing, and write:
%       data/results/jasp_data_other.csv
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

%% 1) Ensure output directory exists
if ~exist(outDir, 'dir')
    ok = mkdir(outDir);
    if ~ok
        error('Failed to create output directory: %s', outDir);
    end
end

%% 2) Read MedSciNet spreadsheet and validate required columns
if ~isfile(inXlsx)
    error('Input file not found: %s', inXlsx);
end

T = readtable(inXlsx, 'PreserveVariableNames', true);

needCols = {COL_PROJECT, COL_PARTICIPANT, COL_ARM, COL_SLEEP};
missing = setdiff(needCols, T.Properties.VariableNames);
if ~isempty(missing)
    error('Missing required columns in medscinet_export_petal.xlsx: %s', strjoin(missing, ', '));
end

%% 3) Extract and normalise source columns (trim leading/trailing whitespace only)
project_raw = string(T.(COL_PROJECT));
part_raw    = string(T.(COL_PARTICIPANT));
arm_raw     = string(T.(COL_ARM));
sleep_raw   = string(T.(COL_SLEEP));

project_raw(ismissing(project_raw)) = "";
part_raw(ismissing(part_raw))       = "";
arm_raw(ismissing(arm_raw))         = "";
sleep_raw(ismissing(sleep_raw))     = "";

project_raw = strtrim(project_raw);
part_raw    = strtrim(part_raw);
arm_raw     = strtrim(arm_raw);
sleep_raw   = strtrim(sleep_raw);

%% 4) Derive subjectID (hard error on blanks)
project_norm = replace(project_raw, "OX", "Ox");
subjectID = project_norm + part_raw;

bad_sid = (subjectID == "");
if any(bad_sid)
    idx = find(bad_sid, 1, 'first');
    error(['Blank subjectID generated at row %d. ', ...
        'Check columns "%s" and "%s" for missing/blank values. ', ...
        'Observed project="%s", participant="%s".'], ...
        idx, COL_PROJECT, COL_PARTICIPANT, project_raw(idx), part_raw(idx));
end

%% 5) Enforce uniqueness of subjectID (hard error on duplicates)
[u, ~, ic] = unique(subjectID, 'stable');
counts = accumarray(ic, 1);
dup_ids = u(counts > 1);

if ~isempty(dup_ids)
    % List a few duplicates for readability
    msg = strjoin(cellstr(dup_ids), ', ');
    error('Duplicate subjectID(s) detected in medscinet_export_petal.xlsx: %s', msg);
end

%% 6) Recode trial arm (allow missing; hard error on unexpected non-empty values)
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
        error('Subject %s: unexpected trial-arm value in "%s": %s', subjectID(i), COL_ARM, a);
    end
end

%% 7) Recode HL sleep state (allow missing; hard error on unexpected non-empty values)
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
        error('Subject %s: unexpected sleep-state value in "%s": %s', subjectID(i), COL_SLEEP, s);
    end
end

%% 8) Assemble output table (fixed column order) and sort by subjectID
Tout = table(subjectID, trial_arm, HL_sleep_state);
Tout.Properties.VariableNames = OUT_COLS;

Tout = sortrows(Tout, 'subjectID');

%% 9) Write CSV (overwrite)
writetable(Tout, outCsv);
fprintf('Wrote Step 9.4 intermediate: %s (%d rows x %d columns)\n', ...
    outCsv, height(Tout), width(Tout));

log_command_window('stop');
