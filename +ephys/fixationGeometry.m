function g = fixationGeometry(config)
%FIXATIONGEOMETRY Pixel geometry and texture images of the fixation overlay.
% Sizes are configured in degrees (stimulus.fixation.*_deg). The viewing
% distance is the one at which the fitted movie has stimulus.target_size_deg,
% so in pixels it is d = (movie width / 2) / tan(target width / 2), and an
% element of angle a spans 2 * d * tan(a / 2) pixels on any screen. The centre
% is the window centre, where the movie is centred.
%
% Drawing order: surround_image, the two diagonal lines (line_xy,
% line_width_px), then dot_image. surround_image is the gray disc, opaque out
% to (1 - surround_fringe) of its radius, then the PsychoPy raised cosine
% 0.5 * (1 + cos(pi * t)) to 0 at its edge. dot_image is the black dot, over a
% white outline centred on its edge when outline_width_deg > 0. The dot is drawn over the
% lines: at a few pixels across, lines drawn over it hide most of the black.
% Both are RGBA uint8 images whose pixels average 8 x 8 samples; texture_rect
% is pixel-aligned, so drawing them needs no resampling.
fix = config.stimulus.fixation;
target = numbers(config.stimulus,'target_size_deg');
assert(numel(target)==2 && all(isfinite(target)) && all(target>0 & target<180), ...
    'ephys:FixationGeometry', ...
    'The fixation size needs stimulus.target_size_deg [width, height] in degrees.');
resolution = numbers(config.display,'resolution_px');
movie = ephys.movieRect(config,tand(target/2));
g.distance_px = (movie(3)-movie(1))/2/tand(target(1)/2);
pixels = @(degrees) 2*g.distance_px*tand(degrees/2);
g.center_px = resolution/2;
g.surround_diameter_px = pixels(fix.surround_diameter_deg);
g.surround_fringe = fix.surround_fringe;
g.dot_diameter_px = pixels(fix.dot_diameter_deg);
g.outline_width_px = pixels(fix.outline_width_deg);
g.line_width_px = pixels(fix.line_width_deg);
g.line_rgb255 = numbers(fix,'line_rgb255');
% Lines through the centre at 45 and 135 degrees, long enough to leave the window.
reach = sum(resolution);
c = g.center_px;
g.line_xy = [c(1)-reach c(1)+reach c(1)-reach c(1)+reach; ...
    c(2)-reach c(2)+reach c(2)+reach c(2)-reach];

% Square textures, pixel-aligned, with a one-pixel transparent margin.
side = ceil(max(g.surround_diameter_px,g.dot_diameter_px+g.outline_width_px))+2;
corner = floor(c-side/2);
g.texture_rect = [corner corner+side];
outerRadius = g.surround_diameter_px/2;
innerRadius = (1-g.surround_fringe)*outerRadius;
% Surround opacity, as PsychoPy's raisedCosine mask.
surround = @(r) (r<outerRadius).*(0.5+0.5*cos(pi* ...
    min(max((r-innerRadius)/max(outerRadius-innerRadius,eps),0),1)));
g.surround_image = layers(corner,side,c, ...
    {{numbers(fix,'surround_rgb255'),surround}});
dot = {{numbers(fix,'dot_rgb255'),@(r) double(r<=g.dot_diameter_px/2-g.outline_width_px/2)}};
if g.outline_width_px>0
    dot = [{{numbers(fix,'outline_rgb255'), ...
        @(r) double(r<=g.dot_diameter_px/2+g.outline_width_px/2)}},dot];
end
g.dot_image = layers(corner,side,c,dot);
end

function image = layers(corner,side,c,stack)
% Composite each {rgb, opacity(r)} layer over the ones before it, per sample,
% and average 8 x 8 samples per pixel into an RGBA uint8 image.
samples = 8;
offsets = ((1:samples)-0.5)/samples;
[x,y] = meshgrid(corner(1)+(0:side-1),corner(2)+(0:side-1));
premultiplied = zeros(side,side,3);
alpha = zeros(side,side);
for sx = offsets
    for sy = offsets
        r = hypot(x+sx-c(1),y+sy-c(2));
        color = zeros(side,side,3);
        cover = zeros(side,side);
        for layer = stack
            a = layer{1}{2}(r);
            color = reshape(layer{1}{1},1,1,3).*a+color.*(1-a);
            cover = a+cover.*(1-a);
        end
        premultiplied = premultiplied+color;
        alpha = alpha+cover;
    end
end
premultiplied = premultiplied/samples^2;
alpha = alpha/samples^2;
rgb = premultiplied./max(alpha,eps);
image = uint8(cat(3,round(rgb),round(255*alpha)));
end

function value = numbers(s,field)
% YAML lists arrive as cells.
value = s.(field);
if iscell(value), value = cell2mat(value); end
value = double(value(:)');
end
