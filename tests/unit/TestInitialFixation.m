classdef TestInitialFixation < matlab.unittest.TestCase
    methods (Test)
        function debugRetainsTheSharedInitialBaseline(tc)
            root = ephys.projectRoot();
            shared = ephys.readYaml(fullfile(root,'config','experiment.yml'));
            [c,~] = ephys.loadConfig("video",fullfile(root,'config', ...
                'runs','debug_blank.yml'),testSite(),true,"");
            tc.verifyEqual(c.protocol.video_initial_fixation_s,shared.protocol.video_initial_fixation_s);
            tc.verifyEqual(c.protocol.video_pre_fixation_s,0.5);
            for invalid=[-1,NaN,Inf]
                c.protocol.video_initial_fixation_s=invalid;
                tc.verifyError(@() ephys.validateConfig(c),'ephys:RunFixation');
            end
        end
        function capacityIncludesBaselineFlips(tc)
            [c,~] = ephys.loadConfig("video",fullfile(ephys.projectRoot(), ...
                'config','runs','debug_blank.yml'), ...
                testSite(),true,"");
            c.protocol.video_initial_fixation_s=0;
            [before,eventsBefore,markersBefore]=ephys.logCapacity(c);
            c.protocol.video_initial_fixation_s=14.3;
            [after,eventsAfter,markersAfter]=ephys.logCapacity(c);
            tc.verifyGreaterThanOrEqual(after-before,ceil(14.3*60)+2);
            tc.verifyGreaterThan(eventsAfter,eventsBefore);
            tc.verifyEqual(markersAfter,markersBefore);
            c.task_kind="memory";
            withBaseline=ephys.logCapacity(c);
            c.protocol.video_initial_fixation_s=0;
            tc.verifyEqual(ephys.logCapacity(c),withBaseline);
        end
        function reconstructsBoundaryFlipsWithoutCreatingATrial(tc)
            [log,c,ctx,first]=TestInitialFixation.trace();
            last=log.flip(ctx,"initial_fixation_end",1, ...
                TestInitialFixation.raw(24.3),24.3,ephys.noFrame("fixation"),"off");
            ev=log.event(ctx,"initial_fixation_offset","initial_fixation_end",24.3,last);
            ev.planned_onset_getsecs=24.3;
            log.updateLastEvent(ev);
            r=ephys.reconstructRecords(log.flipRecords(),log.eventRecords(), ...
                repmat(ephys.emptyMarker(),0,1),struct([]),c);
            tc.verifyEqual(r.initial_fixation.status,"complete");
            tc.verifyEqual(r.initial_fixation.onset_getsecs,first.stimulus_onset_getsecs);
            tc.verifyEqual(r.initial_fixation.observed_duration_s,14.3,'AbsTol',1e-12);
            tc.verifyEqual(r.initial_fixation.offset_error_s,0,'AbsTol',1e-12);
            tc.verifyEqual(r.initial_fixation.timestamp_issue_count,0);
            tc.verifyEqual(r.run_qc.trial_count,0);
            tc.verifyEmpty(r.frames);
        end
        function earlyAbortNeverInventsAFullBaseline(tc)
            [log,c,ctx]=TestInitialFixation.trace();
            log.event(ctx,"initial_fixation_abort","initial_fixation",11,[]);
            value=ephys.initialFixationSummary(log.flipRecords(),log.eventRecords(),c);
            tc.verifyEqual(value.status,"aborted");
            tc.verifyTrue(value.aborted);
            tc.verifyTrue(isnan(value.offset_getsecs));
            tc.verifyTrue(isnan(value.observed_duration_s));
        end
        function oldDisabledAndMemoryConfigurationsRemainReadable(tc)
            empty=struct([]);
            value=ephys.initialFixationSummary(empty,empty,struct());
            tc.verifyEqual(value.status,"not_configured");
            c=struct('protocol',struct('video_initial_fixation_s',0));
            value=ephys.initialFixationSummary(empty,empty,c);
            tc.verifyEqual(value.status,"disabled");
            c.task_kind="memory";
            c.protocol.video_initial_fixation_s=14.3;
            value=ephys.initialFixationSummary(empty,empty,c);
            tc.verifyEqual(value.status,"not_applicable");
        end
    end
    methods (Static)
        function [log,c,ctx,first]=trace()
            c=struct('task_kind',"video",'protocol', ...
                struct('video_initial_fixation_s',14.3,'video_duration_s',2.5));
            ctx=ephys.context("video",0,"");
            log=ephys.TimelineLog(4,4);
            first=log.flip(ctx,"initial_fixation",1, ...
                TestInitialFixation.raw(10),10,ephys.noFrame("fixation"),"off");
            ev=log.event(ctx,"initial_fixation_onset","initial_fixation",10,first);
            ev.planned_deadline_getsecs=24.3;
            log.updateLastEvent(ev);
        end
        function value=raw(time)
            value=struct('vbl',time,'stimulus',time,'returned',time,'missed',0);
        end
    end
end
