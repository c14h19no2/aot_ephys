function result = reconstructRecords(flips,events,markers,inventory,config,ttl)
%RECONSTRUCTRECORDS Derive intervals/QC from observed flips, never nominal PTS.
% The optional external rows contain independently verified event identity.
% Historical numeric-code recordings remain readable; current rows use names.
if nargin < 4 || isempty(inventory), inventory = struct([]); end
if nargin < 5, config = struct(); end
if nargin < 6, ttl = []; end
flips = records(flips); events = records(events); markers = records(markers);
ttl = records(ttl);
% A trigger offset is judged against the run's own median offset, so a
% constant audio/visual lag is not an issue; only the spread around it is.
syncLimit = .002;
if isfield(config,'markers') && isfield(config.markers,'wav') && ...
        isfield(config.markers.wav,'max_sync_error_s')
    syncLimit = config.markers.wav.max_sync_error_s;
end
runMedianDelta = runMedianOffset(markers);
if ~isempty(ttl)
    assert(all(isfield(ttl,{'event_id','verified'})) && ...
        all([ttl.verified]) && (isfield(ttl,'trigger_key') || ...
        (isfield(ttl,'code') && isfield(markers,'code'))), ...
        'ephys:TTLUnverified', ...
        'External rows require verified IDs and waveform identity.');
    assert(~any(string({markers.status})=="dummy"), ...
        'ephys:TTLSoftwareOnly', ...
        'Dummy software markers cannot be matched to physical TTL events.');
end
if isempty(flips)
    result = struct('trials',repmat(emptyTrial(),0,1), ...
        'initial_fixation',ephys.runFixationSummary(flips,events,config,"initial_fixation"), ...
        'final_fixation',ephys.runFixationSummary(flips,events,config,"final_fixation"), ...
        'frames',flips,'trigger_validation',"not performed", ...
        'source_frame_identity',"unresolved", ...
        'run_qc',struct('trial_count',0,'video_trial_count',0, ...
        'memory_trial_count',0,'timing_anomaly_count',0, ...
        'incomplete_count',0,'aborted_count',0,'software_valid_count',0, ...
        'debug_unvalidated_count',0, ...
        'interval_log_mismatch_count',0, ...
        'audio_visual_median_s',runMedianDelta, ...
        'audio_sync_issue_count',0, ...
        'unmatched_external_ttl_count',0, ...
        'unexpected_ttl_order_count',0));
    return;
end
sequence = [flips.flip_seq];
assert(all(isfinite(sequence)) && ...
    numel(unique(sequence))==numel(sequence), ...
    'ephys:FlipSequence','Flip sequence numbers must be finite and unique.');
[~,order] = sort(sequence);
flips = flips(order);
intervalMismatchSeq = [];
for k = 1:numel(flips)-1
    actualEnd = flips(k+1).stimulus_onset_getsecs;
    loggedEnd = flips(k).interval_end_getsecs;
    if ~isfinite(loggedEnd) || abs(loggedEnd-actualEnd)>1e-6
        intervalMismatchSeq(end+1) = flips(k).flip_seq; %#ok<AGROW>
    end
    flips(k).interval_end_getsecs = actualEnd;
    flips(k).interval_s = actualEnd-flips(k).stimulus_onset_getsecs;
end
if isfinite(flips(end).interval_end_getsecs)
    intervalMismatchSeq(end+1) = flips(end).flip_seq;
end
flips(end).interval_end_getsecs = NaN;
flips(end).interval_s = NaN;
frames = flips(arrayfun(@(x) string(x.phase)=="video",flips));
flipIds = string({flips([flips.trial_nr]>0).trial_id});
eventIds = string({events([events.trial_nr]>0).trial_id});
markerIds = string({markers([markers.trial_nr]>0).trial_id});
trialIds = unique([flipIds,eventIds,markerIds],'stable');
trialIds(trialIds=="") = [];
trials = repmat(emptyTrial(),numel(trialIds),1);
ifi = NaN; nominal = NaN;
if isstruct(config) && isfield(config,'protocol')
    nominal = config.protocol.video_duration_s;
end
if isstruct(config) && isfield(config,'display')
    ifi = 1/config.display.expected_refresh_hz;
