function preloadStartup(obj)
%PRELOADSTARTUP Prepare the startup movie batch before accepting Space.
    c = obj.Config;
    obj.StartupLoading = struct('status',"not_started", ...
        'requested_movie_count',c.playback.startup_preload_movies, ...
        'planned_movie_count',0,'completed_movie_count',0, ...
        'loaded_files',strings(0,1),'texture_bytes',0, ...
        'start_getsecs',NaN,'end_getsecs',NaN,'flip_count',0, ...
        'ptb_textures_resident',NaN);
    if c.task_kind ~= "video"
        obj.StartupLoading.status = "not_applicable";
        return;
    end
    if c.playback.startup_preload_movies == 0
        obj.StartupLoading.status = "disabled";
        return;
    end
    native = string(c.playback.backend) == "native";
    occurrences = find(c.schedule ~= "blank");
    names = unique(c.schedule(c.schedule ~= "blank"),'stable');
    if native
        names = c.schedule(occurrences);
    end
    count = min(numel(names),c.playback.startup_preload_movies);
    if count == 0
        obj.StartupLoading.status = "no_movies";
        return;
    end
    names = names(1:count);
    ctx = ephys.context("video",0,"");
    obj.CurrentContext = ctx;
    obj.CurrentRunPhase = "loading";
    obj.StartupLoading.status = "loading";
    obj.StartupLoading.planned_movie_count = count;
    obj.StartupLoading.start_getsecs = GetSecs;
    obj.Log.event(ctx,"startup_loading_start","loading",GetSecs,[]);
    limited = false;
    for k = 1:count
        obj.LoadingProgressBucket = -1;
        obj.loadingProgress(ctx,k,count,0);
        ev = obj.Log.event(ctx,"startup_movie_load_start","loading",GetSecs,[]);
        ev.video_file = names(k);
        ev.condition = ephys.condition(names(k));
        obj.Log.updateLastEvent(ev);
        moviePath = fullfile(string(c.paths.video_root),names(k));
        if native
            loaded = obj.MovieCache.preload(occurrences(k),c.protocol.video_duration_s, ...
                @() obj.checkQuit(ctx,"loading"));
            obj.loadingProgress(ctx,k,count,1);
        else
            loaded = obj.MovieCache.preload(moviePath,c.protocol.video_duration_s, ...
                @(fraction) obj.loadingProgress(ctx,k,count,fraction));
        end
        obj.checkQuit(ctx,"loading");
        if ~loaded
            ev = obj.Log.event(ctx,"startup_preload_limit","loading",GetSecs,[]);
            ev.video_file = names(k);
            ev.condition = ephys.condition(names(k));
            ev.detail = "Stopped startup preload at the combined texture budget";
            obj.Log.updateLastEvent(ev);
            limited = true;
            break;
        end
        obj.StartupLoading.completed_movie_count = k;
        obj.StartupLoading.loaded_files(end+1,1) = names(k);
        obj.StartupLoading.texture_bytes = obj.MovieCache.TextureBytes;
        ev = obj.Log.event(ctx,"startup_movie_load_end","loading",GetSecs,[]);
        ev.video_file = names(k);
        ev.condition = ephys.condition(names(k));
        ev.detail = "Prepared source frame 0 and all subsequent textures";
        if native
            ev.detail = "Independent no-drop decoder started; first decoded texture held; source identity logged at onset";
        end
        obj.Log.updateLastEvent(ev);
    end
    % MakeTexture alone can leave first-use work in the graphics driver.
    % Ask PTB to preload the batch before accepting the start key.
    obj.StartupLoading.ptb_textures_resident = obj.MovieCache.ensureResident();
    obj.checkQuit(ctx,"loading");
    obj.StartupLoading.end_getsecs = GetSecs;
    obj.StartupLoading.status = "complete";
    if limited
        obj.StartupLoading.status = "limited_by_budget";
    end
    ev = obj.Log.event(ctx,"startup_loading_end","loading",GetSecs,[]);
    ev.detail = "Loaded "+string(obj.StartupLoading.completed_movie_count)+ ...
        " of "+string(count)+" planned movies; "+obj.StartupLoading.status;
    obj.Log.updateLastEvent(ev);
    obj.CurrentContext = [];
    obj.CurrentRunPhase = "";
end
