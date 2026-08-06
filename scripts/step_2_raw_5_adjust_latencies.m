%% step_2_raw_5_adjust_latencies.m
% Purpose
%   Adjust event-level latencies in raw .set files (continuous data) based on:
%     1) Per-annotation flag:  event_annotation_summary.csv → column "LatencyCorrect"
%     2) Per-file flag:        dataset_list_prelim.xlsx → column "latency_correct"
%
% Key rules
%   - Match annotations exactly (case-sensitive) after trim; ignore missing/empty annotations.
%   - Correction value is user-defined (ms) below; sign convention:  -ms = earlier, +ms = later.
%   - Shift is rounded to nearest sample: Δsamples = round(ms * srate / 1000).
%   - Bounds: if new latency < 1 or > EEG.pnts → warn & skip that event.
%   - Provenance/idempotence:
%       * If EEG.event.urlatency exists, all latencies must match (within TOL) and count must match; otherwise warn & skip file.
%       * Also best-effort cross-check with EEG.urevent via indices; any mismatch → warn & skip file.
%       * If EEG.event.urlatency is absent, create it from current latencies after any available urevent cross-check.
%   - Integrity: run eeg_checkset(EEG,'eventconsistency') before saving.
%   - Save: overwrite .set in place only if at least one event was adjusted; if zero matches → warn & skip saving.
%   - Console output: per-file summary + targeted warnings.

log_command_window('start');
clear; clc;

%% 0) User configuration (EDIT HERE)
PROJECT_ROOT   = "/Users/lukebaxter/Developer/simple-eeg/simple-oxford";
XLSX_PATH      = PROJECT_ROOT + "/data_lists/dataset_list_prelim.xlsx";
MAP_CSV        = PROJECT_ROOT + "/data/info_prelim/event_annotations/event_annotation_summary.csv";

CORRECTION_MS  = -40;     % ms;  NEGATIVE = move earlier; POSITIVE = move later
TOL            = 1e-9;   % tolerance for equality checks (latency vs urlatency / urevent)

fprintf('== Latency adjust: CORRECTION_MS = %g ms  (− earlier, + later)\n', CORRECTION_MS);

%% 1) Environment / EEGLAB
functionsFolder = fullfile(char(PROJECT_ROOT), 'functions');
if exist(functionsFolder,'dir'), addpath(functionsFolder); end

assert(exist('eeglab','file') == 2, "EEGLAB not found on path.");
eeglab;

%% 2) Load mapping CSV (Annotation → LatencyCorrect flag)
mapOpts = detectImportOptions(char(MAP_CSV), 'TextType','string', 'VariableNamingRule','preserve');
mapTbl  = readtable(char(MAP_CSV), mapOpts);

% Require Annotation column; tolerate missing LatencyCorrect by creating blanks
if ~ismember("Annotation", string(mapTbl.Properties.VariableNames))
    error("Mapping file must contain column: Annotation");
end
if ~ismember("LatencyCorrect", string(mapTbl.Properties.VariableNames))
    mapTbl.LatencyCorrect = strings(height(mapTbl),1);
end

annCol  = string(mapTbl.Annotation);        annCol(ismissing(annCol))  = "";   annCol  = strtrim(annCol);
flagCol = string(mapTbl.LatencyCorrect);    flagCol(ismissing(flagCol))= "";   flagCol = strtrim(flagCol);

flaggedMask     = (flagCol == "1");
FLAGGED_ANNOTS  = annCol(flaggedMask & strlength(annCol) > 0);

if isempty(FLAGGED_ANNOTS)
    fprintf('Info: No annotations flagged (LatencyCorrect == "1"). Nothing to do.\n');
    log_command_window('stop');
    return;
end

%% 3) Load file list (which .set files to process)
listOpts = detectImportOptions(char(XLSX_PATH), 'TextType','string', 'VariableNamingRule','preserve');
T        = readtable(char(XLSX_PATH), listOpts);

reqCols = ["path_reformatted","EEGfile_reformatted","latency_correct"];
missing = setdiff(reqCols, string(T.Properties.VariableNames));
if ~isempty(missing)
    error("dataset_list_prelim.xlsx missing required column(s): %s", strjoin(missing, ", "));
end

% Normalize and select rows to process
pathCol = string(T.path_reformatted);          pathCol(ismissing(pathCol))  = ""; pathCol = strtrim(pathCol);
fileCol = string(T.EEGfile_reformatted);       fileCol(ismissing(fileCol))  = ""; fileCol = strtrim(fileCol);
lcorCol = string(T.latency_correct);           lcorCol(ismissing(lcorCol))  = ""; lcorCol = strtrim(lcorCol);

rowsToProcess = (strlength(pathCol) > 0) & (strlength(fileCol) > 0) & (lcorCol == "1");

if ~any(rowsToProcess)
    fprintf('Info: No files flagged in dataset_list_prelim.xlsx (latency_correct == "1"). Nothing to do.\n');
    log_command_window('stop');
    return;
end

procIdx = find(rowsToProcess);
N = numel(procIdx);

%% 4) Iterate files
nSaved = 0; nSkipped = 0; nErrored = 0;

