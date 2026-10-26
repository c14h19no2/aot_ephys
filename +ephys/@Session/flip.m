function row = flip(obj,ctx,phase,n,frame,diode,plannedOnset)
%FLIP Submit one prepared framebuffer and log the returned PTB timestamps.
% plannedOnset is a desired visual onset in GetSecs seconds (NaN = next
% refresh). flipRequestTime is PTB's earlier submission threshold, not
% a measured onset. Audio keeps the time reserved by reserveMarker.
    flipRequestTime = obj.computeFlipRequestTime(plannedOnset);
    % Some external display paths present a distant request early.
    % Keep the prepared framebuffer offscreen until its submit window;
    % poll input/audio so Q can still cancel a future reservation.
    if flipRequestTime-GetSecs>obj.IFI
        while GetSecs<flipRequestTime
            obj.checkQuit(ctx,phase+"_waiting");
            obj.Triggers.poll();
            remaining = flipRequestTime-GetSecs;
            if remaining>0
                WaitSecs('YieldSecs',min(.001,remaining));
            end
        end
    end
    submitted = GetSecs;
    [vblTime,stimulusOnsetTime,flipReturnTime,missedDeadline] = Screen('Flip',obj.Window,flipRequestTime);
    obj.LastVBL = vblTime;
    raw = struct('vbl',vblTime,'stimulus',stimulusOnsetTime, ...
        'returned',flipReturnTime,'missed',missedDeadline, ...
        'flip_submit_getsecs',submitted,'submission_mode',"regular");
    row = obj.Log.flip(ctx,phase,n,raw,flipRequestTime,frame,diode);
    obj.Triggers.poll();
end
