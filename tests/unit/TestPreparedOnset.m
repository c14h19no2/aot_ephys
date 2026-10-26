classdef TestPreparedOnset < matlab.unittest.TestCase
    methods (Test)
        function classFolderIsTheActiveImplementation(tc)
            tc.verifyEqual(which('ephys.Session'),fullfile(ephys.projectRoot(), ...
                '+ephys','@Session','Session.m'));
            ephys.assertSessionImplementation();
            tc.verifyFalse(isfile(fullfile(ephys.projectRoot(),'+ephys','Session.m')));
        end
        function bothLeadsKeepTheSameAudioAndVisualTarget(tc)
            for lead=[.1 .5]
                [output,audio,guard]=TestPreparedOnset.output(lead); %#ok<ASGLU>
                audio.Now=11-lead-.05;
                ready=audio.Now;
                calls=strings(0,1);
                [raw,marker]=ephys.submitPreparedOnset(11-.5/60,11, ...
                    @reserve,@flip,ready);
                tc.verifyEqual(calls,["reserve";"flip"]);
                tc.verifyEqual(marker.planned_audio_getsecs,11);
                tc.verifyEqual(raw.stimulus,11);
                tc.verifyEqual(raw.flip_submit_getsecs,ready);
                tc.verifyEqual(raw.frame_ready_getsecs,ready);
                row=output.associate(marker.event_id,struct('seq',1,'stimulus',raw.stimulus, ...
                    'frame_ready_getsecs',raw.frame_ready_getsecs, ...
                    'flip_submit_getsecs',raw.flip_submit_getsecs, ...
                    'flip_return_getsecs',raw.returned,'submission_mode',"direct"));
                tc.verifyEqual(row.audio_visual_delta_s,0,'AbsTol',1e-12);
                tc.verifyEqual(row.submission_mode,"direct");
                tc.verifyLessThanOrEqual(row.frame_ready_getsecs,row.request_getsecs);
                tc.verifyEqual(row.flip_submit_getsecs,row.write_getsecs);
                clear guard
            end

            function row=reserve(when)
                calls(end+1,1)="reserve";
                row=output.schedule("video_onset",ephys.context("video",1,"movie_fw.mp4"),when);
            end
            function raw=flip(when)
                calls(end+1,1)="flip";
                tc.verifyEqual(when,11-.5/60);
                tc.verifyEqual(output.records().status,"queued");
                submitted=audio.Now;
                audio.Now=11.001;
                raw=struct('vbl',11,'stimulus',11,'returned',audio.Now, ...
                    'missed',0,'flip_submit_getsecs',submitted,'submission_mode',"direct");
            end
        end
        function shortLeadStillSubmitsThePreparedFrameWithTheSameTarget(tc)
            [output,audio,guard]=TestPreparedOnset.output(.5); %#ok<ASGLU>
            audio.Now=10.6;
            flipped=false;
            [~,marker]=ephys.submitPreparedOnset(11-.5/60,11, ...
                @(when) output.schedule("video_onset",ephys.context("video",1,"movie_fw.mp4"),when), ...
                @flip,audio.Now);
            tc.verifyTrue(flipped);
            tc.verifyEqual(marker.planned_audio_getsecs,11);
            tc.verifyEqual(marker.audio_lead_shortfall_s,.1,'AbsTol',1e-12);
            tc.verifyEqual(output.records().audio_qc_flags,"insufficient_audio_lead");
            starts=audio.Calls(cellfun(@(c) strcmp(c{1},'Start') && c{2}~=1,audio.Calls));
            tc.verifyNumElements(starts,1);
            function raw=flip(when)
                tc.verifyEqual(when,11-.5/60);
                flipped=true; raw=struct();
            end
        end
        function unexpectedDisplayDelayStaysVisibleInTheOffset(tc)
            [output,audio,guard]=TestPreparedOnset.output(.5); %#ok<ASGLU>
            [raw,marker]=ephys.submitPreparedOnset(11-.5/60,11, ...
                @(when) output.schedule("blank_onset",ephys.context("video",1,"blank"),when), ...
                @flip,audio.Now);
            row=output.associate(marker.event_id,struct('seq',1,'stimulus',raw.stimulus));
            tc.verifyEqual(row.audio_start_getsecs,11);
            tc.verifyEqual(row.associated_flip_getsecs,11.55);
            tc.verifyEqual(row.audio_visual_delta_s,-.55,'AbsTol',1e-12);
            tc.verifyEqual(row.status,"complete");
            tc.verifyEqual(row.sync_status,"out_of_tolerance");
            function raw=flip(~)
                audio.Now=11.551;
                raw=struct('vbl',11.55,'stimulus',11.55,'returned',audio.Now,'missed',.55);
            end
        end
        function flipFailureKeepsAnIdentifiableCancellableReservation(tc)
            [output,audio,guard]=TestPreparedOnset.output(.5); %#ok<ASGLU>
            tc.verifyError(@() ephys.submitPreparedOnset(11-.5/60,11, ...
                @(when) output.schedule("video_onset",ephys.context("video",1,"movie_fw.mp4"),when), ...
                @flip,audio.Now),'test:FlipFailure');
            tc.verifyEqual(output.records().status,"queued");
            output.cancelPending();
            tc.verifyEqual(output.records().status,"cancelled");
            tc.verifyTrue(isnan(output.records().audio_start_getsecs));
            function raw=flip(~) %#ok<STOUT>
                error('test:FlipFailure','Injected display failure.');
            end
        end
        function submissionObservationsSurviveTsvReadback(tc)
            log=ephys.TimelineLog(2,2);
            raw=struct('vbl',11,'stimulus',11,'returned',11.002,'missed',0, ...
                'frame_ready_getsecs',10.4,'flip_submit_getsecs',10.45, ...
                'submission_mode',"direct");
            row=log.flip(ephys.context("video",1,"blank"),"blank",1,raw, ...
                11-.5/60,ephys.noFrame("fixation"),"off");
            file=[tempname '.tsv']; guard=onCleanup(@() delete(file));
            writetable(struct2table(row),file,'FileType','text','Delimiter','\t');
            loaded=ephys.readTimelineRows(file,ephys.emptyFlip());
            tc.verifyEqual(loaded.frame_ready_getsecs,10.4);
            tc.verifyEqual(loaded.flip_submit_getsecs,10.45);
            tc.verifyEqual(loaded.submission_mode,"direct");
        end
        function timingBreakdownSeparatesSubmissionFromDisplayDelay(tc)
            row=ephys.emptyMarker();
            row.frame_ready_getsecs=10.4; row.request_getsecs=10.41;
            row.write_getsecs=10.42; row.flip_submit_getsecs=10.4201;
            row.planned_audio_getsecs=11; row.predicted_visual_getsecs=11;
            row.audio_start_getsecs=11; row.associated_flip_getsecs=11.55;
            row.flip_return_getsecs=11.552; row.submission_mode="direct";
            result=ephys.triggerTimingBreakdown(row);
            tc.verifyEqual(result.submission_gap_ms,.1,'AbsTol',1e-9);
            tc.verifyEqual(result.visual_prediction_error_ms,550,'AbsTol',1e-9);
            tc.verifyEqual(result.audio_schedule_error_ms,0,'AbsTol',1e-9);
            tc.verifyEqual(result.flip_block_ms,1131.9,'AbsTol',1e-9);
            old=rmfield(row,{'frame_ready_getsecs','flip_submit_getsecs', ...
                'flip_return_getsecs','submission_mode'});
            result=ephys.triggerTimingBreakdown(old);
            tc.verifyTrue(isnan(result.submission_gap_ms));
            tc.verifyEqual(result.submission_mode,"");
        end
    end
    methods (Static,Access=private)
        function [output,audio,guard]=output(lead)
            config=ephys.readYaml(fullfile(ephys.projectRoot(),'config','experiment.yml'));
            config.markers.wav.minimum_lead_s=lead;
            audio=FakeWavAudio();
            backend=ephys.WavTriggerBackend(@audio.call,@() audio.Now, ...
                @(seconds) audio.advance(seconds),@() []);
            output=ephys.TriggerOutput(config.markers,backend,10,@() audio.Now);
            guard=onCleanup(@() delete(output));
            output.open();
        end
    end
end
