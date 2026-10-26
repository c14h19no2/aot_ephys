classdef TestTimelineLog < matlab.unittest.TestCase
    % Chunked log storage: identical records, cheap reads and bounded writes.
    methods (Test)
        function recordsAndIntervalsSpanChunkBoundariesAndGrowth(tc)
            log=ephys.TimelineLog(10,10); % Smaller than the run; storage grows.
            TestTimelineLog.fill(log,300);
            rows=log.flipRecords();
            tc.verifySize(rows,[300 1]);
            tc.verifyEqual([rows.flip_seq],1:300);
            tc.verifyEqual([rows(1:299).interval_end_getsecs],2:300);
            tc.verifyEqual([rows(1:299).interval_s],ones(1,299));
            tc.verifyTrue(isnan(rows(300).interval_end_getsecs) && isnan(rows(300).interval_s));
            tc.verifyEqual(log.Flips,rows);
            range=log.flipRange(127,130);
            tc.verifyEqual([range.flip_seq],127:130);
            tc.verifyEqual([range.interval_end_getsecs],128:131);
            tc.verifyEqual(log.flipValues("flip_seq",120,260),120:260);
            last=log.lastFlip();
            tc.verifyEqual(last.flip_seq,300);
            tc.verifyEqual(last.stimulus_onset_getsecs,300);
        end
        function eventsAndLastEventUpdatesSpanChunks(tc)
            log=ephys.TimelineLog(1,1);
            ctx=ephys.context("video",0,"");
            for k=1:200
                ev=log.event(ctx,"tick","phase",k,[]);
                ev.detail="edited "+k;
                log.updateLastEvent(ev);
            end
            rows=log.eventRecords();
            tc.verifySize(rows,[200 1]);
            tc.verifyEqual([rows.onset_getsecs],1:200);
            tc.verifyEqual(rows(129).detail,"edited 129");
            last=log.lastEvent();
            tc.verifyEqual(last.detail,"edited 200");
            tc.verifyEqual(log.Events,rows);
        end
        function emptyLogReturnsTypedColumns(tc)
            log=ephys.TimelineLog(4,4);
            tc.verifySize(log.flipRecords(),[0 1]);
            tc.verifySize(log.eventRecords(),[0 1]);
            tc.verifyEqual(fieldnames(log.flipRecords()),fieldnames(ephys.emptyFlip()));
            tc.verifyEqual(fieldnames(log.eventRecords()),fieldnames(ephys.emptyEvent()));
            tc.verifyEmpty(log.flipValues("flip_seq",1,0));
        end
        function writesStayCheapWhenStorageIsNotUpdatedInPlace(tc)
            % A fresh interactive session copied the whole log on every write
            % (about 75 ms per write). Sharing the storage before each write
            % forces that path; a write must then copy at most one chunk.
            log=ephys.TimelineLog(28664,1412);
            ctx=ephys.context("video",0,"");
            frame=ephys.noFrame("fixation");
            raw=struct('vbl',0,'stimulus',0,'returned',0,'missed',0);
            elapsed=zeros(40,1);
            for k=1:40
                held=log.FlipStore.Chunks; %#ok<NASGU>
                raw.stimulus=k;
                began=tic;
                log.flip(ctx,"blank",k,raw,NaN,frame,"off");
                elapsed(k)=toc(began);
            end
            tc.verifyLessThan(median(elapsed),.005);
            for k=1:40
                held=log.EventStore.Chunks; %#ok<NASGU>
                began=tic;
                ev=log.event(ctx,"tick","blank",k,[]);
                log.updateLastEvent(ev);
                elapsed(k)=toc(began);
            end
            tc.verifyLessThan(median(elapsed),.005);
        end
    end
    methods (Static)
        function fill(log,count)
            ctx=ephys.context("video",0,"");
            frame=ephys.noFrame("fixation");
            for k=1:count
                raw=struct('vbl',k,'stimulus',k,'returned',k,'missed',0);
                log.flip(ctx,"blank",k,raw,k,frame,"off");
            end
        end
    end
end
