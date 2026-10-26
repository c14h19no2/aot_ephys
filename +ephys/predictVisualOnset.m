function onset = predictVisualOnset(lastVBL,when,ifi,vblDuration)
%PREDICTVISUALONSET First refresh after a Flip request, on the logged Flip timeline.
% Same rule as Psychtoolbox's PredictVisualOnsetForTime, anchored to the VBL
% timestamp the Session logged for its last Flip rather than PTB's internal
% LastVBLTime. On the Windows test laptop that internal value differed from
% the returned timestamps by an amount that depended on how soon after a
% Flip it was read, which moved the scheduled audio by 7-13 ms between trial
% types. vblDuration is PTB's blanking correction; zero when unknown.
assert(isscalar(lastVBL) && isfinite(lastVBL) && lastVBL>0, ...
    'ephys:OnsetPrediction','Onset prediction needs a valid previous Flip timestamp.');
if when <= 0
    % PTB: a nonpositive request means the next refresh.
    when = lastVBL+0.5*ifi;
end
onset = lastVBL+(floor((when-lastVBL)/ifi)+1)*ifi+vblDuration;
end
