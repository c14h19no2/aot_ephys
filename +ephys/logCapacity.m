function [flips,events,markers] = logCapacity(config)
%LOGCAPACITY Preflight bounded buffers from the selected schedule/protocol.
n = numel(config.schedule);
if config.task_kind == "video"
    seconds = config.protocol.video_pre_fixation_s + ...
        config.protocol.video_duration_s + ...
        config.protocol.video_post_fixation_s;
    baselineFlips = 0;
    baselineEvents = 0;
    for duration = [config.protocol.video_initial_fixation_s, ...
            config.protocol.video_final_fixation_s]
        if duration>0
            baselineFlips = baselineFlips + ...
                ceil(duration*config.display.expected_refresh_hz)+2;
            baselineEvents = baselineEvents+3; % onset, offset, or abort.
        end
    end
    preloadCount=0;
    if isfield(config.playback,'startup_preload_movies')
        preloadCount=min(config.playback.startup_preload_movies, ...
            numel(unique(config.schedule(config.schedule~="blank"))));
    end
    % Loading UI is capped at eleven progress flips per movie, plus entry.
    expectedFlips = n*(ceil(seconds*config.display.expected_refresh_hz)+4)+1+baselineFlips+11*preloadCount+1;
    expectedEvents = 11*n+2+baselineEvents+2*preloadCount+3;
    onsetCount=sum(config.schedule~="blank") + ...
        double(config.markers.blank_enabled)*sum(config.schedule=="blank");
    expectedMarkers = onsetCount*(1+double(config.markers.video_offset_enabled)) + ...
        n*double(config.markers.fixation_onset_enabled);
else
    expectedFlips = 2*n+1;
    expectedEvents = 4*n+2;
    expectedMarkers = n*(1+double(config.markers.memory_onset_enabled));
end
expectedMarkers=expectedMarkers+2*double(config.markers.run_boundary_enabled);
expectedEvents=expectedEvents+2*double(config.markers.run_boundary_enabled);
expectedFlips=expectedFlips+double(config.markers.run_boundary_enabled);
flips = expectedFlips + max(1000,ceil(expectedFlips*0.5));
events = expectedEvents + max(100,ceil(expectedEvents*0.5));
markers = expectedMarkers + max(100,ceil(expectedMarkers*0.5));
assert(flips<=config.logging.max_flips && ...
    events<=config.logging.max_events && ...
    markers<=config.logging.max_markers, ...
    'ephys:LogCapacity', ...
    'Configured log ceilings cannot hold the planned run plus safety margin.');
end