end
for i = 1:numel(trialIds)
    id = trialIds(i);
    f = flips(string({flips.trial_id})==id);
    e = events(string({events.trial_id})==id);
    m = markers(string({markers.trial_id})==id);
    t = emptyTrial();
    source = [];
    if ~isempty(f), source = f(1);
    elseif ~isempty(e), source = e(1);
    elseif ~isempty(m), source = m(1);
    end
    t.trial_id = id;
    t.trial_nr = source.trial_nr;
    if isfield(source,'task')
        t.task = string(source.task);
    elseif strlength(string(source.video_file))>0
        t.task = "video";
    else
        t.task = "memory";
    end
    t.video_file = string(source.video_file);
    t.picture_file = string(source.picture_file);
    t.condition = string(source.condition);
    if isfield(config,'display_timing') && ...
            isfield(config.display_timing,'missed_deadline_flag_applicable')
        t.missed_deadline_flag_applicable = ...
            config.display_timing.missed_deadline_flag_applicable;
    end
    times = [f.stimulus_onset_getsecs];
    t.timestamp_issue_count = sum(~isfinite(times)) + sum(diff(times)<=0);
    t.interval_log_mismatch_count = ...
        sum(ismember([f.flip_seq],intervalMismatchSeq));
    t.software_marker_issue = any(ismember(string({m.status}), ...
        ["failed","cancelled","cancel_failed"]));
    if isfield(m,'audio_qc_flags') && ~isempty(m)
        t.audio_qc_issue_count=sum(strlength(string({m.audio_qc_flags}))>0);
        lead=[m.audio_lead_shortfall_s]; lead=lead(isfinite(lead));
        if ~isempty(lead), t.max_audio_lead_shortfall_s=max(lead); end
        t.software_marker_issue=t.software_marker_issue || t.audio_qc_issue_count>0;
    end
    for field=["native_trials","native_pending_trials"]
        if ~isfield(config,field) || isempty(config.(field)), continue; end
        native=config.(field);
        native=native([native.trial_nr]==t.trial_nr);
        for nativeIndex=1:numel(native)
            row=native(nativeIndex);
            if isfield(row,'qc_issues')
                t.native_qc_issue_count=t.native_qc_issue_count+numel(row.qc_issues);
            end
            if isfield(row,'preparation_overrun_s')
                t.preparation_overrun_s=max(t.preparation_overrun_s,row.preparation_overrun_s);
            end
        end
    end
    % The marker's sync_status is relative to zero offset; only its failure
    % states count here. Offsets count when they leave run median +/- limit.
    if isfield(m,'sync_status')
        syncIssue=ismember(string({m.sync_status}), ...
            ["failed","late","missing_timestamp"]);
    else
        syncIssue=false(1,numel(m));
    end
    if isfield(m,'audio_visual_delta_s') && ~isempty(m)
        delta=[m.audio_visual_delta_s]; finite=isfinite(delta);
        if any(finite), t.max_abs_audio_visual_delta_s=max(abs(delta(finite))); end
        observed=finite & ismember(string({m.status}),["complete","failed"]);
        if any(observed) && isfinite(runMedianDelta)
            deviation=abs(delta-runMedianDelta);
            t.max_abs_delta_from_run_median_s=max(deviation(observed));
            syncIssue=syncIssue | (observed & deviation>syncLimit);
        end
    end
    t.audio_sync_issue_count=sum(syncIssue);
    t.software_marker_issue=t.software_marker_issue || t.audio_sync_issue_count>0;
    if t.task == "video"
        vf = f(string({f.phase})=="video");
        t.blank = t.video_file == "blank";
        t.observed_video_refreshes = numel(vf);
        if isfield(vf,'frame_qc_flags') && ~isempty(vf)
            t.frame_qc_issue_count=sum(strlength(string({vf.frame_qc_flags}))>0);
        end
        if t.blank
            bf = f(string({f.phase})=="blank");
            t.observed_blank_refreshes = numel(bf);
            if isfinite(nominal) && isfinite(ifi)
                t.expected_blank_refreshes = round(nominal/ifi);
                t.refresh_count_anomaly = ...
                    abs(t.observed_blank_refreshes-t.expected_blank_refreshes)>1;
            end
            blankOn = e(string({e.event_type})=="blank_onset");
            blankOff = e(string({e.event_type})=="blank_offset");
            t.incomplete = numel(blankOn)~=1 || numel(blankOff)~=1;
            if numel(blankOn)==1
                if ~isempty(bf)
                    t.blank_onset_getsecs = bf(1).stimulus_onset_getsecs;
                end
            end
            if numel(blankOff)==1
                if ~isempty(bf)
                    t.blank_offset_getsecs = bf(end).interval_end_getsecs;
                    t.transition_log_mismatch_s = ...
                        blankOff.onset_getsecs-t.blank_offset_getsecs;
                end
            end
            t.incomplete = t.incomplete || ...
                ~isfinite(t.blank_onset_getsecs) || ...
                ~isfinite(t.blank_offset_getsecs);
            t.missed_deadline_count = sum([f.missed_s]>0);
            if numel(bf)>1
                delta = diff([bf.stimulus_onset_getsecs]);
                t.interflip_median_s = median(delta);
                t.interflip_max_s = max(delta);
            end
        end
        if ~t.blank && ~isempty(vf)
            t.video_onset_getsecs = vf(1).stimulus_onset_getsecs;
            t.first_frame_sequence = vf(1).decoded_frame_sequence;
            t.first_frame_pts_s = vf(1).source_pts_s;
            t.missed_deadline_count = sum([f.missed_s]>0);
            t.decoder_underrun_count = sum(string({vf.frame_status})=="decoder_underrun");
            t.pts_gap_count = sum(string({vf.frame_status})=="pts_gap");
            t.duplicate_pts_delivery_count = ...
                sum(string({vf.frame_status})=="duplicate_pts_delivery");
            t.pts_regression_count = sum(string({vf.frame_status})=="pts_regression");
            t.missing_pts_count = sum(~isfinite([vf.source_pts_s]));
            t.early_end_count = sum(string({vf.frame_status})=="end_of_stream");
            if numel(vf)>1
                delta = diff([vf.stimulus_onset_getsecs]);
                t.interflip_median_s = median(delta);
                t.interflip_max_s = max(delta);
            end
            onsetEvent = e(string({e.event_type})=="video_onset");
            offsetEvent = e(string({e.event_type})=="video_offset");
            t.incomplete = numel(onsetEvent)~=1 || numel(offsetEvent)~=1;
            if numel(onsetEvent)==1
                t.planned_onset_getsecs = onsetEvent.planned_onset_getsecs;
                t.planned_offset_getsecs = onsetEvent.planned_deadline_getsecs;
                t.onset_transition_error_s = ...
                    t.video_onset_getsecs-t.planned_onset_getsecs;
            end
            if numel(offsetEvent)==1
                t.video_offset_getsecs = vf(end).interval_end_getsecs;
                t.transition_log_mismatch_s = ...
                    offsetEvent.onset_getsecs-t.video_offset_getsecs;
                t.actual_video_duration_s = ...
                    t.video_offset_getsecs-t.video_onset_getsecs;
                t.offset_transition_error_s = ...
                    t.video_offset_getsecs-t.planned_offset_getsecs;
            end
            t.incomplete = t.incomplete || ...
                ~isfinite(t.video_offset_getsecs);
            media = struct([]);
            if ~isempty(inventory)
                media = inventory(string({inventory.name})==t.video_file);
            end
            fps = NaN;
            if numel(media)==1, fps = media.fps; end
            t.first_frame_anomaly = ~isequal(vf(1).decoded_frame_sequence,1) || ...
                ~isfinite(vf(1).source_pts_s);
            if isfinite(vf(1).source_frame_index)
                t.first_frame_anomaly=t.first_frame_anomaly || vf(1).source_frame_index~=0;
            else
                t.first_frame_anomaly=t.first_frame_anomaly || ...
                    (isfinite(fps) && vf(1).source_pts_s>max(0.05,1/fps));
            end
            if isfinite(ifi) && isfinite(t.onset_transition_error_s)
                t.first_frame_anomaly = t.first_frame_anomaly || ...
                    t.onset_transition_error_s > ifi;
            end
            seq = [vf.decoded_frame_sequence];
            pts = [vf.source_pts_s];
            validSeq = seq(isfinite(seq));
            t.decoded_deliveries_observed = numel(unique(validSeq));
            t.presented_source_pts_count = numel(unique(pts(isfinite(pts))));
            if isfinite(ifi) && isfinite(fps) && fps>0
                normalRefreshes = ceil((1/ifi)/fps);
                distinct = unique(pts(isfinite(pts)),'stable');
                for j = 1:numel(distinct)
                    allowed=normalRefreshes;
                    if numel(media)==1 && isfield(media,'source_pts_s') && ...
                            ~isempty(media.source_pts_s)
                        sourcePTS=media.source_pts_s(:);
                        index=find(abs(sourcePTS-distinct(j))<1e-9,1);
                        if ~isempty(index)
                            if index<numel(sourcePTS)
                                interval=sourcePTS(index+1)-sourcePTS(index);
                            else
                                interval=media.duration_s-(sourcePTS(end)-sourcePTS(1));
                            end
                            allowed=ceil(interval/ifi-1e-9);
                        end
                    end
                    if sum(abs(pts-distinct(j))<=1e-6) > allowed
                        t.unexpected_repeat_count = t.unexpected_repeat_count+1;
                    end
                end
            else
                t.unexpected_repeat_count = NaN;
            end
            if isfinite(nominal) && isfinite(ifi)
                t.expected_video_refreshes = round(nominal/ifi);
                t.refresh_count_anomaly = ...
                    abs(t.observed_video_refreshes-t.expected_video_refreshes)>1;
            end
            t.unresolved_source_frame_count = sum(~isfinite([vf.source_frame_index]));
            if t.unresolved_source_frame_count==0
                t.source_skip_count=sum(max(0,diff([vf.source_frame_index])-1));
            end
        elseif ~t.blank
            t.incomplete = true;
        end
        onsetMarkers = m(string({m.event_type})=="video_onset");
        offsetMarkers = m(string({m.event_type})=="video_offset");
        if t.blank
            blankOnMarkers=m(string({m.event_type})=="blank_onset");
            blankOffMarkers=m(string({m.event_type})=="blank_offset");
            t.software_marker_issue = t.software_marker_issue || ...
                ~isempty(onsetMarkers)||~isempty(offsetMarkers);
            blankEnabled=isfield(config,'markers') && ...
                isfield(config.markers,'blank_enabled') && config.markers.blank_enabled;
            if blankEnabled
                t.software_marker_issue=t.software_marker_issue || numel(blankOnMarkers)~=1;
                if numel(blankOnMarkers)==1
                    t.blank_onset_marker_id=blankOnMarkers.event_id;
                    t.software_marker_issue=t.software_marker_issue || ...
                        blankOnMarkers.associated_flip_getsecs~=t.blank_onset_getsecs;
                end
                if config.markers.video_offset_enabled && ~t.incomplete
                    t.software_marker_issue=t.software_marker_issue || numel(blankOffMarkers)~=1;
                    if numel(blankOffMarkers)==1
                        t.blank_offset_marker_id=blankOffMarkers.event_id;
                        t.software_marker_issue=t.software_marker_issue || ...
                            blankOffMarkers.associated_flip_getsecs~=t.blank_offset_getsecs;
                    end
                end
            else
                t.software_marker_issue=t.software_marker_issue || ...
                    ~isempty(blankOnMarkers)||~isempty(blankOffMarkers);
            end
        else
            t.software_marker_issue = t.software_marker_issue || ...
                numel(onsetMarkers)~=1;
            if numel(onsetMarkers)==1 && ~isempty(vf)
                t.video_onset_marker_id = onsetMarkers.event_id;
                t.onset_marker_request_lag_s = ...
                    onsetMarkers.request_getsecs-t.video_onset_getsecs;
                t.onset_marker_write_latency_s = ...
                    onsetMarkers.write_getsecs-onsetMarkers.request_getsecs;
                t.software_marker_issue = t.software_marker_issue || ...
                    onsetMarkers.associated_flip_seq~=vf(1).flip_seq;
            end
            if numel(offsetMarkers)==1
                t.video_offset_marker_id = offsetMarkers.event_id;
                t.offset_marker_request_lag_s = ...
                    offsetMarkers.request_getsecs-t.video_offset_getsecs;
                t.offset_marker_write_latency_s = ...
                    offsetMarkers.write_getsecs-offsetMarkers.request_getsecs;
                if isfinite(t.video_offset_getsecs)
                    t.software_marker_issue = t.software_marker_issue || ...
                        offsetMarkers.associated_flip_getsecs~=t.video_offset_getsecs;
                end
            elseif isfield(config,'markers') && config.markers.video_offset_enabled && ...
                    ~t.incomplete
                t.software_marker_issue = true;
            end
        end
    elseif t.task == "memory"
        pictureFlips = f(string({f.phase})=="picture");
        onset = e(string({e.event_type})=="memory_stimulus_onset");
        response = e(string({e.event_type})=="memory_response");
        t.incomplete = numel(pictureFlips)~=1 || ...
            numel(onset)~=1 || numel(response)~=1;
        if numel(pictureFlips)==1
            t.memory_onset_getsecs = pictureFlips.stimulus_onset_getsecs;
            t.incomplete = t.incomplete || ...
                ~isfinite(pictureFlips.interval_end_getsecs);
        end
        if numel(response)==1
            t.memory_response_getsecs = response.input_getsecs;
            t.memory_rt_s = response.rt_s;
            responseMarkers = m(string({m.event_type})=="memory_response");
            t.software_marker_issue = t.software_marker_issue || ...
                numel(responseMarkers)~=1;
            if numel(responseMarkers)==1
                t.memory_response_marker_id = responseMarkers.event_id;
                t.response_marker_request_lag_s = ...
                    responseMarkers.request_getsecs-t.memory_response_getsecs;
                t.response_marker_write_latency_s = ...
                    responseMarkers.write_getsecs-responseMarkers.request_getsecs;
                t.software_marker_issue = t.software_marker_issue || ...
                    responseMarkers.input_getsecs~=response.input_getsecs;
            end
        end
        onsetMarkers=m(string({m.event_type})=="memory_stimulus_onset");
        onsetEnabled=isfield(config,'markers') && ...
            isfield(config.markers,'memory_onset_enabled') && config.markers.memory_onset_enabled;
        if onsetEnabled
            t.software_marker_issue=t.software_marker_issue || numel(onsetMarkers)~=1;
            if numel(onsetMarkers)==1 && numel(pictureFlips)==1
                t.memory_onset_marker_id=onsetMarkers.event_id;
                t.software_marker_issue=t.software_marker_issue || ...
                    onsetMarkers.associated_flip_seq~=pictureFlips.flip_seq || ...
                    onsetMarkers.associated_flip_getsecs~=t.memory_onset_getsecs;
            end
        else
            t.software_marker_issue=t.software_marker_issue || ~isempty(onsetMarkers);
        end
    end
    t.aborted = any(string({e.event_type})=="trial_abort");
    t.incomplete = t.incomplete || t.aborted;
    if isempty(ttl)
        t.ttl_match_status = "hardware_unverified";
    else
        physicalMarkers=m(~ismember(string({m.status}),["cancelled","failed"]));
        ids = string({physicalMarkers.event_id});
        ids(ids=="") = [];
        matchCounts = arrayfun(@(x) sum(string({ttl.event_id})==x),ids);
        if isempty(ids)
            t.ttl_match_status = "no_ttl_expected";
        elseif any(matchCounts==0) && any(matchCounts>1)
            t.ttl_match_status = "missing_and_duplicate";
        elseif any(matchCounts==0), t.ttl_match_status = "missing";
        elseif any(matchCounts>1), t.ttl_match_status = "duplicate";
        else
            t.ttl_match_status = "matched_by_verified_id";
            for j = 1:numel(physicalMarkers)
                match = ttl(string({ttl.event_id})==string(physicalMarkers(j).event_id));
                if numel(match)==1 && ~sameTrigger(match,physicalMarkers(j))
                    t.ttl_match_status = "trigger_identity_mismatch";
                end
            end
        end
    end
    if t.aborted, t.quality_state = "aborted_trial";
    elseif t.incomplete || t.early_end_count>0
        t.quality_state = "incomplete_playback";
    elseif t.software_marker_issue || t.first_frame_anomaly || ...
            t.refresh_count_anomaly || t.interval_log_mismatch_count>0 || ...
            (isfinite(t.transition_log_mismatch_s) && ...
                abs(t.transition_log_mismatch_s)>1e-6) || ...
            t.timestamp_issue_count>0 || ...
            (t.missed_deadline_flag_applicable && t.missed_deadline_count>0) || ...
            t.unexpected_repeat_count>0 || ...
            t.pts_gap_count>0 || t.pts_regression_count>0 || ...
            t.duplicate_pts_delivery_count>0 || t.missing_pts_count>0 || ...
            t.decoder_underrun_count>0 || t.source_skip_count>0 || ...
            t.frame_qc_issue_count>0 || t.native_qc_issue_count>0 || ...
            t.preparation_overrun_s>0 || ...
            any(t.ttl_match_status==["missing","duplicate","code_mismatch","trigger_identity_mismatch", ...
                "missing_and_duplicate"])
        t.quality_state = "timing_anomaly_detected";
    elseif isstruct(config) && isfield(config,'debug') && ...
            config.debug && isfield(config,'display') && ...
            config.display.skip_sync_tests
        t.quality_state = "debug_timing_unvalidated";
    else
        t.quality_state = "software_checks_valid_hardware_unverified";
    end
    trials(i) = t;
