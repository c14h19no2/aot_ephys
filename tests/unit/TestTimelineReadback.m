classdef TestTimelineReadback < matlab.unittest.TestCase
    methods (Test)
        function outputChannelSurvivesMarkerRoundTrip(tc)
            file=[tempname '.tsv'];
            cleanup=onCleanup(@() delete(file));
            rows=repmat(ephys.emptyMarker(),2,1);
            rows(1).event_id="left"; rows(1).output_channel=1;
            rows(2).event_id="right"; rows(2).output_channel=2;
            writetable(struct2table(rows),file,'FileType','text','Delimiter','\t');
            loaded=ephys.readTimelineRows(file,ephys.emptyMarker());
            tc.verifyEqual(loaded.output_channel,[1;2]);
        end
        function filenamesSurviveLongEmptyPrefix(tc)
            file=[tempname '.tsv'];
            guard=onCleanup(@() delete(file)); %#ok<NASGU>
            rows=repmat(ephys.emptyFlip(),402,1);
            for k=1:numel(rows)
                rows(k).flip_seq=k; rows(k).trial_nr=0;
                rows(k).task="video"; rows(k).phase="loading";
            end
            rows(401).video_file="blank";
            rows(402).video_file="1056_rv.mp4";
            rows(402).source_frame_index=0;
            writetable(struct2table(rows),file,'FileType','text','Delimiter','\t');
            loaded=ephys.readTimelineRows(file,ephys.emptyFlip());
            tc.verifyClass(loaded.video_file,'string');
            tc.verifyEqual(loaded.video_file(1),"");
            tc.verifyEqual(loaded.video_file(401:402),["blank";"1056_rv.mp4"]);
            tc.verifyTrue(isnan(loaded.source_frame_index(1)));
            tc.verifyEqual(loaded.source_frame_index(402),0);
        end
        function lateResponsesAndQuotedDetailsSurvive(tc)
            file=[tempname '.tsv'];
            guard=onCleanup(@() delete(file)); %#ok<NASGU>
            rows=repmat(ephys.emptyEvent(),301,1);
            for k=1:numel(rows), rows(k).event_type="startup"; end
            rows(end).response="j"; rows(end).response_type="yes";
            rows(end).rt_s=.123456789123;
            rows(end).detail=string(sprintf('first\tsecond\n"quoted"'));
            writetable(struct2table(rows),file,'FileType','text','Delimiter','\t');
            loaded=ephys.readTimelineRows(file,ephys.emptyEvent());
            tc.verifyEqual(loaded.response(end),"j");
            tc.verifyEqual(loaded.response_type(end),"yes");
            tc.verifyEqual(loaded.rt_s(end),rows(end).rt_s,'AbsTol',1e-12);
            tc.verifyEqual(loaded.detail(end),rows(end).detail);
            tc.verifyEqual(loaded.simulated(end),0);
        end
        function historicalNumericRowsRemainReadable(tc)
            file=[tempname '.tsv'];
            guard=onCleanup(@() delete(file)); %#ok<NASGU>
            old=table("old-event",1,"video_onset", ...
                'VariableNames',{'event_id','code','event_type'});
            writetable(old,file,'FileType','text','Delimiter','\t');
            loaded=ephys.readTimelineRows(file,ephys.emptyMarker());
            tc.verifyEqual(loaded.code,1);
            tc.verifyEqual(loaded.event_id,"old-event");
            tc.verifyFalse(ismember('trigger_key',loaded.Properties.VariableNames));
        end
        function emptyMarkerLogKeepsItsColumns(tc)
            file=[tempname '.tsv'];
            guard=onCleanup(@() delete(file)); %#ok<NASGU>
            empty=repmat(ephys.emptyMarker(),0,1);
            writetable(struct2table(empty),file,'FileType','text','Delimiter','\t');
            loaded=ephys.readTimelineRows(file,ephys.emptyMarker());
            tc.verifyEqual(height(loaded),0);
            tc.verifyClass(loaded.video_file,'string');
            tc.verifyClass(loaded.trigger_key,'string');
            tc.verifyClass(loaded.waveform_file,'string');
            tc.verifyClass(loaded.audio_start_getsecs,'double');
            tc.verifyFalse(ismember('code',loaded.Properties.VariableNames));
            tc.verifyEqual(string(loaded.Properties.VariableNames)',string(fieldnames(ephys.emptyMarker())));
        end
    end
end
