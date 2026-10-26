function drawFixation(window, config, screenFcn)
%DRAWFIXATION Main-task overlay using site-specified pixel dimensions.
% The source's zero-contrast raised-cosine surround is visually the same
% nominal gray as its background. Its exact gamma appearance is unverified.
if nargin < 3
    screenFcn = @Screen;
end
r = config.display.resolution_px;
w = r{1}; h = r{2};
cx = w / 2;
cy = h / 2;
fix = config.stimulus.fixation;
rgb = @(v) cell2mat(v);
d = fix.surround_diameter_px / 2;
screenFcn('FillOval', window, rgb(fix.surround_rgb255), [cx-d cy-d cx+d cy+d]);
d = fix.dot_radius_px;
screenFcn('FillOval', window, rgb(fix.dot_rgb255), [cx-d cy-d cx+d cy+d]);
reach = max(w, h);
line = rgb(fix.line_rgb255);
screenFcn('DrawLine', window, line, cx-reach, cy-reach, ...
    cx+reach, cy+reach, fix.line_width_px);
screenFcn('DrawLine', window, line, cx-reach, cy+reach, ...
    cx+reach, cy-reach, fix.line_width_px);
end
