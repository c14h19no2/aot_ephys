classdef NativeMovieQueue < handle
    %NATIVEMOVIEQUEUE Bounded independent handles keyed by trial occurrence.
    properties (SetAccess=private)
        Window
        Playback
        Inventory
        Schedule
        Entries=struct('trial_nr',{},'player',{},'bytes',{})
        TextureBytes=0
        FactoryFcn
    end
    methods
        function obj=NativeMovieQueue(window,playback,inventory,schedule,factoryFcn)
            obj.Window=window; obj.Playback=playback;
            obj.Inventory=inventory; obj.Schedule=schedule;
            if nargin<5
                factoryFcn=@(map) ephys.NativeMoviePlayer(window,playback,map);
            end
            obj.FactoryFcn=factoryFcn;
        end
        function yes=contains(obj,trialNr)
            yes=any([obj.Entries.trial_nr]==trialNr);
        end
        function loaded=preload(obj,trialNr,minimumDuration,quitFcn,deadline)
            if nargin<4, quitFcn=[]; end
            if nargin<5, deadline=Inf; end
            if obj.contains(trialNr), loaded=true; return; end
            if numel(obj.Entries)>=2, loaded=false; return; end
            name=obj.Schedule(trialNr);
            selected=string({obj.Inventory.name})==name;
            assert(sum(selected)==1,'ephys:NativeMap','Native movie absent from preflight.');
            map=obj.Inventory(selected).native_map;
            bytes=map.frame_count*map.width_px*map.height_px*4;
            if obj.TextureBytes+bytes>obj.Playback.max_texture_bytes
                if ~isempty(obj.Entries), loaded=false; return; end
                error('ephys:TextureBudget','One native movie exceeds the configured texture budget.');
            end
            player=obj.FactoryFcn(map);
            try
                player.prepare(minimumDuration,quitFcn,deadline);
                obj.Entries(end+1)=struct('trial_nr',trialNr,'player',player,'bytes',bytes);
                obj.TextureBytes=obj.TextureBytes+bytes;
            catch cause
                delete(player);
                rethrow(cause);
            end
            loaded=true;
        end
        function [player,hit]=prepare(obj,trialNr,minimumDuration,quitFcn)
            if nargin<4, quitFcn=[]; end
            hit=obj.contains(trialNr);
            if ~hit
                loaded=obj.preload(trialNr,minimumDuration,quitFcn);
                if ~loaded
                    % Required current presentation takes priority over lookahead.
                    obj.close();
                    loaded=obj.preload(trialNr,minimumDuration,quitFcn);
                end
                assert(loaded,'ephys:NativeState','Required current movie could not be prepared.');
            end
            player=obj.Entries([obj.Entries.trial_nr]==trialNr).player;
        end
        function nr=nextToPrepare(obj,currentNr)
            nr=[];
            if numel(obj.Entries)>=2, return; end
            candidates=find((1:numel(obj.Schedule))>currentNr & obj.Schedule(:)'~="blank");
            for candidate=candidates
                if ~obj.contains(candidate), nr=candidate; return; end
            end
        end
        function value=release(obj,trialNr)
            selected=find([obj.Entries.trial_nr]==trialNr);
            assert(numel(selected)==1,'ephys:NativeState','No unique current native handle.');
            entry=obj.Entries(selected);
            entry.player.stop();
            value=entry.player.summary();
            entry.player.closeCurrent();
            obj.Entries(selected)=[];
            obj.TextureBytes=obj.TextureBytes-entry.bytes;
        end
        function resident=ensureResident(obj)
            resident=true;
            for k=1:numel(obj.Entries)
                resident=logical(obj.Entries(k).player.ensureResident()) && resident;
            end
        end
        function values=snapshot(obj)
            values=struct([]);
            for k=1:numel(obj.Entries)
                value=obj.Entries(k).player.summary();
                value.trial_nr=obj.Entries(k).trial_nr;
                value.player_status=obj.Entries(k).player.Status;
                values=[values;value]; %#ok<AGROW>
            end
        end
        function close(obj)
            first=[];
            for k=1:numel(obj.Entries)
                try, obj.Entries(k).player.closeCurrent();
                catch cause, if isempty(first), first=cause; end, end
            end
            obj.Entries=struct('trial_nr',{},'player',{},'bytes',{});
            obj.TextureBytes=0;
            if ~isempty(first), rethrow(first); end
        end
        function delete(obj)
            try, obj.close(); catch, end
        end
    end
end
