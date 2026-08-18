%% step_8_jasp_1_data_prep_eeg_qc.m
% Purpose
%   - Read SCREENED pooled QC features from:
%       data/summary/screening/pooled_screened_eeg_qc_features.csv
%   - Apply screening decisions at item-level (Exclude).
%   - Validate strict dataset assumptions on the INCLUDED subset (hard-stop on violations).
%   - Reshape to a single-row-per-subject, JASP-ready table with a fixed schema:
%       one QC value per subject per eventtype, for each requested QC metric.
%   - Create data/jasp/ if missing, and write:
%       data/jasp/jasp_data_eeg_qc.csv
%
% Input expectations (hard errors if violated, on INCLUDED subset only)
%   - subjectID must be present and non-blank (after trimming).
%   - Exclude must be present and contain only 0/1 (no missing).
%   - Only allowed eventtype values:
%       lance_prestim, lance
%   - Per subject (on included rows only):
%       exactly one sessionID, exactly one runID, and exactly one channel (after trim + case normalisation),
%       and channel must match "CZ" case-insensitively (with trimming).
%       for each required eventtype:
%           - 0 rows: allowed (becomes NaN in output)
%           - 1 row : used (QC metric values copied; must be finite)
%           - >1 rows: ERROR (duplicate ambiguity)
%   - QC metric columns requested in expected_qcname must exist in the input CSV (case-sensitive match).
%
% Mapping
%   eventtype:
%     lance_prestim   -> HL_BL
%     lance           -> HL_ER
%
% Output
%   - Columns in the exact order specified below.
%   - Rows sorted by subjectID.
%   - Output path:
%       data/jasp/jasp_data_eeg_qc.csv
%   - Subjects are retained even if all their rows are excluded; in that case, all QC columns are NaN.

log_command_window('start');
clear; clc;

%% 0) User config: paths and constants
baseDir = '/Users/lukebaxter/Developer/simple-eeg/simple-oxford';

inCsv  = fullfile(baseDir, 'data', 'summary', 'screening', 'pooled_screened_eeg_qc_features.csv');
outDir = fullfile(baseDir, 'data', 'jasp');
outCsv = fullfile(outDir, 'jasp_data_eeg_qc.csv');

expected_channel   = "CZ";
expected_eventtype = ["lance_prestim","lance"];

% User-editable list of QC metric columns to extract (case-sensitive; must match CSV column headers)
expected_qcname = [ ...
    "maxAbsEpoch", ...
    "sdEpoch", ...
    "invSdEpoch", ...
    "MeanAbsDiffNorm", ...
    "MaxAbsDiffNorm", ...
    "RobustSlopeNorm", ...
    "AutoCorrLag1Pos", ...
    "AutoCorrLag1Neg", ...
    "KatzFDNorm" ...
    ];

% Eventtype -> prefix (fixed order for output blocks)
eventtype_order = ["lance_prestim","lance"];
prefix_order    = ["HL_BL","HL_ER"];

% Build output columns (eventtype blocks, metric order preserved within each block)
OUT_COLS = cell(1, 1 + numel(prefix_order) * numel(expected_qcname));
OUT_COLS{1} = 'subjectID';
c = 2;
for p = 1:numel(prefix_order)
    pref = char(prefix_order(p));
    for q = 1:numel(expected_qcname)
        OUT_COLS{c} = sprintf('%s_%s', pref, char(expected_qcname(q)));
        c = c + 1;
    end
end

% Normalised expected channel (trim + upper for case-insensitive match)
expected_channel_norm = upper(strtrim(expected_channel));

%% 1) Ensure output directory exists
if ~exist(outDir, 'dir')
    ok = mkdir(outDir);
    if ~ok
        error('Failed to create output directory: %s', outDir);
    end
end

%% 2) Read SCREENED pooled QC CSV (string-stable import)
if ~isfile(inCsv)
    error('Input file not found: %s', inCsv);
end

opts = detectImportOptions(inCsv, 'PreserveVariableNames', true, 'TextType', 'string');

forceStr = {'subjectID','sessionID','runID','eventtype','channel'};
for k = 1:numel(forceStr)
    if any(strcmp(opts.VariableNames, forceStr{k}))
        opts = setvaropts(opts, forceStr{k}, 'Type', 'string');
    end
