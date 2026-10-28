function [text,level] = siteSummaryText(s)
%SITESUMMARYTEXT Site lines for the run dialog from ephys.siteSummary.
% Screen size, resolution and refresh rate on one line, then a warning when the
% site is not approved for acquisition. level is 'note', 'warning' or 'error'.
level = 'note';
if strlength(s.error)>0
    text = "Site file error: "+s.error;
    level = 'error';
    return;
end
times = char(215); dot = char(183);
screen = "size not set";
if all(isfinite(s.screen_size_cm))
    screen = sprintf('%.2f %s %.2f cm',s.screen_size_cm(1),times,s.screen_size_cm(2));
end
text = string(sprintf('Screen %s   %s   %d %s %d px   %s   %g Hz', ...
    screen,dot,s.resolution_px(1),times,s.resolution_px(2),dot,s.refresh_hz));
if ~s.approved
    text(end+1) = "Not approved: Debug runs only (protocol.approved_for_acquisition).";
    level = 'warning';
end
end
