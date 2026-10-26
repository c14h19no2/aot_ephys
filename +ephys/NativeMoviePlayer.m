classdef NativeMoviePlayer < handle
    %NATIVEMOVIEPLAYER No-drop decoder anchored to the first displayed Flip.
    % Match source indices to the offline PTS map; record delivery anomalies
    % without interrupting presentation. Unmatched source indices stay NaN.
    properties (SetAccess=private)
        Window
        Playback
        Map
        Path
        ScreenFcn
        ClockFcn
        Movie=[]
        Texture=[]
        PendingTexture=[]
        PendingIndex=NaN
        FrameIndex=0
        FetchedCount=0
        DecoderPTS=[]
        SourceIndices=[]
        PresentationPTS=[]
        FrameQCFlags=strings(1,0)
        QCIssues=struct('kind',{},'decoded_sequence',{},'expected',{},'observed',{})
        PreparationDeadline=Inf
        PreparationCompletedTime=NaN
        PreparationOverrun=0
        EarlyEnd=false
        DisplaySkippedIndices=[]
        Running=false
        DecoderPlaying=false
        Ended=false
        StartFlip=NaN
        StartCommandTime=NaN
        StartCommandCompletedTime=NaN
        DecodeStartTime=NaN
        MaxPollSeconds=0
        Status="unprepared"
        PTBDropped=NaN
    end
    methods
        function obj=NativeMoviePlayer(window,playback,map,screenFcn,clockFcn)
            if nargin<4, screenFcn=@Screen; end
            if nargin<5, clockFcn=@GetSecs; end
            obj.Window=window; obj.Playback=playback; obj.Map=map;
            obj.Path=string(map.source); obj.ScreenFcn=screenFcn; obj.ClockFcn=clockFcn;
            obj.DecoderPTS=nan(1,map.frame_count);
            obj.SourceIndices=nan(1,map.frame_count);
            obj.PresentationPTS=nan(1,map.frame_count);
            obj.FrameQCFlags=strings(1,map.frame_count);
        end
        function prepare(obj,minimumDuration,quitFcn,deadline)
            if nargin<3, quitFcn=[]; end
            if nargin<4, deadline=Inf; end
            assert(isempty(obj.Movie),'ephys:NativeState','Native handle already prepared.');
            if obj.Map.duration_s+1e-6<minimumDuration
                obj.addQC("mapped_duration_shorter_than_slot",NaN,minimumDuration,obj.Map.duration_s);
            end
            began=obj.ClockFcn();
            obj.PreparationDeadline=deadline;
            try
                % 4 disables automatic dropping and enables buffered decoding.
                % Independent synchronous opens happen only during loading or
                % static fixation. The decoder then runs in the background.
                % The global async-open route (5) duplicated a PTS in earlier
                % probes, so it is deliberately not used by this backend.
                flags=2;
                if isfield(obj.Playback,'native_disable_hw_decode') && obj.Playback.native_disable_hw_decode
                    flags=flags+4;
                end
                obj.Movie=obj.ScreenFcn('OpenMovie',obj.Window,char(obj.Map.path), ...
                    4,obj.Playback.native_buffer_s,flags);
                obj.ScreenFcn('SetMovieTimeIndex',obj.Movie,0);
                obj.DecodeStartTime=obj.ClockFcn();
                obj.ScreenFcn('PlayMovie',obj.Movie,1,0,0);
                obj.DecoderPlaying=true;
                while true
                    if ~isempty(quitFcn), quitFcn(); end
                    [texture,pts]=obj.ScreenFcn('GetMovieImage',obj.Window,obj.Movie,0);
                    if texture<0, error('ephys:NativeFirstFrame','No native first frame.'); end
                    if texture>0
                        obj.Texture=texture;
                        obj.register(pts);
                        break;
                    end
                    assert(obj.ClockFcn()<began+obj.Playback.native_prepare_timeout_s, ...
                        'ephys:NativeFirstFrameTimeout', ...
                        'No drawable native first frame within the preparation timeout.');
                    % First-frame preparation is outside video presentation.
                    pause(.001);
                end
                obj.ScreenFcn('PreloadTextures',obj.Window,obj.Texture);
                obj.PreparationCompletedTime=obj.ClockFcn();
                obj.PreparationOverrun=max(0,obj.PreparationCompletedTime-deadline);
                if obj.PreparationOverrun>0
                    obj.addQC("load_deadline_overrun",NaN,deadline,obj.PreparationCompletedTime);
                end
                obj.Status="first_frame_prepared";
            catch cause
                obj.closeCurrent();
                rethrow(cause);
            end
        end
        function resident=ensureResident(obj)
            resident=obj.ScreenFcn('PreloadTextures',obj.Window,obj.Texture);
        end
        function start(obj,actualFlip)
            assert(~obj.Running && obj.FrameIndex==0 && obj.FetchedCount==1, ...
                'ephys:FirstFrame','Native playback must start from its held first decoded texture.');
            obj.StartCommandTime=obj.ClockFcn();
            obj.StartFlip=actualFlip;
            % Do not restart or seek a decoder which has already buffered.
            obj.Running=true;
            obj.StartCommandCompletedTime=obj.ClockFcn();
        end
        function draw(obj,rect,predictedOnset)
            assert(~isempty(obj.Texture),'ephys:NoMovieFrame','Prepare before drawing.');
            if obj.Running
                elapsed=max(0,predictedOnset-obj.StartFlip);
                previous=obj.FrameIndex;
                obj.Status="expected_repeat";
                % No blocking movie fetches and bounded work in each refresh.
                for attempt=1:8
                    if isempty(obj.PendingTexture) && ~obj.Ended
                        began=obj.ClockFcn();
                        [texture,pts]=obj.ScreenFcn('GetMovieImage',obj.Window,obj.Movie,0);
                        obj.MaxPollSeconds=max(obj.MaxPollSeconds,obj.ClockFcn()-began);
                        if texture<0
                            obj.Ended=true;
                            if obj.FetchedCount<obj.Map.frame_count
                                obj.EarlyEnd=true;
                                obj.addQC("early_end_of_stream",obj.FetchedCount, ...
                                    obj.Map.frame_count,obj.FetchedCount);
                            end
                        elseif texture>0
                            % Own every delivered texture, including anomalous frames.
                            obj.PendingTexture=texture;
                            obj.PendingIndex=obj.register(pts);
                        end
                    end
                    if isempty(obj.PendingTexture), break; end
                    due=obj.PresentationPTS(obj.PendingIndex+1);
                    if due>elapsed+1e-9, break; end
                    obj.ScreenFcn('Close',obj.Texture);
                    obj.Texture=obj.PendingTexture;
                    obj.FrameIndex=obj.PendingIndex;
                    obj.PendingTexture=[]; obj.PendingIndex=NaN;
                    obj.Status="new_frame";
                end
                if obj.FrameIndex>previous+1
                    obj.DisplaySkippedIndices=[obj.DisplaySkippedIndices ...
                        obj.SourceIndices(previous+2:obj.FrameIndex)];
                    obj.Status="source_frame_skip";
                elseif isempty(obj.PendingTexture) && ~obj.Ended && ...
                        obj.FetchedCount<obj.Map.frame_count && ...
                        obj.Map.relative_pts_s(obj.FetchedCount+1)<=elapsed+1e-9
                    obj.Status="decoder_underrun";
                end
                if obj.EarlyEnd, obj.Status="end_of_stream"; end
            end
            obj.ScreenFcn('DrawTexture',obj.Window,obj.Texture,[],rect);
        end
        function value=info(obj)
            k=obj.FrameIndex+1;
            source=obj.SourceIndices(k); pts=NaN;
            if isfinite(source), pts=obj.Map.source_pts_s(source+1); end
            flags=obj.FrameQCFlags(k);
            if obj.EarlyEnd
                flags=[flags,"early_end_of_stream"];
                flags=join(flags(strlength(flags)>0),"|");
            end
            value=struct('pts',pts, ...
                'raw_pts',obj.DecoderPTS(k),'pts_offset',obj.Map.source_pts_s(1), ...
                'index',k,'decoded_sequence',k,'source_frame_index',source, ...
                'texture_handle',obj.Texture,'status',obj.Status,'qc_flags',flags);
        end
        function stop(obj)
            if ~isempty(obj.Movie) && obj.DecoderPlaying
                obj.PTBDropped=obj.ScreenFcn('PlayMovie',obj.Movie,0);
            end
            obj.Running=false; obj.DecoderPlaying=false;
        end
        function value=summary(obj)
            value=struct('source',obj.Path,'native_path',string(obj.Map.path), ...
                'decode_start_getsecs',obj.DecodeStartTime,'first_flip_getsecs',obj.StartFlip, ...
                'decoded_source_indices',obj.SourceIndices(1:obj.FetchedCount), ...
                'decoder_pts_s',obj.DecoderPTS(1:obj.FetchedCount), ...
                'display_skipped_source_indices',obj.DisplaySkippedIndices, ...
                'max_nonblocking_fetch_s',obj.MaxPollSeconds,'ptb_dropped',obj.PTBDropped, ...
                'preparation_deadline_getsecs',obj.PreparationDeadline, ...
                'preparation_completed_getsecs',obj.PreparationCompletedTime, ...
                'preparation_overrun_s',obj.PreparationOverrun,'qc_issues',obj.QCIssues);
        end
        function closeCurrent(obj)
            % Attempt every resource even if one PTB cleanup call fails.
            first=[];
            try, obj.stop(); catch cause, first=cause; end
            for texture=[obj.Texture obj.PendingTexture]
                try, obj.ScreenFcn('Close',texture);
                catch cause, if isempty(first), first=cause; end, end
            end
            if ~isempty(obj.Movie)
                try, obj.ScreenFcn('CloseMovie',obj.Movie);
                catch cause, if isempty(first), first=cause; end, end
            end
            obj.Movie=[]; obj.Texture=[]; obj.PendingTexture=[];
            obj.Running=false; obj.DecoderPlaying=false; obj.Status="closed";
            if ~isempty(first), rethrow(first); end
        end
        function delete(obj)
            try, obj.closeCurrent(); catch, end
        end
    end
    methods (Access=private)
        function index=register(obj,pts)
            index=obj.FetchedCount;
            expected=NaN; flags=strings(1,0);
            if index<obj.Map.frame_count
                expected=obj.Map.relative_pts_s(index+1);
            else
                flags(end+1)="extra_native_frame";
            end
            if ~isfinite(pts) || ~isfinite(expected) || abs(pts-expected)>1e-6
                flags(end+1)="pts_sequence_mismatch";
            end
            % Identity is inferred only from a unique matching source PTS,
            % never from the count when the decoder changes delivery order.
            matched=find(isfinite(pts) & abs(obj.Map.relative_pts_s-pts)<=1e-6);
            source=NaN;
            if isscalar(matched), source=matched-1; end
            if ~isfinite(source), flags(end+1)="unresolved_source_frame"; end
            for flag=flags
                obj.addQC(flag,index+1,expected,pts);
            end
            due=pts;
            if ~isfinite(due)
                due=expected;
                if ~isfinite(due)
                    tailDuration=max(eps,obj.Map.duration_s-obj.Map.relative_pts_s(end));
                    due=obj.PresentationPTS(index)+tailDuration;
                end
            end
            if index>0, due=max(due,obj.PresentationPTS(index)); end
            obj.FetchedCount=index+1;
            obj.DecoderPTS(index+1)=pts;
            obj.SourceIndices(index+1)=source;
            obj.PresentationPTS(index+1)=max(0,due);
            obj.FrameQCFlags(index+1)=join(flags,"|");
        end
        function addQC(obj,kind,sequence,expected,observed)
            obj.QCIssues(end+1)=struct('kind',string(kind), ...
                'decoded_sequence',sequence,'expected',expected,'observed',observed);
        end
    end
end
