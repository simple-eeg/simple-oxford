%% step_8_jasp_2_data_prep_eeg_nrf.m
% Purpose
%   - Read SCREENED pooled NRF features from:
%       data/summary/screening/pooled_screened_eeg_nrf_features.csv
%   - Apply screening decisions at item-level (Exclude).
%   - Validate strict dataset assumptions on the INCLUDED subset (hard-stop on violations).
%   - Reshape to a single-row-per-subject, JASP-ready table with a fixed schema.
%   - Create data/jasp/ if missing, and write:
%       data/jasp/jasp_data_eeg_nrf.csv
%
% Input expectations (hard errors if violated, on INCLUDED subset only)
%   - subjectID must be present and non-blank (after trimming).
%   - Exclude must be present and contain only 0/1 (no missing).
%   - Only allowed eventtype values:
%       sham_prestim, sham, lance_prestim, lance
%   - Only allowed NRFName values:
%       early_NRF_500Hz, noxious_NRF_500Hz
%   - Per subject (on included rows only):
%       exactly one sessionID, exactly one runID, and exactly one channel (after trim + case normalisation),
%       and channel must match "CZ" case-insensitively (with trimming).
%       for each required (eventtype × NRFName) combination:
%           - 0 rows: allowed (becomes NaN in output)
%           - 1 row : used (must have finite fglsCoef)
%           - >1 rows: ERROR (duplicate ambiguity)
%
% Mapping
%   eventtype:
%     sham_prestim    -> SL_BL
%     sham            -> SL_ER
%     lance_prestim   -> HL_BL
%     lance           -> HL_ER
%   NRFName:
%     early_NRF_500Hz   -> eNRF
%     noxious_NRF_500Hz -> nNRF
%   fglsCoef    -> mag
%
% Output
%   - Columns in the exact order specified below.
%   - Rows sorted by subjectID.
%   - Output path:
%       data/jasp/jasp_data_eeg_nrf.csv
%   - Subjects are retained even if all their rows are excluded; in that case, all magnitude columns are NaN.

log_command_window('start');
clear; clc;

%% 0) User config: paths and constants
baseDir = '/Users/lukebaxter/Developer/simple-eeg/simple-oxford';

inCsv  = fullfile(baseDir, 'data', 'summary', 'screening', 'pooled_screened_eeg_nrf_features.csv');
outDir = fullfile(baseDir, 'data', 'jasp');
outCsv = fullfile(outDir, 'jasp_data_eeg_nrf.csv');

expected_channel   = "CZ";
expected_eventtype = ["sham_prestim","sham","lance_prestim","lance"];
expected_nrfname   = ["early_NRF_500Hz","noxious_NRF_500Hz"];

OUT_COLS = { ...
    'subjectID', ...
    'SL_BL_eNRF_mag', ...
    'SL_BL_nNRF_mag', ...
    'SL_ER_eNRF_mag', ...
    'SL_ER_nNRF_mag', ...
    'HL_BL_eNRF_mag', ...
    'HL_BL_nNRF_mag', ...
    'HL_ER_eNRF_mag', ...
    'HL_ER_nNRF_mag' ...
    };

% Normalised expected channel (trim + upper for case-insensitive match)
expected_channel_norm = upper(strtrim(expected_channel));

%% 1) Ensure output directory exists
if ~exist(outDir, 'dir')
    ok = mkdir(outDir);
    if ~ok
        error('Failed to create output directory: %s', outDir);
    end
end

%% 2) Read SCREENED pooled NRF CSV (string-stable import)
if ~isfile(inCsv)
    error('Input file not found: %s', inCsv);
end

opts = detectImportOptions(inCsv, 'PreserveVariableNames', true, 'TextType', 'string');

forceStr = {'subjectID','sessionID','runID','eventtype','channel','NRFName'};
for k = 1:numel(forceStr)
    if any(strcmp(opts.VariableNames, forceStr{k}))
        opts = setvaropts(opts, forceStr{k}, 'Type', 'string');
    end
