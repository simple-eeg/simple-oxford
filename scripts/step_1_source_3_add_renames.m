%% step_1_source_3_add_renames.m 
% This script adds renamed filenames and destination paths to the EEG file table.
% It loads the existing dataset_list_prelim.xlsx spreadsheet, adds renamed filenames
% using BIDS-style filename conventions and local destination paths, and flags rows
% lacking required identifiers, a recognised source format, or required source files.

log_command_window('start');
clear; clc;

%% Section 1: Setup

% Define base paths and filenames
local_base = '/Users/lukebaxter/Developer/simple-eeg/simple-oxford';
file_list_name = 'dataset_list_prelim.xlsx';
file_list_path = fullfile(local_base, 'data_lists', file_list_name);

% Read the existing table
file_table = readtable(file_list_path, 'PreserveVariableNames', true);

% List of *_missing columns to ensure are strings
missing_columns = {
    "EEGfile_missing", "dap_missing", "rs3_missing", "ceo_missing", "cef_missing", ...
    "cdt_dpa_missing", "cdt_ceo_missing", "cdt_cef_missing", ...
    "urevents_csv_missing", "events_csv_missing"
    };

% Loop through and convert each column to string
for c = 1:length(missing_columns)
    colname = missing_columns{c};
    if ismember(colname, file_table.Properties.VariableNames)
        % Convert column to string if not already
        file_table.(colname) = string(file_table.(colname));
    end
end

n_rows = height(file_table);

% Define file types to rename
file_types = { 'EEGfile', 'dap', 'rs3', 'ceo', 'cef', ...
    'cdt_dpa', 'cdt_ceo', 'cdt_cef', 'urevents_csv', 'events_csv' };

% Create new columns for renamed filenames
for i = 1:length(file_types)
    file_table.(file_types{i} + "_renamed") = repmat("", n_rows, 1);
end

% Add column for renamed path and renaming info status
file_table.path_renamed = repmat("", n_rows, 1);
file_table.renaming_info_missing = repmat("", n_rows, 1);

%% Section 2: Process each row of the table
for i = 1:n_rows
    % Extract required fields for this row
    subjID = file_table.subjectID{i};
    sessID = file_table.sessionID{i};
    runID = file_table.runID{i};
    format = string(file_table.format{i});

    % Show progress in command window
    row_label = subjID + "_" + sessID + "_" + runID;
    fprintf("Processing row %d of %d: %s\n", i, n_rows, row_label);

    % Check if required metadata is missing
    if any(cellfun(@isempty, {subjID, sessID, runID})) || format == ""
        file_table.renaming_info_missing(i) = "missing";
        continue; % Skip to next row
    end

    % Build BIDS base filename and destination path
    bids_prefix = "sub-" + subjID + "_ses-" + sessID + "_run-" + runID;
    dest_path = fullfile("data", "source", "sub-" + subjID, "ses-" + sessID, "eeg");
    file_table.path_renamed(i) = dest_path;

    % Define which files are relevant for the current format
    switch format
        case "Curry 7"
            relevant_files = { 'EEGfile', 'dap', 'rs3', 'ceo', 'cef' };
        case "Curry 8"
            relevant_files = { 'EEGfile', 'cdt_dpa', 'cdt_ceo', 'cdt_cef' };
        case "XDF"
            relevant_files = { 'EEGfile', 'urevents_csv', 'events_csv' };
        otherwise
            % If format not recognized, skip row and flag as missing
            file_table.renaming_info_missing(i) = "missing";
            continue;
    end

    % Check for missing files and build renamed filenames
    missing_flag = false; % Will be set to true if any file is missing

    for j = 1:length(relevant_files)
        field = relevant_files{j};
        missing_col = field + "_missing";

        % If the file is marked as missing, leave renamed blank
        value = file_table.(missing_col)(i);
        if ~(value == "" || ismissing(value))
            missing_flag = true;
            continue;
        end

        % Get the original file name
        original_file = file_table.(field){i};

        % Build renamed filename based on file type and format
        if format == "XDF"
            if field == "EEGfile"
                new_name = bids_prefix + "_eeg.xdf";
            elseif field == "urevents_csv"
                new_name = bids_prefix + "_urevents.csv";
            elseif field == "events_csv"
                new_name = bids_prefix + "_events.csv";
            else
                continue;
            end

        elseif format == "Curry 8"
            if field == "EEGfile"
                new_name = bids_prefix + "_eeg.cdt";
            else
                % Curry 8 sidecar files: reuse .cdt from main EEGfile and append .dpa, .ceo, or .cef
                % In theory, these files should have names like *.cdt.dpa, *.cdt.ceo, *.cdt.cef
                % But on our remote server, the .cef files have been renamed to end only in .cef (e.g., missing '.cdt')
                % This workaround checks for that case and handles it
                if contains(original_file, ".cdt")
                    % Normal case: extract everything after ".cdt" (e.g., ".dpa", ".ceo", ".cef")
                    ext = extractAfter(original_file, ".cdt");
                    new_name = bids_prefix + "_eeg.cdt" + ext;
                else
                    % Workaround for misnamed files (e.g., .cef without .cdt)
                    % Extract extension from the full filename (e.g., ".cef")
                    [~, ~, ext] = fileparts(original_file);
                    new_name = bids_prefix + "_eeg.cdt" + ext;
                end
            end

        elseif format == "Curry 7"
            [~, ~, ext] = fileparts(original_file);  % e.g. .dat, .dap, .rs3, etc.
            new_name = bids_prefix + "_eeg" + ext;

        else
            continue;
        end

        % Save renamed filename to table
        file_table.(field + "_renamed")(i) = new_name;
    end

    % If any file was missing, flag this row
    if missing_flag
        file_table.renaming_info_missing(i) = "missing";
    end
end

%% Section 3: Save updated table
writetable(file_table, file_list_path, 'WriteVariableNames', true);

% Summary output
n_missing_rows = sum(file_table.renaming_info_missing == "missing");
fprintf("\nRenaming complete. %d of %d rows flagged as missing.\n", n_missing_rows, n_rows);

log_command_window('stop');
