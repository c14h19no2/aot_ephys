classdef TestTriggerTimingDiagnostic < matlab.unittest.TestCase
    methods (Test)
        function separatesEarlyAudioFromLateVisual(tc)
            early = TestTriggerTimingDiagnostic.marker();
            early.audio_start_getsecs = 9.45;
            late = TestTriggerTimingDiagnostic.marker();
            late.audio_start_getsecs = 10;
            late.associated_flip_getsecs = 10.55;
            rows = ephys.triggerTimingBreakdown([early;late]);
            tc.verifyEqual(rows.audio_visual_delta_ms,[-550;-550],'AbsTol',1e-9);
            tc.verifyEqual(rows.audio_schedule_error_ms,[-550;0],'AbsTol',1e-9);
            tc.verifyEqual(rows.visual_prediction_error_ms,[0;550],'AbsTol',1e-9);
        end
        function earlierReservationAloneDoesNotCreateAnOffset(tc)
            first = TestTriggerTimingDiagnostic.marker();
            first.write_getsecs = 9.9;
            second = first;
            second.request_getsecs = 9.499;
            second.write_getsecs = 9.5;
            rows = ephys.triggerTimingBreakdown([first;second]);
            tc.verifyEqual(rows.reservation_lead_ms,[100;500],'AbsTol',1e-9);
            tc.verifyEqual(rows.audio_from_write_ms,[100;500],'AbsTol',1e-9);
            tc.verifyEqual(rows.audio_visual_delta_ms,[0;0]);
        end
        function missingAndCancelledObservationsAreNotInvented(tc)
            row = TestTriggerTimingDiagnostic.marker();
            row.status = "cancelled";
            row.audio_start_getsecs = NaN;
            row.associated_flip_getsecs = NaN;
            rows = ephys.triggerTimingBreakdown(row);
            tc.verifyEqual(rows.status,"cancelled");
            tc.verifyTrue(isnan(rows.audio_schedule_error_ms));
            tc.verifyTrue(isnan(rows.visual_prediction_error_ms));
            tc.verifyTrue(isnan(rows.audio_visual_delta_ms));
            tc.verifyEqual(rows.reservation_lead_ms,500,'AbsTol',1e-9);
            empty = ephys.triggerTimingBreakdown([]);
            tc.verifyEqual(height(empty),0);
            tc.verifyTrue(ismember('audio_visual_delta_ms',empty.Properties.VariableNames));
        end
        function recomputesDifferencesFromRawTimes(tc)
            row = TestTriggerTimingDiagnostic.marker();
            row.audio_visual_delta_s = 999;
            row.planned_audio_getsecs = 10.002;
            row.audio_start_getsecs = 10.003;
            row.associated_flip_getsecs = 10.006;
            rows = ephys.triggerTimingBreakdown(row);
            tc.verifyEqual(rows.target_difference_ms,2,'AbsTol',1e-9);
            tc.verifyEqual(rows.audio_visual_delta_ms,-3,'AbsTol',1e-9);
            tc.verifyEqual(rows.audio_visual_delta_ms, ...
                rows.audio_schedule_error_ms-rows.visual_prediction_error_ms+ ...
                rows.target_difference_ms,'AbsTol',1e-9);
        end
        function preflightUsesSelectedDeviceAndLeavesYamlUnchanged(tc)
            folder = tempname;
            mkdir(folder);
            guard = onCleanup(@() rmdir(folder,'s')); %#ok<NASGU>
            site = struct('display',struct('screen_index',0, ...
                'resolution_px',{{1920,1080}},'expected_refresh_hz',60), ...
                'stimulus',struct('fixation',struct('dot_radius_px',5, ...
                'surround_diameter_px',50)), ...
                'playback',struct('native_media_root',fullfile(folder,'unused_media')), ...
                'markers',struct('wav',struct('output_channel',1,'device_index',7, ...
                'minimum_lead_s',.500)), ...
                'paths',struct('output_root',folder));
            sitePath = fullfile(folder,'site.yml');
            yaml.dumpFile(sitePath,site,'block');
            before = ephys.sha256(sitePath);
            output = fullfile(folder,'diagnostic');
            report = diagnose_aot_ephys_trigger_timing('Site',sitePath,'Output',output, ...
                'TrialsPerLead',3,'PreflightOnly',true);
            tc.verifyEqual(report.status,"preflight_complete");
            tc.verifyEqual(report.minimum_lead_s,[.100 .500]);
            tc.verifyEqual(report.site_path,string(sitePath));
            tc.verifyEqual(ephys.sha256(sitePath),before);
            plan = jsondecode(fileread(fullfile(output,'planned_conditions.json')));
            tc.verifyNumElements(plan.conditions,2);
            for k=1:2
                c = plan.conditions(k);
                tc.verifyEqual(c.markers.wav.minimum_lead_s,report.minimum_lead_s(k));
                tc.verifyEqual(c.markers.wav.output_channel,1);
                tc.verifyEqual(c.markers.wav.device_index,7);
                tc.verifyEqual(c.display.resolution_px,[1920;1080]);
                tc.verifyTrue(c.display.full_screen);
                tc.verifyFalse(c.display.skip_sync_tests);
                tc.verifyTrue(c.debug);
                tc.verifyFalse(c.debug_simulated_input_only);
                tc.verifyEqual(string(c.schedule),repmat("blank",3,1));
                tc.verifyEqual(c.protocol.video_pre_fixation_s,1);
                tc.verifyEqual(c.protocol.video_duration_s,.5);
                tc.verifyEqual(c.protocol.video_initial_fixation_s,1);
                tc.verifyEqual(c.protocol.video_final_fixation_s,1);
            end
            tc.verifyFalse(isfolder(fullfile(output,'condition_01')));
            tc.verifyError(@() diagnose_aot_ephys_trigger_timing('Site',sitePath, ...
                'Output',output,'PreflightOnly',true),'ephys:OutputExists');
        end
        function rejectsInvalidLeadsBeforeOpeningDevices(tc)
            for value={0,-.1,NaN,Inf,[.1 .1],[],"0.5",.1+1i}
                tc.verifyError(@() diagnose_aot_ephys_trigger_timing('LeadSeconds',value{1}), ...
                    'ephys:DiagnosticLead');
            end
            tc.verifyError(@() diagnose_aot_ephys_trigger_timing('TrialsPerLead',0), ...
                'ephys:DiagnosticTrials');
            tc.verifyError(@() diagnose_aot_ephys_trigger_timing('SkipSyncTests',1), ...
                'ephys:DiagnosticOption');
        end
    end
    methods (Static,Access=private)
        function row = marker()
            row = ephys.emptyMarker();
            row.marker_nr = 1; row.trial_nr = 1;
            row.event_type = "blank_onset"; row.trigger_key = "video_onset";
            row.status = "complete"; row.output_channel = 2;
            row.request_getsecs = 9.499;
            row.write_getsecs = 9.5;
            row.planned_audio_getsecs = 10;
            row.predicted_visual_getsecs = 10;
            row.audio_start_getsecs = 10;
            row.associated_flip_getsecs = 10;
        end
    end
end
