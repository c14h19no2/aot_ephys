function rect = movieRect(config,sourceSize)
%MOVIERECT Fit the complete source to the window, preserving its aspect ratio.
% sourceSize is [width height]. At movie_scale=1, at least one source dimension
% fills the corresponding window dimension. Without sourceSize, return the
% scaled window bounds. All returned rectangles are centered in the window.
resolution = cell2mat(config.display.resolution_px);
resolution = resolution(:)';
sizePx = resolution * config.stimulus.movie_scale;
if nargin > 1 && ~isempty(sourceSize)
    assert(isnumeric(sourceSize) && isreal(sourceSize) && numel(sourceSize) == 2 && ...
        all(isfinite(sourceSize(:))) && all(sourceSize(:) > 0), ...
        'ephys:MediaGeometry','Source dimensions must be positive finite [width height].');
    sourceSize = double(sourceSize(:)');
    fitScale = min(resolution ./ sourceSize);
    sizePx = sourceSize * fitScale * config.stimulus.movie_scale;
end
center = resolution / 2;
rect = [center-sizePx/2, center+sizePx/2];
end
