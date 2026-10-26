function raw = submitOnsetFlip(obj,ctx,phase,requestTime,predictedOnset,deferred)
%SUBMITONSETFLIP Call PTB from a workspace without nested functions.
% Imaging-pipeline hooks inject variables into Screen's caller workspace.
% A nested callback's static workspace rejects those variables on macOS.
    policy = "direct";
    if deferred
        % This macOS sink presents distant requests early in local tests.
        % Its half-IFI Flip threshold is not a wall-clock onset deadline.
        % Hold the prepared frame until the SAME predicted onset reserved
        % for audio. Do not apply a fitted audio/timestamp bias. The remaining
        % dispatch/presentation delay stays visible in the measured offsets.
        policy = "macos_external_target";
        while GetSecs<predictedOnset
            obj.checkQuit(ctx,phase+"_waiting");
            obj.Triggers.poll();
            remaining = predictedOnset-GetSecs;
            if remaining>0, WaitSecs('YieldSecs',min(.001,remaining)); end
        end
    end
    submitted = GetSecs;
    [vbl,stimulus,returned,missed] = Screen('Flip',obj.Window,requestTime);
    raw = struct('vbl',vbl,'stimulus',stimulus,'returned',returned, ...
        'missed',missed,'flip_submit_getsecs',submitted,'submission_mode',policy);
end