end
result = struct('trials',trials,'frames',frames, ...
    'initial_fixation',ephys.runFixationSummary(flips,events,config,"initial_fixation"), ...
    'final_fixation',ephys.runFixationSummary(flips,events,config,"final_fixation"), ...
    'trigger_validation',"not performed unless independently verified event correspondence is provided", ...
    'source_frame_identity',"unresolved unless validated offline map provided");
debugUnvalidated = isstruct(config) && isfield(config,'debug') && ...
    config.debug && isfield(config,'display') && ...
    config.display.skip_sync_tests;
result.run_qc = struct('trial_count',numel(trials), ...
    'video_trial_count',sum(string({trials.task})=="video"), ...
    'memory_trial_count',sum(string({trials.task})=="memory"), ...
    'timing_anomaly_count',sum(string({trials.quality_state})=="timing_anomaly_detected"), ...
    'incomplete_count',sum(string({trials.quality_state})=="incomplete_playback"), ...
    'aborted_count',sum(string({trials.quality_state})=="aborted_trial"), ...
    'software_valid_count',sum(string({trials.quality_state})== ...
        "software_checks_valid_hardware_unverified"), ...
    'debug_unvalidated_count',numel(trials)*double(debugUnvalidated), ...
    'audio_qc_issue_count',sum([trials.audio_qc_issue_count]), ...
    'native_qc_issue_count',sum([trials.native_qc_issue_count]), ...
    'preparation_overrun_count',sum([trials.preparation_overrun_s]>0), ...
    'interval_log_mismatch_count',sum([trials.interval_log_mismatch_count]), ...
    'audio_visual_median_s',runMedianDelta, ...
    'audio_sync_issue_count',sum([trials.audio_sync_issue_count]), ...
    'unmatched_external_ttl_count',0, ...
    'unexpected_ttl_order_count',0);
