function runFixation(obj,phase,duration)
%RUNFIXATION Present an initial/final baseline with explicit onset and offset Flips.
    ctx = ephys.context("video",0,"");
    obj.CurrentContext = ctx;
    obj.CurrentRunPhase = phase;
    plannedBaselineOnset = NaN;
    if phase == "final_fixation"
        plannedBaselineOnset = obj.NextTrialOnset;
    end
    if phase == "initial_fixation"
        plannedBaselineOnset = obj.NextTrialOnset;
    end
    onsetFlip = obj.fixationFlip(ctx,phase,1,plannedBaselineOnset,"off");
    plannedBaselineOffset = onsetFlip.stimulus_onset_getsecs+duration;
    event = obj.Log.event(ctx,phase+"_onset", ...
        phase,onsetFlip.stimulus_onset_getsecs,onsetFlip);
    event.planned_deadline_getsecs = plannedBaselineOffset;
    obj.Log.updateLastEvent(event);
    endMarker = [];
    if phase == "final_fixation" && obj.Config.markers.run_boundary_enabled
        % Refresh the phase clock close to the reservation deadline,
        % instead of extrapolating from the start of a long baseline.
        audioLead = obj.Config.markers.wav.minimum_lead_s+2*obj.IFI;
        obj.repeatFixation(ctx,phase,onsetFlip,max(0,duration-audioLead));
        obj.checkQuit(ctx,phase);
        [offsetFlip,endMarker,plannedBaselineOffset] = obj.onsetFlip( ...
            ctx,phase+"_end","run_end",plannedBaselineOffset);
    else
        obj.checkQuit(ctx,phase);
        obj.repeatFixation(ctx,phase,onsetFlip,duration);
        offsetFlip = obj.fixationFlip(ctx,phase+"_end",1,plannedBaselineOffset,"off");
    end
    % The prepared boundary Flip closes the original fixed-duration baseline.
    event = obj.Log.event(ctx,phase+"_offset", ...
        phase+"_end",offsetFlip.stimulus_onset_getsecs,offsetFlip);
    event.planned_onset_getsecs = plannedBaselineOffset;
    obj.Log.updateLastEvent(event);
    if ~isempty(endMarker)
        obj.RunEndFlip = offsetFlip;
        obj.Triggers.associate(endMarker.event_id,obj.markerFlip(offsetFlip));
    end
    obj.checkQuit(ctx,phase+"_end");
    obj.CurrentContext = [];
    obj.CurrentRunPhase = "";
end
