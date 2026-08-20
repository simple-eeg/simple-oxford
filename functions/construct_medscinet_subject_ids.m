function subjectID = construct_medscinet_subject_ids(project, participant)
%CONSTRUCT_MEDSCINET_SUBJECT_IDS Build Oxford IDs from MedSciNet fields.
%
% subjectID = construct_medscinet_subject_ids(project, participant)
%
% Inputs must contain one project and participant component per source row.
% Missing values and surrounding whitespace are normalised without changing
% the remaining text. A wholly blank pair produces a blank ID; a partially
% blank pair is rejected by row number. The Oxford project-prefix spelling is
% normalised consistently from "OX" to "Ox" before concatenation.

try
    project = string(project);
    participant = string(participant);
catch
    error('SimpleOxford:MedSciNetSubjectID:InvalidInput', ...
        'Project and participant columns must be representable as text.');
end

if numel(project) ~= numel(participant)
    error('SimpleOxford:MedSciNetSubjectID:SizeMismatch', ...
        'Project and participant columns must contain the same number of rows.');
end

project = project(:);
participant = participant(:);
project(ismissing(project)) = "";
participant(ismissing(participant)) = "";
project = strtrim(project);
participant = strtrim(participant);

partialBlank = (project == "") ~= (participant == "");
if any(partialBlank)
    row = find(partialBlank, 1, 'first');
    error('SimpleOxford:MedSciNetSubjectID:PartialBlank', ...
        ['MedSciNet project and participant components must either both be ' ...
         'present or both be blank. Invalid source row: %d.'], row);
end

project = replace(project, "OX", "Ox");
subjectID = project + participant;
end
