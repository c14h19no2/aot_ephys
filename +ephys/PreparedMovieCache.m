classdef PreparedMovieCache < handle
    %PREPAREDMOVIECACHE Own prepared players under one aggregate RGBA budget.
    properties (SetAccess=private)
        Window
        Playback
        Inventory
        MapDirectory
        FactoryFcn
        Entries = struct('path',{},'player',{},'bytes',{})
        TextureBytes = 0
    end
    methods
        function obj=PreparedMovieCache(window,playback,inventory,mapDirectory,factoryFcn)
            if nargin<5, factoryFcn=@ephys.FrameMoviePlayer; end
            obj.Window=window; obj.Playback=playback; obj.Inventory=inventory;
            obj.MapDirectory=mapDirectory; obj.FactoryFcn=factoryFcn;
        end
        function yes=contains(obj,path)
            yes=any(string({obj.Entries.path})==string(path));
        end
        function loaded=preload(obj,path,minimumDuration,progressFcn)
            if nargin<4, progressFcn=[]; end
            if obj.contains(path), loaded=true; return; end
            available=obj.Playback.max_texture_bytes-obj.TextureBytes;
            if available<=0, loaded=false; return; end
            playback=obj.Playback;
            playback.max_texture_bytes=available;
            player=obj.FactoryFcn(obj.Window,playback,obj.Inventory,obj.MapDirectory);
            try
                player.prepare(path,minimumDuration,progressFcn);
            catch cause
                player.close();
                % A later preload may not fit; retain the already loaded set.
                if strcmp(cause.identifier,'ephys:TextureBudget') && ~isempty(obj.Entries)
                    loaded=false;
                    return;
                end
                rethrow(cause);
            end
            bytes=player.Map.frame_count*player.Map.width_px*player.Map.height_px*4;
            obj.Entries(end+1)=struct('path',string(path),'player',player,'bytes',bytes);
            obj.TextureBytes=obj.TextureBytes+bytes;
            assert(obj.TextureBytes<=obj.Playback.max_texture_bytes,'ephys:TextureBudget', ...
                'Combined prepared movies exceed the configured texture budget.');
            loaded=true;
        end
        function [player,cacheHit]=prepare(obj,path,minimumDuration)
            cacheHit=obj.contains(path);
            if ~cacheHit
                % Playback of the previous trial has stopped. Release the
                % retained batch before loading another full movie.
                obj.close();
                assert(obj.preload(path,minimumDuration),'ephys:TextureBudget', ...
                    'Movie cannot fit in an empty prepared cache.');
            end
            selected=string({obj.Entries.path})==string(path);
            player=obj.Entries(selected).player;
            player.resetToFirstFrame();
        end
        function resident=ensureResident(obj)
            resident=true;
            for k=1:numel(obj.Entries)
                loaded=obj.Entries(k).player.ensureResident();
                resident=resident && logical(loaded);
            end
        end
        function close(obj)
            firstError=[];
            for k=1:numel(obj.Entries)
                if ~isvalid(obj.Entries(k).player), continue; end
                try
                    obj.Entries(k).player.close();
                catch cause
                    if isempty(firstError), firstError=cause; end
                end
            end
            obj.Entries=struct('path',{},'player',{},'bytes',{});
            obj.TextureBytes=0;
            if ~isempty(firstError), rethrow(firstError); end
        end
        function delete(obj)
            try, obj.close(); catch, end
        end
    end
end
