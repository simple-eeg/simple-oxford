%% step_1_source_1_create_dataset_list_prelim.m
% Generate EEG File List from MedSciNet Export
% This script loops through each subject-session pair in a MedSciNet export,
% checks the remote server for EEG data files, determines the EEG format,
% generates expected sidecar file names, and saves the output to a spreadsheet.
%
% Naming systems supported (selection is per-row, from MedSciNet):
%   1) BIDS projects: explicitly listed in 'bids_projects'.
%   2) Legacy projects: all projects not listed in 'bids_projects' and not Poppi.
%   3) Poppi/NPEU special case: project 'Ox52' (on MedSciNet 'OX52'), whose data
%      live under remote 'Poppi(Ox52)/P10NNR/P10NNR/'. Here NPEU IDs are used
%      only to locate remote files; local filenames remain BIDS-style using
%      MedSciNet-derived subject/session/run IDs.

log_command_window('start');
clear; clc;

%% Section 1: Setup

% Define base paths for local files and remote server
local_base   = '/Users/lukebaxter/Developer/simple-eeg/simple-oxford';
medscinet_file = fullfile(local_base, 'data_lists', 'medscinet_export_petal.xlsx');
output_file  = fullfile(local_base, 'data_lists', 'dataset_list_prelim.xlsx');
remote_base  = '/Volumes/NDCN_SLATER/PiPAgroup_data_2TS/pipagroup_data_backup';

% Read the MedSciNet spreadsheet
med_data = readtable(medscinet_file, 'PreserveVariableNames', true);

% List of BIDS-formatted projects (extend as needed)
bids_projects = ["Ox75", "Ox76"];

% Poppi/NPEU special case constants
poppi_project = "Ox52";
poppi_root    = fullfile(remote_base, "Poppi(Ox52)");

% Extract relevant identifiers as strings
project_raw = string(med_data.("RECD - Research project"));
participant = string(med_data.("RECD - Participant number"));
session     = string(med_data.("TESTO - Test occasion number"));

% Normalize project ID casing ('OX' → 'Ox')
project_raw = replace(project_raw, 'OX', 'Ox');

% Define column headers for output table
output_vars = {...
    'subjectID', 'sessionID', 'runID', 'format', 'EEGfile', ...
    'dap', 'rs3', 'ceo', 'cef', ...
    'cdt_dpa', 'cdt_ceo', 'cdt_cef', ...
    'urevents_csv', 'events_csv', ...
    'path'};

% Initialize an empty table with appropriate variable types
output_table = table('Size', [0, numel(output_vars)], ...
    'VariableTypes', repmat("string", 1, numel(output_vars)), ...
    'VariableNames', output_vars);

%% Section 2: Loop Through MedSciNet Rows
n_entries = height(med_data);  % Total number of entries in the spreadsheet

