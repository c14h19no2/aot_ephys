function seconds=audioReservationLead(wav,ifi)
%AUDIORESERVATIONLEAD Reserve early enough for driver lead, CPU work and drawing.
% This is a preparation deadline, not a delay added to an existing visual target.
seconds=wav.minimum_lead_s+wav.reservation_margin_s+2*ifi;
end
