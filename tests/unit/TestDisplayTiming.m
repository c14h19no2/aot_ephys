classdef TestDisplayTiming < matlab.unittest.TestCase
    methods (Test)
        function appleExternalBackendPlaceholderDoesNotAbort(tc)
            % Flags captured in the full-screen M1 preflight, 2026-10-10.
            window = struct('ImagingMode',3178497,'SpecialFlags',83483426836);
            info = ephys.assessDisplayTiming(1/60,1,0,window);
            tc.verifyEqual(info.ifi_source,"external_backend_reported");
            tc.verifyFalse(info.interval_is_measured);
            tc.verifyFalse(info.sample_statistics_applicable);
            tc.verifyFalse(info.missed_deadline_flag_applicable);
            tc.verifyEqual(info.scheduling_ifi_s,1/60);
            tc.verifyNotEmpty(info.warning_message);
        end
        function placeholderIsNotRelabeledByPlausibleStatistics(tc)
            window = struct('ImagingMode',2^20,'SpecialFlags',0);
            info = ephys.assessDisplayTiming(1/120,100,0.00001,window);
            tc.verifyEqual(info.ifi_source,"external_backend_reported");
            tc.verifyFalse(info.interval_is_measured);
            saved = jsondecode(jsonencode(info));
            tc.verifyEqual(string(saved.physical_timestamp_validation), ...
                "not independently verified");
            tc.verifyFalse(saved.sample_statistics_applicable);
        end
        function noisyOrShortMeasurementContinuesWithEvidence(tc)
            for values=[20,100;0.0001,0.002]
                info = ephys.assessDisplayTiming(1/60,values(1),values(2));
                tc.verifyTrue(info.interval_is_measured);
                tc.verifyEqual(info.ifi_source,"measured");
                tc.verifyEqual(info.sample_statistics_status,"outside_reference_limits");
                tc.verifyNotEmpty(info.warning_message);
            end
            info = ephys.assessDisplayTiming(1/60,1,0);
            tc.verifyEqual(info.ifi_source,"unverified_ptb_estimate");
            tc.verifyFalse(info.interval_is_measured);
        end
        function ordinaryMeasurementAndDebugFallbackRemainDistinct(tc)
            info = ephys.assessDisplayTiming(1/60,100,0.00002);
            tc.verifyTrue(info.interval_is_measured);
            tc.verifyEqual(info.sample_statistics_status,"within_reference_limits");
            tc.verifyEqual(info.warning_message,"");
            tc.verifyTrue(info.missed_deadline_flag_applicable);
            info = ephys.assessDisplayTiming(1/60,NaN,NaN,struct(),true);
            tc.verifyEqual(info.ifi_source,"configured_debug_fallback");
            tc.verifyFalse(info.interval_is_measured);
            tc.verifyFalse(info.sample_statistics_applicable);
        end
        function unusableSchedulingIntervalStillFails(tc)
            for ifi=[NaN,Inf,0,-0.01]
                tc.verifyError(@() ephys.assessDisplayTiming(ifi,1,0), ...
                    'ephys:InvalidRefreshInterval');
            end
        end
    end
end
