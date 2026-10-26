classdef TestEphys < matlab.unittest.TestCase
    methods (Test)
        function scannerFreeConfigAndSchedule(tc)
            root = ephys.projectRoot();
            tc.verifyError(@() ephys.loadConfig("video",fullfile(root,'config', ...
                'runs','debug_blank.yml'),"",true,""),'ephys:NativeMediaRoot');
            [c,~] = ephys.loadConfig("video",fullfile(root,'config', ...
                'runs','debug_blank.yml'),testSite(),true,"");
            tc.verifyEqual(numel(c.schedule),4);
            tc.verifyFalse(isfield(c.input,'scanner_trigger_key'));
            tc.verifyFalse(isfield(c.protocol,'dummy_trigger_wait_s'));
            tc.verifyEqual(string(c.markers.waveforms.video_onset),"TrigP16.wav");
            tc.verifyEqual(string(c.markers.waveforms.run_end),"TrigN08.wav");
            tc.verifyFalse(isfield(c.markers,'codes'));
            [flipCap,eventCap,markerCap] = ephys.logCapacity(c);
            tc.verifyGreaterThan(flipCap,4*60);
            tc.verifyLessThan(flipCap,c.logging.max_flips);
            tc.verifyGreaterThan(eventCap,0);
            tc.verifyGreaterThan(markerCap,0);
        end
        function archivedMemoryAnswersMatchSavedOrder(tc)
            settings = fullfile(ephys.projectRoot(),'config','runs','memory_main');
            schedule = ephys.readYaml(fullfile(settings, ...
                'experiment_settings_sub_01_ses_01_run_01.yml'));
            pictures = ephys.validatePictureSchedule( ...
                schedule.stimuli.picture_files);
            tc.verifyEqual(numel(pictures),180);
            answers = ephys.loadAnswers(fullfile(settings,'answers', ...
                'answer_dict_sub_01_ses_01.tsv'),pictures);
            tc.verifyEqual(double(answers.Count),180);
            [expected,correct] = ephys.scoreMemory(answers,pictures(1),"yes");
            tc.verifyEqual(expected,"Y");
            tc.verifyEqual(correct,1);
        end
        function markerAssociationsAndDummyFailure(tc)
            backend = ephys.DummyTriggerBackend(@() 10,3);
            counter = 0;
            c=TestTriggerLifecycle.config(); settings=c.markers;
            output = ephys.TriggerOutput(settings,backend,5,@() 9,@nextId);
            output.open();
            ctx = TestEphys.makeContext("video","0001_fw.mp4");
            row = output.emit("video_onset",ctx, ...
                struct('seq',1,'stimulus',2),NaN,"");
            tc.verifyEqual(row.trigger_key,"video_onset");
            tc.verifyEqual(row.associated_flip_seq,1);
            tc.verifyEqual(row.associated_flip_getsecs,2);
            tc.verifyEqual(row.status,"dummy");
            tc.verifyTrue(isnan(row.physical_onset_getsecs));
            ctx.video_file = "0001_rv.mp4";
            row = output.emit("video_onset",ctx, ...
                struct('seq',3,'stimulus',4),NaN,"");
            tc.verifyEqual(row.trigger_key,"video_onset");
            tc.verifyEqual(row.video_file,"0001_rv.mp4");
            tc.verifyError(@() output.emit("video_offset",ctx, ...
                struct('seq',4,'stimulus',5),NaN,""), ...
                'ephys:TriggerFailure');
            tc.verifyEqual(output.Count,3);
            saved = output.records();
            tc.verifyEqual(saved(end).status,"failed");
            tc.verifyError(@() output.close(),'ephys:TriggerFailure');
            tc.verifyFalse(backend.IsOpen);
            function id = nextId()
                counter = counter+1;
                id = "event-"+string(counter);
            end
        end
        function pendingPulseFailsAtClose(tc)
            backend = QueuedTriggerBackend();
            c=TestTriggerLifecycle.config(); settings=c.markers;
            output = ephys.TriggerOutput(settings,backend,2,@() 2,@() "queued-id");
            output.open();
            ctx = TestEphys.makeContext("video","0001_fw.mp4");
            output.emit("video_onset",ctx, ...
                struct('seq',1,'stimulus',1),NaN,"");
            tc.verifyError(@() output.close(),'ephys:TriggerFailure');
            tc.verifyFalse(backend.IsOpen);
            tc.verifyNotEmpty(output.CloseError);
        end
        function memoryOnsetResponseAndScoring(tc)
            log = ephys.TimelineLog(5,5);
            ctx = TestEphys.makeContext("memory","1056_fw.png");
            raw = TestEphys.raw(5,0);
            picture = log.flip(ctx,"picture",1,raw,4.99, ...
                ephys.noFrame("picture"),"off");
            log.event(ctx,"memory_stimulus_onset","picture",5,picture);
            response = log.event(ctx,"memory_response","picture",5.6,[]);
            response.input_getsecs = 5.6;
            response.rt_s = response.input_getsecs-picture.stimulus_onset_getsecs;
            log.updateLastEvent(response);
            log.flip(ctx,"memory_clear",1,TestEphys.raw(5.7,0), ...
                5.69,ephys.noFrame("fixation"),"off");
            tc.verifyEqual(response.rt_s,0.6,'AbsTol',1e-12);
            tc.verifyEqual(log.Events(1).associated_flip_seq,1);
            tc.verifyEqual(log.Events(2).associated_flip_seq,NaN);
            answers = containers.Map({'1056_fw'},{'Y'});
            [expected,correct] = ephys.scoreMemory(answers, ...
                "1056_fw.png","yes");
            tc.verifyEqual(expected,"Y");
            tc.verifyEqual(correct,1);
            r = ephys.reconstructRecords(log.flipRecords(), ...
                log.eventRecords(),repmat(ephys.emptyMarker(),0,1));
            tc.verifyEqual(r.trials.memory_onset_getsecs,5);
            tc.verifyTrue(r.trials.software_marker_issue);
        end
        function perfectRefreshCadenceAndFeatures(tc)
            [f,e,m,media,c] = TestEphys.videoTrace();
            r = ephys.reconstructRecords(f,e,m,media,c);
            tc.verifyEqual(r.trials.observed_video_refreshes,120);
            tc.verifyEqual(r.trials.expected_video_refreshes,120);
            tc.verifyEqual(r.trials.unexpected_repeat_count,0);
            tc.verifyEqual(r.trials.pts_gap_count,0);
            tc.verifyEqual(r.trials.quality_state, ...
                "software_checks_valid_hardware_unverified");
            tc.verifyEqual(r.frames(1).interval_end_getsecs,1/120, ...
                'AbsTol',1e-12);
            tc.verifyEqual(r.frames(end).interval_end_getsecs,1, ...
                'AbsTol',1e-12);
            tc.verifyTrue(all(isnan([r.frames.source_frame_index])));
            map = repmat(struct('video_file',"0001_fw.mp4", ...
                'media_sha256',"hash",'pts_s',NaN, ...
                'feature_value',NaN,'validated',true),60,1);
            for i=1:60
                map(i).pts_s = (i-1)/60;
                map(i).feature_value = i^2;
            end
            features = ephys.attachFeatures(r.frames,map,media);
            tc.verifyEqual([features(1:4).feature_value],[1 1 4 4]);
            tc.verifyEqual(features(end).interval_end_getsecs,1);
        end
        function delayedFirstFrame(tc)
            [f,e,m,media,c] = TestEphys.videoTrace();
            e(1).planned_onset_getsecs = -0.05;
            r = ephys.reconstructRecords(f,e,m,media,c);
            tc.verifyTrue(r.trials.first_frame_anomaly);
            tc.verifyEqual(r.trials.quality_state,"timing_anomaly_detected");
        end
        function debugTimingFlagSurvivesAnomaly(tc)
            [f,e,m,media,c] = TestEphys.videoTrace();
            c.debug = true;
            c.display.skip_sync_tests = true;
            f(10).missed_s = 0.01;
            r = ephys.reconstructRecords(f,e,m,media,c);
            tc.verifyEqual(r.trials.quality_state,"timing_anomaly_detected");
            tc.verifyEqual(r.run_qc.timing_anomaly_count,1);
            tc.verifyEqual(r.run_qc.debug_unvalidated_count,1);
        end
        function unexpectedRepeat(tc)
            [f,e,m,media,c] = TestEphys.videoTrace();
            f(3).decoded_frame_sequence = 1;
            f(3).source_pts_s = 0;
            f(3).frame_status = "duplicate_pts_delivery";
            r = ephys.reconstructRecords(f,e,m,media,c);
            tc.verifyEqual(r.trials.unexpected_repeat_count,1);
            tc.verifyEqual(r.trials.duplicate_pts_delivery_count,1);
        end
        function ptsGapDoesNotInventSourceIndex(tc)
            [f,e,m,media,c] = TestEphys.videoTrace();
            f(7).frame_status = "pts_gap";
            r = ephys.reconstructRecords(f,e,m,media,c);
            tc.verifyEqual(r.trials.pts_gap_count,1);
            tc.verifyTrue(isnan(r.trials.source_skip_count));
        end
        function predecodedSourceIndicesDriveQC(tc)
            [f,e,m,media,c]=TestEphys.videoTrace();
            for k=1:120
                f(k).source_frame_index=f(k).decoded_frame_sequence-1;
                f(k).source_pts_s=f(k).source_pts_s+1;
            end
            media.source_pts_s=1+(0:59)'/60;
            media.duration_s=1;
            r=ephys.reconstructRecords(f,e,m,media,c);
            tc.verifyFalse(r.trials.first_frame_anomaly);
            tc.verifyEqual(r.trials.source_skip_count,0);
            tc.verifyEqual(r.trials.unresolved_source_frame_count,0);
            f(3).source_frame_index=2; f(4).source_frame_index=2;
            r=ephys.reconstructRecords(f,e,m,media,c);
            tc.verifyEqual(r.trials.source_skip_count,1);
            tc.verifyEqual(r.trials.quality_state,"timing_anomaly_detected");
        end
        function missedFlip(tc)
            [f,e,m,media,c] = TestEphys.videoTrace();
            f(10).missed_s = 0.01;
            r = ephys.reconstructRecords(f,e,m,media,c);
            tc.verifyEqual(r.trials.missed_deadline_count,1);
        end
        function externalMissedFlagDoesNotInventTimingFailure(tc)
            [f,e,m,media,c] = TestEphys.videoTrace();
            c.display_timing = ephys.assessDisplayTiming(1/120,1,0, ...
                struct('ImagingMode',2^20));
            f(10).missed_s = 0.01;
            r = ephys.reconstructRecords(f,e,m,media,c);
            tc.verifyEqual(r.trials.missed_deadline_count,1);
            tc.verifyFalse(r.trials.missed_deadline_flag_applicable);
            tc.verifyEqual(r.trials.quality_state, ...
                "software_checks_valid_hardware_unverified");
            f(7).frame_status = "pts_gap";
            r = ephys.reconstructRecords(f,e,m,media,c);
            tc.verifyEqual(r.trials.quality_state,"timing_anomaly_detected");
        end
        function nonIncreasingPresentationTimesAreFlagged(tc)
            [f,e,m,media,c] = TestEphys.videoTrace();
            f(10).stimulus_onset_getsecs = f(9).stimulus_onset_getsecs;
            r = ephys.reconstructRecords(f,e,m,media,c);
            tc.verifyEqual(r.trials.timestamp_issue_count,1);
            tc.verifyEqual(r.trials.quality_state,"timing_anomaly_detected");
            f(10).stimulus_onset_getsecs = NaN;
            r = ephys.reconstructRecords(f,e,m,media,c);
            tc.verifyEqual(r.trials.timestamp_issue_count,1);
        end
        function missingAndDuplicatedTTL(tc)
            [f,e,m,media,c] = TestEphys.videoTrace();
            dummyTTL = struct('event_id',"onset",'ephys_time_s',10, ...
                'trigger_key',"video_onset",'waveform_file',"TrigP16.wav",'verified',true);
            tc.verifyError(@() ephys.reconstructRecords( ...
                f,e,m,media,c,dummyTTL),'ephys:TTLSoftwareOnly');
            m(1).status = "hardware_requested";
            m(2).status = "hardware_requested";
            ttl = struct('event_id',"unrelated",'ephys_time_s',10, ...
                'trigger_key',"video_onset",'waveform_file',"TrigP16.wav",'verified',true);
            r = ephys.reconstructRecords(f,e,m,media,c,ttl);
            tc.verifyEqual(r.trials.ttl_match_status,"missing");
            ttl = repmat(struct('event_id',"onset",'ephys_time_s',10, ...
                'trigger_key',"video_onset",'waveform_file',"TrigP16.wav",'verified',true),3,1);
            ttl(3).event_id = "offset";
            ttl(3).trigger_key = "video_offset";
            ttl(3).waveform_file = "TrigN16.wav";
            r = ephys.reconstructRecords(f,e,m,media,c,ttl);
            tc.verifyEqual(r.trials.ttl_match_status,"duplicate");
        end
        function prematureTerminationAndAbort(tc)
            [f,e,m,media,c] = TestEphys.videoTrace();
            f = f(1:end-1);
            e = e(1);
            m = m(1);
            r = ephys.reconstructRecords(f,e,m,media,c);
            tc.verifyTrue(r.trials.incomplete);
            tc.verifyEqual(r.trials.quality_state,"incomplete_playback");
            abort = ephys.emptyEvent();
            abort.trial_id = f(1).trial_id;
            abort.event_type = "trial_abort";
            e(2) = abort;
            r = ephys.reconstructRecords(f,e,m,media,c);
            tc.verifyEqual(r.trials.quality_state,"aborted_trial");
        end
        function abortBeforeTrialFlipIsStillReported(tc)
            instruction = ephys.emptyFlip();
            instruction.flip_seq = 1;
            instruction.trial_nr = 0;
            instruction.trial_id = "instruction";
            instruction.stimulus_onset_getsecs = 1;
            abort = ephys.emptyEvent();
            abort.trial_id = "trial-2";
            abort.trial_nr = 2;
            abort.task = "video";
            abort.video_file = "0002_fw.mp4";
            abort.event_type = "trial_abort";
            r = ephys.reconstructRecords(instruction,abort, ...
                repmat(ephys.emptyMarker(),0,1));
            tc.verifyEqual(r.run_qc.trial_count,1);
            tc.verifyEqual(r.trials.video_file,"0002_fw.mp4");
            tc.verifyEqual(r.trials.quality_state,"aborted_trial");
        end
        function blankNeverGetsVideoMarkers(tc)
            [f,e,m,media,c] = TestEphys.videoTrace();
            f(1:end-1) = [];
            f(1).video_file = "blank";
            f(1).phase = "blank";
            f(1).condition = "blank";
            e = repmat(ephys.emptyEvent(),0,1);
            m = repmat(ephys.emptyMarker(),0,1);
            r = ephys.reconstructRecords(f,e,m,media,c);
            tc.verifyTrue(r.trials.blank);
            tc.verifyFalse(r.trials.software_marker_issue);
        end
        function clockFitRequiresVerifiedUniqueAnchors(tc)
            software = repmat(ephys.emptyMarker(),4,1);
            ttl = repmat(struct('event_id',"",'ephys_time_s',NaN, ...
                'trigger_key',"video_onset",'waveform_file',"TrigP16.wav",'verified',true),4,1);
            for i=1:4
                software(i).event_id = "id-"+string(i);
                software(i).request_getsecs = 1000+i*100;
                software(i).trigger_key = "video_onset";
                software(i).waveform_file = "TrigP16.wav";
                software(i).status = "complete"; % Synthetic completed clock anchors.
                software(i).audio_start_getsecs = software(i).request_getsecs;
                ttl(i).event_id = software(i).event_id;
                ttl(i).ephys_time_s = 3+1.0001*software(i).request_getsecs;
            end
            fit = ephys.fitClockMapping(software,ttl,0.001);
            tc.verifyEqual(fit.clock_rate,1.0001,'AbsTol',1e-10);
            tc.verifyTrue(fit.within_threshold);
            shifted = ttl;
            shifted(4).ephys_time_s = shifted(4).ephys_time_s+0.02;
            fit = ephys.fitClockMapping(software,shifted,0.001);
            tc.verifyFalse(fit.within_threshold);
            reordered = ttl;
            reordered(3).ephys_time_s = reordered(2).ephys_time_s-1;
            tc.verifyError(@() ephys.fitClockMapping(software,reordered), ...
                'ephys:ClockOrder');
            ttl(2).event_id = ttl(1).event_id;
            tc.verifyError(@() ephys.fitClockMapping(software,ttl), ...
                'ephys:ClockDuplicate');
        end
    end
    methods (Static)
        function ctx = makeContext(task,name)
            ctx = struct('trial_id',"trial-1",'trial_nr',1, ...
                'task',string(task),'video_file',"",'picture_file',"", ...
                'condition',"forward");
            if task=="video", ctx.video_file = string(name); end
            if task=="memory", ctx.picture_file = string(name); end
        end
        function raw = raw(t,missed)
            raw = struct('vbl',t,'stimulus',t, ...
                'returned',t+0.0001,'missed',missed);
        end
        function [f,e,m,media,c] = videoTrace()
            ctx = TestEphys.makeContext("video","0001_fw.mp4");
            log = ephys.TimelineLog(130,5);
            for i=1:120
                seq = ceil(i/2);
                info = struct('texture_handle',seq, ...
                    'decoded_sequence',seq,'source_frame_index',NaN, ...
                    'pts',(seq-1)/60,'status',"expected_repeat");
                if i==1, info.status="first_frame_prepared"; end
                if mod(i,2)==1 && i>1, info.status="new_frame"; end
                row = log.flip(ctx,"video",i, ...
                    TestEphys.raw((i-1)/120,0),(i-1)/120-0.004, ...
                    info,"off");
                if i==1
                    ev = log.event(ctx,"video_onset","video",0,row);
                    ev.planned_onset_getsecs = 0;
                    ev.planned_deadline_getsecs = 1;
                    ev.marker_event_id = "onset";
                    log.updateLastEvent(ev);
                end
            end
            off = log.flip(ctx,"post_fixation",1, ...
                TestEphys.raw(1,0),0.996,ephys.noFrame("fixation"),"off");
            ev = log.event(ctx,"video_offset","post_fixation",1,off);
            ev.marker_event_id = "offset";
            log.updateLastEvent(ev);
            f = log.flipRecords(); e = log.eventRecords();
            m = repmat(ephys.emptyMarker(),2,1);
            m(1).event_id="onset"; m(1).event_type="video_onset";
            m(1).trial_id=ctx.trial_id; m(1).associated_flip_seq=1;
            m(1).associated_flip_getsecs=0; m(1).status="dummy";
            m(1).trigger_key="video_onset"; m(1).waveform_file="TrigP16.wav";
            m(2).event_id="offset"; m(2).event_type="video_offset";
            m(2).trial_id=ctx.trial_id; m(2).associated_flip_seq=121;
            m(2).associated_flip_getsecs=1; m(2).status="dummy";
            m(2).trigger_key="video_offset"; m(2).waveform_file="TrigN16.wav";
            media = struct('name',"0001_fw.mp4",'fps',60,'sha256',"hash");
            c = struct('protocol',struct('video_duration_s',1), ...
                'display',struct('expected_refresh_hz',120), ...
                'markers',struct('video_offset_enabled',true));
        end
    end
end
