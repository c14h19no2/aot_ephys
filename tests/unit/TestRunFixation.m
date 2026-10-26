classdef TestRunFixation < matlab.unittest.TestCase
    methods (Test)
        function debugRetainsSharedBaselineDurations(tc)
            root=ephys.projectRoot();
            shared=ephys.readYaml(fullfile(root,'config','experiment.yml'));
            schedule=fullfile(root,'config','runs','debug_blank.yml');
            for debugMode=[false,true]
                [c,p]=ephys.loadConfig("video",schedule, ...
                    testSite(),debugMode,"");
                tc.verifyEqual(c.protocol.video_initial_fixation_s,shared.protocol.video_initial_fixation_s);
                tc.verifyEqual(c.protocol.video_final_fixation_s,shared.protocol.video_final_fixation_s);
                tc.verifyEqual(p.files{1},fullfile(root,'config','experiment.yml'));
                if debugMode
                    tc.verifyEqual(c.protocol.video_pre_fixation_s,0.5);
                else
                    tc.verifyEqual(c.protocol.video_pre_fixation_s,1);
                    tc.verifyEqual(c.protocol.video_duration_s,2.5);
                    tc.verifyEqual(c.protocol.video_post_fixation_s,0.1);
                end
            end
            for field=["video_initial_fixation_s","video_final_fixation_s"]
                for invalid=[-1,NaN,Inf]
                    bad=c; bad.protocol.(field)=invalid;
                    tc.verifyError(@() ephys.validateConfig(bad),'ephys:RunFixation');
                end
            end
        end
        function siteHardwareDoesNotRedefineDurations(tc)
            root=ephys.projectRoot();
            shared=ephys.readYaml(fullfile(root,'config','experiment.yml'));
            for file={testSite(),fullfile(root,'config','site.example.yml')}
                site=ephys.readYaml(file{1});
                tc.verifyEqual(fieldnames(site.protocol),{'approved_for_acquisition'});
            end
            % A new site's display settings inherit the same common timing.
            file=[tempname '.yml'];
            cleanup=onCleanup(@() delete(file)); %#ok<NASGU>
            fid=fopen(file,'w');
            fprintf(fid,'display:\n  screen_index: 2\n  expected_refresh_hz: 144\nplayback:\n  native_media_root: ''%s''\n',tempdir);
            fclose(fid);
            [c,~]=ephys.loadConfig("video",fullfile(root,'config','runs', ...
                'debug_blank.yml'),file,true,"");
            tc.verifyEqual(c.protocol.video_initial_fixation_s,shared.protocol.video_initial_fixation_s);
            tc.verifyEqual(c.protocol.video_final_fixation_s,shared.protocol.video_final_fixation_s);
        end
        function capacityIncludesBothBaselines(tc)
            [c,~]=ephys.loadConfig("video",fullfile(ephys.projectRoot(), ...
                'config','runs','debug_blank.yml'), ...
                testSite(),true,"");
            c.protocol.video_initial_fixation_s=0;
            c.protocol.video_final_fixation_s=0;
            [before,eventsBefore,markersBefore]=ephys.logCapacity(c);
            c.protocol.video_initial_fixation_s=14.4;
            c.protocol.video_final_fixation_s=14.4;
            [after,eventsAfter,markersAfter]=ephys.logCapacity(c);
            tc.verifyGreaterThanOrEqual(after-before,2*(ceil(14.4*60)+2));
            tc.verifyGreaterThan(eventsAfter,eventsBefore);
            tc.verifyEqual(markersAfter,markersBefore);
            c.task_kind="memory";
            withBaseline=ephys.logCapacity(c);
            c.protocol.video_initial_fixation_s=0;
            c.protocol.video_final_fixation_s=0;
            tc.verifyEqual(ephys.logCapacity(c),withBaseline);
        end
        function reconstructsBothBoundaryFlipsWithoutCreatingTrials(tc)
            log=ephys.TimelineLog(10,10);
            c=TestRunFixation.config();
            TestRunFixation.trace(log,"initial_fixation",true);
            TestRunFixation.trace(log,"final_fixation",true,30);
            r=ephys.reconstructRecords(log.flipRecords(),log.eventRecords(), ...
                repmat(ephys.emptyMarker(),0,1),struct([]),c);
            for phase=["initial_fixation","final_fixation"]
                value=r.(phase);
                tc.verifyEqual(value.status,"complete");
                tc.verifyEqual(value.observed_duration_s,14.4,'AbsTol',1e-12);
                tc.verifyEqual(value.offset_error_s,0,'AbsTol',1e-12);
                tc.verifyEqual(value.timestamp_issue_count,0);
            end
            tc.verifyEqual(r.run_qc.trial_count,0);
            tc.verifyEmpty(r.frames);
        end
        function earlyAbortNeverInventsAFullBaseline(tc)
            c=TestRunFixation.config();
            for phase=["initial_fixation","final_fixation"]
                log=ephys.TimelineLog(4,4);
                TestRunFixation.trace(log,phase,false);
                log.event(ephys.context("video",0,""),phase+"_abort",phase,11,[]);
                value=ephys.runFixationSummary( ...
                    log.flipRecords(),log.eventRecords(),c,phase);
                tc.verifyEqual(value.status,"aborted");
                tc.verifyTrue(value.aborted);
                tc.verifyTrue(isnan(value.offset_getsecs));
                tc.verifyTrue(isnan(value.observed_duration_s));
            end
        end
        function trialAbortLeavesFinalBaselineNotStarted(tc)
            log=ephys.TimelineLog(4,5);
            c=TestRunFixation.config();
            TestRunFixation.trace(log,"initial_fixation",true);
            log.event(ephys.context("video",1,"0001_fw.mp4"), ...
                "trial_abort","video",25,[]);
            value=ephys.runFixationSummary(log.flipRecords(), ...
                log.eventRecords(),c,"final_fixation");
            tc.verifyEqual(value.status,"not_started");
            tc.verifyEqual(value.flip_count,0);
            tc.verifyTrue(isnan(value.observed_duration_s));
        end
        function invalidBoundaryAndBoundaryAbortRemainVisible(tc)
            c=TestRunFixation.config();
            log=ephys.TimelineLog(4,4);
            TestRunFixation.trace(log,"final_fixation",true);
            f=log.flipRecords(); e=log.eventRecords();
            f(end).stimulus_onset_getsecs=9;
            e(end).onset_getsecs=9;
            value=ephys.runFixationSummary(f,e,c,"final_fixation");
            tc.verifyEqual(value.status,"incomplete");
            tc.verifyGreaterThan(value.timestamp_issue_count,0);
            log.event(ephys.context("video",0,""),"final_fixation_abort", ...
                "final_fixation_end",24.4,[]);
            value=ephys.runFixationSummary(log.flipRecords(), ...
                log.eventRecords(),c,"final_fixation");
            tc.verifyEqual(value.status,"aborted");
            tc.verifyTrue(value.aborted);
        end
        function oldDisabledAndMemoryConfigurationsRemainReadable(tc)
            empty=struct([]);
            for phase=["initial_fixation","final_fixation"]
                value=ephys.runFixationSummary(empty,empty,struct(),phase);
                tc.verifyEqual(value.status,"not_configured");
                c=TestRunFixation.config(); c.protocol.("video_"+phase+"_s")=0;
                value=ephys.runFixationSummary(empty,empty,c,phase);
                tc.verifyEqual(value.status,"disabled");
                c.task_kind="memory";
                value=ephys.runFixationSummary(empty,empty,c,phase);
                tc.verifyEqual(value.status,"not_applicable");
            end
            % The historical 14.3 s configuration remains readable unchanged.
            log=ephys.TimelineLog(4,4);
            c=TestRunFixation.config();
            c.protocol.video_initial_fixation_s=14.3;
            c.protocol=rmfield(c.protocol,'video_final_fixation_s');
            ctx=ephys.context("video",0,"");
            first=log.flip(ctx,"initial_fixation",1,TestRunFixation.raw(10), ...
                10,ephys.noFrame("fixation"),"off");
            ev=log.event(ctx,"initial_fixation_onset","initial_fixation",10,first);
            ev.planned_deadline_getsecs=24.3; log.updateLastEvent(ev);
            last=log.flip(ctx,"initial_fixation_end",1,TestRunFixation.raw(24.3), ...
                24.3,ephys.noFrame("fixation"),"off");
            log.event(ctx,"initial_fixation_offset","initial_fixation_end",24.3,last);
            tc.verifyEqual(ephys.runFixationSummary(log.flipRecords(), ...
                log.eventRecords(),c,"initial_fixation").observed_duration_s, ...
                14.3,'AbsTol',1e-12);
            tc.verifyEqual(ephys.runFixationSummary(log.flipRecords(), ...
                log.eventRecords(),c,"final_fixation").status,"not_configured");
        end
    end
    methods (Static)
        function c=config()
            c=struct('task_kind',"video",'protocol',struct( ...
                'video_initial_fixation_s',14.4,'video_final_fixation_s',14.4, ...
                'video_duration_s',2.5));
        end
        function trace(log,phase,complete,startTime)
            if nargin<4, startTime=10; end
            endTime=startTime+14.4;
            ctx=ephys.context("video",0,"");
            first=log.flip(ctx,phase,1,TestRunFixation.raw(startTime), ...
                startTime,ephys.noFrame("fixation"),"off");
            ev=log.event(ctx,phase+"_onset",phase,startTime,first);
            ev.planned_deadline_getsecs=endTime; log.updateLastEvent(ev);
            if complete
                last=log.flip(ctx,phase+"_end",1,TestRunFixation.raw(endTime), ...
                    endTime,ephys.noFrame("fixation"),"off");
                ev=log.event(ctx,phase+"_offset",phase+"_end",endTime,last);
                ev.planned_onset_getsecs=endTime; log.updateLastEvent(ev);
            end
        end
        function value=raw(time)
            value=struct('vbl',time,'stimulus',time,'returned',time,'missed',0);
        end
    end
end
