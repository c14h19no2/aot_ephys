classdef TestTriggerBookkeeping < matlab.unittest.TestCase
    % Indexed trigger records: identity, collision state and bounded writes.
    methods (Test)
        function duplicateAndUnknownIdsAreRejected(tc)
            f=FakeWavAudio(); b=TestWavTriggers.backend(f);
            o=ephys.TriggerOutput(TestWavTriggers.settings(),b,4,@() f.Now,@() "same-id");
            o.open(); cleanup=onCleanup(@() delete(o)); %#ok<NASGU>
            c=ephys.context("video",1,"movie_fw.mp4");
            o.schedule("video_onset",c,10.2);
            tc.verifyError(@() o.schedule("video_onset",c,10.5),'ephys:MarkerId');
            tc.verifyError(@() o.associate("missing",struct('seq',1,'stimulus',10.2)), ...
                'ephys:MarkerReceipt');
            f2=FakeWavAudio(); b2=TestWavTriggers.backend(f2);
            b2.configure(TestWavTriggers.settings()); b2.open();
            closer=onCleanup(@() b2.close()); %#ok<NASGU>
            b2.submit("video_onset","one",10.2);
            tc.verifyError(@() b2.submit("run_end","one",10.5),'ephys:MarkerId');
        end
        function cancelledReservationNoLongerBlocksTheOutput(tc)
            f=FakeWavAudio(); b=TestWavTriggers.backend(f);
            b.configure(TestWavTriggers.settings()); b.open();
            closer=onCleanup(@() b.close()); %#ok<NASGU>
            b.submit("video_onset","first",10.2);
            tc.verifyError(@() b.submit("run_end","overlap",10.205),'ephys:TriggerCollision');
            receipt=b.cancel("first");
            tc.verifyEqual(receipt.status,"cancelled");
            b.submit("run_end","after_cancel",10.205);
        end
        function collisionUsesTheObservedStartOnceKnown(tc)
            f=FakeWavAudio(); f.StartDelay=.05;
            b=TestWavTriggers.backend(f); b.configure(TestWavTriggers.settings()); b.open();
            closer=onCleanup(@() b.close()); %#ok<NASGU>
            b.submit("video_onset","late",10.2);
            % Before the start is observed, the planned time decides.
            b.submit("run_start","planned_clear",10.215);
            f.Now=10.3; b.poll();
            tc.verifyEqual(b.ReservationTimes(1,2),10.25,'AbsTol',1e-12);
            tc.verifyError(@() b.submit("run_end","observed_overlap",10.255), ...
                'ephys:TriggerCollision');
        end
        function nextAllowedTimeFollowsActiveReservationsOnly(tc)
            [o,f]=TestWavTriggers.output(); cleanup=onCleanup(@() delete(o)); %#ok<NASGU>
            tc.verifyEqual(o.nextAllowedRequestTime(),-Inf);
            c=ephys.context("video",1,"movie_fw.mp4");
            r=o.schedule("video_onset",c,10.2);
            expected=10.2+100/48000+.01;
            tc.verifyEqual(o.nextAllowedRequestTime(),expected,'AbsTol',1e-12);
            o.cancelPending();
            tc.verifyEqual(o.records().status,"cancelled");
            tc.verifyEqual(o.nextAllowedRequestTime(),-Inf);
            tc.verifyEqual(f.Now,10);
            tc.verifyEqual(r.marker_nr,1);
        end
        function postOnsetCostDoesNotScaleWithLogCapacity(tc)
            % A fresh interactive session copied whole arrays on every write.
            % Sharing storage before each call forces that path; with bounded
            % stores the cost must not grow with the preallocated capacity.
            small=TestTriggerBookkeeping.postOnsetMedian(30);
            large=TestTriggerBookkeeping.postOnsetMedian(6000);
            tc.verifyLessThan(large,2*small+.002);
        end
    end
    methods (Static)
        function value=postOnsetMedian(capacity)
            f=FakeWavAudio(); b=TestWavTriggers.backend(f);
            o=ephys.TriggerOutput(TestWavTriggers.settings(),b,capacity,@() f.Now);
            o.open(); cleanup=onCleanup(@() delete(o)); %#ok<NASGU>
            c=ephys.context("video",1,"movie_fw.mp4");
            elapsed=zeros(30,1);
            for k=1:30
                onset=f.Now+.5;
                row=o.schedule("video_onset",c,onset);
                f.Now=onset+.0005;
                began=tic;
                held=TestTriggerBookkeeping.share(o); o.poll();
                held=TestTriggerBookkeeping.share(o); o.associate(row.event_id, ...
                    struct('seq',k,'stimulus',onset));
                for step=1:3
                    f.Now=f.Now+1/60;
                    held=TestTriggerBookkeeping.share(o); o.poll(); %#ok<NASGU>
                end
                elapsed(k)=toc(began);
                f.Now=f.Now+3;
            end
            o.close();
            value=median(elapsed);
        end
        function held=share(o)
            held={o.RowStore.Chunks,o.Backend.ReservationTimes,o.Backend.Completed};
        end
    end
end