for k = 1:N
    r       = procIdx(k);
    relDir  = pathCol(r);
    setName = fileCol(r);

    srcDir  = fullfile(char(PROJECT_ROOT), char(relDir));
    setPath = fullfile(srcDir, char(setName));

    fprintf('[%d/%d] %s/%s\n', k, N, relDir, setName);

    % Missing file → error and stop
    if ~isfile(setPath)
        error('Missing .set file: %s', setPath);
    end

    % Load EEG
    EEG = pop_loadset('filepath', srcDir, 'filename', char(setName), 'loadmode', 'all');

    % Basic sanity
    if ~isfield(EEG,'event') || isempty(EEG.event)
        warning('  [WARN] No events present → skipping file.');
        nSkipped = nSkipped + 1;
        continue;
    end
    if ~isfield(EEG,'srate') || isempty(EEG.srate) || EEG.srate <= 0 || ~isfield(EEG,'pnts') || EEG.pnts <= 0
        error('  [ERR] Invalid srate/pnts for: %s', setPath);
    end

    % ----- Idempotence checks -----
    evCount = numel(EEG.event);
    L  = arrayfun(@(e) double(e.latency), EEG.event);

    % A) urlatency presence and equality (if exists)
    hasUrlField = all(isfield(EEG.event,'urlatency'));
    if hasUrlField
        % Ensure all urlatency values exist and are numeric
        hasUrlValue = arrayfun(@(e) isfield(e,'urlatency') && ~isempty(e.urlatency) && isnumeric(e.urlatency), EEG.event);
        if ~all(hasUrlValue)
            warning('  [WARN] urlatency field exists but contains missing/non-numeric values → skipping file.');
            nSkipped = nSkipped + 1;
            continue;
        end
        UL = arrayfun(@(e) double(e.urlatency), EEG.event);
        if numel(UL) ~= evCount
            warning('  [WARN] urlatency length mismatch (urlatency=%d, events=%d) → skipping file.', numel(UL), evCount);
            nSkipped = nSkipped + 1;
            continue;
        end
        if any(abs(L - UL) > TOL)
            warning('  [WARN] Current latencies differ from urlatency (>%g) → skipping file.', TOL);
            nSkipped = nSkipped + 1;
            continue;
        end
    end

    % B) urevent cross-check (best-effort)
    if isfield(EEG,'urevent') && ~isempty(EEG.urevent) && all(isfield(EEG.event,'urevent'))
        % Only check events with a valid urevent index & defined urevent.latency
        mismatchFound = false;
        for e = 1:evCount
            uix = [];
            if isfield(EEG.event(e),'urevent')
                try uix = double(EEG.event(e).urevent); catch, uix = []; end
            end
            if ~isempty(uix) && isfinite(uix) && uix >= 1 && uix <= numel(EEG.urevent)
                if isfield(EEG.urevent,'latency') && ~isempty(EEG.urevent(uix).latency)
                    U = double(EEG.urevent(uix).latency);
                    if abs(L(e) - U) > TOL
                        warning('  [WARN] urevent mismatch at event %d (|%g - %g| > %g) → skipping file.', e, L(e), U, TOL);
                        mismatchFound = true; break;
                    end
                end
            end
        end
        if mismatchFound
            nSkipped = nSkipped + 1;
            continue;
        end
    end

    % ----- Backup original latencies if needed -----
    if ~hasUrlField
        for e = 1:evCount
            EEG.event(e).urlatency = EEG.event(e).latency;
        end
        fprintf('  [INFO] Backed up original latencies to EEG.event.urlatency\n');
    end

    % ----- Determine which events to adjust -----
    matchedMask = false(1, evCount);
    hasAnnotField = all(isfield(EEG.event, 'annotation'));
    if ~hasAnnotField
        % No annotation field → nothing to match
        warning('  [WARN] No annotation field on events; nothing to adjust → skipping save.');
        nSkipped = nSkipped + 1;
        continue;
    end

    for e = 1:evCount
        ann = "";
        try
            ann = string(EEG.event(e).annotation);
        catch
            ann = "";
        end
        if ~ismissing(ann)
            ann = strtrim(ann);
        else
            ann = "";
        end
        if strlength(ann) > 0
            % exact, case-sensitive match against flagged set
            if any(ann == FLAGGED_ANNOTS)
                matchedMask(e) = true;
            end
        end
    end

    nMatched = nnz(matchedMask);
    if nMatched == 0
        warning('  [WARN] No events with flagged annotations in this file → skipping save.');
        nSkipped = nSkipped + 1;
        continue;
    end

    % ----- Compute Δsamples and apply with bounds checks -----
    deltaSamples = round(CORRECTION_MS * EEG.srate / 1000);
    applied = 0; oobSkips = 0;

    for e = find(matchedMask)
        newLat = EEG.event(e).latency + deltaSamples;
        if newLat < 1 || newLat > EEG.pnts
            warning('  [WARN] Event %d OOB after shift (old=%.6g, new=%.6g; pnts=%d) → skipped.', ...
                e, EEG.event(e).latency, newLat, EEG.pnts);
            oobSkips = oobSkips + 1;
        else
            EEG.event(e).latency = newLat;
            applied = applied + 1;
        end
    end

    % ----- Integrity & save / summary -----
    EEG = eeg_checkset(EEG, 'eventconsistency');

    if applied > 0
        pop_saveset(EEG, 'filename', char(setName), 'filepath', srcDir, 'savemode','onefile');
        fprintf('  [OK] matched=%d, adjusted=%d, OOB skipped=%d → saved\n', nMatched, applied, oobSkips);
        nSaved = nSaved + 1;
    else
        warning('  [WARN] matched=%d but adjusted=0 (OOB skipped=%d) → file left unchanged.', nMatched, oobSkips);
        nSkipped = nSkipped + 1;
    end
end

fprintf('== Done. Files processed: %d | saved: %d | skipped: %d\n', N, nSaved, nSkipped);

log_command_window('stop');
