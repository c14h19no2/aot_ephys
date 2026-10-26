function value = runFixationSummary(flips,events,config,phase)
%RUNFIXATIONSUMMARY Reconstruct an initial/final baseline from boundary flips.
setting = "video_"+phase+"_s";
value = struct('configured_duration_s',NaN,'status',"not_configured", ...
    'onset_getsecs',NaN,'offset_getsecs',NaN, ...
    'observed_duration_s',NaN,'planned_offset_getsecs',NaN, ...
    'offset_error_s',NaN,'flip_count',0,'aborted',false, ...
    'timestamp_issue_count',0);
if isfield(config,'task_kind') && string(config.task_kind)=="memory"
    value.status = "not_applicable";
    return;
end
if isfield(config,'protocol') && ...
        isfield(config.protocol,setting)
    value.configured_duration_s = config.protocol.(setting);
    value.status = "not_started";
    if value.configured_duration_s==0, value.status = "disabled"; end
end
bf = struct([]); boundary = struct([]);
on = struct([]); off = struct([]); abort = struct([]);
if ~isempty(flips)
    bf = flips(string({flips.phase})==phase);
    boundary = flips(string({flips.phase})==phase+"_end");
end
if ~isempty(events)
    on = events(string({events.event_type})==phase+"_onset");
    off = events(string({events.event_type})==phase+"_offset");
    abort = events(string({events.event_type})==phase+"_abort");
end
value.flip_count = numel(bf);
value.aborted = ~isempty(abort);
if isempty(bf)
    if value.aborted, value.status = "aborted"; end
    return;
end
value.status = "incomplete";
if value.aborted, value.status = "aborted"; end
times = [bf.stimulus_onset_getsecs];
value.onset_getsecs = times(1);
value.timestamp_issue_count = sum(~isfinite(times)) + sum(diff(times)<=0);
if numel(on)==1
    value.planned_offset_getsecs = on.planned_deadline_getsecs;
    value.timestamp_issue_count = value.timestamp_issue_count + ...
        ~isequal(on.associated_flip_seq,bf(1).flip_seq) + ...
        ~isequal(on.onset_getsecs,value.onset_getsecs);
else
    value.timestamp_issue_count = value.timestamp_issue_count+1;
end
if numel(boundary)==1 && numel(off)==1
    value.offset_getsecs = boundary.stimulus_onset_getsecs;
    value.observed_duration_s = value.offset_getsecs-value.onset_getsecs;
    value.offset_error_s = value.offset_getsecs-value.planned_offset_getsecs;
    value.timestamp_issue_count = value.timestamp_issue_count + ...
        ~isequal(off.associated_flip_seq,boundary.flip_seq) + ...
        ~isequal(off.onset_getsecs,value.offset_getsecs) + ...
        ~isfinite(value.offset_getsecs) + ...
        (value.offset_getsecs<=times(end));
    if value.timestamp_issue_count==0 && ~value.aborted
        value.status = "complete";
    end
end
end
