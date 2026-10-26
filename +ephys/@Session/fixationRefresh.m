function row = fixationRefresh(obj,ctx,phase,n,anchor,phaseEnd,previousIndex)
%FIXATIONREFRESH Draw once, then submit a future fixed-grid refresh.
% Keep Screen('Flip') here without nested functions: PTB imaging hooks may
% inject variables into this workspace. Video and WAV onset paths are separate.
    frame = obj.drawFrame("fixation","off");
    Screen('DrawingFinished',obj.Window);
    frameReady = GetSecs;
    deferred = obj.usesDeferredOnset();
    row = [];
    while true
        % Drawing, input polling or OS scheduling may have consumed a slot.
        % Reselect from the original grid instead of submitting past targets.
        obj.checkQuit(ctx,phase+"_waiting");
        obj.Triggers.poll();
        plan = ephys.nextFixationRefresh(anchor,phaseEnd,obj.IFI,previousIndex,GetSecs);
        if isempty(plan), return; end
        mode = "fixed_fixation_timed";
        if deferred
            % Preserve the Mac external-backend guard against early presents.
            mode = "fixed_fixation_macos_target";
            while GetSecs<plan.target_getsecs
                obj.checkQuit(ctx,phase+"_waiting");
                obj.Triggers.poll();
                remaining = plan.target_getsecs-GetSecs;
                if remaining>0, WaitSecs('YieldSecs',min(.001,remaining)); end
            end
        end
        % Ordinary backends accept the timed request immediately and block
        % inside PTB until the next slot. Only the Mac guard waits in MATLAB.
        obj.checkQuit(ctx,phase+"_waiting");
        obj.Triggers.poll();
        submitted = GetSecs;
        latestSubmit = plan.target_getsecs;
        if deferred, latestSubmit=latestSubmit+.5*obj.IFI; end
        if submitted>=latestSubmit
            continue;
        end
        [vbl,stimulus,returned,missed] = Screen('Flip',obj.Window,plan.request_getsecs);
        obj.LastVBL = vbl;
        raw = struct('vbl',vbl,'stimulus',stimulus,'returned',returned,'missed',missed, ...
            'frame_ready_getsecs',frameReady,'flip_submit_getsecs',submitted, ...
            'submission_mode',mode,'refresh_target_getsecs',plan.target_getsecs, ...
            'refresh_index',plan.refresh_index,'refresh_skipped_slots',plan.skipped_slots, ...
            'refresh_error_s',stimulus-plan.target_getsecs);
        row = obj.Log.flip(ctx,phase,n,raw,plan.request_getsecs,frame,"off");
        obj.Triggers.poll();
        return;
    end
end
