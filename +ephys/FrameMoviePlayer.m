classdef FrameMoviePlayer < handle
    %FRAMEMOVIEPLAYER Predecoded source frames, selected by their actual PTS.
    properties (SetAccess=private)
        Window
        Playback
        Inventory
        MapDirectory
        Textures = []
        Map = struct()
        Path = ""
        FrameIndex = 1
        StartFlip = NaN
        StartCommandTime = NaN
        StartCommandCompletedTime = NaN
        Running = false
        Status = "unprepared"
        ScreenFcn
        ClockFcn
        DecodeFcn
    end
    methods
        function obj=FrameMoviePlayer(window,playback,inventory,mapDirectory,screenFcn,clockFcn,decodeFcn)
            if nargin<5 || isempty(screenFcn), screenFcn=@Screen; end
            if nargin<6 || isempty(clockFcn), clockFcn=@GetSecs; end
            if nargin<7 || isempty(decodeFcn), decodeFcn=@ephys.decodeMovieFrames; end
            obj.Window=window; obj.Playback=playback; obj.Inventory=inventory;
            obj.MapDirectory=mapDirectory; obj.ScreenFcn=screenFcn;
            obj.ClockFcn=clockFcn; obj.DecodeFcn=decodeFcn;
        end
        function prepare(obj,path,minimumDuration,progressFcn)
            if nargin<4, progressFcn=[]; end
            obj.closeCurrent();
            media=obj.Inventory(string({obj.Inventory.path})==string(path));
            assert(numel(media)==1,'ephys:FrameMap','Movie not in preflight inventory: %s',path);
            assert(media.duration_s+1e-6>=minimumDuration,'ephys:ShortVideo', ...
                'Movie shorter than scheduled slot: %s',path);
            folder=tempname; mkdir(folder);
            removeTemporary=onCleanup(@() rmdir(folder,'s')); %#ok<NASGU>
            try
                [map,rawPath]=obj.DecodeFcn(path,obj.Playback,folder,media.sha256);
                assert(map.width_px==media.width_px && map.height_px==media.height_px, ...
                    'ephys:FrameMap','Decoded dimensions differ from preflight: %s',path);
                assert(map.relative_pts_s(end)<media.duration_s+1e-6, ...
                    'ephys:FrameMap','Frame PTS exceeds movie duration: %s',path);
                estimate=map.frame_count*map.width_px*map.height_px*4;
                assert(estimate<=obj.Playback.max_texture_bytes,'ephys:TextureBudget', ...
                    'Movie needs approximately %.0f MiB of textures; configured limit %.0f MiB.', ...
                    estimate/2^20,obj.Playback.max_texture_bytes/2^20);
                obj.Map=map; obj.Path=string(path);
                obj.Textures=zeros(1,map.frame_count);
                fid=fopen(rawPath,'rb');
                assert(fid>=0,'ephys:FrameRead','Cannot open decoded frames.');
                closeRaw=onCleanup(@() fclose(fid)); %#ok<NASGU>
                frameBytes=map.width_px*map.height_px*3;
                if ~isempty(progressFcn), progressFcn(0); end
                for k=1:map.frame_count
                    bytes=fread(fid,frameBytes,'*uint8');
                    assert(numel(bytes)==frameBytes,'ephys:FrameRead','Truncated RGB frame %d.',k-1);
                    pixels=permute(reshape(bytes,[3,map.width_px,map.height_px]),[3 2 1]);
                    obj.Textures(k)=obj.ScreenFcn('MakeTexture',obj.Window,pixels);
                    if ~isempty(progressFcn) && (mod(k,8)==0 || k==map.frame_count)
                        progressFcn(k/map.frame_count);
                    end
                end
                clear closeRaw
                if ~isfolder(obj.MapDirectory), mkdir(obj.MapDirectory); end
                [~,stem]=fileparts(path);
                mapPath=fullfile(obj.MapDirectory,[char(stem) '.json']);
                fid=fopen(mapPath,'w');
                assert(fid>=0,'ephys:FrameMap','Cannot save frame map.');
                closeMap=onCleanup(@() fclose(fid)); %#ok<NASGU>
                fprintf(fid,'%s\n',jsonencode(map,'PrettyPrint',true));
                clear closeMap
                obj.resetToFirstFrame();
            catch cause
                obj.closeCurrent();
                rethrow(cause);
            end
        end
        function resetToFirstFrame(obj)
            % Reuse verified textures without consuming frames while waiting.
            assert(~isempty(obj.Textures),'ephys:NoMovieFrame','Movie has not been prepared.');
            obj.Running=false;
            obj.FrameIndex=1;
            obj.StartFlip=NaN;
            obj.StartCommandTime=NaN;
            obj.StartCommandCompletedTime=NaN;
            obj.Status="first_frame_prepared";
        end
        function resident=ensureResident(obj)
            assert(~isempty(obj.Textures),'ephys:NoMovieFrame','Movie has not been prepared.');
            resident=obj.ScreenFcn('PreloadTextures',obj.Window,obj.Textures);
        end
        function start(obj,actualFlip)
            assert(~isempty(obj.Textures) && obj.FrameIndex==1, ...
                'ephys:FirstFrame','Playback must start with preloaded source frame zero.');
            obj.StartCommandTime=obj.ClockFcn();
            obj.StartFlip=actualFlip;
            obj.Running=true;
            obj.StartCommandCompletedTime=obj.ClockFcn();
        end
        function draw(obj,rect,presentationTime)
            assert(~isempty(obj.Textures),'ephys:NoMovieFrame','Movie has not been prepared.');
            if nargin<3, presentationTime=obj.ClockFcn(); end
            if obj.Running
                elapsed=max(0,presentationTime-obj.StartFlip);
                selected=find(obj.Map.relative_pts_s<=elapsed+1e-9,1,'last');
                if isempty(selected), selected=1; end
                selected=max(obj.FrameIndex,selected);
                if selected==obj.FrameIndex
                    obj.Status="expected_repeat";
                elseif selected>obj.FrameIndex+1
                    obj.Status="source_frame_skip";
                else
                    obj.Status="new_frame";
                end
                obj.FrameIndex=selected;
            end
            obj.ScreenFcn('DrawTexture',obj.Window,obj.Textures(obj.FrameIndex),[],rect);
        end
        function value=info(obj)
            k=obj.FrameIndex;
            value=struct('pts',obj.Map.source_pts_s(k), ...
                'raw_pts',obj.Map.source_pts_s(k),'pts_offset',0, ...
                'index',k,'decoded_sequence',k,'source_frame_index',k-1, ...
                'texture_handle',obj.Textures(k),'status',obj.Status);
        end
        function stop(obj)
            obj.Running=false;
        end
        function closeCurrent(obj)
            obj.stop();
            textures=obj.Textures(obj.Textures>0);
            obj.Textures=[];
            if ~isempty(textures), obj.ScreenFcn('Close',textures); end
            obj.Map=struct(); obj.Path=""; obj.FrameIndex=1;
            obj.StartFlip=NaN; obj.Status="closed";
        end
        function close(obj)
            obj.closeCurrent();
        end
        function delete(obj)
            try, obj.close(); catch, end
        end
    end
end
