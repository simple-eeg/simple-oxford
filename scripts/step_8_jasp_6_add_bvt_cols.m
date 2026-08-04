%% step_8_jasp_6_add_bvt_cols.m
% Purpose
%   - Read:  data/jasp/jasp_data_all.csv
%   - Read:  data_lists/medscinet_export_petal_pub.xlsx
%   - Derive a pub subjectID list from the XLSX:
%       subjectID = (RECD - Research project, with "OX" -> "Ox") + (RECD - Participant number)
%       (trim leading/trailing whitespace only; preserve leading zeros)
%   - Add (or re-create) three columns at the end of jasp_data_all.csv:
%       HL_ER_nNRF_mag_Screening
%       HL_ER_nNRF_mag_pub
%       HL_ER_nNRF_mag_pub_Screening
%   - Overwrite data/jasp/jasp_data_all.csv in place
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

jaspDir = fullfile(baseDir, 'data', 'jasp');
csvPath = fullfile(jaspDir, 'jasp_data_all.csv');

xlsPath = fullfile(baseDir, 'data_lists', 'medscinet_export_petal_pub.xlsx');

%% 1) Column names (preserve exact input headers)
COL_ID   = 'subjectID';
COL_MAG  = 'HL_ER_nNRF_mag';

COL_PROJECT     = 'RECD - Research project';
COL_PARTICIPANT = 'RECD - Participant number';

COL_SCR      = 'HL_ER_nNRF_mag_Screening';
COL_PUB_MAG  = 'HL_ER_nNRF_mag_pub';
COL_PUB_SCR  = 'HL_ER_nNRF_mag_pub_Screening';

%% 2) Read CSV (preserve variable names)
assert(isfile(csvPath), 'Missing input CSV: %s', csvPath);

opts = detectImportOptions(csvPath, 'PreserveVariableNames', true);
opts.VariableNamingRule = 'preserve';
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

%% 3) Read pub XLSX and build pub subject list
assert(isfile(xlsPath), 'Missing pub XLSX: %s', xlsPath);

optsX = detectImportOptions(xlsPath, 'PreserveVariableNames', true);
optsX.VariableNamingRule = 'preserve';
X = readtable(xlsPath, optsX);

% Validate required XLSX columns exist
assert(any(strcmp(X.Properties.VariableNames, COL_PROJECT)),     'Missing required column in XLSX: %s', COL_PROJECT);
assert(any(strcmp(X.Properties.VariableNames, COL_PARTICIPANT)), 'Missing required column in XLSX: %s', COL_PARTICIPANT);

proj = strtrim(string(X.(COL_PROJECT)));
part = strtrim(string(X.(COL_PARTICIPANT)));

proj(ismissing(proj)) = "";
part(ismissing(part)) = "";

% Normalise project: "OX" -> "Ox"
proj = replace(proj, "OX", "Ox");

pubID = proj + part;
pubID = pubID(pubID ~= "");

if isempty(pubID)
    error('Derived pub subjectID list is empty. Check XLSX columns and contents.');
end

% Ensure unique pub IDs
if numel(unique(pubID)) ~= numel(pubID)
    error('Pub XLSX derived subjectIDs are not unique. Aborting.');
end

%% 4) Extract HL_ER_nNRF_mag and define missingness
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

%% 5) Validate pub IDs exist in CSV and have non-missing mag
csvID = T.(COL_ID);

[tf_pub, loc_pub] = ismember(pubID, csvID);
if ~all(tf_pub)
    missingPub = pubID(~tf_pub);
    error('Pub subjectID(s) not found in CSV: %s', strjoin(cellstr(missingPub), ', '));
end

isPubRow = false(height(T), 1);
isPubRow(loc_pub) = true;

% Pub rows must have non-missing mag
if any(isMagMissing & isPubRow)
    bad = csvID(isMagMissing & isPubRow);
    error('Pub subjectID(s) have missing %s in CSV: %s', COL_MAG, strjoin(cellstr(bad), ', '));
end

%% 6) Drop existing script-owned columns (if present), then add/recreate
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

%% 7) Write back to CSV (overwrite in place)
writetable(T, csvPath);

%% 8) Summary
fprintf('\nAdded columns to: %s\n', csvPath);
fprintf('  %s: Excluded %d / %d\n', COL_SCR, sum(scr == "Excluded"), height(T));
fprintf('  %s: Included %d / %d\n', COL_PUB_SCR, sum(pubScr == "Included"), height(T));

log_command_window('stop');