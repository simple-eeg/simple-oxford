%% step_1_source_4_create_source.m 
% Copy and rename EEG files to BIDS-style folder structure
% This script reads dataset_list_prelim.xlsx and copies EEG data and sidecar files
% from remote server paths to a local destination with BIDS-style filenames

log_command_window('start');
clear; clc;

%% Section 1: Setup paths and read table
local_base = '/Users/lukebaxter/pipeline_paper/simple-oxford';
file_list_name = 'dataset_list_prelim.xlsx';
file_list_path = fullfile(local_base, 'data_lists', file_list_name);

% Detect import options and set all *_missing and renaming_info_missing columns to string
opts = detectImportOptions(file_list_path, 'PreserveVariableNames', true);
varNames = opts.VariableNames;

% Force *_missing and renaming_info_missing columns to string type
for i = 1:length(varNames)
    if endsWith(varNames{i}, '_missing') || varNames{i} == "renaming_info_missing"
        opts = setvaropts(opts, varNames{i}, 'Type', 'string');
    end
end

% Read table with modified import options
file_table = readtable(file_list_path, opts);

%% Section 2: Loop through each row
N = height(file_table);
for i = 1:N
    % Print progress
    row_label = file_table.subjectID{i} + "_" + file_table.sessionID{i} + "_" + file_table.runID{i};
    fprintf('Checking row %d of %d: %s\n', i, N, row_label);

    % Skip rows with missing info
    value = file_table.renaming_info_missing(i);
    if ~(value == "" || ismissing(value))
        fprintf('  Skipped due to missing renaming info.\n');
        continue;
    end

    % Get format
    format = string(file_table.format(i));

    % Get list of original and renamed file columns based on format
    original_fields = {"EEGfile"};
    renamed_fields  = {"EEGfile_renamed"};

    if format == "Curry 7"
        original_fields = [original_fields, "dap", "rs3", "ceo", "cef"];
        renamed_fields  = [renamed_fields,  "dap_renamed", "rs3_renamed", "ceo_renamed", "cef_renamed"];
    elseif format == "Curry 8"
        original_fields = [original_fields, "cdt_dpa", "cdt_ceo", "cdt_cef"];
        renamed_fields  = [renamed_fields,  "cdt_dpa_renamed", "cdt_ceo_renamed", "cdt_cef_renamed"];
    elseif format == "XDF"
        original_fields = [original_fields, "urevents_csv", "events_csv"];
        renamed_fields  = [renamed_fields,  "urevents_csv_renamed", "events_csv_renamed"];
    end

    %% Section 3: Copy each file (if it doesn't already exist)
    for j = 1:length(original_fields)
        original_col = original_fields{j};
        renamed_col  = renamed_fields{j};

        % Extract source and destination file names
        original_file = string(file_table.(original_col){i});
        renamed_file  = string(file_table.(renamed_col){i});

        % Skip if original or renamed file is missing (i.e. empty or <missing>)
        if ismissing(original_file) || ismissing(renamed_file)
            fprintf('  Skipping %s: missing filename.\n', original_col);
            continue;
        end

        % Build full source and destination paths
        source_path = file_table.path{i};
        destination_rel_path = file_table.path_renamed{i};

        source_file      = fullfile(source_path, original_file);
        destination_dir  = fullfile(local_base, destination_rel_path);
        destination_file = fullfile(destination_dir, renamed_file);

        % Create destination folder if it doesn't exist
        if ~exist(destination_dir, 'dir')
            mkdir(destination_dir);
        end

        % Skip copy if destination file already exists
        if exist(destination_file, 'file')
            fprintf('  Already exists: %s\n', renamed_file);
            continue;
        end

        % Attempt to copy the file with error handling
        try
            copyfile(source_file, destination_file);
            fprintf('  Copied: %s\n', renamed_file);
        catch ME
            warning('  Failed to copy %s: %s', original_file, ME.message);
        end
    end
end

fprintf('\nAll eligible files copied.\n');

log_command_window('stop');
