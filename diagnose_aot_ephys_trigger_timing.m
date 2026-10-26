function report = diagnose_aot_ephys_trigger_timing(varargin)
%DIAGNOSE_AOT_EPHYS_TRIGGER_TIMING Compare WAV scheduling leads in the real Session.
% report = diagnose_aot_ephys_trigger_timing()
% Defaults: eight blank trials each at 0.100 and 0.500 seconds minimum lead.
% Press Space for each condition; Q stops the diagnostic. Real WAV pulses use
% the selected site's audio device and output channel. No YAML is modified.
% Optional 'Movie','1056_rv.mp4' repeats a prepared movie instead of blanks.
% 'PreflightOnly',true saves configurations without opening any PTB device.
% This measures software/driver timestamps, not electrical or optical onset.

parser = inputParser;
addParameter(parser,'Site',"");
addParameter(parser,'Output',"");
addParameter(parser,'LeadSeconds',[.100 .500]);
addParameter(parser,'TrialsPerLead',8);
addParameter(parser,'Movie',"");
addParameter(parser,'SkipSyncTests',false);
addParameter(parser,'PreflightOnly',false);
parse(parser,varargin{:});
options = parser.Results;
leads = options.LeadSeconds;
assert(isnumeric(leads) && isreal(leads) && isvector(leads) && ...
    ~isempty(leads) && all(isfinite(leads)) && all(leads>0) && ...
    numel(unique(leads))==numel(leads),'ephys:DiagnosticLead', ...
    'LeadSeconds must contain distinct finite positive durations in seconds.');
assert(isnumeric(options.TrialsPerLead) && isscalar(options.TrialsPerLead) && ...
    isfinite(options.TrialsPerLead) && options.TrialsPerLead>=1 && ...
    options.TrialsPerLead==floor(options.TrialsPerLead),'ephys:DiagnosticTrials', ...
    'TrialsPerLead must be a positive integer.');
assert(islogical(options.SkipSyncTests) && isscalar(options.SkipSyncTests) && ...
    islogical(options.PreflightOnly) && isscalar(options.PreflightOnly), ...
    'ephys:DiagnosticOption','SkipSyncTests and PreflightOnly must be logical scalars.');
movie = string(options.Movie);
assert(isscalar(movie) && ~ismissing(movie),'ephys:DiagnosticMovie', ...
    'Movie must be one movie basename, or empty for blank trials.');
