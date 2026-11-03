function [config, provenance] = loadConfig(taskKind, schedulePath, sitePath, debugMode, answerPath, selectionPath)
%LOADCONFIG Strict experiment configuration and exact saved schedule order.
% taskKind is "video", "memory" or "practice"; practice loads as task_kind
% "video" with paths.video_root set to paths.practice_video_root and
% playback.native_media_root set to playback.practice_native_media_root.
if nargin < 4, debugMode = false; end
if nargin < 5, answerPath = ""; end
if nargin < 6, selectionPath = ""; end
root = ephys.projectRoot();
parserDir = fullfile(root,'third_party','yaml');
if ~contains(path,parserDir), addpath(parserDir); end
configDir = fullfile(root,'config');
basePath = fullfile(configDir,'experiment.yml');
schema = ephys.readYaml(basePath);
config = schema;
files = {basePath};
if strlength(string(sitePath)) == 0
    assert(debugMode,'ephys:SiteRequired', ...
        'A site/protocol YAML is required outside debug mode.');
    sitePath = "";
else
    sitePath = char(sitePath);
    site = ephys.readYaml(sitePath);
    ephys.checkSchema(site,schema);
    config = ephys.mergeConfig(config,site);
    files{end+1} = sitePath;
end
if strlength(string(selectionPath)) > 0
    files{end+1} = char(selectionPath);
end
if debugMode
    debugPath = fullfile(configDir,'debug.yml');
    debugOverride = ephys.readYaml(debugPath);
    ephys.checkSchema(debugOverride,schema);
    config = ephys.mergeConfig(config,debugOverride);
    files{end+1} = debugPath;
end
config.debug = logical(debugMode);
config.debug_simulated_input_only = false;
if string(taskKind) == "practice"
    % The practice task is the video task with the shared practice schedule
    % and its own clip and copy folders, kept apart from the main videos;
    % everything else is presented the same way.
    taskKind = "video";
    config.paths.video_root = config.paths.practice_video_root;
    if string(config.playback.backend) == "native"
        ephys.nativeMediaRoot(config.playback,'practice_native_media_root');
    end
    config.playback.native_media_root = config.playback.practice_native_media_root;
end
config.task_kind = string(taskKind);
config.schedule_path = string(schedulePath);
config.site_path = string(sitePath);
config.site_selection_path = string(selectionPath);
config.answer_path = string(answerPath);
if debugMode && strlength(string(config.paths.output_root)) == 0
    config.paths.output_root = fullfile(root,'outputs','ephys_debug');
end
scheduleDoc = ephys.readYaml(schedulePath);
assert(isequal(fieldnames(scheduleDoc),{'stimuli'}), ...
    'ephys:ScheduleSchema','Schedule must contain only stimuli.');
stim = scheduleDoc.stimuli;
if string(taskKind) == "video"
    assert(isequal(fieldnames(stim),{'movie_files'}), ...
        'ephys:ScheduleSchema','Video schedule must contain movie_files only.');
    config.schedule = ephys.validateSchedule(stim.movie_files);
elseif string(taskKind) == "memory"
    assert(isfield(stim,'picture_files') && ...
        all(ismember(fieldnames(stim),{'picture_files';'movie_files'})), ...
        'ephys:ScheduleSchema','Memory schedule must contain picture_files.');
    if isfield(stim,'movie_files')
        assert(isempty(stim.movie_files), 'ephys:ScheduleSchema', ...
            'Memory schedule movie_files must be empty.');
    end
    config.schedule = ephys.validatePictureSchedule(stim.picture_files);
else
    error('ephys:TaskKind','Task must be video, memory or practice.');
end
ephys.validateConfig(config);
files{end+1} = char(schedulePath);
if strlength(string(answerPath)) > 0
    assert(isfile(answerPath),'ephys:AnswerFile','Missing answer file.');
    files{end+1} = char(answerPath);
end
% Preserve the exact pulse assets alongside the configuration and schedule.
waves=ephys.loadTriggerWaveforms(config.markers);
for i=1:numel(waves)
    files{end+1}=char(waves(i).path);
end
provenance.files = files;
provenance.sha256 = cellfun(@ephys.sha256,files,'UniformOutput',false);
end
