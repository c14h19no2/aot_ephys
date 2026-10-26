function writeOutput(session,status,reason)
%WRITEOUTPUT Persist buffered logs only after presentation has stopped.
folder = char(session.OutputDir);
stem = char(session.RunId);
flips = session.Log.flipRecords();
events = session.Log.eventRecords();
markers = session.Triggers.records();
for i = 1:numel(events)
    events(i).onset_s = events(i).onset_getsecs-session.StartTime;
end
writeRows(flips,ephys.emptyFlip(),fullfile(folder,[stem '_flips.tsv']));
writeRows(events,ephys.emptyEvent(),fullfile(folder,[stem '_events.tsv']));
writeRows(markers,ephys.emptyMarker(),fullfile(folder,[stem '_markers.tsv']));
resolved = session.Config;
resolved.schedule = cellstr(resolved.schedule);
writeJson(fullfile(folder,[stem '_resolved_config.json']),resolved);
qcConfig = session.Config;
qcConfig.display_timing = session.DisplayTiming;
for field=["NativeTrials","NativePendingTrials"]
    if isprop(session,field) || (isstruct(session) && isfield(session,field))
        name="native_trials";
        if field=="NativePendingTrials", name="native_pending_trials"; end
        qcConfig.(name)=session.(field);
    end
end
qcStatus=struct('status',"complete",'error_id',"",'error',"");
try
    qc = ephys.reconstructRecords(flips,events,markers,session.Inventory,qcConfig);
    writeRows(qc.trials,emptyTrialTemplate(),fullfile(folder,[stem '_trial_qc.tsv']));
catch cause
    % QC never changes the completion state of the recorded presentation.
    qcStatus=struct('status',"failed",'error_id',string(cause.identifier), ...
        'error',string(cause.message));
    qc=struct('run_qc',qcStatus,'initial_fixation',struct('status',"qc_unavailable"), ...
        'final_fixation',struct('status',"qc_unavailable"));
    warning('ephys:PostRunQC','Raw logs/config saved; post-run QC failed: %s',cause.message);
end
sources = repmat(struct('original',"",'copy',"",'sha256',"", ...
    'expected_sha256',"",'status',"",'error',""), ...
    numel(session.Provenance.files),1);
sourceDir = fullfile(folder,'sources');
if ~isfolder(sourceDir), mkdir(sourceDir); end
for i = 1:numel(sources)
    original = string(session.Provenance.files{i});
    [~,name,ext] = fileparts(original);
    destination = fullfile(sourceDir,sprintf('%02d_%s%s',i,name,ext));
    sources(i).original = original;
    sources(i).copy = string(destination);
    sources(i).expected_sha256 = string(session.Provenance.sha256{i});
    try
        [ok,message] = copyfile(original,destination);
        if ~ok, error('ephys:SourceCopy','Could not copy source: %s',message); end
        sources(i).sha256 = string(ephys.sha256(destination));
        sources(i).status = "verified";
        if sources(i).sha256~=sources(i).expected_sha256
            sources(i).status = "changed_after_preflight";
            sources(i).error = "Configuration or schedule changed after preflight.";
        end
    catch cause
        sources(i).status = "copy_failed";
        sources(i).error = string(cause.message);
    end
    if sources(i).status~="verified"
        warning('ephys:SourceProvenance','Raw logs/config saved; source %s: %s', ...
            original,sources(i).error);
    end
end
manifest = struct();
manifest.run_id = session.RunId;
if isfield(session.Config,'run_identity')
    manifest.run_identity = session.Config.run_identity;
end
if isfield(session.Config,'run_output')
    manifest.run_output = session.Config.run_output;
end
manifest.status = string(status);
manifest.reason = string(reason);
manifest.task = session.Config.task_kind;
manifest.memory_variant = string(session.Config.task.memory_variant);
manifest.session_start_getsecs = session.StartTime;
manifest.session_stop_getsecs = session.StopTime;
manifest.debug = session.Config.debug;
manifest.debug_simulated_input_only = ...
    session.Config.debug_simulated_input_only;