if ~isempty(ttl)
    emitted=markers(~ismember(string({markers.status}),["cancelled","failed"]));
    result.run_qc.unmatched_external_ttl_count = ...
        sum(~ismember(string({ttl.event_id}),string({emitted.event_id})));
    if isfield(ttl,'ephys_time_s') && ~isempty(markers)
        [~,order] = sort([emitted.marker_nr]);
        ordered = emitted(order);
        matchedTimes = nan(1,numel(ordered));
        for j = 1:numel(ordered)
            match = ttl(string({ttl.event_id})==string(ordered(j).event_id));
            if numel(match)==1, matchedTimes(j) = match.ephys_time_s; end
        end
        adjacent = isfinite(matchedTimes(1:end-1)) & ...
            isfinite(matchedTimes(2:end));
        result.run_qc.unexpected_ttl_order_count = ...
            sum(diff(matchedTimes)<=0 & adjacent);
    end
end
end

function value = records(value)
if istable(value), value = table2struct(value); end
if isempty(value) && ~isstruct(value), value = struct([]); end
value = value(:);
end

function value = runMedianOffset(markers)
% Median over all observed audio/Flip pairs of the run, including run
% boundaries; the same rows as the trigger offset summary. NaN if none.
value = NaN;
if isempty(markers) || ~all(isfield(markers,{'status','audio_visual_delta_s'}))
    return;
