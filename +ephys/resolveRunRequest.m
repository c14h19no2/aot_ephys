function request = resolveRunRequest(subject,sessionNumber,runNumber,varargin)
%RESOLVERUNREQUEST Select a saved schedule and an optional recording number.
% Subject is a number (zero-padded to three digits) or a letters-and-digits
% label; its schedule set comes from ephys.scheduleSet. Session and run select
% the saved schedule. Task "practice" uses the one shared practice schedule. A fourth positive integer labels a separate output
% recording; [] is equivalent to omitting it.
label = ephys.subjectLabel(subject);
assert(validNumber(sessionNumber) && validNumber(runNumber),'ephys:RunIdentity', ...
    'Session and run must be finite positive integers.');
recordingNumber = [];
if ~isempty(varargin) && ...
        ~(ischar(varargin{1}) || isstring(varargin{1}))
    recordingNumber = varargin{1};
    assert((isnumeric(recordingNumber) && isempty(recordingNumber)) || ...
        validNumber(recordingNumber),'ephys:RecordingNumber', ...
        'The optional fourth argument must be a positive integer or [].');
    varargin = varargin(2:end);
end
parser = inputParser;
addParameter(parser,'Task',"video",@(x) ischar(x)||isstring(x));
addParameter(parser,'Site',"",@(x) ischar(x)||isstring(x));
addParameter(parser,'Schedule',"",@(x) ischar(x)||isstring(x));
addParameter(parser,'SubjectMap',"",@(x) ischar(x)||isstring(x));
addParameter(parser,'Answers',"",@(x) ischar(x)||isstring(x));
addParameter(parser,'Overwrite',false,@(x) islogical(x)&&isscalar(x));
addParameter(parser,'Debug',false,@(x) islogical(x)&&isscalar(x));
addParameter(parser,'DebugSkipSyncTests',false,@(x) islogical(x)&&isscalar(x));
addParameter(parser,'DebugSimulatedInputOnly',false,@(x) islogical(x)&&isscalar(x));
addParameter(parser,'Backend',[],@(x) isempty(x)||isa(x,'ephys.TriggerBackend'));
parse(parser,varargin{:});
p = parser.Results;
assert(p.Debug || (~p.DebugSkipSyncTests && ~p.DebugSimulatedInputOnly), ...
    'ephys:DebugOnly','Debug timing/input overrides are forbidden in acquisition.');
task = string(p.Task);
assert(isscalar(task) && any(task==["video","memory","practice"]), ...
    'ephys:TaskKind','Task must be video, memory or practice.');
root = ephys.projectRoot();
[sitePath,selectionPath] = ephys.resolveSitePath(p.Site);
schedulePath = string(p.Schedule);
setNumber = [];
setSource = "explicit Schedule";
if strlength(schedulePath)==0 && task=="practice"
    % One practice schedule for every subject; no schedule set is needed.
    schedulePath = string(fullfile(root,'config','runs','practice','practice_videos.yml'));
    setSource = "shared practice schedule";
elseif strlength(schedulePath)==0
    [setNumber,setSource] = ephys.scheduleSet(label,p.SubjectMap);
    sourceFolder = "main";
    if task=="memory", sourceFolder = "memory_main_complete"; end
    schedulePath = string(fullfile(root,'config','runs',sourceFolder, ...
        sprintf('experiment_settings_sub_%02d_ses_%02d_run_%02d.yml', ...
        setNumber,sessionNumber,runNumber)));
    if p.Debug && task=="video" && ~isfile(schedulePath)
        schedulePath = string(fullfile(root,'config','runs','debug_blank.yml'));
        warning('ephys:DebugBlankSchedule', ...
            ['No saved video schedule for schedule set %d ses-%02d run-%02d; ' ...
            'using the four-blank debug schedule. Use an existing run ' ...
            'number to test its movies, or pass Schedule.'], ...
            setNumber,sessionNumber,runNumber);
    end
    assert(isfile(schedulePath),'ephys:ScheduleMissing',['No saved %s schedule for ' ...
        'subject %s (schedule set %d), session %d, run %d: %s'],task,label, ...
        setNumber,sessionNumber,runNumber,schedulePath);
end
stem = sprintf('sub-%s_ses-%02d_run-%02d_task-%s', ...
    char(label),sessionNumber,runNumber,char(task));
if ~isempty(recordingNumber)
    stem = [stem sprintf('_record-%02d',recordingNumber)];
end
if p.Debug, stem = [stem '_debug']; end
request = struct('options',p,'task',task,'site_path',string(sitePath), ...
    'site_selection_path',string(selectionPath), ...
    'schedule_path',schedulePath,'run_id',string(stem), ...
    'collection_date',string(datetime('now','Format','yyyy-MM-dd')));
request.identity = struct('subject',label,'task',task,'session',sessionNumber, ...
    'run',runNumber,'recording_number',recordingNumber, ...
    'schedule_set',setNumber,'schedule_set_source',setSource);
end

function ok = validNumber(value)
ok = isnumeric(value) && isreal(value) && isscalar(value) && ...
    isfinite(value) && value>0 && value==floor(value);
end
