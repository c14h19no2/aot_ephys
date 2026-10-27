function [row,marker,plannedOnset] = onsetFlip(obj,ctx,phase,eventType,plannedOnset)
%ONSETFLIP Draw first, then reserve WAV and submit the same timed framebuffer.
% The visible front buffer stays unchanged while the prepared Flip is pending.
% No fixation Flip, movie fetch or drawing runs after the audio reservation.
% steadyOnsetFlip is the display.steady_flip alternative.
    [kind,diode] = obj.onsetFrameKind(phase);
    frame = obj.drawFrame(kind,diode);
    Screen('DrawingFinished',obj.Window);
    frameReady = GetSecs;
    obj.checkQuit(ctx,phase+"_prepared");
    marker = [];
    if strlength(eventType)==0
        row = obj.flip(ctx,phase,1,frame,diode,plannedOnset);
        return;
    end
    if ~isfinite(plannedOnset)
        plannedOnset = max(GetSecs+obj.Config.markers.wav.minimum_lead_s+3*obj.IFI, ...
            obj.Triggers.nextAllowedRequestTime()+3*obj.IFI);
    end
    % Freeze the visual request before predicting/reserving its audio onset.
    % Predict from the logged last Flip, so the audio keeps one relation to
    % the request whatever PTB's internal last-Flip time reads at this point.
    requestTime = obj.computeFlipRequestTime(plannedOnset);
    predictedOnset = ephys.predictVisualOnset(obj.LastVBL,requestTime,obj.IFI,obj.VBLDuration);
    deferred = obj.usesDeferredOnset();
    [raw,marker] = ephys.submitPreparedOnset(requestTime,predictedOnset, ...
        @(when) obj.scheduleOnsetMarker(ctx,eventType,when), ...
        @(when) obj.submitOnsetFlip(ctx,phase,when,predictedOnset,deferred),frameReady);
    obj.LastVBL = raw.vbl;
    row = obj.Log.flip(ctx,phase,1,raw,requestTime,frame,diode);
    obj.Triggers.poll();
end