end

T = readtable(inCsv, opts);

% Validate required columns exist (now includes Exclude)
needCols = {'subjectID','sessionID','runID','eventtype','channel','NRFName','fglsCoef','Exclude'};
missing = setdiff(needCols, T.Properties.VariableNames);
if ~isempty(missing)
    error('Missing required columns in pooled_screened_eeg_nrf_features.csv: %s', strjoin(missing, ', '));
end

% Normalise identifier columns: string + trim; treat missing as ""
for i = 1:numel(forceStr)
    c = forceStr{i};
    T.(c) = strtrim(string(T.(c)));
    T.(c)(ismissing(T.(c))) = "";
end

% Hard error on blank subjectID (pre-filter; this is a data integrity issue)
if any(T.subjectID == "")
    idx = find(T.subjectID == "", 1, 'first');
    error('Blank subjectID detected (after trimming) at input row %d. Aborting.', idx);
end

% Coerce Exclude to numeric 0/1 and validate
ex = T.Exclude;
if islogical(ex)
    ex = double(ex);
elseif isstring(ex) || ischar(ex)
    ex = double(str2double(string(ex)));
else
    ex = double(ex);
end

if any(~isfinite(ex))
    idx = find(~isfinite(ex), 1, 'first');
    error('Non-finite Exclude detected at input row %d. Aborting.', idx);
end
if any(~ismember(ex, [0 1]))
    idx = find(~ismember(ex, [0 1]), 1, 'first');
    error('Exclude must contain only 0/1. Found invalid value at input row %d.', idx);
end
T.Exclude = ex;

%% 3) Subject list (from ALL rows), sorted
subjects = unique(T.subjectID);
subjects = sort(subjects);
nSub = numel(subjects);

%% 4) Filter to INCLUDED rows only (Exclude == 0) for magnitude extraction
Tincl = T(T.Exclude == 0, :);

%% 5) Global strict validation for unexpected eventtype/NRFName (INCLUDED subset only)
if ~isempty(Tincl)
    u_et = unique(Tincl.eventtype);
    bad_et = setdiff(u_et, expected_eventtype);
    if ~isempty(bad_et)
        error('Unexpected eventtype value(s) found (included rows only): %s', strjoin(cellstr(bad_et), ', '));
    end

    u_nn = unique(Tincl.NRFName);
    bad_nn = setdiff(u_nn, expected_nrfname);
    if ~isempty(bad_nn)
        error('Unexpected NRFName value(s) found (included rows only): %s', strjoin(cellstr(bad_nn), ', '));
    end
end

%% 6) Preallocate output arrays
subjectID = strings(nSub, 1);

SL_BL_eNRF_mag = nan(nSub,1);
SL_BL_nNRF_mag = nan(nSub,1);
SL_ER_eNRF_mag = nan(nSub,1);
SL_ER_nNRF_mag = nan(nSub,1);

HL_BL_eNRF_mag = nan(nSub,1);
HL_BL_nNRF_mag = nan(nSub,1);

HL_ER_eNRF_mag = nan(nSub,1);
HL_ER_nNRF_mag = nan(nSub,1);