end

T = readtable(inCsv, opts);

%% 3) Validate required columns exist
needBase = {'subjectID','sessionID','runID','epoch_index','channel','eventtype','Exclude'};
missing = setdiff(needBase, T.Properties.VariableNames);
if ~isempty(missing)
    error('Missing required columns in pooled_screened_eeg_qc_features.csv: %s', strjoin(missing, ', '));
end

% QC metric columns requested must exist (case-sensitive match)
qcCols = cellstr(expected_qcname);
missingQC = setdiff(qcCols, T.Properties.VariableNames);
if ~isempty(missingQC)
    error('Requested QC metric column(s) not found in pooled_screened_eeg_qc_features.csv: %s', strjoin(missingQC, ', '));
end

%% 4) Normalise key text columns
for i = 1:numel(forceStr)
    cName = forceStr{i};
    T.(cName) = strtrim(string(T.(cName)));
    T.(cName)(ismissing(T.(cName))) = "";
end

% Hard error on blank subjectID (data integrity issue)
if any(T.subjectID == "")
    idx = find(T.subjectID == "", 1, 'first');
    error('Blank subjectID detected (after trimming) at input row %d. Aborting.', idx);
end

%% 5) Coerce and validate Exclude as 0/1
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

%% 6) Subject list from ALL rows (retain fully excluded subjects)
subjects = unique(T.subjectID);
subjects = sort(subjects);
nSub = numel(subjects);

%% 7) Included-only table for extraction and strict checks
Tincl = T(T.Exclude == 0, :);

% Global strict validation on included rows only
if ~isempty(Tincl)
    u_et = unique(Tincl.eventtype);
    bad_et = setdiff(u_et, expected_eventtype);
    if ~isempty(bad_et)
        error('Unexpected eventtype value(s) found (included rows only): %s', strjoin(cellstr(bad_et), ', '));
    end
end

%% 8) Preallocate output arrays (one row per subject)
subjectID = subjects;

nQC = numel(expected_qcname);
nPref = numel(prefix_order);

% Store outputs in a numeric matrix aligned to OUT_COLS(2:end):
% [nSub x (nPref*nQC)], initialised to NaN
Y = nan(nSub, nPref * nQC);

%% 9) Per-subject extraction (no aggregation)
for s = 1:nSub
    sid = subjects(s);

    Ts = Tincl(Tincl.subjectID == sid, :);

    % If no included rows for this subject, keep row with NaNs.
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

    % For each eventtype in fixed order, expect 0 or 1 included row (no aggregation)
    for p = 1:nPref
        et = eventtype_order(p);

        Te = Ts(Ts.eventtype == et, :);
        nmatch = height(Te);

        if nmatch > 1
            error('Subject %s: duplicate included rows for eventtype=%s, found %d.', sid, et, nmatch);
        elseif nmatch == 0
            % Missing after exclusion (or absent in source): leave NaNs for this prefix block
            continue
        end

        % Exactly one row: copy requested QC metrics (must be finite)
        for q = 1:nQC
            qc = expected_qcname(q);

            val = double(Te.(char(qc)));

            if ~isfinite(val)
                error('Subject %s: non-finite QC value for eventtype=%s, metric=%s.', sid, et, qc);
            end

            % Column index into Y: eventtype block then metric within block
            col = (p-1)*nQC + q;
            Y(s, col) = val;
        end
    end
end

%% 10) Assemble output table and write CSV
Tout = table(subjectID);

% Add numeric columns in OUT_COLS order (eventtype blocks, metric order preserved)
varNames = OUT_COLS(2:end);
for k = 1:numel(varNames)
    Tout.(varNames{k}) = Y(:, k);
end

Tout.Properties.VariableNames = OUT_COLS;

% Rows already follow sorted(subjects) order, but enforce explicitly
Tout = sortrows(Tout, 'subjectID');

writetable(Tout, outCsv);
fprintf('Wrote Step 8.1 intermediate: %s (%d rows x %d columns)\n', ...
    outCsv, height(Tout), width(Tout));

log_command_window('stop');
