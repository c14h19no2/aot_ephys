function inventory = mediaInventory(config)
%MEDIAINVENTORY Hash assets and read native maps or inspect legacy media.
% Native playback uses only previously verified JSON metadata, never a process.
names = unique(config.schedule(config.schedule~="blank"),'stable');
native = config.task_kind == "video" && string(config.playback.backend) == "native";
inventory = repmat(struct('name',"",'path',"",'kind',"", ...
    'condition',"",'size_bytes',NaN,'sha256',"", ...
    'duration_s',NaN,'fps',NaN,'width_px',NaN,'height_px',NaN, ...
    'source_pts_s',[],'display_rect_px',[]), ...
    numel(names),1);
for i = 1:numel(names)
    name = names(i);
    if config.task_kind == "video"
        filename = fullfile(string(config.paths.video_root),name);
        inventory(i).kind = "video";
        if ~native
            info = ephys.probeMovie(filename,config.playback);
            inventory(i).duration_s = info.duration;
            inventory(i).fps = info.fps;
            inventory(i).width_px = info.width;
            inventory(i).height_px = info.height;
        end
    else
        filename = fullfile(string(config.paths.picture_root),name);
        info = imfinfo(char(filename));
        inventory(i).kind = "picture";
        inventory(i).width_px = info(1).Width;
        inventory(i).height_px = info(1).Height;
    end
    file = dir(filename);
    inventory(i).name = name;
    inventory(i).path = filename;
    inventory(i).condition = ephys.condition(name);
    inventory(i).size_bytes = file.bytes;
    inventory(i).sha256 = string(ephys.sha256(filename));
end
if native
    inventory = ephys.nativeInventory(inventory,config.playback);
end
for i = 1:numel(inventory)
    if inventory(i).kind == "video"
        assert(inventory(i).duration_s+1e-6>=config.protocol.video_duration_s, ...
            'ephys:ShortVideo','Video shorter than scheduled duration: %s',inventory(i).name);
    end
    inventory(i).display_rect_px = ephys.movieRect(config, ...
        [inventory(i).width_px, inventory(i).height_px]);
    if isfield(config,'photodiode') && config.photodiode.enabled
        diode = cell2mat(config.photodiode.rect_px);
        stimulus = inventory(i).display_rect_px;
        overlap = diode(1)<stimulus(3) && diode(3)>stimulus(1) && ...
            diode(2)<stimulus(4) && diode(4)>stimulus(2);
        assert(~overlap,'ephys:PhotodiodeOverlap', ...
            'Photodiode rectangle overlaps stimulus %s.',inventory(i).name);
    end
end
end
