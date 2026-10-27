function videoTrial(obj,trialNr,movieName,preparedContext)
%VIDEOTRIAL Present pre-fixation, movie/blank, and post-fixation in order.
    if isempty(preparedContext)
        context = obj.TrialContexts{trialNr};
        obj.prepareVideo(context,movieName);
    else
        context = preparedContext;
    end
    obj.CurrentContext = context;
    config = obj.Config;
    isBlank = movieName == "blank";
    preFixationDuration = config.protocol.video_pre_fixation_s;
    plannedVideoOnset = NaN;
    % Pre-fixation: finish lookahead and reference Flips before drawing onset.
    if preFixationDuration > 0
        preFixationFlip = obj.fixationFlip(context,"pre_fixation",1,obj.NextTrialOnset, ...
            obj.fixationDiode(1));
        marker = [];
        if config.markers.fixation_onset_enabled
            marker = obj.Triggers.emit("fixation_onset",context, ...
                obj.markerFlip(preFixationFlip),NaN,"");
        end
        event = obj.Log.event(context,"pre_fixation_onset", ...
            "pre_fixation",preFixationFlip.stimulus_onset_getsecs,preFixationFlip);
        event.planned_onset_getsecs = obj.NextTrialOnset;
        if config.photodiode.enabled && config.photodiode.fixation_onset_enabled
            event.photodiode_transition = "on";
        end
        if ~isempty(marker)
            event.marker_event_id = marker.event_id;
        end
        obj.Log.updateLastEvent(event);
        plannedVideoOnset = preFixationFlip.stimulus_onset_getsecs+preFixationDuration;
        if preFixationFlip.photodiode_state == "on"
            % End the fixation pulse before preparing/drawing the video. The
            % ordinary path now holds fixation instead of refreshing it.
            offFlip = obj.fixationFlip(context,"pre_fixation",2,NaN,"off");
            event = obj.Log.event(context,"photodiode_off","pre_fixation", ...
                offFlip.stimulus_onset_getsecs,offFlip);
            event.photodiode_transition = "off";
            obj.Log.updateLastEvent(event);
        end
        % Finish blocking preparation before the audio reservation
        % deadline, leaving additional time for drawing the first frame.
        obj.prepareAhead(context,plannedVideoOnset-config.markers.wav.minimum_lead_s-2*obj.IFI);
        if obj.usesDeferredOnset() && ~obj.usesSteadyFlip()
            % Renew the macOS external sink's refresh anchor before drawing.
            audioLead = config.markers.wav.minimum_lead_s+2*obj.IFI;
            obj.repeatFixation(context,"pre_fixation",preFixationFlip, ...
                max(0,preFixationDuration-audioLead));
        end
        % Ordinary backends reserve as soon as drawing/preparation permits;
        % do not burn the available lead in a nominal-refresh waiting loop.
    end
    % Default: draw source frame zero (or blank) before reserving the common
    % onset. The remaining pre-fixation holds the front buffer; no reference
    % Flip or drawing command separates the WAV reservation from the prepared
    % Flip. display.steady_flip instead refreshes fixation every frame up to
    % the onset slot (steadyOnsetFlip).
    obj.checkQuit(context,"pre_fixation_end");
    eventType = "video_onset";
    phase = "video";
    if isBlank
        phase = "blank";
        eventType = "blank_onset";
        if ~config.markers.blank_enabled, eventType = ""; end
    end
    if obj.usesSteadyFlip() && preFixationDuration > 0
        [onsetFlip,onsetMarker,plannedVideoOnset] = obj.steadyOnsetFlip( ...
            context,"pre_fixation",preFixationFlip,phase,eventType,plannedVideoOnset);
    else
        [onsetFlip,onsetMarker,plannedVideoOnset] = obj.onsetFlip( ...
            context,phase,eventType,plannedVideoOnset);
    end
    if isBlank
        event = obj.Log.event(context,"blank_onset","blank", ...
            onsetFlip.stimulus_onset_getsecs,onsetFlip);
        if ~isempty(onsetMarker)
            event.marker_event_id = onsetMarker.event_id;
        end
        event.planned_onset_getsecs = plannedVideoOnset;
        obj.Log.updateLastEvent(event);
    else
        obj.Player.start(onsetFlip.stimulus_onset_getsecs);
        event = obj.Log.event(context,"video_onset","video", ...
            onsetFlip.stimulus_onset_getsecs,onsetFlip);
        event.planned_onset_getsecs = plannedVideoOnset;
        event.planned_deadline_getsecs = ...
            onsetFlip.stimulus_onset_getsecs+config.protocol.video_duration_s;
        if config.photodiode.enabled
            event.photodiode_transition = "on";
        end
        event.marker_event_id = onsetMarker.event_id;
        obj.Log.updateLastEvent(event);
        playbackEvent = obj.Log.event(context,"playback_command","video", ...
            obj.Player.StartCommandTime,[]);
        playbackEvent.detail = "Display scheduling anchored to first displayed texture Flip; start completed at " + ...
            string(obj.Player.StartCommandCompletedTime);
        obj.Log.updateLastEvent(playbackEvent);
    end
    if ~isempty(onsetMarker)
        obj.Triggers.associate(onsetMarker.event_id,obj.markerFlip(onsetFlip));
    end
    % A synchronous scheduled Flip retains queued Q input until it returns.
    obj.checkQuit(context,phase);
    % Offset removes the last frame; post-fixation starts at that actual Flip.
    offsetMarker = [];
    plannedVideoOffset = onsetFlip.stimulus_onset_getsecs+config.protocol.video_duration_s;
    if config.markers.video_offset_enabled && (~isBlank || config.markers.blank_enabled)
        eventType = "video_offset";
        if isBlank
            eventType = "blank_offset";
        end
        [offsetMarker,plannedVideoOffset] = obj.reserveMarker(eventType,context,plannedVideoOffset);
    end
    if isBlank
        obj.repeatFixation(context,"blank",onsetFlip,config.protocol.video_duration_s);
    else
        obj.repeatVideo(context,onsetFlip,config.protocol.video_duration_s);
    end
    % This flip removes the final movie frame; its timestamp defines offset.
    offsetFlip = obj.fixationFlip(context,"post_fixation",1,plannedVideoOffset,"off");
    if ~isBlank
        event = obj.Log.event(context,"video_offset","post_fixation", ...
            offsetFlip.stimulus_onset_getsecs,offsetFlip);
        event.planned_onset_getsecs = plannedVideoOffset;
        if config.photodiode.enabled
            event.photodiode_transition = "off";
        end
        if ~isempty(offsetMarker)
            event.marker_event_id = offsetMarker.event_id;
        end
        obj.Log.updateLastEvent(event);
        obj.Player.stop();
        if string(config.playback.backend) == "native"
            value = obj.MovieCache.release(trialNr);
            value.trial_nr = trialNr;
            obj.NativeTrials = [obj.NativeTrials;value];
        end
    else
        event = obj.Log.event(context,"blank_offset","post_fixation", ...
            offsetFlip.stimulus_onset_getsecs,offsetFlip);
        if ~isempty(offsetMarker)
            event.marker_event_id = offsetMarker.event_id;
            obj.Log.updateLastEvent(event);
        end
    end
    if ~isempty(offsetMarker)
        obj.Triggers.associate(offsetMarker.event_id,obj.markerFlip(offsetFlip));
    end
    obj.repeatFixation(context,"post_fixation",offsetFlip, ...
        config.protocol.video_post_fixation_s);
    obj.NextTrialOnset = offsetFlip.stimulus_onset_getsecs+config.protocol.video_post_fixation_s;
    % The next independently prepared native occurrence remains open.
end
