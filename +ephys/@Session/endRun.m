function endRun(obj,status)
%ENDRUN Handle exactly one run-end attempt for normal completion or abort.
    if ~obj.RunStarted || obj.RunEndHandled
        return;
    end
    if ~obj.Config.markers.run_boundary_enabled
        obj.RunEndHandled = true;
        return;
    end
    % This flag prevents a second attempt during cleanup; it does not
    % assert that the waveform has already reached the audio output.
    obj.RunEndHandled = true;
    endFlip = [];
    marker = [];
    if strlength(obj.RunEndMarkerId)>0
        markers = obj.Triggers.records();
        matches = string({markers.event_id}) == obj.RunEndMarkerId;
        if any(matches)
            priorMarker = markers(matches);
            if priorMarker.status ~= "cancelled"
                marker = priorMarker;
                if string(status) == "complete"
                    endFlip = obj.RunEndFlip;
                end
            end
        end
    end
    if isempty(marker) && string(status) == "complete" && ~obj.PresentationStopped
        [endFlip,marker] = obj.onsetFlip(obj.RunContext,"run_end","run_end",NaN);
        obj.RunEndFlip = endFlip;
        marker = obj.Triggers.associate(marker.event_id,obj.markerFlip(endFlip));
    elseif isempty(marker)
        % Abort markers have no invented visual association. Finish any
        % already-started short pulse before emitting the end waveform.
        audioReadyTime = obj.Triggers.nextAllowedRequestTime();
        assert(~isfinite(audioReadyTime) || audioReadyTime-GetSecs <= obj.Config.markers.wav.completion_timeout_s, ...
            'ephys:TriggerPending','A future audio reservation could not be cancelled before abort cleanup.');
        if isfinite(audioReadyTime)
            WaitSecs('UntilTime',audioReadyTime);
        end
        marker = obj.Triggers.emit("run_end",obj.RunContext,[], ...
            obj.QuitInputTime,"");
        obj.RunEndMarkerId = marker.event_id;
    end
    if ~isempty(endFlip)
        eventTime = endFlip.stimulus_onset_getsecs;
    elseif isfinite(marker.audio_start_getsecs)
        eventTime = marker.audio_start_getsecs;
    elseif isfinite(obj.QuitInputTime)
        eventTime = obj.QuitInputTime;
    else
        eventTime = GetSecs;
    end
    event = obj.Log.event(obj.RunContext,"run_end","run_end",eventTime,endFlip);
    event.input_getsecs = obj.QuitInputTime;
    event.marker_event_id = marker.event_id;
    event.status = string(status);
    obj.Log.updateLastEvent(event);
end
