function prepareVideo(obj,ctx,name)
%PREPAREVIDEO Select this occurrence and hold its first texture for onset.
    obj.CurrentContext = ctx;
    c = obj.Config;
    if name ~= "blank"
        moviePath = fullfile(string(c.paths.video_root),name);
        obj.Log.event(ctx,"movie_preparation_start","preparation",GetSecs,[]);
        if string(c.playback.backend) == "native"
            [obj.Player,cacheHit] = obj.MovieCache.prepare(ctx.trial_nr,c.protocol.video_duration_s, ...
                @() obj.checkQuit(ctx,"preparation"));
        else
            [obj.Player,cacheHit] = obj.MovieCache.prepare(moviePath,c.protocol.video_duration_s);
        end
        selected = string({obj.Inventory.path}) == moviePath;
        obj.MovieDestinationRect = obj.Inventory(selected).display_rect_px;
        obj.Inventory(selected).source_pts_s = obj.Player.Map.source_pts_s;
        ev = obj.Log.event(ctx,"movie_preparation_end","preparation",GetSecs,[]);
        ev.status = "decoded";
        if cacheHit
            ev.status = "cache_hit";
        end
        first = obj.Player.info();
        ev.detail = ev.status+": "+string(obj.Player.Map.frame_count)+ ...
            " mapped source frames; held texture source index: "+string(first.source_frame_index);
        obj.Log.updateLastEvent(ev);
    end
end
