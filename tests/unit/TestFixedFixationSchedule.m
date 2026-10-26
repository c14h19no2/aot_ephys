classdef TestFixedFixationSchedule < matlab.unittest.TestCase
    methods (Test)
        function usesMeasuredDisplayIntervalAcrossRefreshRates(tc)
            rates=[59.94,60,75,120,144];
            expectedCounts=[862,863,1079,1727,2073];
            for caseNr=1:numel(rates)
                ifi=1/rates(caseNr);
                anchor=100;
                phaseEnd=anchor+14.4;
                previous=0;
                available=anchor;
                targets=[];
                requests=[];
                indices=[];
                skipped=[];
                availabilities=[];
                while true
                    plan=ephys.nextFixationRefresh(anchor,phaseEnd,ifi,previous,available);
                    if isempty(plan), break; end
                    targets(end+1)=plan.target_getsecs; %#ok<AGROW>
                    requests(end+1)=plan.request_getsecs; %#ok<AGROW>
                    indices(end+1)=plan.refresh_index; %#ok<AGROW>
                    skipped(end+1)=plan.skipped_slots; %#ok<AGROW>
                    availabilities(end+1)=available; %#ok<AGROW>
                    previous=plan.refresh_index;
                    % Each simulated Flip returns 1 ms after its target.
                    available=plan.target_getsecs+.001;
                end
                tc.verifyNumElements(targets,expectedCounts(caseNr));
                tc.verifyEqual(indices,1:expectedCounts(caseNr));
                tc.verifyEqual(skipped,zeros(size(skipped)));
                tc.verifyEqual(targets,anchor+(1:expectedCounts(caseNr))*ifi);
                tc.verifyEqual(requests,targets-.5*ifi);
                tc.verifyGreaterThan(requests,availabilities);
                tc.verifyLessThan(targets+.5*ifi,phaseEnd);
            end
        end

        function lateRefreshesSkipSlotsWithoutMovingPhaseOrigin(tc)
            anchor=100;
            ifi=1/60;
            phaseEnd=anchor+2;
            first=ephys.nextFixationRefresh(anchor,phaseEnd,ifi,0,anchor+.007);
            tc.verifyEqual(first.refresh_index,1);
            tc.verifyEqual(first.skipped_slots,0);
            % Drawing misses slot 1's half-frame submission deadline.
            afterDrawing=ephys.nextFixationRefresh(anchor,phaseEnd,ifi,0,anchor+.009);
            tc.verifyEqual(afterDrawing.refresh_index,2);
            tc.verifyEqual(afterDrawing.skipped_slots,1);
            tc.verifyEqual(afterDrawing.target_getsecs,anchor+2*ifi);

            late=ephys.nextFixationRefresh(anchor,phaseEnd,ifi,1,anchor+3.1*ifi);
            tc.verifyEqual(late.refresh_index,4);
            tc.verifyEqual(late.skipped_slots,2);
            tc.verifyEqual(late.target_getsecs,anchor+4*ifi);
            veryLate=ephys.nextFixationRefresh(anchor,phaseEnd,ifi,4,anchor+24.2*ifi);
            tc.verifyEqual(veryLate.refresh_index,25);
            tc.verifyEqual(veryLate.skipped_slots,20);
            tc.verifyEqual(veryLate.target_getsecs,anchor+25*ifi);
            recovered=ephys.nextFixationRefresh(anchor,phaseEnd,ifi,25,anchor+25.1*ifi);
            tc.verifyEqual(recovered.refresh_index,26);
            tc.verifyEqual(recovered.skipped_slots,0);
            tc.verifyEqual(recovered.target_getsecs,anchor+26*ifi);
        end

        function cannotResubmitAnAlreadySubmittedSlot(tc)
            anchor=10;
            plan=ephys.nextFixationRefresh(anchor,anchor+1,.02,7,anchor+.001);
            tc.verifyEqual(plan.refresh_index,8);
            tc.verifyEqual(plan.skipped_slots,0);
            tc.verifyEqual(plan.target_getsecs,10.16,'AbsTol',1e-12);
        end

        function deadlineEqualityIsExpiredAtLargeClockValues(tc)
            anchor=1e6;
            ifi=1/60;
            deadline=anchor+10*ifi-.5*ifi;
            plan=ephys.nextFixationRefresh(anchor,anchor+1,ifi,0,deadline);
            tc.verifyEqual(plan.refresh_index,11);
            tc.verifyEqual(plan.skipped_slots,10);
            tc.verifyEqual(plan.target_getsecs,anchor+11*ifi);
            before=ephys.nextFixationRefresh(anchor,anchor+1,ifi,0,deadline-1e-6);
            tc.verifyEqual(before.refresh_index,10);
            tc.verifyGreaterThan(before.request_getsecs,deadline-1e-6);
        end

        function zeroShortAndExpiredPhasesDoNotCreateRefreshes(tc)
            anchor=100;
            ifi=1/60;
            for duration=[0,.25*ifi,ifi,1.5*ifi]
                tc.verifyEmpty(ephys.nextFixationRefresh(anchor,anchor+duration,ifi,0,anchor));
            end
            plan=ephys.nextFixationRefresh(anchor,anchor+1.5001*ifi,ifi,0,anchor);
            tc.verifyEqual(plan.refresh_index,1);
            tc.verifyEmpty(ephys.nextFixationRefresh(anchor,anchor+1,ifi,0,anchor+1));
            tc.verifyEmpty(ephys.nextFixationRefresh(anchor,anchor+1,ifi,0,anchor+3));
        end

        function doesNotConsumeProtectedAudioBookingWindow(tc)
            anchor=200;
            ifi=1/60;
            runEnd=anchor+14.4;
            minimumLead=.1;
            protectedEnd=runEnd-minimumLead-2*ifi;
            % Slot 855 is the final admissible filler at 60 Hz.
            last=ephys.nextFixationRefresh(anchor,protectedEnd,ifi,854,anchor+854*ifi+.001);
            tc.verifyEqual(last.refresh_index,855);
            tc.verifyEqual(last.target_getsecs,anchor+14.25,'AbsTol',1e-12);
            tc.verifyGreaterThan(runEnd-last.target_getsecs,minimumLead+2*ifi);
            tc.verifyEmpty(ephys.nextFixationRefresh(anchor,protectedEnd,ifi,855, ...
                last.target_getsecs+.001));
        end

        function logKeepsRequestedGridAndObservedTimesSeparate(tc)
            log=ephys.TimelineLog(4,2);
            ctx=ephys.context("video",0,"");
            raw=struct('vbl',10.073,'stimulus',10.074,'returned',10.075, ...
                'missed',.004,'refresh_target_getsecs',10.070, ...
                'refresh_index',4,'refresh_skipped_slots',2,'refresh_error_s',.004, ...
                'submission_mode',"fixed_fixation_timed");
            row=log.flip(ctx,"initial_fixation",2,raw,10.060, ...
                ephys.noFrame("fixation"),"off");
            tc.verifyEqual(row.phase_flip_seq,2);
            tc.verifyEqual(row.refresh_index,4);
            tc.verifyEqual(row.refresh_skipped_slots,2);
            tc.verifyEqual(row.refresh_target_getsecs,10.070);
            tc.verifyEqual(row.requested_deadline_getsecs,10.060);
            tc.verifyEqual(row.stimulus_onset_getsecs,10.074);
            tc.verifyEqual(row.vbl_getsecs,10.073);
            tc.verifyEqual(row.flip_return_getsecs,10.075);
            tc.verifyEqual(row.refresh_error_s,.004);
            tc.verifyEqual(log.flipRecords(),row);
        end

        function ordinaryAndHistoricalRawRecordsRetainUnknownGrid(tc)
            log=ephys.TimelineLog(2,2);
            ctx=ephys.context("video",1,"0001_fw.mp4");
            raw=struct('vbl',10,'stimulus',10.001,'returned',10.002,'missed',0);
            row=log.flip(ctx,"video",1,raw,9.99,ephys.noFrame("video"),"off");
            for name=["refresh_target_getsecs","refresh_index", ...
                    "refresh_skipped_slots","refresh_error_s"]
                tc.verifyTrue(isnan(row.(name)));
            end
            tc.verifyEqual(row.stimulus_onset_getsecs,10.001);
        end
    end
end
