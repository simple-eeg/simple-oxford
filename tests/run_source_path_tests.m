function run_source_path_tests(repoRoot)
%RUN_SOURCE_PATH_TESTS Check source-to-raw registry paths in a temporary tree.

temporaryRoot = tempname;
mkdir(fullfile(temporaryRoot, 'data_lists'));
mkdir(fullfile(temporaryRoot, 'scripts'));
originalPath = path;
originalFolder = pwd;
cleanup = onCleanup(@() restore_environment( ...
    originalPath, originalFolder, temporaryRoot));
scriptsRoot = fullfile(temporaryRoot, 'scripts');
addpath(scriptsRoot, '-begin');
write_text(fullfile(scriptsRoot, 'log_command_window.m'), ...
    sprintf('function log_command_window(varargin)\nend\n'));
clear log_command_window

T = table(["SubjectA"; "SubjectB"], ["VisitA"; "VisitB"], ...
    ["RunA"; "RunB"], repmat("Curry 7", 2, 1), [""; "missing"], ...
    'VariableNames', {'subjectID', 'sessionID', 'runID', 'format', 'event_missing'});
for field = ["EEGfile", "dap", "rs3", "ceo", "cef"]
    T.(field) = repmat("recording." + field, 2, 1);
    T.(field + "_missing") = [""; "missing"];
end
T.EEGfile(:) = "recording.dat";
registry = fullfile(temporaryRoot, 'data_lists', 'dataset_list_prelim.xlsx');
writetable(T, registry);

run_preparation(repoRoot, temporaryRoot, ...
    'step_1_source_3_add_renames.m', 'local_base');
stored = readtable(registry, 'TextType', 'string');
assert(stored.path_renamed(1) == "data/source/sub-SubjectA/ses-VisitA/eeg");
assert(~any(contains(stored.path_renamed, "\")));

run_preparation(repoRoot, temporaryRoot, ...
    'step_2_raw_3_add_reformats.m', 'baseDir');
stored = readtable(registry, 'TextType', 'string');
assert(stored.path_reformatted(1) == "data/raw/sub-SubjectA/ses-VisitA/eeg");
assert(endsWith(stored.EEGfile_reformatted(1), '.set'));
fprintf('SOURCE PATH TEST PASSED: source and raw registry paths use forward slashes.\n');
end

function run_preparation(repoRoot, temporaryRoot, filename, variable)
source = fileread(fullfile(repoRoot, 'scripts', filename));
assignment = regexp(source, ['(?m)^' variable '\s*=\s*''[^'']+'';'], 'match');
assert(isscalar(assignment));
replacement = [variable ' = ''' strrep(temporaryRoot, '''', '''''') ''';'];
source = strrep(source, assignment{1}, replacement);
runner = sprintf('function run_preparation_fixture\n%s\nend\n', source);
scriptsRoot = fullfile(temporaryRoot, 'scripts');
write_text(fullfile(scriptsRoot, 'run_preparation_fixture.m'), runner);
clear run_preparation_fixture
rehash path
cd(scriptsRoot);
run_preparation_fixture();
end

function write_text(filename, value)
fid = fopen(filename, 'wt');
assert(fid >= 0);
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s', value);
end

function restore_environment(originalPath, originalFolder, temporaryRoot)
cd(originalFolder);
path(originalPath);
clear run_preparation_fixture log_command_window
if isfolder(temporaryRoot)
    rmdir(temporaryRoot, 's');
end
end