for i = 1:n_entries
    % Extract identifiers for this row
    proj = project_raw(i);
    part = participant(i);
    sess = session(i);

    % Construct subject and session IDs (MedSciNet/legacy-derived)
    subject_id = proj + part;
    session_id = sess;
    session_folder_old = subject_id + session_id;  % legacy prefix
    bids_subject = "sub-" + subject_id;
    bids_session = "ses-" + session_id;

    % Decide naming system for this row
    if proj == poppi_project
        naming_system = "poppi";
    elseif ismember(proj, bids_projects)
        naming_system = "bids";
    else
        naming_system = "legacy";
    end

    % Display progress to the console
    fprintf('%d of %d: %s\n', i, n_entries, session_folder_old);

    % Determine remote session path based on naming system
    poppi_base = "";  % will hold the matched NPEU base (e.g., 'P10015') for Poppi rows
    if naming_system == "poppi"
        % Derive NN (two digits) from participant number for Poppi folder matching
        digits_only = regexprep(part, '\D', '');
        if digits_only == ""
            % Mirror existing behavior for "missing session folder": log blank row and continue
            new_row = cell2table({subject_id, session_id, "", "", "", ...
                "", "", "", "", ...
                "", "", "", ...
                "", "", poppi_root}, ...
                'VariableNames', output_vars);
            output_table = [output_table; new_row];
            continue;
        end
        NN = sprintf('%02d', str2double(digits_only));   % e.g., "001" -> "01"

        % Find exactly one top-level folder in Poppi root matching ^P10NN\d$
        dir_list = dir(poppi_root);
        dir_list = dir_list([dir_list.isdir]);
        names = string({dir_list.name});
        names = names(~startsWith(names, "."));  % skip hidden dirs

        pattern = "^P10" + NN + "\d$";
        match_mask = ~cellfun('isempty', regexp(cellstr(names), pattern, 'once'));
        matches = names(match_mask);

        if numel(matches) == 1
            poppi_base = matches(1);  % includes the random digit R
            session_path = fullfile(poppi_root, poppi_base, poppi_base);
        elseif isempty(matches)
            % Mirror existing behavior: append blank row and continue (path = poppi_root)
            new_row = cell2table({subject_id, session_id, "", "", "", ...
                "", "", "", "", ...
                "", "", "", ...
                "", "", poppi_root}, ...
                'VariableNames', output_vars);
            output_table = [output_table; new_row];
            continue;
        else
            error('Multiple Poppi candidates found for project=%s, participant=%s: %s', ...
                proj, part, strjoin(cellstr(matches), ', '));
        end

    elseif naming_system == "bids"
        session_path = fullfile(remote_base, proj, bids_subject, bids_session, 'eeg');
    else
        % legacy
        session_path = fullfile(remote_base, proj, subject_id, session_folder_old);
    end

    % If session folder is missing, log a blank row and continue
    if ~isfolder(session_path)
        new_row = cell2table({subject_id, session_id, "", "", "", ...
            "", "", "", "", ...
            "", "", "", ...
            "", "", session_path}, ...
            'VariableNames', output_vars);
        output_table = [output_table; new_row];
        continue;
    end

    % List non-hidden, non-folder files in the session directory
    file_list = dir(session_path);
    file_list = file_list(~[file_list.isdir]);
    file_list = file_list(~startsWith({file_list.name}, '.'));

    % Identify EEG data files based on extension (case-sensitive)
    all_filenames = string({file_list.name});
    eeg_mask = endsWith(all_filenames, {'.dat', '.cdt', '.xdf'}, 'IgnoreCase', false);
    eeg_files = all_filenames(eeg_mask);

    % If no EEG files are found, log partial row and continue
    if isempty(eeg_files)
        new_row = cell2table({subject_id, session_id, "", "", "", ...
            "", "", "", "", ...
            "", "", "", ...
            "", "", session_path}, ...
            'VariableNames', output_vars);
        output_table = [output_table; new_row];
        continue;
    end

    %% Section 3: Loop Through EEG Files
    for j = 1:length(eeg_files)
        eeg_file = eeg_files(j);

        % Step 1: Identify EEG format
        if endsWith(eeg_file, '.dat')
            format = "Curry 7";
        elseif endsWith(eeg_file, '.cdt')
            format = "Curry 8";
        elseif endsWith(eeg_file, '.xdf')
            format = "XDF";
        else
            continue;
        end

        % Step 2: Extract runID
        if naming_system == "poppi"
            % Poppi: remove extension/_raw/timestamp, then strip the exact Poppi base prefix (incl. random digit)
            base = erase(eeg_file, {'.dat', '.cdt', '.xdf'});     % remove extension
            base = erase(base, '_raw');                           % remove '_raw'
            base = regexprep(base, '_\d{14}$', '');               % remove trailing timestamp
            if poppi_base ~= ""
                prefixPattern = "^" + regexptranslate('escape', poppi_base);
                base = regexprep(base, prefixPattern, '');        % strip 'P10NNR' prefix
            end
            runID = erase(base, '_');                             % remove remaining underscores
            if runID == ""
                runID = "01";                                     % default if empty
            end

        elseif naming_system == "bids"
            % For BIDS-formatted filenames, capture anything between '_run-' and the next '_'
            tokens = regexp(eeg_file, '_run-([^_]+)_', 'tokens');
            if ~isempty(tokens)
                runID = tokens{1}{1};  % Use extracted run ID (letters/digits/mixed, any length)
            else
                runID = "01";          % Default if no run info is found
            end

        else
            % Legacy naming
            base = erase(eeg_file, {'.dat', '.cdt', '.xdf'});     % remove extension
            base = erase(base, '_raw');                           % remove '_raw'
            base = regexprep(base, '_\d{14}$', '');               % remove timestamp
            base = erase(base, session_folder_old);               % remove legacy session prefix
            runID = erase(base, '_');                             % remove remaining underscores
            if runID == ""
                runID = "01";                                     % default when empty
            end
        end

        % Step 3: Define sidecar file names
        if format == "Curry 7"
            base_name = erase(eeg_file, '.dat');
            base_root = regexprep(base_name, '_\d{14}_raw$', '');
            sidecars = struct(...
                'dap', base_name + ".dap", ...
                'rs3', base_name + ".rs3", ...
                'ceo', base_name + ".ceo", ...
                'cef', base_root + "_eventlist.cef");
        elseif format == "Curry 8"
            base_name = erase(eeg_file, '.cdt');
            base_root = regexprep(base_name, '_\d{14}_raw$', '');
            sidecars = struct(...
                'cdt_dpa', base_name + ".cdt.dpa", ...
                'cdt_ceo', base_name + ".cdt.ceo", ...
                'cdt_cef', base_root + "_eventlist.cef");
        elseif format == "XDF"
            base_root = extractBefore(eeg_file, '_eeg.xdf');
            sidecars = struct(...
                'urevents_csv', base_root + "_urevents.csv", ...
                'events_csv', base_root + "_events.csv");
        end

        % Step 4: Populate new row for output table
        new_row = {subject_id, session_id, runID, format, eeg_file, ...
            "", "", "", "", ...
            "", "", "", ...
            "", "", session_path};

        % Fill in sidecar filenames by format
        switch format
            case "Curry 7"
                new_row{6}  = sidecars.dap;
                new_row{7}  = sidecars.rs3;
                new_row{8}  = sidecars.ceo;
                new_row{9}  = sidecars.cef;
            case "Curry 8"
                new_row{10} = sidecars.cdt_dpa;
                new_row{11} = sidecars.cdt_ceo;
                new_row{12} = sidecars.cdt_cef;
            case "XDF"
                new_row{13} = sidecars.urevents_csv;
                new_row{14} = sidecars.events_csv;
        end

        % Append new row to output table
        output_table = [output_table; new_row];
    end
end

%% Section 4: Finalize Output
writetable(output_table, output_file);  % Write table to disk
fprintf('Finished writing EEG file list to: %s\n', output_file);

log_command_window('stop');