end
delta = [markers.audio_visual_delta_s];
observed = ismember(string({markers.status}),["complete","failed"]) & ...
    isfinite(delta);
if any(observed), value = median(delta(observed)); end
end

function t = emptyTrial()
t = struct('trial_id',"",'trial_nr',NaN,'task',"", ...
    'video_file',"",'picture_file',"",'condition',"",'blank',false, ...
    'blank_onset_getsecs',NaN,'blank_offset_getsecs',NaN, ...
    'expected_blank_refreshes',NaN,'observed_blank_refreshes',0, ...
    'video_onset_getsecs',NaN,'video_offset_getsecs',NaN, ...
    'planned_onset_getsecs',NaN,'planned_offset_getsecs',NaN, ...
    'onset_transition_error_s',NaN,'offset_transition_error_s',NaN, ...
    'actual_video_duration_s',NaN,'expected_video_refreshes',NaN, ...
    'observed_video_refreshes',0,'refresh_count_anomaly',false, ...
    'interval_log_mismatch_count',0,'transition_log_mismatch_s',NaN, ...
    'decoded_deliveries_observed',0,'presented_source_pts_count',0, ...
    'interflip_median_s',NaN,'interflip_max_s',NaN, ...
    'missed_deadline_count',0,'missed_deadline_flag_applicable',true, ...
    'timestamp_issue_count',0,'unexpected_repeat_count',0, ...
    'pts_gap_count',0,'pts_regression_count',0, ...
    'duplicate_pts_delivery_count',0,'missing_pts_count',0, ...
    'decoder_underrun_count',0,'early_end_count',0, ...
    'frame_qc_issue_count',0,'native_qc_issue_count',0,'preparation_overrun_s',0, ...
    'first_frame_sequence',NaN,'first_frame_pts_s',NaN, ...
    'first_frame_anomaly',false,'unresolved_source_frame_count',0, ...
    'source_skip_count',NaN,'incomplete',false,'aborted',false, ...
    'video_onset_marker_id',"",'video_offset_marker_id',"", ...
    'blank_onset_marker_id',"",'blank_offset_marker_id',"", ...
    'onset_marker_request_lag_s',NaN, ...
    'onset_marker_write_latency_s',NaN, ...
    'offset_marker_request_lag_s',NaN, ...
    'offset_marker_write_latency_s',NaN, ...
    'memory_onset_getsecs',NaN,'memory_response_getsecs',NaN, ...
    'memory_rt_s',NaN,'memory_response_marker_id',"",'memory_onset_marker_id',"", ...
    'response_marker_request_lag_s',NaN, ...
    'response_marker_write_latency_s',NaN, ...
    'audio_sync_issue_count',0,'max_abs_audio_visual_delta_s',NaN, ...
    'max_abs_delta_from_run_median_s',NaN, ...
    'audio_qc_issue_count',0,'max_audio_lead_shortfall_s',NaN, ...
    'software_marker_issue',false,'ttl_match_status',"", ...
    'quality_state',"");
end

function equal=sameTrigger(external,marker)
% Compare current waveform names, or numeric codes in historical records.
if isfield(marker,'trigger_key') && isfield(external,'trigger_key') && ...
        strlength(string(marker.trigger_key))>0
    equal=string(marker.trigger_key)==string(external.trigger_key);
    if isfield(external,'waveform_file') && isfield(marker,'waveform_file')
        equal=equal && string(marker.waveform_file)==string(external.waveform_file);
    end
elseif isfield(marker,'code') && isfield(external,'code')
    equal=marker.code==external.code;
else
    equal=false;
end
end
