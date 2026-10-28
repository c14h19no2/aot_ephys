function v = viewingDistance(config)
%VIEWINGDISTANCE Eye-to-screen distance at which the movie has its target angle.
% Uses display.resolution_px, display.screen_size_cm (the visible picture area)
% and stimulus.target_size_deg [width height]. The movie area is the window fit
% (ephys.movieRect, including movie_scale) of a source with the aspect of the
% target angles, which is where a movie of that aspect is drawn. Each axis
% gives its own distance; they agree when the screen size has the aspect of
% the resolution. distance_cm is their mean and size_deg the movie's angle at
% that distance. status is "ok", "no_screen_size" or "no_target_size"; unknown
% values stay NaN. Invalid settings raise ephys:ScreenSize or ephys:TargetSize.
v = struct('status',"no_target_size",'message',"",'distance_cm',NaN, ...
    'size_deg',[NaN NaN],'target_size_deg',[NaN NaN], ...
    'axis_distance_cm',[NaN NaN],'movie_px',[NaN NaN],'movie_cm',[NaN NaN], ...
    'screen_size_cm',[NaN NaN],'resolution_px',[NaN NaN]);
target = pair(config,'stimulus','target_size_deg','ephys:TargetSize');
screen = pair(config,'display','screen_size_cm','ephys:ScreenSize');
assert(isempty(target) || (numel(target)==2 && all(isfinite(target)) && ...
    all(target>0) && all(target<180)),'ephys:TargetSize', ...
    'stimulus.target_size_deg must be null or two angles [width, height] between 0 and 180 degrees.');
assert(isempty(screen) || (numel(screen)==2 && all(isfinite(screen)) && all(screen>0)), ...
    'ephys:ScreenSize', ...
    'display.screen_size_cm must be null or two positive lengths [width, height] in cm.');
if isempty(target), return; end
v.target_size_deg = target;
if isempty(screen)
    v.status = "no_screen_size";
    return;
end
v.screen_size_cm = screen;
v.resolution_px = pair(config,'display','resolution_px','ephys:Display');
tanHalf = tand(target/2);
rect = ephys.movieRect(config,tanHalf);
v.movie_px = rect(3:4)-rect(1:2);
v.movie_cm = v.movie_px.*screen./v.resolution_px;
v.axis_distance_cm = (v.movie_cm/2)./tanHalf;
v.distance_cm = mean(v.axis_distance_cm);
v.size_deg = 2*atand((v.movie_cm/2)/v.distance_cm);
v.status = "ok";
end

function value = pair(config,section,field,id)
% YAML lists arrive as cells; null arrives as [].
value = [];
if ~isfield(config,section) || ~isfield(config.(section),field), return; end
value = config.(section).(field);
if isempty(value), value = []; return; end
if iscell(value)
    assert(all(cellfun(@(x) isnumeric(x) && isscalar(x) && isreal(x),value)), ...
        id,'%s.%s must contain numbers.',section,field);
    value = cell2mat(value);
end
assert(isnumeric(value) && isreal(value),id,'%s.%s must contain numbers.',section,field);
value = double(value(:)');
end
