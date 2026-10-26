function [number,source] = scheduleSet(subject,mapPath)
%SCHEDULESET Saved schedule set (the sub_NN in schedule filenames) for a subject.
% A numeric label always uses its own number, as before. A name takes its set
% from the local map, config/subjects.local.yml by default; a name without an
% entry is an error, so no schedule is chosen silently. The map may not give a
% numeric label another set.
if nargin<2 || strlength(string(mapPath))==0
    mapPath = fullfile(ephys.projectRoot(),'config','subjects.local.yml');
end
mapPath = string(mapPath);
label = ephys.subjectLabel(subject);
entries = readSubjectMap(mapPath);
match = entries(string({entries.label})==label);
if isscalar(match)
    number = match.schedule_set;
    source = "subject map "+mapPath;
elseif ~isempty(regexp(label,'^[0-9]+$','once'))
    number = str2double(label);
    source = "subject number";
else
    error('ephys:ScheduleSet',['No schedule set for subject "%s". Add a line to ' ...
        'the subjects list in %s, e.g.  - {label: %s, schedule_set: 3}'],label,mapPath,label);
end
end

function entries = readSubjectMap(file)
% Entries with labels normalized by ephys.subjectLabel; none if the file is absent.
entries = struct('label',{},'schedule_set',{});
if ~isfile(file), return; end
parserDir = fullfile(ephys.projectRoot(),'third_party','yaml');
if ~contains(path,parserDir), addpath(parserDir); end
try
    doc = ephys.readYaml(file);
catch cause
    % readYaml's duplicate-key guard sees repeated keys across block-style items.
    error('ephys:SubjectMap',['Cannot read %s: %s\nWrite one entry per line, ' ...
        'e.g.  - {label: patientname, schedule_set: 3}'],file,cause.message);
end
assert(isequal(fieldnames(doc),{'subjects'}),'ephys:SubjectMap', ...
    '%s must contain only a "subjects" list.',file);
items = doc.subjects;
if isempty(items), return; end
assert(iscell(items),'ephys:SubjectMap','"subjects" in %s must be a list.',file);
for k = 1:numel(items)
    item = items{k};
    assert(isstruct(item) && isscalar(item) && ...
        isequal(sort(fieldnames(item)),{'label';'schedule_set'}),'ephys:SubjectMap', ...
        'Entry %d in %s needs exactly "label" and "schedule_set".',k,file);
    try
        label = ephys.subjectLabel(item.label);
    catch cause
        error('ephys:SubjectMap','Entry %d in %s: %s',k,file,cause.message);
    end
    number = item.schedule_set;
    assert(isnumeric(number) && isscalar(number) && isfinite(number) && ...
        number>0 && number==floor(number),'ephys:SubjectMap', ...
        'Entry %d in %s: schedule_set must be a positive integer.',k,file);
    assert(isempty(regexp(label,'^[0-9]+$','once')) || number==str2double(label), ...
        'ephys:SubjectMap',['Entry %d in %s: subject %s always uses schedule set %d, ' ...
        'its own number; remove the entry or correct schedule_set.'],k,file,label, ...
        str2double(label));
    assert(~any(string({entries.label})==label),'ephys:SubjectMap', ...
        'Subject "%s" appears more than once in %s.',label,file);
    entries(end+1) = struct('label',label,'schedule_set',double(number)); %#ok<AGROW>
end
end
