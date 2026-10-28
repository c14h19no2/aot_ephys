function drawFixation(window, fixation, screenFcn)
%DRAWFIXATION Draw the fixation overlay prepared by ephys.fixationGeometry.
% fixation.surround_texture and fixation.dot_texture hold surround_image and
% dot_image, made once when the window opens. Order: surround, lines, dot.
% Alpha blending is enabled only here, for the masked textures and the smoothed
% lines, and the previous blend function is restored afterwards.
if nargin < 3
    screenFcn = @Screen;
end
[source,destination] = screenFcn('BlendFunction',window, ...
    'GL_SRC_ALPHA','GL_ONE_MINUS_SRC_ALPHA');
% Textures are pixel-aligned, so nearest filtering keeps them exact.
screenFcn('DrawTexture',window,fixation.surround_texture,[],fixation.texture_rect,0,0);
% Diagonal lines, anti-aliased (smooth 1); lenient keeps a width outside the
% driver's smooth-line range from stopping the run.
screenFcn('DrawLines',window,fixation.line_xy,fixation.line_width_px, ...
    fixation.line_rgb255,[],1,1);
% The dot and its outline on top, so the lines do not hide the black dot.
screenFcn('DrawTexture',window,fixation.dot_texture,[],fixation.texture_rect,0,0);
screenFcn('BlendFunction',window,source,destination);
end
