function repeatFixation(obj,ctx,phase,onsetFlip,duration)
%REPEATFIXATION Keep refresh targets on one grid for the whole static phase.
% Callers may shorten duration to protect an audio reservation window. The
% original onset and the caller's phase boundary are never moved by lateness.
    anchor = onsetFlip.stimulus_onset_getsecs;
    phaseEnd = anchor+duration;
    flipNumber = 1;
    previousIndex = 0;
    previousDiode = onsetFlip.photodiode_state;
    if obj.Log.FlipCount>0
        previous = obj.Log.lastFlip();
        if previous.trial_id == ctx.trial_id && previous.phase == string(phase)
            flipNumber = previous.phase_flip_seq;
            previousDiode = previous.photodiode_state;
            % A pre-fixation diode-off Flip may already occupy a grid slot.
            previousIndex = max(0,round((previous.stimulus_onset_getsecs-anchor)/obj.IFI));
            if isfinite(previous.refresh_index), previousIndex=previous.refresh_index; end
        end
    end
    while true
        obj.checkQuit(ctx,phase);
        obj.Triggers.poll();
        if isempty(ephys.nextFixationRefresh(anchor,phaseEnd,obj.IFI,previousIndex,GetSecs))
            return;
        end
        row = obj.fixationRefresh(ctx,phase,flipNumber+1,anchor,phaseEnd,previousIndex);
        if isempty(row), return; end
        flipNumber = flipNumber+1;
        previousIndex = row.refresh_index;
        if previousDiode == "on"
            event = obj.Log.event(ctx,"photodiode_off",phase,row.stimulus_onset_getsecs,row);
            event.photodiode_transition = "off";
            obj.Log.updateLastEvent(event);
        end
        previousDiode = row.photodiode_state;
    end
end