manifest.ptb_skip_sync_tests = session.Config.display.skip_sync_tests;
manifest.ptb_effective_skip_sync_tests = session.EffectiveSkipSync;
manifest.display_timing = session.DisplayTiming;
manifest.ifi_source = "unavailable";
manifest.ifi_valid_samples = session.IFISamples;
manifest.ifi_stddev_s = session.IFIStddev;
manifest.scheduling_ifi_s = session.IFI;
manifest.measured_ifi_s = NaN;
manifest.measured_refresh_hz = NaN;
if isfield(session.DisplayTiming,'ifi_source')
    manifest.ifi_source = session.DisplayTiming.ifi_source;
    if session.DisplayTiming.interval_is_measured
        manifest.measured_ifi_s = session.IFI;
        manifest.measured_refresh_hz = 1/session.IFI;
    end
end
manifest.matlab_version = string(version);
manifest.ptb_version = "";
if exist('PsychtoolboxVersion','file')>0
    manifest.ptb_version = string(PsychtoolboxVersion);
end
manifest.matlab_code_revision = string(ephys.gitRevision(ephys.projectRoot()));
% Retain the historical field without looking outside this MATLAB project.
manifest.python_source_revision = "";
manifest.ordered_schedule = cellstr(session.Config.schedule);
manifest.configuration_sources = sources;
manifest.media = session.Inventory;
manifest.media_hash_scope = ...
    "SHA-256 at preflight; video bytes rechecked before and after each complete decode";
manifest.trigger_backend = class(session.Triggers.Backend);
manifest.marker_protocol=session.Config.markers;
manifest.trigger_offset_policy="report_only";
manifest.runtime_qc_policy="record_and_continue_recoverable_anomalies";
manifest.post_run_qc=qcStatus;
manifest.trigger_offset_reference_s=session.Config.markers.wav.max_sync_error_s;
if isa(session.Triggers.Backend,'ephys.WavTriggerBackend')
    manifest.trigger_signal="named analog WAV waveform; no integer TTL encoding";
    manifest.trigger_time_source="PTB audio start estimate, not a measured electrical edge";
else
    manifest.trigger_signal="named dummy events; no electrical or audio output";
    manifest.trigger_time_source="software simulation only";
end
if isprop(session.Triggers.Backend,'Metadata')
    manifest.trigger_audio=session.Triggers.Backend.Metadata;
end
manifest.trigger_close_error = session.Triggers.CloseError;
manifest.hardware_validation = "not performed";
manifest.source_frame_identity = ...
    "Zero-based FFmpeg display-order frame index, mapped to preloaded PTB texture; exact per-frame PTS saved in frame_maps";
manifest.pts_origin_handling = ...
    "Source PTS from the same FFmpeg decode pass, with copyts and passthrough; scheduling uses PTS minus first PTS, logs preserve original PTS";
manifest.video_playback_backend = "ephys.FrameMoviePlayer";
if string(session.Config.playback.backend)=="native"
    manifest.video_playback_backend="ephys.NativeMoviePlayer";
    manifest.source_frame_identity= ...
        "Zero-based source index inferred only from a unique offline PTS match within 1 us; unmatched identity is NaN; sequence mismatches are reported; native texture pixels are not hashed";
    manifest.pts_origin_handling= ...
        "Lossless native copies normalized to first source PTS; display clock starts at first displayed texture Flip; logs preserve original source PTS and raw native PTS";
    manifest.media_hash_scope= ...
        "Original/native bytes hashed at preflight; offline conversion verifies source SHA before/after and every decoded YUV frame plus PTS; no disk/hash work during video playback";
    if isprop(session,'NativeTrials'), manifest.native_trials=session.NativeTrials; end
    if isprop(session,'NativePendingTrials'), manifest.native_pending_trials=session.NativePendingTrials; end
