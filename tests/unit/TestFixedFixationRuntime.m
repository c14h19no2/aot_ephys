classdef TestFixedFixationRuntime < matlab.unittest.TestCase
    % Exercise the real Session refresh loop using an isolated clock/display.
    properties
        Folder
        SteadyFlip = false % display.steady_flip for createJob; held unless a test sets it.
        FinalSeconds = 0 % Final baseline duration for createJob.
    end
    methods (TestMethodSetup)
        function isolateDevices(tc)
            fixture=tc.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            tc.Folder=fixture.Folder;
            tc.writeStub('Screen',[
                "function varargout=Screen(varargin)"
                "[varargout{1:nargout}]=TestFixedFixationRuntime.sim('screen',varargin{:});"
                "end"]);
            tc.writeStub('GetSecs',[
                "function value=GetSecs"
                "value=TestFixedFixationRuntime.sim('time');"
                "end"]);
            tc.writeStub('WaitSecs',[
                "function WaitSecs(varargin)"
                "TestFixedFixationRuntime.sim('wait',varargin{:});"
                "end"]);
            tc.writeStub('ismac',[
                "function value=ismac"
                "value=TestFixedFixationRuntime.sim('platform');"
                "end"]);
            for name=["HideCursor","ShowCursor","Priority","DrawFormattedText"]
                tc.writeStub(name,["function value="+name+"(varargin)";"value=0;";"end"]);
            end
            TestFixedFixationRuntime.sim('reset');
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(tc.Folder));
            TestFixedFixationRuntime.clearStubs();
            tc.addTeardown(@TestFixedFixationRuntime.clearStubs);
        end
    end
    methods (Test)
        function baselineRequestsStayOnOriginalGridAndEndAtOriginalBoundary(tc)
            job=tc.createJob();
            job.run();
            rows=job.Log.Flips(1:job.Log.FlipCount);
            rows=rows(ismember([rows.phase],["initial_fixation","initial_fixation_end"]));
            refresh=rows(isfinite([rows.refresh_index]));
            tc.verifyNotEmpty(refresh);
            onset=rows(1).stimulus_onset_getsecs;
            expected=onset+[refresh.refresh_index]*job.IFI;
            tc.verifyEqual([refresh.refresh_target_getsecs],expected,'AbsTol',1e-10);
            tc.verifyEqual([refresh.requested_deadline_getsecs],expected-.5*job.IFI,'AbsTol',1e-10);
            tc.verifyEqual(rows(end).stimulus_onset_getsecs,onset+.2,'AbsTol',1e-10);
            tc.verifyTrue(all([refresh.refresh_skipped_slots]==0));
        end
        function drawingStallSkipsExpiredSlotsWithoutMovingThePhaseClock(tc)
            TestFixedFixationRuntime.sim('set','stallOnDraw',3);
            TestFixedFixationRuntime.sim('set','stallSeconds',.065);
            job=tc.createJob();
            job.run();
            rows=job.Log.Flips(1:job.Log.FlipCount);
            rows=rows(ismember([rows.phase],["initial_fixation","initial_fixation_end"]));
            refresh=rows(isfinite([rows.refresh_index]));
            onset=rows(1).stimulus_onset_getsecs;
            tc.verifyGreaterThan(refresh(1).refresh_index,1);
            tc.verifyGreaterThan(refresh(1).refresh_skipped_slots,0);
            tc.verifyEqual([refresh.refresh_target_getsecs], ...
                onset+[refresh.refresh_index]*job.IFI,'AbsTol',1e-10);
            tc.verifyTrue(all([refresh.flip_submit_getsecs]<[refresh.refresh_target_getsecs]));
            tc.verifyEqual(rows(end).stimulus_onset_getsecs,onset+.2,'AbsTol',1e-10);
        end
        function quitDetectedAfterPreparationPreventsThePendingRefresh(tc)
            TestFixedFixationRuntime.sim('set','stallOnDraw',3);
            TestFixedFixationRuntime.sim('set','stallSeconds',.010);
            TestFixedFixationRuntime.sim('set','quitAt',10+1/60+.005);
            job=tc.createJob();
            tc.verifyError(@() job.run(),'ephys:UserAbort');
            state=TestFixedFixationRuntime.sim('state');
            tc.verifyEqual(numel(state.requests),2);
            tc.verifyEqual(job.Log.FlipCount,2);
            tc.verifyEqual(job.QuitInputTime,10+1/60+.010,'AbsTol',1e-10);
        end
        function macGuardReselectsAfterWaitOversleepWithoutCatchupFlips(tc)
            % Select the guard explicitly so this test also runs on Windows.
            TestFixedFixationRuntime.sim('set','macBackend',true);
            TestFixedFixationRuntime.sim('set','imagingMode',2^20);
            TestFixedFixationRuntime.sim('set','waitOvershoot',.040);
            job=tc.createJob();
            job.run();
            rows=job.Log.Flips(1:job.Log.FlipCount);
            rows=rows(ismember([rows.phase],["initial_fixation","initial_fixation_end"]));
            refresh=rows(isfinite([rows.refresh_index]));
            onset=rows(1).stimulus_onset_getsecs;
            tc.verifyGreaterThan(refresh(1).refresh_index,1);
            tc.verifyGreaterThan(refresh(1).refresh_skipped_slots,0);
            tc.verifyTrue(all([refresh.submission_mode]=="fixed_fixation_macos_target"));
            tc.verifyTrue(all([refresh.flip_submit_getsecs]< ...
                [refresh.refresh_target_getsecs]+.5*job.IFI));
            tc.verifyEqual([refresh.refresh_target_getsecs], ...
                onset+[refresh.refresh_index]*job.IFI,'AbsTol',1e-10);
            tc.verifyEqual(rows(end).stimulus_onset_getsecs,onset+.2,'AbsTol',1e-10);
        end
        function shortBaselineRecordsTheGuardWithoutDecision(tc)
            job=tc.createJob();
            job.run();
            tc.verifyEqual(job.RefreshGuard.status,"not_evaluated");
            events=job.Log.Events(1:job.Log.EventCount);
            guard=events([events.event_type]=="refresh_guard");
            tc.verifyNumElements(guard,1);
            tc.verifyEqual(guard.status,"not_evaluated");
            tc.verifyEqual(guard.trial_nr,0);
        end
        function healthyBaselinePassesWithoutDelayingTheFirstTrial(tc)
            job=tc.createJob(1.2);
            job.run();
            tc.verifyEqual(job.RefreshGuard.status,"passed");
            tc.verifyEqual(job.RefreshGuard.presented_slots,job.RefreshGuard.available_slots);
            % The live decision reads slot indices only; metrics come after the run.
            tc.verifyTrue(isnan(job.RefreshGuard.interval_median_ms));
            rows=job.Log.Flips(1:job.Log.FlipCount);
            baseline=rows([rows.phase]=="initial_fixation");
            boundary=rows([rows.phase]=="initial_fixation_end");
            first=rows([rows.phase]=="pre_fixation");
            % Baseline duration and the first trial's refresh are unchanged.
            tc.verifyEqual(boundary.stimulus_onset_getsecs, ...
                baseline(1).stimulus_onset_getsecs+1.2,'AbsTol',1e-10);
            tc.verifyEqual(first(1).stimulus_onset_getsecs, ...
                boundary.stimulus_onset_getsecs+job.IFI,'AbsTol',1e-10);
        end
        function audioIsScheduledOnTheLoggedFlipTimeline(tc)
            job=tc.createJob(.2,true);
            job.run();
            markers=job.Triggers.records();
            tc.verifyEqual(sort([markers.event_type]), ...
                sort(["run_start","blank_onset","blank_offset","blank_onset","blank_offset","run_end"]));
            rows=job.Log.flipRecords();
            for k=1:numel(markers)
                m=markers(k);
                flip=rows([rows.flip_seq]==m.associated_flip_seq);
                tc.verifyNumElements(flip,1);
                % Each pulse targets the frame its Flip request presents: the
                % first refresh after the request on the logged timeline.
                tc.verifyEqual(m.planned_audio_getsecs,flip.stimulus_onset_getsecs, ...
                    'AbsTol',1e-9,char(m.event_type));
                lead=m.planned_audio_getsecs-flip.requested_deadline_getsecs;
                tc.verifyGreaterThan(lead,0,char(m.event_type));
                tc.verifyLessThanOrEqual(lead,job.IFI+1e-9,char(m.event_type));
                if any(m.event_type==["blank_onset","blank_offset"])
                    % Trial boundaries request half a refresh early, in every trial.
                    tc.verifyEqual(lead,.5*job.IFI,'AbsTol',1e-9,char(m.event_type));
                end
            end
        end
        function slowBaselineLoopStopsBeforeTheFirstTrial(tc)
            % Every draw costs 100 ms, so most baseline refresh slots expire.
            TestFixedFixationRuntime.sim('set','stallEachDraw',.1);
            job=tc.createJob(1.2);
            tc.verifyError(@() job.run(),'ephys:RefreshGuard');
            tc.verifyEqual(job.RefreshGuard.status,"failed");
            tc.verifyLessThan(job.RefreshGuard.presented_fraction,.9);
            % A failure stops the run, so its message includes the interval.
            tc.verifyGreaterThan(job.RefreshGuard.interval_median_ms,50);
            tc.verifySubstring(char(job.RefreshGuard.message),'median refresh interval');
            rows=job.Log.Flips(1:job.Log.FlipCount);
            tc.verifyTrue(any([rows.phase]=="initial_fixation_end"));
            tc.verifyTrue(all([rows.trial_nr]==0));
            events=job.Log.Events(1:job.Log.EventCount);
            guard=events([events.event_type]=="refresh_guard");
            tc.verifyNumElements(guard,1);
            tc.verifyEqual(guard.status,"failed");
            tc.verifyFalse(any([events.event_type]=="pre_fixation_onset"));
        end
    end
    methods (Test)
        function acquisitionRunUsesDatedFolderAndKeepsReplacedOutput(tc)
            root=fullfile(tc.Folder,'outputs');
            old=fullfile(root,'2026-10-25','fixed_fixation');
            mkdir(old);
            fid=fopen(fullfile(old,'old_markers.tsv'),'w'); fprintf(fid,'kept\n'); fclose(fid);
            runOutput=struct('root',root,'collection_date',"2026-10-25", ...
                'overwrite',true,'replaced_output',"");
            job=tc.createJob(.2,false,runOutput);
            tc.verifyEqual(job.OutputDir,string(old));
            replaced=job.Config.run_output.replaced_output;
            tc.verifyTrue(startsWith(replaced,string(old)+"_replaced-"));
            tc.verifyTrue(isfile(fullfile(replaced,'old_markers.tsv')));
            tc.verifyEmpty(dir(fullfile(old,'*.tsv')));
            job.run();
            tc.verifyGreaterThan(job.Log.FlipCount,0);
            % A refused repeat must leave the existing recording untouched.
            fid=fopen(fullfile(old,'fixed_fixation_manifest.json'),'w'); fprintf(fid,'kept'); fclose(fid);
            before=string({dir(old).name});
            runOutput.overwrite=false;
            lastwarn('','');
            tc.verifyError(@() tc.createJob(.2,false,runOutput),'ephys:OutputExists');
            % close() on the unfinished object must finish cleanly.
            [~,warningId]=lastwarn;
            tc.verifyNotEqual(warningId,'MATLAB:class:DestructorError');
            tc.verifyEqual(string({dir(old).name}),before);
            tc.verifyEqual(fileread(fullfile(old,'fixed_fixation_manifest.json')),'kept');
        end
    end
    methods (Test)
        function heldModeKeepsOneFlipBeforeEachOnset(tc)
            job=tc.createJob(.2,true);
            job.run();
            tc.verifyEqual(job.DisplayTiming.onset_flip_mode,"held");
            rows=job.Log.flipRecords();
            for trial=1:2
                tc.verifyNumElements(rows([rows.trial_nr]==trial & [rows.phase]=="pre_fixation"),1);
            end
            onsets=rows([rows.phase]=="blank" & [rows.phase_flip_seq]==1);
            tc.verifyEqual(unique([onsets.submission_mode]),"direct");
        end
        function steadyFlipRefreshesEveryFrameUpToEachOnset(tc)
            tc.SteadyFlip=true;
            job=tc.createJob(.2,true);
            job.run();
            tc.verifyEqual(job.DisplayTiming.onset_flip_mode,"steady");
            rows=job.Log.flipRecords();
            markers=job.Triggers.records();
            onsets=markers([markers.event_type]=="blank_onset");
            tc.verifyNumElements(onsets,2);
            lead=job.Config.markers.wav.minimum_lead_s;
            for m=onsets(:)'
                onset=rows([rows.flip_seq]==m.associated_flip_seq);
                held=rows([rows.trial_nr]==onset.trial_nr & [rows.phase]=="pre_fixation");
                anchor=held(1).stimulus_onset_getsecs;
                slot=round(job.Config.protocol.video_pre_fixation_s/job.IFI);
                % Every refresh between the pre-fixation onset and the onset
                % slot was flipped, and the onset landed on its slot.
                tc.verifyEqual([held(2:end).refresh_index],1:slot-1);
                tc.verifyEqual(onset.stimulus_onset_getsecs,anchor+slot*job.IFI,'AbsTol',1e-9);
                tc.verifyEqual(onset.submission_mode,"steady_direct");
                % The WAV targets that slot at the usual lead, and refreshing
                % continued after it was reserved.
                tc.verifyEqual(m.planned_audio_getsecs,onset.stimulus_onset_getsecs,'AbsTol',1e-9);
                tc.verifyGreaterThanOrEqual(m.planned_audio_getsecs-m.write_getsecs,lead);
                tc.verifyTrue(any([held.flip_submit_getsecs]>m.write_getsecs));
            end
        end
        function quitDuringSteadyRefreshCancelsTheReservedOnset(tc)
            tc.SteadyFlip=true;
            TestFixedFixationRuntime.sim('set','quitWhenReserved',true);
            job=tc.createJob(.2,true);
            tc.verifyError(@() job.run(),'ephys:UserAbort');
            job.stopPresentation();
            markers=job.Triggers.records();
            onset=markers([markers.event_type]=="blank_onset");
            tc.verifyNumElements(onset,1);
            tc.verifyEqual(onset.status,"cancelled");
            rows=job.Log.flipRecords();
            tc.verifyFalse(any([rows.phase]=="blank"));
        end
        function steadyFlipRefreshesTheFinalBaselineUpToRunEnd(tc)
            tc.SteadyFlip=true;
            tc.FinalSeconds=.2;
            job=tc.createJob(.2,true);
            job.run();
            rows=job.Log.flipRecords();
            held=rows([rows.phase]=="final_fixation");
            endFlip=rows([rows.phase]=="final_fixation_end");
            tc.verifyNumElements(endFlip,1);
            slot=round(.2/job.IFI);
            tc.verifyEqual([held(2:end).refresh_index],1:slot-1);
            tc.verifyEqual(endFlip.stimulus_onset_getsecs, ...
                held(1).stimulus_onset_getsecs+slot*job.IFI,'AbsTol',1e-9);
            tc.verifyEqual(endFlip.submission_mode,"steady_direct");
            markers=job.Triggers.records();
            runEnd=markers([markers.event_type]=="run_end");
            tc.verifyNumElements(runEnd,1);
            tc.verifyEqual(runEnd.associated_flip_seq,endFlip.flip_seq);
            tc.verifyEqual(runEnd.planned_audio_getsecs,endFlip.stimulus_onset_getsecs,'AbsTol',1e-9);
        end
        function steadyFlipKeepsTheMacExternalTargetWait(tc)
            % The Mac external-backend submission policy applies unchanged.
            TestFixedFixationRuntime.sim('set','macBackend',true);
            TestFixedFixationRuntime.sim('set','imagingMode',2^20);
            tc.SteadyFlip=true;
            job=tc.createJob(.2,true);
            job.run();
            rows=job.Log.flipRecords();
            onsets=rows([rows.phase]=="blank" & [rows.phase_flip_seq]==1);
            tc.verifyEqual(unique([onsets.submission_mode]),"steady_macos_external_target");
            held=rows([rows.trial_nr]==1 & [rows.phase]=="pre_fixation");
            tc.verifyTrue(all([held(2:end).submission_mode]=="fixed_fixation_macos_target"));
            slot=round(job.Config.protocol.video_pre_fixation_s/job.IFI);
            tc.verifyEqual(onsets(1).stimulus_onset_getsecs, ...
                held(1).stimulus_onset_getsecs+slot*job.IFI,'AbsTol',1e-9);
        end
        function steadyFlipSettingIsOnByDefaultAndLogical(tc)
            shared=ephys.readYaml(fullfile(ephys.projectRoot(),'config','experiment.yml'));
            tc.verifyEqual(shared.display.steady_flip,true);
            schedule=fullfile(ephys.projectRoot(),'config','runs','debug_blank.yml');
            [c,~]=ephys.loadConfig("video",schedule,testSite(),true,"");
            c.display.steady_flip=1;
            tc.verifyError(@() ephys.validateConfig(c),'ephys:SteadyFlipConfig');
        end
    end
    methods (Access=private)
        function writeStub(tc,name,lines)
            fid=fopen(fullfile(tc.Folder,char(name+".m")),'w');
            guard=onCleanup(@() fclose(fid)); %#ok<NASGU>
            fprintf(fid,'%s\n',char(join(lines,newline)));
        end
        function job=createJob(tc,initialSeconds,withMarkers,runOutput)
            if nargin<2, initialSeconds=.2; end
            if nargin<3, withMarkers=false; end
            schedule=fullfile(ephys.projectRoot(),'config','runs','debug_blank.yml');
            [c,p]=ephys.loadConfig("video",schedule,testSite(),true,"");
            c.schedule="blank";
            c.debug_simulated_input_only=true;
            c.display.resolution_px={1440,900};
            c.display.skip_sync_tests=false;
            c.photodiode.enabled=false;
            c.eyelink.enabled=false;
            c.markers.run_boundary_enabled=false;
            c.markers.blank_enabled=false;
            c.markers.video_offset_enabled=false;
            c.markers.fixation_onset_enabled=false;
            c.playback.startup_preload_movies=0;
            c.protocol.video_initial_fixation_s=initialSeconds;
            c.protocol.video_final_fixation_s=tc.FinalSeconds;
            c.display.steady_flip=tc.SteadyFlip;
            c.protocol.video_pre_fixation_s=.2;
            c.protocol.video_duration_s=.2;
            c.protocol.video_post_fixation_s=.02;
            if withMarkers
                % Two blanks: the second onset follows a blank, as in the
                % trials whose PTB prediction drifted on the Windows laptop.
                c.schedule=["blank";"blank"];
                c.markers.run_boundary_enabled=true;
                c.markers.blank_enabled=true;
                c.markers.video_offset_enabled=true;
            end
            c.paths.output_root=tempname(tc.Folder);
            if nargin>=4
                c.paths.output_root=runOutput.root;
                c.run_output=rmfield(runOutput,'root');
            end
            job=FixedFixationSessionProbe(c,p,"fixed_fixation",@TestFixedFixationRuntime.input);
            tc.addTeardown(@() delete(job));
        end
    end
    methods (Static)
        function [key,time]=input(job)
            state=TestFixedFixationRuntime.sim('state');
            key=""; time=NaN;
            if job.CurrentRunPhase=="instruction" && ~state.spaceSent
                key="space"; time=state.time;
                TestFixedFixationRuntime.sim('set','spaceSent',true);
                return;
            end
            if state.time>=state.quitAt
                key="q"; time=state.time;
                TestFixedFixationRuntime.sim('set','quitAt',Inf);
            end
            if state.quitWhenReserved && job.Triggers.Count>0 && ...
                    any([job.Triggers.records().event_type]=="blank_onset")
                % Q while a reserved onset is still in the future.
                key="q"; time=state.time;
                TestFixedFixationRuntime.sim('set','quitWhenReserved',false);
            end
        end
        function clearStubs()
            clear Screen GetSecs WaitSecs HideCursor ShowCursor Priority ismac DrawFormattedText
        end
        function varargout=sim(action,varargin)
            persistent state
            switch string(action)
                case "reset"
                    state=struct('time',10,'ifi',1/60,'preference',0, ...
                        'windows',[],'requests',[],'draws',0, ...
                        'stallOnDraw',0,'stallSeconds',0,'stallEachDraw',0,'quitAt',Inf, ...
                        'imagingMode',0,'waitOvershoot',0,'macBackend',false,'spaceSent',false, ...
                        'quitWhenReserved',false);
                case "state"
                    varargout={state};
                case "set"
                    state.(varargin{1})=varargin{2};
                case "time"
                    varargout={state.time};
                case "platform"
                    varargout={state.macBackend};
                case "wait"
                    state.time=state.time+varargin{end}+state.waitOvershoot;
                    state.waitOvershoot=0;
                case "screen"
                    command=lower(string(varargin{1}));
                    switch command
                        case "preference"
                            old=state.preference;
                            if numel(varargin)>2, state.preference=varargin{3}; end
                            varargout={old};
                        case "screens"
                            varargout={0};
                        case "openwindow"
                            state.windows=10; varargout={10};
                        case "rect"
                            varargout={[0 0 1440 900]};
                        case "getwindowinfo"
                            % A bogus internal last-Flip time; predictions must not read it.
                            varargout={struct('ImagingMode',state.imagingMode,'SpecialFlags',0, ...
                                'LastVBLTime',-1)};
                        case "getflipinterval"
                            varargout={state.ifi,100,0};
                        case "fillrect"
                            state.draws=state.draws+1;
                            if state.draws==state.stallOnDraw
                                state.time=state.time+state.stallSeconds;
                            end
                            state.time=state.time+state.stallEachDraw;
                        case {"filloval","drawline","drawingfinished","textsize"}
                        case "flip"
                            request=varargin{3};
                            state.requests(end+1)=request;
                            slot=ceil((max(state.time,request)-10)/state.ifi-1e-9);
                            state.time=10+slot*state.ifi;
                            varargout={state.time,state.time,state.time,0};
                        case "windows"
                            varargout={state.windows};
                        case "close"
                            state.windows=[];
                        otherwise
                            error('test:UnexpectedScreen','Unexpected Screen command %s.',command);
                    end
            end
        end
    end
end
