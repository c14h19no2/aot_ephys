classdef TestRuntimeQC < matlab.unittest.TestCase
    methods (Test)
        function logsGrowAndPreserveEveryRecord(tc)
            log=ephys.TimelineLog(1,1);
            ctx=ephys.context("video",1,"blank");
            for k=1:300
                raw=TestRuntimeQC.raw(k);
                row=log.flip(ctx,"blank",k,raw,k,ephys.noFrame("blank"),"off");
                log.event(ctx,"observation","blank",k,row);
            end
            tc.verifyEqual([log.flipRecords().flip_seq],1:300);
            tc.verifyEqual([log.eventRecords().onset_getsecs],1:300);
            tc.verifyEqual([log.Flips(1:299).interval_s],ones(1,299));
            f=FakeWavAudio(); backend=TestWavTriggers.backend(f);
            output=ephys.TriggerOutput(TestWavTriggers.settings(),backend,1,@() f.Now);
            guard=onCleanup(@() delete(output)); %#ok<NASGU>
            output.open();
            for k=1:140
                output.schedule("video_onset",ctx,f.Now+.2);
                f.Now=f.Now+.21; output.poll();
            end
            output.close();
            tc.verifyEqual([output.records().marker_nr],1:140);
            tc.verifyTrue(all(string({output.records().status})=="complete"));
        end
        function extraFramesHaveUnknownSourceIdentityAndReleaseAllTextures(tc)
            [p,snapshot,guard]=TestNativeMoviePlayer.fixture([0 .04 .08 .12]); %#ok<ASGLU>
            p.prepare(.1); p.start(10); p.draw([0 0 2 2],10.12);
            tc.verifyEqual(p.FetchedCount,4);
            tc.verifyTrue(isnan(p.info().source_frame_index));
            tc.verifyTrue(isnan(p.info().pts));
            tc.verifyEqual(p.info().raw_pts,.12);
            tc.verifyTrue(contains(p.info().qc_flags,"extra_native_frame"));
            p.closeCurrent(); tc.verifyEmpty(snapshot().live);
        end
        function noDrawableFirstFrameStillFails(tc)
            [p,snapshot,guard]=TestNativeMoviePlayer.fixture(-Inf); %#ok<ASGLU>
            tc.verifyError(@() p.prepare(.1),'ephys:NativeFirstFrame');
            tc.verifyEmpty(snapshot().live); tc.verifyEmpty(p.Movie);
        end
        function fullScheduleSurvivesInjectedRecoverableAnomalies(tc)
            root=ephys.projectRoot();
            schedule=ephys.readYaml(fullfile(root,'config','runs','main', ...
                'experiment_settings_sub_01_ses_01_run_08.yml'));
            names=string(schedule.stimuli.movie_files);
            names=names(:);
            tc.verifyEqual(numel(names),84);
            f=FakeWavAudio(); backend=TestWavTriggers.backend(f);
            output=ephys.TriggerOutput(TestWavTriggers.settings(),backend,1,@() f.Now);
            guard=onCleanup(@() delete(output)); %#ok<NASGU>
            output.open(); log=ephys.TimelineLog(1,1); native=struct([]);
            boundary=ephys.context("video",0,"");
            output.emit("run_start",boundary); f.Now=f.Now+.01; output.poll();
            for trial=1:numel(names)
                ctx=ephys.context("video",trial,names(trial));
                time=f.Now+.05; phase="blank"; frame=ephys.noFrame("blank");
                player=[];
                if names(trial)~="blank"
                    phase="video"; stream=[0 .04 .08];
                    if mod(trial,3)==0, stream=0; end
                    if mod(trial,7)==0, stream=[0 NaN]; end
                    if mod(trial,11)==0, stream=[.04 .08]; end
                    [player,~,~]=TestNativeMoviePlayer.fixture(stream,false);
                    player.prepare(.1,[],9); frame=player.info();
                end
                marker=output.schedule(phase+"_onset",ctx,time);
                onset=log.flip(ctx,phase,1,TestRuntimeQC.raw(time),time,frame,"off");
                ev=log.event(ctx,phase+"_onset",phase,time,onset);
                ev.planned_onset_getsecs=time; ev.planned_deadline_getsecs=time+.12;
                log.updateLastEvent(ev);
                f.Now=time+.001; f.XRuns=double(trial==9);
                f.NeverStart=trial==5;
                output.associate(marker.event_id,struct('seq',onset.flip_seq,'stimulus',time));
                if ~isempty(player)
                    player.start(time); player.draw([0 0 2 2],time+.08);
                    log.flip(ctx,phase,2,TestRuntimeQC.raw(time+.08),time+.08,player.info(),"off");
                    player.stop(); value=player.summary(); value.trial_nr=trial;
                    native=[native;value]; %#ok<AGROW>
                    player.closeCurrent(); delete(player);
                end
                offset=log.flip(ctx,"post_fixation",1,TestRuntimeQC.raw(time+.12), ...
                    time+.12,ephys.noFrame("fixation"),"off");
                log.event(ctx,phase+"_offset","post_fixation",time+.12,offset);
                f.Now=time+.13;
                if trial==5, f.Now=time+.8; end
                output.poll(); f.NeverStart=false; f.XRuns=0;
            end
            output.emit("run_end",boundary); output.close();
            markers=output.records();
            tc.verifyEqual(numel(native),72);
            tc.verifyEqual(numel(markers),86);
            tc.verifyEqual(sum(string({markers.status})=="failed"),1);
            tc.verifyTrue(markers(6).qc_only_failure);
            tc.verifyEqual(markers(end).trigger_key,"run_end");
            tc.verifyEqual(markers(end).status,"complete");
            tc.verifyEqual(output.CloseError,"");
            c=struct('protocol',struct('video_duration_s',.12), ...
                'display',struct('expected_refresh_hz',25),'native_trials',native);
            result=ephys.reconstructRecords(log.flipRecords(),log.eventRecords(),markers,struct([]),c);
            tc.verifyEqual(result.run_qc.trial_count,84);
            tc.verifyGreaterThan(result.run_qc.audio_qc_issue_count,0);
            tc.verifyGreaterThan(result.run_qc.native_qc_issue_count,0);
            tc.verifyEqual(result.run_qc.preparation_overrun_count,72);
            tc.verifyTrue(any([result.trials.unresolved_source_frame_count]>0));
        end
        function postRunQCFailureStillSavesCompletedManifestAndRawData(tc)
            root=ephys.projectRoot();
            [c,p]=ephys.loadConfig("video",fullfile(root,'config','runs','debug_blank.yml'), ...
                testSite(),true,"");
            folder=tempname; mkdir(folder);
            guard=onCleanup(@() rmdir(folder,'s')); %#ok<NASGU>
            source=fullfile(folder,'source.yml'); TestRuntimeQC.write(source,'before');
            p.files={source}; p.sha256={ephys.sha256(source)};
            TestRuntimeQC.write(source,'after');
            frame=ephys.emptyFlip(); frame.flip_seq=1;
            events=repmat(ephys.emptyEvent(),0,1);
            s=struct('OutputDir',folder,'RunId',"qc_failure",'Config',c, ...
                'Provenance',p,'StartTime',0,'StopTime',1, ...
                'DisplayTiming',struct(),'EffectiveSkipSync',0, ...
                'IFI',1/60,'IFISamples',NaN,'IFIStddev',NaN, ...
                'Eye',struct('LocalPath',""),'Inventory',struct([]), ...
                'Log',struct('flipRecords',@() [frame;frame],'eventRecords',@() events));
            s.Triggers=ephys.TriggerOutput(c.markers,ephys.DummyTriggerBackend(@() 0),1,@() 0);
            triggerGuard=onCleanup(@() delete(s.Triggers)); %#ok<NASGU>
            ephys.writeOutput(s,"complete","");
            manifest=jsondecode(fileread(fullfile(folder,'qc_failure_manifest.json')));
            tc.verifyEqual(string(manifest.status),"complete");
            tc.verifyEqual(string(manifest.post_run_qc.status),"failed");
            tc.verifyEqual(string(manifest.post_run_qc.error_id),"ephys:FlipSequence");
            tc.verifyEqual(string(manifest.configuration_sources.status),"changed_after_preflight");
            tc.verifyNotEqual(manifest.configuration_sources.sha256, ...
                manifest.configuration_sources.expected_sha256);
            rows=ephys.readTimelineRows(fullfile(folder,'qc_failure_flips.tsv'),ephys.emptyFlip());
            tc.verifyEqual(height(rows),2);
            tc.verifyTrue(isfile(fullfile(folder,'qc_failure_resolved_config.json')));
            tc.verifyEqual(string(manifest.trigger_offset_report.status),"created");
            tc.verifyEqual(string(manifest.refresh_guard.status),"not_run");
        end
    end
    methods (Static,Access=private)
        function value=raw(time)
            value=struct('vbl',time,'stimulus',time,'returned',time,'missed',0);
        end
        function write(path,value)
            fid=fopen(path,'w'); guard=onCleanup(@() fclose(fid)); %#ok<NASGU>
            fprintf(fid,'%s',value);
        end
    end
end