end
if isprop(session,'StartupLoading') || (isstruct(session) && isfield(session,'StartupLoading'))
    manifest.startup_loading = session.StartupLoading;
else
    manifest.startup_loading = struct('status',"not_configured");
end
maps=dir(fullfile(folder,'frame_maps','*.json'));
manifest.frame_maps=repmat(struct('path',"",'sha256',""),numel(maps),1);
for k=1:numel(maps)
    path=fullfile(maps(k).folder,maps(k).name);
    manifest.frame_maps(k).path=string(fullfile('frame_maps',maps(k).name));
    manifest.frame_maps(k).sha256=string(ephys.sha256(path));
end
manifest.eyelink_enabled = session.Config.eyelink.enabled;
manifest.eyelink_edf = session.Eye.LocalPath;
manifest.run_qc = qc.run_qc;
manifest.initial_fixation = qc.initial_fixation;
manifest.final_fixation = qc.final_fixation;
manifest.refresh_guard = ephys.refreshGuard();
if isprop(session,'RefreshGuard') || (isstruct(session) && isfield(session,'RefreshGuard'))
    manifest.refresh_guard = refreshGuardMetrics(session.RefreshGuard,flips);
end
manifestPath=fullfile(folder,[stem '_manifest.json']);
manifest.trigger_offset_report=struct('status',"pending");
% Persist the complete data before invoking MATLAB graphics or PDF export.
writeJson(manifestPath,manifest);
offsetSummary=[];
try
    offsetSummary=ephys.triggerOffsetSummary(markers,events, ...
        session.Config.markers.wav.max_sync_error_s);
    manifest.trigger_offset_report=ephys.writeTriggerOffsetReport( ...
        folder,stem,markers,events, ...
        session.Config.markers.wav.max_sync_error_s,status);
catch cause
    manifest.trigger_offset_report=struct('status',"failed",'file',"", ...
        'error_id',string(cause.identifier),'error',string(cause.message));
    warning('ephys:OffsetReport','Logs saved; offset PDF export failed: %s',cause.message);
end
try
    writeJson(manifestPath,manifest);
catch cause
    warning('ephys:OffsetReportMetadata', ...
        'Logs saved; could not update offset report metadata: %s',cause.message);
end
if ~isempty(offsetSummary), ephys.printTriggerOffsetSummary(offsetSummary); end
end

function guard = refreshGuardMetrics(guard,flips)
% The live check decides from slot indices only; add its interval metrics
% from the same baseline rows now that presentation has stopped.
if ~isfield(guard,'first_flip_seq') || ~isfinite(guard.first_flip_seq) || isempty(flips)
    return;
end
sequence = [flips.flip_seq];
rows = flips(sequence>=guard.first_flip_seq & sequence<=guard.last_flip_seq);
minimum = guard.min_fraction;
if isnan(minimum), minimum = []; end
full = ephys.refreshGuard(rows,guard.phase,guard.duration_s,guard.ifi_s,minimum);
for name = ["max_skipped_slots","interval_median_ms","timestamp_grid_deviation_median_ifi"]
    guard.(char(name)) = full.(char(name));
end
end

function writeRows(rows,template,path)
if isempty(rows), rows = repmat(template,0,1); end
writetable(struct2table(rows),path,'FileType','text','Delimiter','\t');
end

function writeJson(path,value)
fid = fopen(path,'w');
assert(fid>0,'ephys:OutputWrite','Could not open %s',path);
guard = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true));
end

function value = emptyTrialTemplate()
% Use a zero-row QC result to preserve a stable TSV header on early abort.
r = ephys.reconstructRecords(repmat(ephys.emptyFlip(),0,1), ...
    repmat(ephys.emptyEvent(),0,1),repmat(ephys.emptyMarker(),0,1));
value = r.trials;
end
