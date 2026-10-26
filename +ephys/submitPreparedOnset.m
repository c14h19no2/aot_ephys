function [raw,marker] = submitPreparedOnset(requestTime,predictedOnset,reserveFcn,flipFcn,frameReady)
%SUBMITPREPAREDONSET Reserve audio and immediately dispatch a prepared Flip.
% Drawing, media preparation, prediction and input checks belong before this
% function. Both callbacks use frozen absolute deadlines. The Flip callback
% records its actual Screen call time; a display-specific wait belongs there.
    marker = reserveFcn(predictedOnset);
    raw = flipFcn(requestTime);
    raw.frame_ready_getsecs = frameReady;
end
