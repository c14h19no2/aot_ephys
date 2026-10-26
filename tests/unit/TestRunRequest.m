classdef TestRunRequest < matlab.unittest.TestCase
    methods (Test)
        function explicitSiteSelectsTheSavedRun(tc)
            r = ephys.resolveRunRequest(1,1,8,'Site',testSite(),'SubjectMap',subjectMap());
            tc.verifyEqual(r.run_id,"sub-001_ses-01_run-08_task-video");
            tc.verifyEmpty(r.identity.recording_number);
            tc.verifyEqual(r.identity.subject,"001");
            tc.verifyEqual(r.identity.schedule_set,1);
            tc.verifyEqual(r.task,"video");
            [sitePath,selectionPath] = ephys.resolveSitePath(testSite());
            tc.verifyEqual(r.site_path,sitePath);
            tc.verifyEqual(r.site_selection_path,selectionPath);
            tc.verifyTrue(isfile(r.schedule_path));
            tc.verifyEqual(r.schedule_path,string(fullfile(ephys.projectRoot(), ...
                'config','runs','main','experiment_settings_sub_01_ses_01_run_08.yml')));
        end
        function recordingNumberKeepsRunEightSchedule(tc)
            first = ephys.resolveRunRequest(1,1,8,1,'Debug',true,'Site',testSite(), ...
                'SubjectMap',subjectMap());
            repeat = ephys.resolveRunRequest(1,1,8,128,'Debug',true,'Site',testSite(), ...
                'SubjectMap',subjectMap());
            tc.verifyEqual(first.schedule_path,repeat.schedule_path);
            tc.verifyTrue(endsWith(repeat.schedule_path, ...
                'experiment_settings_sub_01_ses_01_run_08.yml'));
            tc.verifyEqual(repeat.run_id, ...
                "sub-001_ses-01_run-08_task-video_record-128_debug");
            tc.verifyEqual(repeat.identity.run,8);
            tc.verifyEqual(repeat.identity.recording_number,128);
            % Load the actual saved run to check that the numbered request
            % selects its movies, rather than the blank fallback schedule.
            [c,~] = ephys.loadConfig(repeat.task,repeat.schedule_path, ...
                repeat.site_path,true,"");
            doc = ephys.readYaml(first.schedule_path);
            tc.verifyEqual(c.schedule,ephys.validateSchedule(doc.stimuli.movie_files));
            tc.verifyTrue(any(c.schedule~="blank"));
        end
        function memoryUsesSameNumberingWithItsOwnSchedule(tc)
            r = ephys.resolveRunRequest(1,1,1,2,'Task','memory','Site',testSite(), ...
                'SubjectMap',subjectMap());
            tc.verifyTrue(contains(r.schedule_path,'memory_main_complete'));
            tc.verifyEqual(r.schedule_path,string(fullfile(ephys.projectRoot(), ...
                'config','runs','memory_main_complete', ...
                'experiment_settings_sub_01_ses_01_run_01.yml')));
            tc.verifyTrue(isfile(r.schedule_path));
            tc.verifyEqual(r.run_id, ...
                "sub-001_ses-01_run-01_task-memory_record-02");
        end
        function namedOptionsStillWorkWithOrWithoutNumber(tc)
            backend = ephys.DummyTriggerBackend(@() 0);
            args = {'Task','memory','Site','custom.yml', ...
                'Schedule','schedule.yml','Answers','answers.tsv', ...
                'Debug',true,'DebugSkipSyncTests',true, ...
                'DebugSimulatedInputOnly',true,'Backend',backend,'Overwrite',true};
            original = ephys.resolveRunRequest(2,3,4,args{:});
            numbered = ephys.resolveRunRequest(2,3,4,5,args{:});
            tc.verifyEqual(original.options,numbered.options);
            tc.verifyEqual(numbered.schedule_path,"schedule.yml");
            tc.verifyEqual(numbered.site_path,"custom.yml");
            tc.verifyEqual(numbered.site_selection_path,"");
            tc.verifyEqual(numbered.options.Answers,'answers.tsv');
            tc.verifyEqual(numbered.options.Backend,backend);
            tc.verifyTrue(numbered.options.Overwrite);
            % An explicit Schedule is used as given; no schedule set is chosen.
            tc.verifyEmpty(numbered.identity.schedule_set);
            tc.verifyEqual(numbered.identity.schedule_set_source,"explicit Schedule");
        end
        function emptyNumberIsEquivalentToOmission(tc)
            original = ephys.resolveRunRequest(1,1,8,'Debug',true,'Site',testSite(), ...
                'SubjectMap',subjectMap());
            empty = ephys.resolveRunRequest(1,1,8,[],'Debug',true,'Site',testSite(), ...
                'SubjectMap',subjectMap());
            tc.verifyEqual(empty,original);
        end
        function invalidNumbersFailBeforePresentation(tc)
            for bad = {0,-1,1.5,NaN,Inf,[1 2],1+1i,true,struct()}
                tc.verifyError(@() run_aot_ephys(1,1,8,bad{1}), ...
                    'ephys:RecordingNumber');
            end
            for bad = {0,-1,1.5,NaN,Inf,[1 2],1+1i,true,'','patient name','../1'}
                tc.verifyError(@() ephys.resolveRunRequest(bad{1},1,8), ...
                    'ephys:RunIdentity');
            end
            for bad = {0,-1,1.5,NaN,Inf,[1 2],1+1i,'1',true}
                tc.verifyError(@() ephys.resolveRunRequest(1,bad{1},8), ...
                    'ephys:RunIdentity');
                tc.verifyError(@() ephys.resolveRunRequest(1,1,bad{1}), ...
                    'ephys:RunIdentity');
            end
        end
        function debugOverridesStillRequireDebug(tc)
            tc.verifyError(@() ephys.resolveRunRequest(1,1,8,2, ...
                'DebugSkipSyncTests',true),'ephys:DebugOnly');
            tc.verifyError(@() ephys.resolveRunRequest(1,1,8,2, ...
                'DebugSimulatedInputOnly',true),'ephys:DebugOnly');
        end
        function missingDebugScheduleStillWarns(tc)
            tc.verifyWarning(@() ephys.resolveRunRequest(99999,1,1,2, ...
                'Debug',true,'Site',testSite(),'SubjectMap',subjectMap()), ...
                'ephys:DebugBlankSchedule');
        end
        function outputSavesActualRunAndRecordingIdentity(tc)
            blank = fullfile(ephys.projectRoot(),'config','runs', ...
                'debug_blank.yml');
            r = ephys.resolveRunRequest(1,1,8,2,'Schedule',blank,'Debug',true,'Site',testSite());
            [c,p] = ephys.loadConfig(r.task,r.schedule_path,r.site_path,true,"", ...
                r.site_selection_path);
            c.run_identity = r.identity;
            c.run_output = struct('collection_date',r.collection_date,'overwrite',true, ...
                'replaced_output',"old_replaced-101500");
            folder = tempname; mkdir(folder);
            cleanup = onCleanup(@() rmdir(folder,'s')); %#ok<NASGU>
            s = struct('OutputDir',folder,'RunId',r.run_id,'Config',c, ...
                'Provenance',p,'StartTime',0,'StopTime',1, ...
                'DisplayTiming',struct(),'EffectiveSkipSync',0, ...
                'IFI',1/60,'IFISamples',NaN,'IFIStddev',NaN, ...
                'Eye',struct('LocalPath',""));
            s.Inventory = ephys.mediaInventory(c);
            s.Log = ephys.TimelineLog(1,1);
            s.Triggers = ephys.TriggerOutput(c.markers, ...
                ephys.DummyTriggerBackend(@() 0),1,@() 0,@() "test");
            ephys.writeOutput(s,"aborted","Output identity test; no presentation");
            manifest = jsondecode(fileread(fullfile(folder, ...
                r.run_id+"_manifest.json")));
            resolved = jsondecode(fileread(fullfile(folder, ...
                r.run_id+"_resolved_config.json")));
            % JSON stores text as char; compare it as strings.
            expected = r.identity;
            expected.subject = char(expected.subject);
            expected.schedule_set_source = char(expected.schedule_set_source);
            tc.verifyEqual(manifest.run_identity,expected);
            tc.verifyEqual(resolved.run_identity,expected);
            tc.verifyEqual(string(manifest.run_output.collection_date),r.collection_date);
            tc.verifyTrue(manifest.run_output.overwrite);
            tc.verifyEqual(string(manifest.run_output.replaced_output),"old_replaced-101500");
            tc.verifyEqual(string(resolved.site_selection_path),r.site_selection_path);
            tc.verifyTrue(any(string({manifest.configuration_sources.original}) == ...
                r.site_path));
            tc.verifyEqual(string(manifest.run_id),r.run_id);
            tc.verifyEqual(string(manifest.initial_fixation.status),"not_started");
            tc.verifyEqual(string(manifest.final_fixation.status),"not_started");
            tc.verifyEqual(manifest.initial_fixation.configured_duration_s,c.protocol.video_initial_fixation_s);
            tc.verifyEqual(manifest.final_fixation.configured_duration_s,c.protocol.video_final_fixation_s);
            tc.verifyEqual(string(manifest.python_source_revision),"");
            tc.verifyEqual(string(manifest.trigger_offset_policy),"report_only");
            tc.verifyEqual(manifest.trigger_offset_reference_s,c.markers.wav.max_sync_error_s);
            tc.verifyEqual(string(manifest.trigger_offset_report.status),"created");
            tc.verifyEqual(manifest.trigger_offset_report.plotted_marker_count,0);
            tc.verifyEqual(manifest.trigger_offset_report.page_count,2);
            pdf=fullfile(folder,manifest.trigger_offset_report.file);
            tc.verifyTrue(isfile(pdf));
            fid=fopen(pdf,'r'); header=fread(fid,5,'*char')'; fclose(fid);
            tc.verifyEqual(char(header),'%PDF-');
        end
    end
end

function map = subjectMap()
% Isolated subject map: unit tests never read config/subjects.local.yml.
map = string(fullfile(ephys.projectRoot(),'tests','fixtures','subjects.test.yml'));
end
