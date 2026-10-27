function [row,marker,plannedOnset] = steadyOnsetFlip(obj,ctx,holdPhase,anchorFlip,phase,eventType,plannedOnset)
%STEADYONSETFLIP Keep refreshing every frame, then flip a WAV onset on its slot.
% Used instead of onsetFlip when display.steady_flip is true. Once the onset
% slot on holdPhase's onset + n x IFI grid is known, the WAV is reserved for
% it. The held fixation is then refreshed on every slot up to the onset, so
% the display pipeline is in the same continuous state at every onset, and the
% onset frame is drawn after the last held refresh. Reserving before the
% refresh stream keeps the 1-25 ms audio scheduling call out of it. A late
% refresh cannot move the reserved audio: a missed onset slot stays visible
% in the logged timestamps.
    assert(isfinite(plannedOnset),'ephys:SteadyOnset', ...
        'A steady onset needs a finite planned onset.');
    anchor = anchorFlip.stimulus_onset_getsecs;
    % Onset slot on the hold grid. After long preparation, take the next slot
    % that still leaves one refresh for drawing.
    slot = max([1,round((plannedOnset-anchor)/obj.IFI),floor((GetSecs-anchor)/obj.IFI)+2]);
    requestTime = anchor+(slot-0.5)*obj.IFI;
    obj.checkQuit(ctx,holdPhase);
    predictedOnset = ephys.predictVisualOnset(obj.LastVBL,requestTime,obj.IFI,obj.VBLDuration);
    marker = [];
    if strlength(eventType)>0
        marker = obj.scheduleOnsetMarker(ctx,eventType,predictedOnset);
    end
    % Refresh every slot before the onset; Q still cancels the reserved WAV.
    obj.repeatFixation(ctx,holdPhase,anchorFlip,slot*obj.IFI);
    [kind,diode] = obj.onsetFrameKind(phase);
    frame = obj.drawFrame(kind,diode);
    Screen('DrawingFinished',obj.Window);
    frameReady = GetSecs;
    obj.checkQuit(ctx,phase+"_prepared");
    raw = obj.submitOnsetFlip(ctx,phase,requestTime,predictedOnset,obj.usesDeferredOnset());
    raw.frame_ready_getsecs = frameReady;
    raw.submission_mode = "steady_"+raw.submission_mode;
    obj.LastVBL = raw.vbl;
    row = obj.Log.flip(ctx,phase,1,raw,requestTime,frame,diode);
    obj.Triggers.poll();
end
