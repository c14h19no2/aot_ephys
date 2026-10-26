function plan = nextFixationRefresh(anchor,phaseEnd,ifi,previousIndex,availableTime)
%NEXTFIXATIONREFRESH Select a future slot on the original phase refresh grid.
% Slot zero is the observed phase onset. A missed slot is skipped, never used
% as a new clock origin. Leave half an IFI both to submit and to hand off the
% final refresh to the phase boundary (or the protected audio booking window).
    tolerance = 8*eps(max(abs([anchor,phaseEnd,availableTime])));
    index = max(previousIndex+1, ...
        floor((availableTime+tolerance-anchor)/ifi+.5)+1);
    target = anchor+index*ifi;
    plan = [];
    if target+.5*ifi >= phaseEnd-tolerance
        return;
    end
    plan = struct('target_getsecs',target,'request_getsecs',target-.5*ifi, ...
        'refresh_index',index,'skipped_slots',index-previousIndex-1);
end
