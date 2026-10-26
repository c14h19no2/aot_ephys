classdef TestRefreshGuard < matlab.unittest.TestCase
    % Decision rules and configuration of the initial-fixation refresh guard.
    methods (Test)
        function allAvailableSlotsPass(tc)
            ifi=1/60;
            value=ephys.refreshGuard(TestRefreshGuard.rows(ifi,1:299), ...
                "initial_fixation",5,ifi,.9);
            tc.verifyEqual(value.status,"passed");
            tc.verifyEqual(value.available_slots,299);
            tc.verifyEqual(value.presented_slots,299);
            tc.verifyEqual(value.presented_fraction,1);
            tc.verifyEqual(value.max_skipped_slots,0);
            tc.verifyEqual(value.interval_median_ms,1000*ifi,'AbsTol',1e-9);
            tc.verifyEqual(value.timestamp_grid_deviation_median_ifi,0,'AbsTol',1e-6);
            tc.verifyEqual(value.message,"");
        end
        function stalledLoopFailsWithAnOperatorMessage(tc)
            % About one refresh in fourteen, as in the 2026-10-23 laptop run.
            ifi=1/60;
            value=ephys.refreshGuard(TestRefreshGuard.rows(ifi,14:14:299), ...
                "initial_fixation",5,ifi,.9);
            tc.verifyEqual(value.status,"failed");
            tc.verifyEqual(value.presented_slots,21);
            tc.verifyLessThan(value.presented_fraction,.1);
            tc.verifyEqual(value.max_skipped_slots,13);
            tc.verifySubstring(char(value.message),'21 of 299 refresh slots');
            tc.verifySubstring(char(value.message),'stopped before the first trial');
        end
        function singleTransientStallPasses(tc)
            ifi=1/60;
            slots=setdiff(1:299,50:61); % One 200 ms interruption.
            value=ephys.refreshGuard(TestRefreshGuard.rows(ifi,slots), ...
                "initial_fixation",5,ifi,.9);
            tc.verifyEqual(value.status,"passed");
            tc.verifyEqual(value.max_skipped_slots,12);
            tc.verifyEqual(value.presented_fraction,287/299,'AbsTol',1e-12);
        end
        function thresholdIsInclusive(tc)
            ifi=1/60;
            duration=101*ifi; % Exactly 100 available slots.
            value=ephys.refreshGuard(TestRefreshGuard.rows(ifi,1:90), ...
                "initial_fixation",duration,ifi,.9);
            tc.verifyEqual(value.available_slots,100);
            tc.verifyEqual(value.status,"passed");
            value=ephys.refreshGuard(TestRefreshGuard.rows(ifi,1:89), ...
                "initial_fixation",duration,ifi,.9);
            tc.verifyEqual(value.status,"failed");
        end
        function baselineShorterThanOneSecondIsNotEvaluated(tc)
            ifi=1/60;
            value=ephys.refreshGuard(TestRefreshGuard.rows(ifi,10), ...
                "initial_fixation",.5,ifi,.9);
            tc.verifyEqual(value.status,"not_evaluated");
            tc.verifyEqual(value.available_slots,29);
            tc.verifyEqual(value.message,"");
        end
        function nullSettingRecordsMetricsWithoutDecision(tc)
            ifi=1/60;
            value=ephys.refreshGuard(TestRefreshGuard.rows(ifi,14:14:299), ...
                "initial_fixation",5,ifi,[]);
            tc.verifyEqual(value.status,"disabled");
            tc.verifyTrue(isnan(value.min_fraction));
            tc.verifyEqual(value.presented_slots,21);
            tc.verifyEqual(value.message,"");
        end
        function onsetBoundaryAndOtherPhasesAreNotCounted(tc)
            ifi=1/60;
            value=ephys.refreshGuard(TestRefreshGuard.rows(ifi,1:299,true), ...
                "initial_fixation",5,ifi,.9);
            tc.verifyEqual(value.presented_slots,299);
            tc.verifyEqual(value.status,"passed");
        end
        function presentedCountGivesTheSameDecisionWithoutMetrics(tc)
            ifi=1/60;
            for slots={1:299,setdiff(1:299,50:61),14:14:299,1:268,1:269}
                full=ephys.refreshGuard(TestRefreshGuard.rows(ifi,slots{1}), ...
                    "initial_fixation",5,ifi,.9);
                live=ephys.refreshGuard(numel(slots{1}),"initial_fixation",5,ifi,.9);
                tc.verifyEqual(live.status,full.status);
                tc.verifyEqual(live.presented_fraction,full.presented_fraction);
                tc.verifyTrue(isnan(live.interval_median_ms));
                tc.verifyTrue(isnan(live.max_skipped_slots));
                tc.verifyEqual(fieldnames(live),fieldnames(full));
            end
            live=ephys.refreshGuard(22,"initial_fixation",5,ifi,.9);
            tc.verifySubstring(char(live.message),'22 of 299 refresh slots');
            tc.verifyFalse(contains(live.message,"NaN"));
        end
        function writeOutputAddsMetricsAndKeepsTheLiveDecision(tc)
            ifi=1/60;
            root=ephys.projectRoot();
            [c,p]=ephys.loadConfig("video",fullfile(root,'config','runs','debug_blank.yml'), ...
                testSite(),true,"");
            folder=tempname; mkdir(folder);
            guard=onCleanup(@() rmdir(folder,'s')); %#ok<NASGU>
            rows=TestRefreshGuard.rows(ifi,setdiff(1:299,50:61),true);
            live=ephys.refreshGuard(287,"initial_fixation",5,ifi,.9);
            live.first_flip_seq=1; live.last_flip_seq=numel(rows)-1;
            events=repmat(ephys.emptyEvent(),0,1);
            s=struct('OutputDir',folder,'RunId',"guard_metrics",'Config',c, ...
                'Provenance',p,'StartTime',0,'StopTime',1, ...
                'DisplayTiming',struct(),'EffectiveSkipSync',0, ...
                'IFI',ifi,'IFISamples',NaN,'IFIStddev',NaN, ...
                'Eye',struct('LocalPath',""),'Inventory',struct([]), ...
                'Log',struct('flipRecords',@() rows,'eventRecords',@() events), ...
                'RefreshGuard',live);
            s.Triggers=ephys.TriggerOutput(c.markers,ephys.DummyTriggerBackend(@() 0),1,@() 0);
            triggerGuard=onCleanup(@() delete(s.Triggers)); %#ok<NASGU>
            ephys.writeOutput(s,"complete","");
            manifest=jsondecode(fileread(fullfile(folder,'guard_metrics_manifest.json')));
            saved=manifest.refresh_guard;
            tc.verifyEqual(string(saved.status),"passed");
            tc.verifyEqual(saved.presented_slots,287);
            tc.verifyEqual(saved.max_skipped_slots,12);
            tc.verifyEqual(saved.interval_median_ms,1000*ifi,'AbsTol',1e-6);
            tc.verifyEqual(string(saved.detail),live.detail);
        end
        function unobservedBaselineKeepsTheDefaultRecord(tc)
            empty=ephys.refreshGuard();
            tc.verifyEqual(empty.status,"not_run");
            value=ephys.refreshGuard(repmat(ephys.emptyFlip(),0,1), ...
                "initial_fixation",5,1/60,.9);
            tc.verifyEqual(value.status,"not_run");
            tc.verifyEqual(fieldnames(value),fieldnames(empty));
        end
        function availableSlotsMatchTheFixedGridScheduler(tc)
            anchor=10;
            for hz=[60 120 144]
                ifi=1/hz;
                for duration=[1 5 14.4]
                    count=0; previous=0;
                    while true
                        plan=ephys.nextFixationRefresh(anchor,anchor+duration,ifi,previous,anchor);
                        if isempty(plan), break; end
                        count=count+1; previous=plan.refresh_index;
                    end
                    value=ephys.refreshGuard(TestRefreshGuard.rows(ifi,1,false,anchor), ...
                        "initial_fixation",duration,ifi,.9);
                    tc.verifyEqual(value.available_slots,count, ...
                        sprintf('%g Hz, %g s',hz,duration));
                end
            end
        end
        function settingMustBeNullOrAFraction(tc)
            root=ephys.projectRoot();
            schedule=fullfile(root,'config','runs','debug_blank.yml');
            [c,~]=ephys.loadConfig("video",schedule,testSite(),true,"");
            shared=ephys.readYaml(fullfile(root,'config','experiment.yml'));
            tc.verifyEqual(c.display.refresh_guard_min_fraction, ...
                shared.display.refresh_guard_min_fraction);
            for valid={[],.5,1}
                c.display.refresh_guard_min_fraction=valid{1};
                ephys.validateConfig(c);
            end
            for invalid={0,-.1,1.5,NaN,Inf,[.5 .6],"0.9",true}
                c.display.refresh_guard_min_fraction=invalid{1};
                tc.verifyError(@() ephys.validateConfig(c),'ephys:RefreshGuardConfig');
            end
        end
        function siteNullDisablesTheDecision(tc)
            file=[tempname '.yml'];
            cleanup=onCleanup(@() delete(file)); %#ok<NASGU>
            fid=fopen(file,'w');
            fprintf(fid,['display:\n  refresh_guard_min_fraction: null\n' ...
                'playback:\n  native_media_root: ''%s''\n'],tempdir);
            fclose(fid);
            [c,~]=ephys.loadConfig("video",fullfile(ephys.projectRoot(),'config', ...
                'runs','debug_blank.yml'),file,true,"");
            tc.verifyEmpty(c.display.refresh_guard_min_fraction);
        end
    end
    methods (Static)
        function rows=rows(ifi,slots,others,anchor)
            % One phase onset, then fixed-grid refreshes at the given slots.
            if nargin<3, others=false; end
            if nargin<4, anchor=10; end
            log=ephys.TimelineLog(numel(slots)+4,4);
            ctx=ephys.context("video",0,"");
            frame=ephys.noFrame("fixation");
            log.flip(ctx,"initial_fixation",1,TestRefreshGuard.raw(anchor,NaN,NaN), ...
                anchor,frame,"off");
            previous=0;
            for k=1:numel(slots)
                time=anchor+slots(k)*ifi;
                log.flip(ctx,"initial_fixation",k+1, ...
                    TestRefreshGuard.raw(time,slots(k),slots(k)-previous-1), ...
                    time-ifi/2,frame,"off");
                previous=slots(k);
            end
            if others
                time=anchor+(slots(end)+1)*ifi;
                log.flip(ctx,"initial_fixation_end",1, ...
                    TestRefreshGuard.raw(time,NaN,NaN),time,frame,"off");
                trial=ephys.context("video",1,"blank");
                log.flip(trial,"pre_fixation",1, ...
                    TestRefreshGuard.raw(time+ifi,1,0),time+ifi,frame,"off");
            end
            rows=log.flipRecords();
        end
        function value=raw(time,index,skipped)
            value=struct('vbl',time,'stimulus',time,'returned',time,'missed',0, ...
                'refresh_index',index,'refresh_skipped_slots',skipped);
        end
    end
end
