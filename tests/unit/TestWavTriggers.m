classdef TestWavTriggers < matlab.unittest.TestCase
    methods (Test)
        function dummyCanReserveAgainAfterCancellingTheLastRow(tc)
            f=FakeWavAudio(); b=ephys.DummyTriggerBackend(@() f.Now,NaN,@(s) f.advance(s));
            b.configure(TestWavTriggers.settings()); b.open();
            b.submit("video_onset","first",10.2); r=b.cancel("first");
            tc.verifyEqual(r.status,"cancelled");
            b.submit("video_onset","second",10.3); f.Now=10.31;
            r=b.poll(); tc.verifyNumElements(r,1); tc.verifyEqual(r.event_id,"second");
            b.submit("video_onset","third",10.5); r=b.cancel("third");
            tc.verifyEqual(r.status,"cancelled");
            b.submit("run_end","fourth",10.6); b.close(); r=b.poll();
            tc.verifyNumElements(r,1); tc.verifyEqual(r.event_id,"fourth");
        end
        function bufferedPulseDrainsPastInactiveStatusBeforeClose(tc)
            f=FakeWavAudio(); f.RenderAhead_s=.02;
            b=TestWavTriggers.backend(f); b.configure(TestWavTriggers.settings()); b.open();
            b.submit("video_onset","buffered",10.2); f.Now=10.19;
            receipts=b.poll(); tc.verifyEqual(receipts.status,"queued");
            tc.verifyEqual(receipts.audio_start_getsecs,10.2,'AbsTol',1e-12);
            tc.verifyEqual(receipts.audio_stop_getsecs,10.2+100/48000,'AbsTol',1e-12);
            receipt=b.cancel("buffered"); tc.verifyEqual(receipt.cancellation_status,"already_buffered");
            stops=f.Calls(cellfun(@(c) strcmp(c{1},'Stop'),f.Calls)); tc.verifyEmpty(stops);
            b.close(); tc.verifyGreaterThanOrEqual(f.Now,10.2+100/48000);
            receipts=b.poll(); tc.verifyEqual(receipts.status,"complete");
            tc.verifyGreaterThanOrEqual(receipts.completion_getsecs,receipts.audio_stop_getsecs);
        end
        function originalSamplesAndSilentPrewarm(tc)
            s=TestWavTriggers.settings(); waves=ephys.loadTriggerWaveforms(s);
            tc.verifyEqual([waves.samples],repmat(100,1,4));
            tc.verifyEqual([waves.source_sample_rate_hz],repmat(22050,1,4));
            tc.verifyEqual([waves.output_sample_rate_hz],repmat(48000,1,4));
            tc.verifyEqual([waves.duration_s],repmat(100/48000,1,4));
            f=FakeWavAudio(); b=TestWavTriggers.backend(f); b.configure(s); b.open();
            cleanup=onCleanup(@() b.close()); %#ok<NASGU>
            tc.verifyEqual(numel(f.Handles),5);
            tc.verifyTrue(f.Handles(1).master);
            tc.verifyFalse(any([f.Handles(2:5).active]));
            for k=1:4, tc.verifyEqual(f.Handles(k+1).samples,waves(k).data); end
            starts=f.Calls(cellfun(@(c) strcmp(c{1},'Start'),f.Calls));
            tc.verifyNumElements(starts,1); tc.verifyEqual(starts{1}{2},1);
            tc.verifyFalse(isfield(b.Metadata.waveforms,'data'));
        end
        function scheduledAudioAssociatesActualFlip(tc)
            [o,f]=TestWavTriggers.output(); cleanup=onCleanup(@() delete(o)); %#ok<NASGU>
            c=ephys.context("video",1,"movie_fw.mp4");
            r=o.schedule("video_onset",c,10.2);
            tc.verifyEqual(r.trigger_key,"video_onset"); tc.verifyEqual(r.waveform_file,"TrigP16.wav");
            tc.verifyEqual(r.output_channel,2);
            tc.verifyEqual(r.audio_lead_s,.2,'AbsTol',1e-12);
            tc.verifyFalse(isfield(r,'code')); tc.verifyTrue(isnan(r.physical_onset_getsecs));
            start=f.Calls{find(cellfun(@(c) strcmp(c{1},'Start'),f.Calls),1,'last')};
            tc.verifyEqual(start(3:5),{1,10.2,0});
            f.Now=10.201; r=o.associate(r.event_id,struct('seq',9,'stimulus',10.201));
            tc.verifyEqual(r.sync_status,"within_tolerance");
            tc.verifyEqual(r.audio_visual_delta_s,-.001,'AbsTol',1e-12);
            f.Now=10.21; o.poll(); tc.verifyEqual(o.records().status,"complete");
            tc.verifyEqual(o.records().audio_stop_getsecs,10.2+100/48000,'AbsTol',1e-12);
            o.close();
        end
        function selectedChannelReachesAudioBuffersAndReceipts(tc)
            for channel=1:2
                s=TestWavTriggers.settings(); s.wav.output_channel=channel;
                f=FakeWavAudio(); b=TestWavTriggers.backend(f);
                o=ephys.TriggerOutput(s,b,4,@() f.Now);
                cleanup=onCleanup(@() delete(o));
                o.open();
                for k=1:4
                    [original,~]=audioread(fullfile(ephys.projectRoot(), ...
                        s.wav.directory,b.Metadata.waveforms(k).file));
                    buffer=f.Handles(k+1).samples;
                    tc.verifyEqual(buffer(channel,:),original(:,1).');
                    tc.verifyEqual(buffer(3-channel,:),zeros(1,100));
                    tc.verifyEqual(b.Metadata.waveforms(k).output_channel,channel);
                end
                row=o.schedule("video_onset",ephys.context("video",1,"movie_fw.mp4"),10.2);
                tc.verifyEqual(row.output_channel,channel);
                f.Now=10.21; o.poll(); o.close();
                tc.verifyEqual(o.records().output_channel,channel);
                tc.verifyEqual(o.records().status,"complete");
                clear cleanup
            end
        end
        function lateVisualFlipIsReportedWithoutAborting(tc)
            [o,f]=TestWavTriggers.output(); cleanup=onCleanup(@() delete(o)); %#ok<NASGU>
            r=o.schedule("blank_onset",ephys.context("video",1,"blank"),10.2);
            f.Now=10.22;
            o.associate(r.event_id,struct('seq',3,'stimulus',10.216));
            saved=o.records(); tc.verifyEqual(saved.event_type,"blank_onset");
            tc.verifyEqual(saved.trigger_key,"video_onset"); tc.verifyEqual(saved.status,"complete");
            tc.verifyEqual(saved.sync_status,"out_of_tolerance");
            tc.verifyEqual(saved.error,"");
            tc.verifyEqual(saved.audio_visual_delta_s,-.016,'AbsTol',1e-12);
            o.close(); tc.verifyEqual(o.CloseError,"");
        end
        function runStartOutlierCanCompleteAndContinueToNextTrigger(tc)
            [o,f]=TestWavTriggers.output(); cleanup=onCleanup(@() delete(o)); %#ok<NASGU>
            r=o.schedule("run_start",ephys.context("video",0,""),10.2);
            f.Now=10.196;
            o.associate(r.event_id,struct('seq',1,'stimulus',10.195212));
            tc.verifyEqual(o.records().status,"queued");
            f.Now=10.21; o.poll();
            saved=o.records();
            tc.verifyEqual(saved.status,"complete");
            tc.verifyEqual(saved.sync_status,"out_of_tolerance");
            tc.verifyEqual(saved.audio_visual_delta_s,.004788,'AbsTol',1e-12);
            next=o.schedule("video_onset",ephys.context("video",1,"movie_fw.mp4"),10.5);
            f.Now=10.52;
            o.associate(next.event_id,struct('seq',2,'stimulus',10.516));
            o.close(); saved=o.records();
            tc.verifyEqual(string({saved.status}),["complete","complete"]);
            tc.verifyEqual(string({saved.sync_status}),["out_of_tolerance","out_of_tolerance"]);
            [summary,~]=ephys.triggerOffsetSummary(saved);
            tc.verifyEqual(summary.plotted_marker_count,2);
            tc.verifyEqual(summary.outside_reference_count,2);
            tc.verifyEqual(summary.failed_marker_count,0);
            tc.verifyEqual(o.CloseError,"");
        end
        function futureCancellationDoesNotEmitOrReturnStaleStatus(tc)
            [o,f]=TestWavTriggers.output(); cleanup=onCleanup(@() delete(o)); %#ok<NASGU>
            c=ephys.context("video",1,"movie_fw.mp4");
            o.schedule("video_onset",c,10.2); o.cancelPending(); o.poll();
            r=o.records(); tc.verifyEqual(r.status,"cancelled");
            tc.verifyEqual(r.cancellation_status,"cancelled_before_start");
            tc.verifyTrue(isnan(r.audio_start_getsecs)); tc.verifyEqual(o.nextAllowedRequestTime(),-Inf);
            tc.verifyFalse(any([f.Handles(2:5).active]));
            r=o.emit("run_end",ephys.context("video",0,""));
            tc.verifyEqual(r.waveform_file,"TrigN08.wav");
            o.close(); saved=o.records(); tc.verifyEqual(saved(2).status,"complete");
        end
        function startedPulseSurvivesCancellationAndCloseDrains(tc)
            [o,f]=TestWavTriggers.output(); cleanup=onCleanup(@() delete(o)); %#ok<NASGU>
            o.schedule("video_onset",ephys.context("video",1,"movie_fw.mp4"),10.2);
            f.Now=10.201; o.cancelPending();
            r=o.records(); tc.verifyEqual(r.cancellation_status,"already_started");
            tc.verifyEqual(r.status,"queued");
            stopped=f.Calls(cellfun(@(c) strcmp(c{1},'Stop') && c{2}~=1,f.Calls));
            tc.verifyEmpty(stopped); o.close();
            tc.verifyEqual(o.records().status,"complete");
            tc.verifyGreaterThanOrEqual(f.Now,10.2+100/48000);
        end
        function cancellationRaceIsReported(tc)
            [o,f]=TestWavTriggers.output(); cleanup=onCleanup(@() delete(o)); %#ok<NASGU>
            o.schedule("video_onset",ephys.context("video",1,"movie_fw.mp4"),10.2);
            f.CancelRace=true; tc.verifyError(@() o.cancelPending(),'ephys:TriggerFailure'); r=o.records();
            tc.verifyEqual(r.status,"failed"); tc.verifyEqual(r.cancellation_status,"started_during_cancel");
            tc.verifyTrue(isfinite(r.audio_start_getsecs));
        end
        function deviceFailureHasNoFallbackAndRateMustMatch(tc)
            s=TestWavTriggers.settings(); f=FakeWavAudio(); f.FailOpen=true;
            b=TestWavTriggers.backend(f); b.configure(s);
            tc.verifyError(@() b.open(),'test:AudioOpen'); tc.verifyFalse(b.IsOpen);
            opens=cellfun(@(c) strcmp(c{1},'Open'),f.Calls); tc.verifyEqual(sum(opens),1);
            f=FakeWavAudio(); f.SampleRate=44100; b=TestWavTriggers.backend(f); b.configure(s);
            tc.verifyError(@() b.open(),'ephys:TriggerSampleRate'); tc.verifyEmpty(b.Master);
        end
        function shortLeadAndUnderrunsAreReportedWithoutAborting(tc)
            [o,f]=TestWavTriggers.output(); cleanup=onCleanup(@() delete(o)); %#ok<NASGU>
            c=ephys.context("video",1,"movie_fw.mp4");
            row=o.schedule("video_onset",c,10.05);
            tc.verifyEqual(row.status,"queued");
            tc.verifyEqual(row.audio_lead_shortfall_s,.05,'AbsTol',1e-12);
            tc.verifyEqual(row.audio_qc_flags,"insufficient_audio_lead");
            tc.verifyEqual(o.records().output_channel,2);
            f.Now=10.06; o.poll(); o.close();
            tc.verifyEqual(o.records().status,"complete");
            [o2,f2]=TestWavTriggers.output(); cleanup2=onCleanup(@() delete(o2)); %#ok<NASGU>
            o2.schedule("video_onset",c,10.2); f2.Now=10.201; f2.XRuns=1;
            o2.poll();
            tc.verifyEqual(o2.records().audio_xruns,1);
            tc.verifyEqual(o2.records().audio_qc_flags,"audio_underrun");
            f2.Now=10.21; o2.close();
            tc.verifyEqual(o2.records().status,"complete");
        end
        function missingCompletionIsRecordedAndTheNextPulseCanRun(tc)
            c=ephys.context("video",1,"movie_fw.mp4");
            [o3,f3]=TestWavTriggers.output(); cleanup3=onCleanup(@() delete(o3)); %#ok<NASGU>
            o3.schedule("video_onset",c,10.2); f3.NeverStart=true; f3.Now=10.8;
            o3.poll();
            tc.verifyEqual(o3.records().status,"failed");
            tc.verifyTrue(o3.records().qc_only_failure);
            tc.verifyTrue(isnan(o3.records().audio_start_getsecs));
            f3.NeverStart=false;
            o3.schedule("run_end",c,11); f3.Now=11.01; o3.poll(); o3.close();
            saved=o3.records(); tc.verifyEqual(string({saved.status}),["failed","complete"]);
            tc.verifyEqual(o3.CloseError,"");
        end
        function backendRejectsCrossSlaveOverlapAndMinimumLowViolation(tc)
            f=FakeWavAudio(); b=TestWavTriggers.backend(f); b.configure(TestWavTriggers.settings()); b.open();
            cleanup=onCleanup(@() b.close()); %#ok<NASGU>
            b.submit("run_start","start",10.2);
            tc.verifyError(@() b.submit("video_onset","overlap",10.2),'ephys:TriggerCollision');
            tc.verifyError(@() b.submit("video_onset","short-low",10.205),'ephys:TriggerCollision');
            b.submit("video_onset","separate",10.22);
            f.Now=10.24; receipts=b.poll();
            tc.verifyEqual(string({receipts.status}),["complete","complete"]);
            b.close();
        end
        function selectedDeviceIdentityIsRecordedAndAmbiguityFails(tc)
            s=TestWavTriggers.settings(); f=FakeWavAudio(); b=TestWavTriggers.backend(f);
            b.configure(s); b.open(); cleanup=onCleanup(@() b.close()); %#ok<NASGU>
            tc.verifyEqual(b.DeviceInfo.DeviceIndex,7);
            tc.verifyEqual(b.DeviceInfo.DeviceName,'Test analog output');
            tc.verifyEqual(b.Metadata.master_status.OutDeviceIndex,7);
            s.wav.device_name='missing device'; f2=FakeWavAudio(); b2=TestWavTriggers.backend(f2); b2.configure(s);
            tc.verifyError(@() b2.open(),'ephys:TriggerDevice'); tc.verifyEmpty(f2.Handles);
        end
        function unobservedStartRetainsFailureAndPollWorksAfterClosing(tc)
            f=FakeWavAudio(); f.NeverStart=true;
            b=TestWavTriggers.backend(f); b.configure(TestWavTriggers.settings()); b.open();
            b.submit("video_onset","pending",10.2);
            b.close();
            tc.verifyEmpty(b.Pending); tc.verifyEmpty(b.Master); tc.verifyFalse(b.IsOpen);
            receipts=b.poll(); tc.verifyEqual(receipts.event_id,"pending");
            tc.verifyEqual(receipts.status,"failed"); tc.verifyTrue(isfinite(receipts.completion_getsecs));
            tc.verifyTrue(receipts.qc_only_failure);
            tc.verifyEmpty(b.poll());
        end
        function renamedDuplicateSamplesFailValidation(tc)
            s=TestWavTriggers.settings(); source=ephys.loadTriggerWaveforms(s);
            directory=tempname; mkdir(directory); cleanup=onCleanup(@() rmdir(directory,'s')); %#ok<NASGU>
            for k=1:4, copyfile(char(source(k).path),fullfile(directory,char(source(k).file))); end
            copyfile(char(source(1).path),fullfile(directory,'TrigP16.wav'),'f');
            s.wav.directory=directory;
            tc.verifyError(@() ephys.loadTriggerWaveforms(s),'ephys:TriggerWaveform');
        end
    end
    methods (Static)
        function s=settings()
            s=struct('backend',"wav",'memory_backend',"dummy", ...
                'waveforms',struct('run_start','TrigP08.wav','run_end','TrigN08.wav', ...
                    'video_onset','TrigP16.wav','video_offset','TrigN16.wav'), ...
                'wav',struct('directory','assets/triggers','device_index',[], ...
                    'device_name','','sample_rate_hz',48000,'channels',2,'output_channel',2,'gain',.5, ...
                    'latency_class',2,'minimum_lead_s',.1,'minimum_low_s',.01, ...
                    'completion_timeout_s',.5,'max_sync_error_s',.002));
        end
        function b=backend(f)
            b=ephys.WavTriggerBackend(@(varargin) f.call(varargin{:}), ...
                @() f.Now,@(s) f.advance(s),@() []);
        end
        function [o,f]=output()
            f=FakeWavAudio(); b=TestWavTriggers.backend(f);
            o=ephys.TriggerOutput(TestWavTriggers.settings(),b,30,@() f.Now);
            o.open();
        end
    end
end
