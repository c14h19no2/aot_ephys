function value = blankingDuration(windowInfo,ifi)
%BLANKINGDURATION VBL duration that PredictVisualOnsetForTime adds, or zero.
% PTB adds it only when beamposition gives a known VBL endline and the VBL
% timestamp marks the start of blanking (SpecialFlags bit 16).
value = 0;
if isstruct(windowInfo) && all(isfield(windowInfo,{'VBLEndline','VBLStartline','SpecialFlags'})) && ...
        windowInfo.VBLEndline > 0 && bitand(windowInfo.SpecialFlags,16) == 16
    value = (windowInfo.VBLEndline-windowInfo.VBLStartline)/windowInfo.VBLEndline*ifi;
end
end