%% 7) Loop subjects and build rows
for s = 1:nSub
    sid = subjects(s);
    subjectID(s) = sid;

    Ts = Tincl(Tincl.subjectID == sid, :);

    % If this subject has no included rows, keep the row (all magnitudes remain NaN).
    if isempty(Ts)
        continue
    end

    % Per-subject: exactly one sessionID and runID (included rows only)
    u_sess = unique(Ts.sessionID);
    u_run  = unique(Ts.runID);

    if numel(u_sess) ~= 1 || u_sess(1) == ""
        error('Subject %s: expected exactly 1 non-blank sessionID (included rows), found: %s', sid, strjoin(cellstr(u_sess), ', '));
    end
    if numel(u_run) ~= 1 || u_run(1) == ""
        error('Subject %s: expected exactly 1 non-blank runID (included rows), found: %s', sid, strjoin(cellstr(u_run), ', '));
    end

    % Per-subject: exactly one channel after normalisation (trim + upper), and must match expected_channel
    ch_norm = upper(strtrim(string(Ts.channel)));
    u_ch = unique(ch_norm);

    if numel(u_ch) ~= 1 || u_ch(1) == ""
        error('Subject %s: expected exactly 1 channel after normalisation (included rows), found: %s', sid, strjoin(cellstr(u_ch), ', '));
    end
    if u_ch(1) ~= expected_channel_norm
        error('Subject %s: expected channel "%s" (case-insensitive, trimmed), found "%s".', sid, expected_channel, u_ch(1));
    end

    % Pull 0-or-1 row for (eventtype, NRFName); error if >1
    % Note: do not use epoch_index.
    req_pairs = [ ...
        "sham_prestim",  "early_NRF_500Hz"; ...
        "sham_prestim",  "noxious_NRF_500Hz"; ...
        "sham",          "early_NRF_500Hz"; ...
        "sham",          "noxious_NRF_500Hz"; ...
        "lance_prestim", "early_NRF_500Hz"; ...
        "lance_prestim", "noxious_NRF_500Hz"; ...
        "lance",         "early_NRF_500Hz"; ...
        "lance",         "noxious_NRF_500Hz" ...
        ];

    mags = nan(8,1);

    for j = 1:size(req_pairs,1)
        et = req_pairs(j,1);
        nn = req_pairs(j,2);

        mask = (Ts.eventtype == et) & (Ts.NRFName == nn);
        nmatch = sum(mask);

        if nmatch > 1
            error('Subject %s: duplicate included rows for (eventtype=%s, NRFName=%s), found %d.', sid, et, nn, nmatch);
        elseif nmatch == 0
            % Missing after exclusion (or absent in source): leave NaN
            continue
        end

        row = Ts(mask, :);

        mag = double(row.fglsCoef);

        if ~isfinite(mag)
            error('Subject %s: non-finite fglsCoef for (eventtype=%s, NRFName=%s).', sid, et, nn);
        end

        mags(j) = mag;
    end

    % Unpack by required-pair order (may include NaNs)
    SL_BL_e_mag = mags(1);
    SL_BL_n_mag = mags(2);

    SL_ER_e_mag = mags(3);
    SL_ER_n_mag = mags(4);

    HL_BL_e_mag = mags(5);
    HL_BL_n_mag = mags(6);

    HL_ER_e_mag = mags(7);
    HL_ER_n_mag = mags(8);

    % Populate single-condition magnitude columns
    SL_BL_eNRF_mag(s) = SL_BL_e_mag;
    SL_BL_nNRF_mag(s) = SL_BL_n_mag;
    SL_ER_eNRF_mag(s) = SL_ER_e_mag;
    SL_ER_nNRF_mag(s) = SL_ER_n_mag;

    HL_BL_eNRF_mag(s) = HL_BL_e_mag;
    HL_BL_nNRF_mag(s) = HL_BL_n_mag;

    HL_ER_eNRF_mag(s) = HL_ER_e_mag;
    HL_ER_nNRF_mag(s) = HL_ER_n_mag;
end

%% 8) Assemble output table (fixed column order) and write CSV
Tout = table( ...
    subjectID, ...
    SL_BL_eNRF_mag, ...
    SL_BL_nNRF_mag, ...
    SL_ER_eNRF_mag, ...
    SL_ER_nNRF_mag, ...
    HL_BL_eNRF_mag, ...
    HL_BL_nNRF_mag, ...
    HL_ER_eNRF_mag, ...
    HL_ER_nNRF_mag ...
    );

Tout.Properties.VariableNames = OUT_COLS;

% Rows already follow sorted(subjects) order, but enforce explicitly
Tout = sortrows(Tout, 'subjectID');

writetable(Tout, outCsv);

log_command_window('stop');