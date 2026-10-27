classdef Session < handle
    %SESSION Coordinate one scanner-free run and own its resources.
    % Read run() for the experiment sequence. Longer methods live beside this
    % class in @Session; see README.md for the method map and timing contract.
    properties (SetAccess = private)
        % Configuration, identities, and persisted records.
        Config
        Provenance
        RunId
        OutputDir
        Inventory
        Answers
        Log
        TrialContexts = {}

        % Audio, eye tracking, and media resources.
        Triggers
        Eye
        Player
        MovieCache
        MovieDestinationRect = [] % Fitted source rectangle, cached before onset.
        NativeTrials = struct([])
        NativePendingTrials = struct([])
        StartupLoading = struct()
        LoadingProgressBucket = -1

        % Display timing: absolute timestamps use the GetSecs clock.
        Window = []
        IFI = NaN
        IFIEstimated = false
        IFISamples = NaN
        IFIStddev = NaN
        DisplayTiming = struct()
        RefreshGuard = struct() % Initial-fixation refresh check; see checkRefreshGuard.
        VBLDuration = 0 % PTB blanking correction for predicted onsets, fixed at open.
        LastVBL = NaN
        NextTrialOnset = NaN
        SavedSkipSync = []
        EffectiveSkipSync = NaN

        % Input and the active phase (also used to attribute aborts).
        QueueActive = false
        InputFcn = []
        QuitInputTime = NaN
        CurrentContext = []
        CurrentRunPhase = ""
        RunContext = []

        % Lifecycle: stopping presentation, saving output, and closing are distinct.
        StartTime = NaN
        StopTime = NaN
        RunStarted = false
        RunEndHandled = false % One end attempt claimed, including disabled output.
        RunEndMarkerId = ""
        RunEndFlip = []
        PresentationStopped = false
        PresentationCleanupError = ""
        Finalized = false
        FinalStatus = ""
        Closed = false
    end

    methods
        % Public lifecycle. ephys.runSession calls run -> stopPresentation -> finish;
        % the onCleanup guard calls close on both normal and exceptional exits.
        function obj = Session(config,provenance,runId,backend,inputFcn)
            if nargin < 4
                backend = [];
            end
            if nargin < 5
                inputFcn = [];
            end
            assert(isempty(inputFcn) || (config.debug && isa(inputFcn,'function_handle')), ...
                'ephys:DebugInput','A scripted input callback requires Debug mode.');
            obj.InputFcn = inputFcn;
            obj.initialize(config,provenance,runId,backend);
        end

        open(obj)

        function run(obj)
            % Cold device/movie initialization must precede elevated scheduling.
            % Also clear a nonzero priority inherited from an earlier script.
            if exist('Priority','file')>0
                Priority(0);
            end
            obj.open();
            obj.StartTime = GetSecs;
            if obj.Eye.Enabled
                obj.Eye.calibrate();
                obj.Eye.start();
            end
            try
                % Loading and instructions precede the recorded run boundary.
                obj.preloadStartup();
                obj.instruction();
                % Device/movie startup and the Space wait are complete.
                % Raise priority only after Space, before the run-start marker.
                if ~obj.Config.debug
                    Priority(MaxPriority(obj.Window));
                end
                obj.beginRun();
                preparedContext = [];
                if obj.Config.task_kind == "video" && ...
                        obj.Config.protocol.video_initial_fixation_s>0
                    % Keep first-movie decoding outside the fixed baseline.
                    preparedContext = obj.TrialContexts{1};
                    obj.prepareVideo(preparedContext,obj.Config.schedule(1));
                    obj.checkQuit(preparedContext,"preparation");
                    firstBaselineFlip = obj.Log.FlipCount+1;
                    obj.runFixation("initial_fixation", ...
                        obj.Config.protocol.video_initial_fixation_s);
                    % Stop before trial 1 if the baseline loop missed refreshes.
                    obj.checkRefreshGuard(firstBaselineFlip);
                end
                % Present the saved schedule exactly once, in order.
                for trialNr = 1:numel(obj.Config.schedule)
                    name = obj.Config.schedule(trialNr);
                    if obj.Config.task_kind == "video"
                        obj.videoTrial(trialNr,name,preparedContext);
                        preparedContext = [];
                    else
                        obj.memoryTrial(trialNr,name);
                    end
                    obj.Triggers.poll();
                    obj.CurrentContext = [];
                end
                if obj.Config.task_kind == "video" && ...
                        obj.Config.protocol.video_final_fixation_s>0
                    obj.runFixation("final_fixation", ...
                        obj.Config.protocol.video_final_fixation_s);
                end
                obj.endRun("complete");
            catch cause
                if isfield(obj.StartupLoading,'status') && obj.StartupLoading.status == "loading"
                    obj.StartupLoading.status = "aborted";
                    obj.StartupLoading.end_getsecs = GetSecs;
                    obj.StartupLoading.texture_bytes = obj.MovieCache.TextureBytes;
                end
                if ~isempty(obj.CurrentContext)
                    kind = "trial_abort";
                    phase = "abort";
                    if obj.CurrentContext.trial_nr == 0
                        phase = obj.CurrentRunPhase;
                        kind = phase+"_abort";
                    end
                    ev = obj.Log.event(obj.CurrentContext,kind,phase,GetSecs,[]);
                    ev.status = "aborted";
                    ev.detail = string(cause.message);
                    obj.Log.updateLastEvent(ev);
                end
                rethrow(cause);
            end
            obj.StopTime = GetSecs;
        end

        % Save after presentation stops. Repeated calls return the saved status.
        function finalStatus = finish(obj,status,reason)
            if obj.Finalized
                finalStatus = obj.FinalStatus;
                return;
            end
            if isnan(obj.StartTime)
                obj.StartTime = ephys.getTimeOrNaN();
            end
            if isnan(obj.StopTime)
                obj.StopTime = ephys.getTimeOrNaN();
            end
            if strlength(obj.PresentationCleanupError)>0
                status = "aborted";
                reason = string(reason) + "; presentation cleanup: " + ...
                    obj.PresentationCleanupError;
            end
            if obj.RunStarted && ~obj.RunEndHandled
                try
                    obj.endRun(status);
                catch cause
                    status = "aborted";
                    reason = string(reason)+"; run end marker: "+cause.message;
                end
            end
            try
                obj.Triggers.close();
            catch cause
                status = "aborted";
                reason = string(reason) + "; trigger cleanup: " + cause.message;
            end
            try
                obj.Eye.stopAndTransfer();
            catch cause
                status = "aborted";
                reason = string(reason) + "; EyeLink transfer: " + cause.message;
            end
            if obj.Log.EventCount>0
                lastEvent = obj.Log.lastEvent();
                if lastEvent.event_type == "run_end"
                    lastEvent.status = string(status);
                    obj.Log.updateLastEvent(lastEvent);
                end
            end
            ephys.writeOutput(obj,status,reason);
            obj.Finalized = true;
            obj.FinalStatus = string(status);
            finalStatus = obj.FinalStatus;
        end

        stopPresentation(obj)

        function close(obj)
            if obj.Closed
                return;
            end
            obj.Closed = true;
            obj.stopPresentation();
            % OutputDir is set only after this Session created the folder, so a
            % failed construction never writes into an existing recording.
            if ~obj.Finalized && ~isempty(obj.OutputDir) && isfolder(obj.OutputDir)
                try
                    obj.finish("aborted","Closed before completion");
                catch cause
                    warning('ephys:PartialOutput','%s',cause.message);
                end
            end
            try
                obj.Eye.close();
            catch cause
                warning('ephys:EyeCleanup','%s',cause.message);
            end
            try
                obj.Triggers.close();
            catch cause
                warning('ephys:TriggerCleanup','%s',cause.message);
            end
        end

        function delete(obj)
            obj.close();
        end

    end

    methods (Access = private)
        % Setup, loading, and instructions.
        initialize(obj,config,provenance,runId,backend)

        preloadStartup(obj)

        instruction(obj)

        function loadingProgress(obj,ctx,movieNumber,total,fraction)
            obj.checkQuit(ctx,"loading");
            bucket = floor(fraction*10);
            if bucket <= obj.LoadingProgressBucket
                return;
            end
            obj.LoadingProgressBucket = bucket;
            c = obj.Config;
            Screen('FillRect',obj.Window,cell2mat(c.stimulus.background_rgb255));
            Screen('TextSize',obj.Window,c.instructions.text_height_px);
            text = sprintf('Loading videos...\n\nVideo %d / %d\nPreparing: %d%%\n\nPlease wait. Press %s to cancel.', ...
                movieNumber,total,round(fraction*100),upper(char(c.input.quit_key)));
            DrawFormattedText(obj.Window,text,'center','center',[255 255 255]);
            ephys.drawPhotodiode(obj.Window,c,"off");
            obj.StartupLoading.flip_count = obj.StartupLoading.flip_count+1;
            obj.flip(ctx,"loading",obj.StartupLoading.flip_count, ...
                ephys.noFrame("loading"),"off",NaN);
        end

        function drawInstructions(obj)
            background = cell2mat(obj.Config.stimulus.background_rgb255);
            Screen('FillRect',obj.Window,background);
            Screen('TextSize',obj.Window,obj.Config.instructions.text_height_px);
            label = obj.Config.instructions.video;
            if obj.Config.task_kind == "memory"
                label = obj.Config.instructions.memory;
            end
            label = string(label)+sprintf('\n\nPress %s to start.', ...
                upper(char(obj.Config.input.instruction_continue_key)));
            DrawFormattedText(obj.Window,char(label),'center','center',[255 255 255]);
            ephys.drawPhotodiode(obj.Window,obj.Config,"off");
        end

    end

    methods (Access = private)
        % Trial preparation and presentation.
        prepareVideo(obj,ctx,name)

        function prepareAhead(obj,ctx,deadline)
            if string(obj.Config.playback.backend) ~= "native"
                return;
            end
            nextTrialNr = obj.MovieCache.nextToPrepare(ctx.trial_nr);
            if isempty(nextTrialNr)
                return;
            end
            nextContext = obj.TrialContexts{nextTrialNr};
            event = obj.Log.event(nextContext,"native_lookahead_start","pre_fixation",GetSecs,[]);
            event.planned_deadline_getsecs = deadline;
            event.detail = "Prepared during trial "+string(ctx.trial_nr)+" pre-fixation";
            obj.Log.updateLastEvent(event);
            % Reserve one display interval for drawing the actual movie onset.
            loaded = obj.MovieCache.preload(nextTrialNr,obj.Config.protocol.video_duration_s, ...
                @() obj.checkQuit(ctx,"pre_fixation"),deadline-obj.IFI);
            completed = GetSecs;
            kind = "native_lookahead_ready";
            if ~loaded, kind = "native_lookahead_deferred"; end
            event = obj.Log.event(nextContext,kind,"pre_fixation",completed,[]);
            event.planned_deadline_getsecs = deadline;
            event.status = "ready_before_deadline";
            if ~loaded
                event.status = "deferred_by_budget";
            elseif completed>deadline-obj.IFI
                event.status = "ready_after_deadline";
                event.detail = "Loading extended the visible fixation; actual onset is logged.";
            end
            obj.Log.updateLastEvent(event);
        end

        videoTrial(obj,trialNr,movieName,preparedContext)

        [row,marker,plannedOnset] = onsetFlip(obj,ctx,phase,eventType,plannedOnset)

        [row,marker,plannedOnset] = steadyOnsetFlip(obj,ctx,holdPhase,anchorFlip,phase,eventType,plannedOnset)

        raw = submitOnsetFlip(obj,ctx,phase,requestTime,predictedOnset,deferred)

        function value = usesDeferredOnset(obj)
            value = ismac && obj.DisplayTiming.external_display_backend;
        end

        function value = usesSteadyFlip(obj)
            % display.steady_flip applies to the video task's WAV-marked onsets.
            value = obj.Config.task_kind == "video" && ...
                isfield(obj.Config.display,'steady_flip') && obj.Config.display.steady_flip;
        end

        function [kind,diode] = onsetFrameKind(obj,phase)
            % A video onset shows its first frame; other boundaries show fixation.
            kind = "fixation";
            diode = "off";
            if phase == "video"
                kind = "video";
                if obj.Config.photodiode.enabled, diode = "on"; end
            end
        end

        function marker = scheduleOnsetMarker(obj,ctx,eventType,predictedOnset)
            % Run-end markers belong to the run context and are tracked for endRun.
            markerContext = ctx;
            if eventType == "run_end", markerContext = obj.RunContext; end
            marker = obj.Triggers.schedule(eventType,markerContext,predictedOnset);
            if eventType == "run_end", obj.RunEndMarkerId = marker.event_id; end
        end

        memoryTrial(obj,trialNr,pictureName)

        runFixation(obj,phase,duration)

    end

    methods (Access = private)
        % Run boundaries and scheduled audio/visual association.
        function beginRun(obj)
            obj.RunStarted = true;
            if ~obj.Config.markers.run_boundary_enabled
                return;
            end
            % Renew the refresh anchor after an arbitrarily long instruction
            % wait, keeping the instruction image visible until run start.
            obj.drawInstructions();
            obj.flip(obj.RunContext,"instruction_ready",1,ephys.noFrame("instruction"),"off",NaN);
            [startFlip,marker] = obj.onsetFlip(obj.RunContext,"run_start","run_start",NaN);
            event = obj.Log.event(obj.RunContext,"run_start","run_start", ...
                startFlip.stimulus_onset_getsecs,startFlip);
            event.marker_event_id = marker.event_id;
            obj.Log.updateLastEvent(event);
            obj.Triggers.associate(marker.event_id,obj.markerFlip(startFlip));
            % A short boundary interval is outside the fixed trial/baseline.
            obj.NextTrialOnset = max(startFlip.stimulus_onset_getsecs+obj.IFI, ...
                obj.Triggers.nextAllowedRequestTime()+obj.IFI/2);
        end

        function checkRefreshGuard(obj,firstFlip)
            % An acquisition precondition, not a recoverable QC finding: a
            % failure raises before the first trial, and the usual abort path
            % saves the logs and attempts one run end. Trial 1 is drawn next,
            % so only numeric slot indices are read here (about 1 ms); the
            % interval metrics are added by writeOutput after presentation.
            c = obj.Config;
            minimum = [];
            if isfield(c.display,'refresh_guard_min_fraction')
                minimum = c.display.refresh_guard_min_fraction;
            end
            lastFlip = obj.Log.FlipCount;
            presented = sum(isfinite(obj.Log.flipValues("refresh_index",firstFlip,lastFlip)));
            duration = c.protocol.video_initial_fixation_s;
            guard = ephys.refreshGuard(presented,"initial_fixation",duration,obj.IFI,minimum);
            if guard.status == "failed"
                % The run stops here, so the full analysis can name the interval.
                guard = ephys.refreshGuard(obj.Log.flipRange(firstFlip,lastFlip), ...
                    "initial_fixation",duration,obj.IFI,minimum);
            end
            guard.first_flip_seq = firstFlip;
            guard.last_flip_seq = lastFlip;
            obj.RefreshGuard = guard;
            event = obj.Log.event(obj.RunContext,"refresh_guard", ...
                "initial_fixation_end",GetSecs,[]);
            event.status = obj.RefreshGuard.status;
            event.detail = obj.RefreshGuard.detail;
            obj.Log.updateLastEvent(event);
            if obj.RefreshGuard.status == "failed"
                error('ephys:RefreshGuard','%s',obj.RefreshGuard.message);
            end
        end

        endRun(obj,status)

        function [marker,plannedOnset] = reserveMarker(obj,eventType,ctx,plannedOnset)
            % All times are absolute GetSecs seconds. Audio is reserved for the
            % predicted visual onset; the actual Flip is associated afterward.
            % plannedOnset is retained for the visual request and never replaced
            % with an observed timestamp. Offsets are reported by TriggerOutput.
            if ~isfinite(plannedOnset)
                plannedOnset = max(GetSecs+obj.Config.markers.wav.minimum_lead_s+3*obj.IFI, ...
                    obj.Triggers.nextAllowedRequestTime()+3*obj.IFI);
            end
            predictedVisualOnset = ephys.predictVisualOnset(obj.LastVBL, ...
                obj.computeFlipRequestTime(plannedOnset),obj.IFI,obj.VBLDuration);
            marker = obj.Triggers.schedule(eventType,ctx,predictedVisualOnset);
        end

        function value = markerFlip(~,row)
            value = struct('seq',row.flip_seq, ...
                'stimulus',row.stimulus_onset_getsecs, ...
                'frame_ready_getsecs',row.frame_ready_getsecs, ...
                'flip_submit_getsecs',row.flip_submit_getsecs, ...
                'flip_return_getsecs',row.flip_return_getsecs, ...
                'submission_mode',row.submission_mode);
        end

    end

    methods (Access = private)
        % Refresh loops and drawing. These paths do no file writes or full decodes.
        repeatFixation(obj,ctx,phase,onsetFlip,duration)

        row = fixationRefresh(obj,ctx,phase,n,anchor,phaseEnd,previousIndex)

        function repeatVideo(obj,ctx,onsetFlip,duration)
            phaseEnd = onsetFlip.stimulus_onset_getsecs+duration;
            flipNumber = 1;
            while obj.LastVBL+1.5*obj.IFI < phaseEnd
                flipNumber = flipNumber+1;
                obj.videoFlip(ctx,flipNumber,NaN);
                obj.checkQuit(ctx,"video");
            end
        end

        function row = videoFlip(obj,ctx,flipNumber,plannedOnset)
            photodiodeState = "off";
            if obj.Config.photodiode.enabled
                photodiodeState = "on";
            end
            frame = obj.drawFrame("video",photodiodeState);
            row = obj.flip(ctx,"video",flipNumber,frame,photodiodeState,plannedOnset);
        end

        function frame = drawFrame(obj,kind,photodiodeState)
            background = cell2mat(obj.Config.stimulus.background_rgb255);
            Screen('FillRect',obj.Window,background);
            frame = ephys.noFrame("fixation");
            if kind == "video"
                obj.Player.draw(obj.MovieDestinationRect,max(obj.LastVBL+obj.IFI,GetSecs));
                frame = obj.Player.info();
            end
            ephys.drawFixation(obj.Window,obj.Config);
            ephys.drawPhotodiode(obj.Window,obj.Config,photodiodeState);
        end

        function row = fixationFlip(obj,ctx,phase,flipNumber,plannedOnset,photodiodeState)
            frame = obj.drawFrame("fixation",photodiodeState);
            row = obj.flip(ctx,phase,flipNumber,frame,photodiodeState,plannedOnset);
        end

        function state = fixationDiode(obj,n)
            state = "off";
            if n == 1 && obj.Config.photodiode.enabled && ...
                    obj.Config.photodiode.fixation_onset_enabled
                state = "on";
            end
        end

        row = flip(obj,ctx,phase,n,frame,diode,plannedOnset)

        function flipRequestTime = computeFlipRequestTime(obj,plannedOnset)
            if isnan(obj.LastVBL)
                flipRequestTime = 0;
                if isfinite(plannedOnset)
                    flipRequestTime = plannedOnset-0.5*obj.IFI;
                end
            else
                flipRequestTime = obj.LastVBL+0.5*obj.IFI;
                if isfinite(plannedOnset)
                    flipRequestTime = max(flipRequestTime,plannedOnset-0.5*obj.IFI);
                end
            end
        end

    end

    methods (Access = private)
        % Timestamped input and abort attribution.
        [key,inputTime] = nextKey(obj)

        function checkQuit(obj,ctx,phase)
            if obj.Config.debug_simulated_input_only && isempty(obj.InputFcn)
                return;
            end
            while true
                [key,time] = obj.nextKey();
                if strlength(key) == 0
                    break;
                end
                if key == lower(string(obj.Config.input.quit_key))
                    obj.abortFromKey(ctx,phase,key,time);
                end
                obj.logKey(ctx,phase,key,time,"key_press");
            end
        end

        function abortFromKey(obj,ctx,phase,key,time)
            obj.QuitInputTime = time;
            obj.logKey(ctx,phase,key,time,"quit_key");
            try
                obj.Triggers.cancelPending();
            catch cause
                warning('ephys:AudioCancellation','%s',cause.message);
            end
            error('ephys:UserAbort','Participant/operator pressed quit.');
        end

        function logKey(obj,ctx,phase,key,time,kind)
            ev = obj.Log.event(ctx,kind,phase,time,[]);
            ev.response = key;
            ev.input_getsecs = time;
            ev.simulated = obj.Config.debug_simulated_input_only;
            obj.Log.updateLastEvent(ev);
        end

    end

end
