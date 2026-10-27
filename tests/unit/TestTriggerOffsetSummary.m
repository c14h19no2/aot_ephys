classdef TestTriggerOffsetSummary < matlab.unittest.TestCase
    methods (Test)
        function keepsFailedOffsetsAndRecomputesFromActualTimes(tc)
            rows=repmat(ephys.emptyMarker(),8,1);
            states=["complete","failed","dummy","cancelled","queued", ...
                "complete","complete","failed"];
            for k=1:numel(rows)
                rows(k).marker_nr=k;
                rows(k).trial_nr=k;
                rows(k).event_type="video_onset";
                rows(k).trigger_key="video_onset";
                rows(k).status=states(k);
                rows(k).associated_flip_getsecs=10*k;
                rows(k).audio_start_getsecs=10*k+.001;
                rows(k).audio_visual_delta_s=999;
            end
            rows(2).audio_start_getsecs=20-.004;
            rows(2).sync_status="failed";
            rows(6).audio_start_getsecs=NaN;
            rows(7).associated_flip_getsecs=NaN;
            rows(8).audio_start_getsecs=Inf;
            [s,p]=ephys.triggerOffsetSummary(rows);
            tc.verifyEqual([p.marker_nr],[1 2]);
            tc.verifyEqual([p.time_s],[0 10]);
            tc.verifyEqual([p.delta_ms],[1 -4],'AbsTol',1e-9);
            tc.verifyEqual(string({p.status}),["complete","failed"]);
            tc.verifyEqual(s.total_marker_count,8);
            tc.verifyEqual(s.plotted_marker_count,2);
            tc.verifyEqual(s.excluded_marker_count,6);
            tc.verifyEqual(s.failed_marker_count,1);
            tc.verifyEqual(s.outside_reference_count,1);
            tc.verifyEqual(s.outside_median_reference_count,2);
            tc.verifyEqual(s.min_s,-.004,'AbsTol',1e-12);
            tc.verifyEqual(s.max_s,.001,'AbsTol',1e-12);
            tc.verifyEqual(s.mean_s,-.0015,'AbsTol',1e-12);
            tc.verifyEqual(s.median_s,-.0015,'AbsTol',1e-12);
            tc.verifyEqual(s.stddev_s,std([.001 -.004]),'AbsTol',1e-12);
            tc.verifyEqual(s.p95_absolute_s,.00385,'AbsTol',1e-12);
            tc.verifyEqual(s.reference_limit_s,.002);
            tc.verifyEqual(s.origin_getsecs,10);
            tc.verifyEqual(s.origin_kind,"first_observed_flip");
        end
        function prefersRunStartFlipEvenWithoutItsAudioReceipt(tc)
            start=ephys.emptyMarker(); start.event_type="run_start";
            start.associated_flip_getsecs=100;
            row=TestTriggerOffsetSummary.observation(114.4,114.401);
            event=ephys.emptyEvent(); event.event_type="run_start";
            event.onset_getsecs=99;
            [s,p]=ephys.triggerOffsetSummary([start;row],event,.0015);
            tc.verifyEqual(s.origin_kind,"run_start_flip");
            tc.verifyEqual(s.origin_getsecs,100);
            tc.verifyEqual(p.time_s,14.4,'AbsTol',1e-12);
            tc.verifyEqual(s.plotted_marker_count,1);
            tc.verifyEqual(s.excluded_marker_count,1);
            tc.verifyEqual(s.reference_limit_s,.0015);
        end
        function fallsBackToRunStartEvent(tc)
            row=TestTriggerOffsetSummary.observation(25,25.003);
            events=repmat(ephys.emptyEvent(),3,1);
            events(1).event_type="run_start";
            events(2).event_type="run_start"; events(2).onset_getsecs=20;
            events(3).event_type="run_start"; events(3).onset_getsecs=21;
            [s,p]=ephys.triggerOffsetSummary(row,events);
            tc.verifyEqual(s.origin_kind,"run_start_event");
            tc.verifyEqual(s.origin_getsecs,20);
            tc.verifyEqual(p.time_s,5);
            tc.verifyTrue(isnan(s.stddev_s));
            tc.verifyEqual(s.p95_absolute_s,.003,'AbsTol',1e-12);
        end
        function emptyOrNonvisualDataNeverBecomesZeroOffset(tc)
            [s,p]=ephys.triggerOffsetSummary();
            tc.verifyEmpty(p);
            tc.verifySize(p,[0 1]);
            tc.verifyEqual(fieldnames(p), ...
                {'marker_nr';'trial_nr';'event_type';'trigger_key'; ...
                'time_s';'delta_ms';'status'});
            tc.verifyEqual(s.origin_kind,"unavailable");
            tc.verifyTrue(isnan(s.origin_getsecs));
            tc.verifyEqual(s.plotted_marker_count,0);
            tc.verifyTrue(all(isnan([s.min_s,s.max_s,s.mean_s, ...
                s.median_s,s.stddev_s,s.p95_absolute_s])));
            row=ephys.emptyMarker(); row.event_type="run_end";
            row.status="complete"; row.audio_start_getsecs=35;
            [s,p]=ephys.triggerOffsetSummary(row);
            tc.verifyEmpty(p);
            tc.verifyEqual(s.excluded_marker_count,1);
            tc.verifyEqual(s.outside_reference_count,0);
            tc.verifyEqual(s.outside_median_reference_count,0);
        end
        function constantOffsetIsOnlyOutsideTheZeroReference(tc)
            rows=repmat(ephys.emptyMarker(),4,1);
            delta=[.0074 .0075 .0076 .0102];
            for k=1:4
                rows(k)=TestTriggerOffsetSummary.observation(k,k+delta(k));
            end
            s=ephys.triggerOffsetSummary(rows);
            tc.verifyEqual(s.median_s,.00755,'AbsTol',1e-12);
            tc.verifyEqual(s.outside_reference_count,4);
            tc.verifyEqual(s.outside_median_reference_count,1);
        end
        function referenceLimitMustBeValid(tc)
            for limit={-1,NaN,Inf,[.001 .002],1i,".002"}
                tc.verifyError(@() ephys.triggerOffsetSummary([],[],limit{1}), ...
                    'ephys:TriggerOffsetLimit');
            end
        end
        function consoleSummaryHasThreeQuantitativeLines(tc)
            rows=[TestTriggerOffsetSummary.observation(0,.001); ...
                TestTriggerOffsetSummary.observation(1,1.004788)];
            summary=ephys.triggerOffsetSummary(rows);
            output=evalc('ephys.printTriggerOffsetSummary(summary);');
            lines=splitlines(strtrim(string(output)));
            tc.verifyNumElements(lines,3);
            tc.verifyTrue(contains(lines(1),'N=2'));
            tc.verifyTrue(contains(lines(1),'median=+2.894 ms'));
            tc.verifyTrue(contains(lines(2),'Range=[+1.000, +4.788] ms'));
            tc.verifyTrue(contains(lines(3),'Beyond median +/-2 ms (trial QC rule): 0/2 (0.0%)'));
            tc.verifyTrue(contains(lines(3),'beyond +/-2 ms of zero: 1/2'));
        end
        function consoleSummaryDoesNotInventEmptyStatistics(tc)
            summary=ephys.triggerOffsetSummary();
            output=evalc('ephys.printTriggerOffsetSummary(summary);');
            lines=splitlines(strtrim(string(output)));
            tc.verifyNumElements(lines,2);
            tc.verifyTrue(contains(lines(1),'0 observed'));
            tc.verifyFalse(contains(string(output),'NaN'));
        end
    end
    methods (Static,Access=private)
        function row=observation(visual,audio)
            row=ephys.emptyMarker(); row.status="complete";
            row.event_type="video_onset"; row.trigger_key="video_onset";
            row.associated_flip_getsecs=visual;
            row.audio_start_getsecs=audio;
        end
    end
end
