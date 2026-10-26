function waitFixation(obj,ctx,phase,onsetFlip,duration,refreshAnchor)
%WAITFIXATION Hold the front buffer while polling input and audio receipts.
% duration is cumulative from the observed onset, including time already spent
% preparing media. Return before the boundary to allow drawing/submission.
% refreshAnchor adds one identical Flip before a future audio reservation.
    if nargin < 6
        refreshAnchor = false;
    end
    previousFlip = obj.Log.lastFlip();
    assert(previousFlip.trial_id == ctx.trial_id && previousFlip.phase == string(phase), ...
        'ephys:FixationPhase','Static waiting must continue the active fixation phase.');
    flipNumber = previousFlip.phase_flip_seq;
    if previousFlip.photodiode_state == "on"
        % End a fixation photodiode pulse on the next refresh, before loading.
        flipNumber = flipNumber+1;
        offFlip = obj.fixationFlip(ctx,phase,flipNumber,NaN,"off");
        event = obj.Log.event(ctx,"photodiode_off",phase, ...
            offFlip.stimulus_onset_getsecs,offFlip);
        event.photodiode_transition = "off";
        obj.Log.updateLastEvent(event);
    end
    if duration <= 0 && ~refreshAnchor
        return;
    end
    phaseEnd = onsetFlip.stimulus_onset_getsecs+duration;
    waitDeadline = phaseEnd-1.5*obj.IFI;
    if refreshAnchor
        waitDeadline = phaseEnd-2*obj.IFI;
    end
    % Long pauses between Flips can stall the macOS external display path.
    % Refresh an identical image sparsely, retaining the original phase clock.
    maxIdle = obj.DisplayTiming.static_fixation_max_idle_s;
    while maxIdle>0 && obj.LastVBL+maxIdle < waitDeadline-obj.IFI
        referenceOnset = obj.LastVBL+maxIdle;
        obj.waitUntil(ctx,phase,referenceOnset-0.5*obj.IFI);
        flipNumber = flipNumber+1;
        obj.fixationFlip(ctx,phase,flipNumber,referenceOnset,"off");
    end
    obj.waitUntil(ctx,phase,waitDeadline);
    if refreshAnchor
        % Renew PTB's LastVBL near the audio lead deadline. The image and the
        % original phase onset/deadline stay unchanged by this reference Flip.
        obj.fixationFlip(ctx,phase,flipNumber+1,phaseEnd-obj.IFI,"off");
    end
end