asset = "blank";
if strlength(movie)>0
    assert(~contains(movie,"/") && ~contains(movie,"\"), ...
        'ephys:DiagnosticMovie','Movie must be a basename under the configured video root.');
    asset = movie;
end

root = ephys.projectRoot();
addpath(fullfile(root,'third_party','yaml'));
[sitePath,selectionPath] = ephys.resolveSitePath(options.Site);
basePath = fullfile(root,'config','experiment.yml');
base = ephys.readYaml(basePath);
site = ephys.readYaml(sitePath);
ephys.checkSchema(site,base);
config = ephys.mergeConfig(base,site);
config.debug = true;
config.debug_simulated_input_only = false;
config.task_kind = "video";
config.site_path = string(sitePath);
config.site_selection_path = string(selectionPath);
config.answer_path = "";
config.schedule = ephys.validateSchedule(cellstr(repmat(asset,1,options.TrialsPerLead)));
config.display.full_screen = true;
config.display.skip_sync_tests = options.SkipSyncTests;
config.eyelink.enabled = false;
config.markers.backend = 'wav';
config.markers.blank_enabled = true;
config.markers.run_boundary_enabled = true;
config.protocol.video_initial_fixation_s = 1;
config.protocol.video_final_fixation_s = 1;
config.protocol.video_pre_fixation_s = 1;
config.protocol.video_post_fixation_s = .1;
if asset=="blank", config.protocol.video_duration_s = .5; end

folder = string(options.Output);
if strlength(folder)==0
    assert(strlength(string(config.paths.output_root))>0,'ephys:OutputRoot', ...
        'Set paths.output_root in the selected site, or pass Output.');
    folder = fullfile(config.paths.output_root,'diagnostics', ...
        "trigger_timing_"+string(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
end
outputFile = java.io.File(char(folder));
folder = string(char(outputFile.getAbsolutePath()));
assert(~isfolder(folder) && ~isfile(folder),'ephys:OutputExists', ...
    'Diagnostic output already exists: %s',folder);
[ok,message] = mkdir(folder);
assert(ok,'ephys:OutputCreate','Cannot create %s: %s',folder,message);
config.paths.output_root = folder;
schedulePath = fullfile(folder,'schedule.yml');
yaml.dumpFile(schedulePath,struct('stimuli',struct('movie_files', ...
    {cellstr(config.schedule)})),'block');
config.schedule_path = schedulePath;

planned = cell(1,numel(leads));
for k=1:numel(leads)
    condition = config;
    condition.markers.wav.minimum_lead_s = leads(k);
    condition.instructions.video = sprintf( ...
        'Trigger timing diagnostic: condition %d/%d, minimum lead %.0f ms.\nKeep fixating at the center.', ...
        k,numel(leads),1000*leads(k));
    ephys.validateConfig(condition);
    planned{k} = condition;
end
planPath = fullfile(folder,'planned_conditions.json');
writeJson(planPath,struct('purpose',"WAV scheduling diagnostic, not an acquisition", ...
    'conditions',{planned},'physical_timing_validated',false));
files = {basePath,char(sitePath),char(schedulePath), ...
    [mfilename('fullpath') '.m'],char(planPath)};
if strlength(string(selectionPath))>0, files{end+1} = char(selectionPath); end
waves = ephys.loadTriggerWaveforms(config.markers);
files = [files,cellstr(string({waves.path}))];
provenance = struct('files',{files}, ...
    'sha256',{cellfun(@ephys.sha256,files,'UniformOutput',false)});
report = struct('output',folder,'status',"preflight_complete", ...
    'purpose',"Separate audio scheduling and visual prediction errors", ...
    'minimum_lead_s',leads,'trials_per_lead',options.TrialsPerLead, ...
    'asset',asset,'skip_sync_tests',options.SkipSyncTests, ...
    'site_path',string(sitePath),'site_selection_path',string(selectionPath), ...
    'matlab_version',version,'computer',computer, ...
    'screen_path',string(which('Screen')), ...
    'psychportaudio_path',string(which('PsychPortAudio')), ...
    'physical_timing_validated',false,'conditions',struct([]));
writeJson(fullfile(folder,'summary.json'),report);
if options.PreflightOnly
    fprintf('Trigger diagnostic preflight saved: %s\n',folder);
    return;
end

assert(exist('Screen','file')>0 && exist('PsychPortAudio','file')>0, ...
    'ephys:PTBMissing','Add Psychtoolbox to the MATLAB path before running this diagnostic.');
combined = table();
ephys.assertSessionImplementation();
for k=1:numel(planned)
    condition = planned{k};
    runId = sprintf('condition_%02d',k);
    job = ephys.Session(condition,provenance,runId,ephys.WavTriggerBackend(),@readInput);
    guard = onCleanup(@() job.close());
    prioritySet = false;
    fprintf('Condition %d/%d: lead %.0f ms, %d %s trials; press Space to start, Q to stop.\n', ...
        k,numel(planned),1000*leads(k),options.TrialsPerLead,char(asset));
    status = "complete"; errorId = ""; reason = "";
    try
        job.run();
    catch cause
        status = "aborted"; errorId = string(cause.identifier); reason = string(cause.message);
    end
    job.stopPresentation();
    status = job.finish(status,reason);
    rows = ephys.triggerTimingBreakdown(job.Triggers.records());
    rows.condition_index = repmat(k,height(rows),1);
    rows.minimum_lead_s = repmat(leads(k),height(rows),1);
    writetable(rows,fullfile(job.OutputDir,runId+"_timing_breakdown.tsv"), ...
        'FileType','text','Delimiter','\t');
    combined = [combined;rows]; %#ok<AGROW>
    observed = ismember(rows.status,["complete","failed"]) & ...
        isfinite(rows.audio_start_getsecs) & isfinite(rows.associated_flip_getsecs);
    onsets = observed & ismember(rows.event_type,["video_onset","blank_onset"]);
    summary = struct('minimum_lead_s',leads(k),'status',status, ...
        'error_identifier',errorId,'error_message',reason,'output',job.OutputDir, ...
        'onset_count',sum(onsets), ...
        'audio_schedule_error_ms',describe(rows.audio_schedule_error_ms(onsets)), ...
        'visual_prediction_error_ms',describe(rows.visual_prediction_error_ms(onsets)), ...
        'audio_visual_delta_ms',describe(rows.audio_visual_delta_ms(onsets)), ...
        'audio_from_write_ms',describe(rows.audio_from_write_ms(onsets)));
    report.conditions = [report.conditions;summary];
    report.status = "running";
    writetable(combined,fullfile(folder,'timing_breakdown.tsv'), ...
        'FileType','text','Delimiter','\t');
    writeJson(fullfile(folder,'summary.json'),report);
    fprintf('Lead %.0f ms: N=%d, mean audio-target=%+.3f ms, visual-target=%+.3f ms, audio-visual=%+.3f ms.\n', ...
        1000*leads(k),summary.onset_count,summary.audio_schedule_error_ms.mean, ...
        summary.visual_prediction_error_ms.mean,summary.audio_visual_delta_ms.mean);
    clear guard
    if errorId=="ephys:UserAbort", break; end
end
report.status = "complete";
if numel(report.conditions)~=numel(planned) || ...
        any(string({report.conditions.status})~="complete")
    report.status = "incomplete";
end
writeJson(fullfile(folder,'summary.json'),report);
fprintf('Saved trigger timing diagnostic: %s\n',folder);

    function [key,time] = readInput(active)
        % Preserve the real keyboard queue and acquisition process priority.
        if ~prioritySet
            Priority(MaxPriority(active.Window));
            prioritySet = true;
        end
        key = ""; time = NaN;
        [event,remaining] = KbEventGet(active.Config.input_device_index,0);
        assert(remaining<=9000,'ephys:InputOverflow','Keyboard queue nearly full.');
        if ~isempty(event) && event.Pressed
            key = lower(string(KbName(event.Keycode)));
            time = event.Time;
        end
    end
end

function result = describe(values)
values = values(isfinite(values));
result = struct('count',numel(values),'mean',NaN,'stddev',NaN,'min',NaN,'max',NaN);
if isempty(values), return; end
result.mean = mean(values);
result.min = min(values); result.max = max(values);
if numel(values)>1, result.stddev = std(values); end
end

function writeJson(file,value)
fid = fopen(file,'w');
assert(fid>=0,'ephys:DiagnosticOutput','Cannot write %s.',file);
guard = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true));
end
