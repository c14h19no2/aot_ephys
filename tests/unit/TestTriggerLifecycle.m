classdef TestTriggerLifecycle < matlab.unittest.TestCase
    % Named-waveform lifecycle: shared stimulus waveforms, reservations and cancellation.
    methods (Test)
        function sharedStimulusWaveformsAndNamedMemory(tc)
            c=TestTriggerLifecycle.config(); clock=containers.Map({'now'},{10});
            backend=ephys.DummyTriggerBackend(@() clock('now'));
            output=ephys.TriggerOutput(c.markers,backend,20,@() clock('now'));
            cleanup=onCleanup(@() delete(output)); %#ok<NASGU>
            output.open();
            types=["video_onset","video_offset","video_onset","video_offset","blank_onset","blank_offset"];
            files=["0001_fw.mp4","0001_fw.mp4","0001_rv.mp4","0001_rv.mp4","blank","blank"];
            for k=1:numel(types)
                ctx=ephys.context("video",k,files(k));
                row=output.emit(types(k),ctx,struct('seq',k,'stimulus',clock('now')),NaN,"");
                key="video_onset"; wave="TrigP16.wav";
                if mod(k,2)==0, key="video_offset"; wave="TrigN16.wav"; end
                tc.verifyEqual(row.trigger_key,key);
                tc.verifyEqual(row.waveform_file,wave);
                tc.verifyEqual(row.event_type,types(k));
                tc.verifyEqual(row.video_file,files(k));
                tc.verifyEqual(row.waveform_samples,100);
                tc.verifyEqual(row.output_sample_rate_hz,48000);
                tc.verifyEqual(row.pulse_width_s,100/48000,'AbsTol',1e-12);
                clock('now')=clock('now')+1;
            end
            ctx=ephys.context("memory",1,"0001_fw.png");
            for response=["yes","no"]
                row=output.emit("memory_response",ctx,[],clock('now'),response);
                tc.verifyEqual(row.trigger_key,"memory_response_"+response);
                tc.verifyEqual(row.waveform_file,"");
                clock('now')=clock('now')+1;
            end
            output.close(); rows=output.records();
            tc.verifyTrue(all(string({rows.status})=="dummy"));
            tc.verifyTrue(all(isnan([rows.physical_onset_getsecs])));
            tc.verifyFalse(isfield(rows,'code'));
        end
        function futureReservationAssociatesAndCompletes(tc)
            c=TestTriggerLifecycle.config(); clock=containers.Map({'now'},{10});
            backend=ephys.DummyTriggerBackend(@() clock('now'),[],@advance);
            output=ephys.TriggerOutput(c.markers,backend,4,@() clock('now'));
            cleanup=onCleanup(@() delete(output)); %#ok<NASGU>
            output.open(); ctx=ephys.context("video",1,"0001_fw.mp4");
            row=output.schedule("video_onset",ctx,10.5);
            tc.verifyEqual(row.status,"queued");
            tc.verifyEqual(row.audio_lead_s,.5);
            row=output.associate(row.event_id,struct('seq',1,'stimulus',10.5));
            tc.verifyEqual(row.sync_status,"simulated");
            tc.verifyTrue(isnan(row.audio_start_getsecs));
            clock('now')=10.51; output.poll(); row=output.records();
            tc.verifyEqual(row.status,"dummy");
            tc.verifyEqual(row.associated_flip_getsecs,10.5);
            tc.verifyError(@() output.associate(row.event_id, ...
                struct('seq',2,'stimulus',10.6)),'ephys:MarkerAssociation');
            function advance(seconds), clock('now')=clock('now')+seconds; end
        end
        function cancellationPreservesRaceOutcome(tc)
            c=TestTriggerLifecycle.config(); clock=containers.Map({'now'},{0});
            backend=ephys.DummyTriggerBackend(@() clock('now'),[],@advance);
            output=ephys.TriggerOutput(c.markers,backend,4,@() clock('now'));
            cleanup=onCleanup(@() delete(output)); %#ok<NASGU>
            output.open(); ctx=ephys.context("video",1,"blank");
            output.schedule("blank_onset",ctx,1);
            output.cancelPending(); rows=output.records();
            tc.verifyEqual(rows.status,"cancelled");
            tc.verifyEqual(rows.cancellation_status,"cancelled_before_start");
            output.schedule("blank_onset",ctx,2);
            clock('now')=2; output.cancelPending(); rows=output.records();
            tc.verifyEqual(rows(2).status,"queued");
            tc.verifyEqual(rows(2).cancellation_status,"already_started");
            clock('now')=2.01; output.poll(); rows=output.records();
            tc.verifyEqual(rows(2).status,"dummy");
            tc.verifyTrue(isnan(rows(2).physical_onset_getsecs));
            function advance(seconds), clock('now')=clock('now')+seconds; end
        end
        function closeCollectsLastWaveformCompletion(tc)
            c=TestTriggerLifecycle.config(); clock=containers.Map({'now'},{0});
            backend=ephys.DummyTriggerBackend(@() clock('now'),[],@advance);
            output=ephys.TriggerOutput(c.markers,backend,2,@() clock('now'));
            output.open(); ctx=ephys.context("video",0,"");
            output.schedule("run_end",ctx,.1);
            tc.verifyEqual(output.records().status,"queued");
            output.close(); row=output.records();
            tc.verifyEqual(row.status,"dummy");
            tc.verifyEqual(row.trigger_key,"run_end");
            tc.verifyEqual(row.waveform_file,"TrigN08.wav");
            tc.verifyGreaterThanOrEqual(row.completion_getsecs,.1+100/48000);
            tc.verifyTrue(isnan(row.audio_start_getsecs));
            tc.verifyFalse(backend.IsOpen);
            function advance(seconds), clock('now')=clock('now')+seconds; end
        end
        function namedClockFitUsesAudioRatherThanReservation(tc)
            rows=repmat(ephys.emptyMarker(),4,1);
            external=repmat(struct('event_id',"",'trigger_key',"video_onset", ...
                'waveform_file',"TrigP16.wav",'ephys_time_s',NaN,'verified',true),4,1);
            for k=1:4
                rows(k).event_id="wave-"+k; rows(k).trigger_key="video_onset";
                rows(k).waveform_file="TrigP16.wav"; rows(k).status="complete";
                rows(k).request_getsecs=k*100-.1*k;
                rows(k).audio_start_getsecs=k*100;
                external(k).event_id=rows(k).event_id;
                external(k).ephys_time_s=3+1.0001*rows(k).audio_start_getsecs;
            end
            fit=ephys.fitClockMapping(rows,external,.001);
            tc.verifyEqual(fit.clock_rate,1.0001,'AbsTol',1e-10);
            for state=["queued","cancelled"]
                invalid=rows; invalid(2).status=state;
                tc.verifyError(@() ephys.fitClockMapping(invalid,external),'ephys:ClockSoftwareOnly');
            end
            external(2).waveform_file="TrigN08.wav";
            tc.verifyError(@() ephys.fitClockMapping(rows,external),'ephys:ClockTrigger');
        end
        function blankOnsetUsesItsActualFlipWithoutOffsetOutput(tc)
            c=TestTriggerLifecycle.config(); log=ephys.TimelineLog(4,4);
            ctx=ephys.context("video",1,"blank");
            on=log.flip(ctx,"blank",1,TestTriggerLifecycle.raw(10),10,ephys.noFrame("blank"),"off");
            log.event(ctx,"blank_onset","blank",10,on);
            off=log.flip(ctx,"post_fixation",1,TestTriggerLifecycle.raw(12.5),12.5,ephys.noFrame("fixation"),"off");
            log.event(ctx,"blank_offset","post_fixation",12.5,off);
            m=ephys.emptyMarker();
            m.trial_id=ctx.trial_id; m.trial_nr=1; m.video_file="blank";
            m.event_id="blank-onset"; m.trigger_key="video_onset";
            m.waveform_file="TrigP16.wav"; m.status="dummy";
            m.associated_flip_getsecs=10; m.associated_flip_seq=1;
            m.event_type="blank_onset";
            result=ephys.reconstructRecords(log.flipRecords(),log.eventRecords(),m,[],c);
            tc.verifyFalse(result.trials.software_marker_issue);
            tc.verifyEqual(result.trials.blank_onset_marker_id,"blank-onset");
            m.associated_flip_getsecs=10.01;
            result=ephys.reconstructRecords(log.flipRecords(),log.eventRecords(),m,[],c);
            tc.verifyTrue(result.trials.software_marker_issue);
            m.associated_flip_getsecs=10;
            m.status="complete"; m.sync_status="out_of_tolerance";
            m.audio_start_getsecs=10.004788; m.audio_visual_delta_s=.004788;
            result=ephys.reconstructRecords(log.flipRecords(),log.eventRecords(),m,[],c);
            tc.verifyEqual(result.trials.audio_sync_issue_count,1);
            tc.verifyEqual(result.trials.max_abs_audio_visual_delta_s,.004788,'AbsTol',1e-12);
            tc.verifyTrue(result.trials.software_marker_issue);
        end
    end
    methods (Static)
        function c=config()
            root=ephys.projectRoot();
            [c,~]=ephys.loadConfig("video",fullfile(root,'config','runs','debug_blank.yml'), ...
                testSite(),true,"");
            c.protocol.video_duration_s=2.5;
        end
        function value=raw(time)
            value=struct('vbl',time,'stimulus',time,'returned',time,'missed',0);
        end
    end
end
