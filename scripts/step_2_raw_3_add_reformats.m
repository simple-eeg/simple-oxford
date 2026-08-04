%% step_2_raw_3_add_reformats.m
% Purpose:
%   - Read dataset_list_prelim.xlsx
%   - Add three columns (overwriting if present), in this order:
%       1) excluded_datasets  -> "excluded" if row should be excluded, "" otherwise
%       2) EEGfile_reformatted -> EEGfile_renamed but with extension changed to .set
%       3) path_reformatted    -> path_renamed but with "data/source/" -> "data/raw/"
%   - Exclusion rule: exclude if either renaming_info_missing == "missing"
%     OR event_missing == "missing"
%
% Conventions:
%   - Treat both "" and <missing> as blank for checks.
%   - Case-sensitive extensions (.dat, .cdt, .xdf).
%   - Only write EEGfile_reformatted and path_reformatted for non-excluded rows.
%   - If EEGfile_renamed is blank in a non-excluded row, warn and leave EEGfile_reformatted blank.
%   - If path_renamed does not start with "data/source/", warn and leave path_reformatted blank.
%
% Output:
%   - Overwrites dataset_list_prelim.xlsx in-place with the three new columns appended.

log_command_window('start');
clear; clc;

%% Paths
baseDir      = '/Users/lukebaxter/Developer/simple-eeg/simple-oxford';
fileListPath = fullfile(baseDir, 'data_lists', 'dataset_list_prelim.xlsx');

%% Load table with stable typing for key columns
fprintf('Loading: %s\n', fileListPath);
opts = detectImportOptions(fileListPath, 'PreserveVariableNames', true);

% Ensure required columns exist (as names)
requiredCols = {'renaming_info_missing','event_missing','EEGfile_renamed','path_renamed'};
missingCols  = setdiff(requiredCols, opts.VariableNames);
if ~isempty(missingCols)
    error('Missing required columns in dataset_list_prelim.xlsx: %s', strjoin(missingCols, ', '));
end

% Force these columns to be read as string
forceStrCols = requiredCols;
for k = 1:numel(forceStrCols)
    opts = setvaropts(opts, forceStrCols{k}, 'Type', 'string');
end

T = readtable(fileListPath, opts);

%% Create/overwrite the three output columns (append at the end)
N = height(T);
T.excluded_datasets   = strings(N, 1);
T.EEGfile_reformatted = strings(N, 1);
T.path_reformatted    = strings(N, 1);

%% Pass 1: mark exclusions
fprintf('Marking exclusions...\n');
for i = 1:N
    rmiss = T.renaming_info_missing(i);
    emiss = T.event_missing(i);

    % Treat "" and <missing> as blank
    isR = ~(rmiss == "" || ismissing(rmiss));
    isE = ~(emiss == "" || ismissing(emiss));

    if isR || isE
        T.excluded_datasets(i) = "excluded";
    else
        T.excluded_datasets(i) = "";
    end
end

%% Pass 2: fill reformatted filename/path for non-excluded rows
fprintf('Updating reformatted filenames and paths...\n');
nExcluded = 0;
nUpdated  = 0;

for i = 1:N
    if T.excluded_datasets(i) ~= ""
        nExcluded = nExcluded + 1;
        fprintf('Row %d/%d: excluded\n', i, N);
        continue;
    end

    % ---- EEGfile_reformatted ----
    srcName = T.EEGfile_renamed(i);

    if srcName == "" || ismissing(srcName)
        warning('Row %d: EEGfile_renamed is empty but row not excluded. Leaving EEGfile_reformatted blank.', i);
        T.EEGfile_reformatted(i) = "";
    else
        % Change extension to .set based on exact ext
        [~, baseName, ext] = fileparts(srcName);  % srcName expected to be just a filename
        switch ext
            case {'.dat', '.cdt', '.xdf'}
                T.EEGfile_reformatted(i) = baseName + ".set";
            otherwise
                warning('Row %d: Unexpected EEGfile_renamed extension "%s". Leaving EEGfile_reformatted blank.', i, ext);
                T.EEGfile_reformatted(i) = "";
        end
    end

    % ---- path_reformatted ----
    srcPath = T.path_renamed(i);

    if startsWith(srcPath, "data/source/")
        % Replace the *prefix* "data/source/" with "data/raw/"
        T.path_reformatted(i) = "data/raw/" + extractAfter(srcPath, "data/source/");
    else
        warning('Row %d: path_renamed does not start with "data/source/": %s. Leaving path_reformatted blank.', i, srcPath);
        T.path_reformatted(i) = "";
    end

    nUpdated = nUpdated + 1;
    fprintf('Row %d/%d: updated\n', i, N);
end

%% Save and summarize
writetable(T, fileListPath);
fprintf('Done. Updated table saved to: %s\n', fileListPath);

fprintf('Summary:\n');
fprintf('  Kept rows updated : %d\n', nUpdated);
fprintf('  Excluded rows     : %d\n', nExcluded);
fprintf('  Total rows        : %d\n', N);

log_command_window('stop');
