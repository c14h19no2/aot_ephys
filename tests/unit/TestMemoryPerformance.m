classdef TestMemoryPerformance < matlab.unittest.TestCase
    % Memory answers from the session's video schedules, scores and their printout.
    methods (Test)
        function sessionSchedulesReproduceArchivedAnswerFiles(tc)
            runs = fullfile(ephys.projectRoot(),'config','runs');
            for id = [1 1; 5 3]'
                name = sprintf('experiment_settings_sub_%02d_ses_%02d_run_01.yml',id(1),id(2));
                memory = fullfile(runs,'memory_main',name);
                pictures = TestMemoryPerformance.pictures(memory);
                videos = ephys.memoryAnswerSchedules(memory);
                tc.verifyNumElements(videos,10);
                tc.verifyTrue(all(startsWith(videos,string(fullfile(runs,'main')))));
                derived = ephys.memoryAnswerKey(videos,pictures);
                archived = ephys.loadAnswers(fullfile(runs,'memory_main','answers', ...
                    sprintf('answer_dict_sub_%02d_ses_%02d.tsv',id(1),id(2))),pictures);
                tc.verifyEqual(sort(string(keys(derived))),sort(string(keys(archived))));
                tc.verifyEqual(string(values(derived,keys(archived))), ...
                    string(values(archived)));
            end
        end
        function defaultScheduleIsHalfFromTheSession(tc)
            memory = fullfile(ephys.projectRoot(),'config','runs','memory_main_complete', ...
                'experiment_settings_sub_01_ses_01_run_01.yml');
            pictures = TestMemoryPerformance.pictures(memory);
            key = ephys.memoryAnswerKey(ephys.memoryAnswerSchedules(memory),pictures);
            tc.verifyEqual(double(key.Count),360);
            tc.verifyEqual(sum(string(values(key))=="Y"),180);
        end
        function otherSchedulesHaveNoAnswerSchedules(tc)
            runs = fullfile(ephys.projectRoot(),'config','runs');
            tc.verifyEmpty(ephys.memoryAnswerSchedules(fullfile(runs,'debug_blank.yml')));
            tc.verifyEmpty(ephys.memoryAnswerSchedules(fullfile(runs,'main', ...
                'experiment_settings_sub_01_ses_01_run_01.yml')));
            tc.verifyEmpty(ephys.memoryAnswerSchedules(fullfile(tempdir,'memory_main_complete', ...
                'experiment_settings_sub_01_ses_01_run_01.yml')));
        end
        function configRecordsTheAnswerSource(tc)
            runs = fullfile(ephys.projectRoot(),'config','runs');
            memory = fullfile(runs,'memory_main_complete','experiment_settings_sub_01_ses_01_run_01.yml');
            [site,guard] = TestMemoryPerformance.siteWithPictures(memory); %#ok<ASGLU>
            [c,p] = ephys.loadConfig("memory",memory,site,false,"");
            tc.verifyEqual(c.answer_source,"session_video_schedules");
            tc.verifyNumElements(c.answer_schedules,10);
            tc.verifyTrue(all(ismember(c.answer_schedules,string(p.files))));
            % An explicit answer file takes precedence.
            old = fullfile(runs,'memory_main','experiment_settings_sub_01_ses_01_run_01.yml');
            [site,guard2] = TestMemoryPerformance.siteWithPictures(old); %#ok<ASGLU>
            answers = fullfile(runs,'memory_main','answers','answer_dict_sub_01_ses_01.tsv');
            c = ephys.loadConfig("memory",old,site,false,answers);
            tc.verifyEqual(c.answer_source,"answer_file");
            tc.verifyEmpty(c.answer_schedules);
            % Video runs have no answers.
            c = ephys.loadConfig("video",fullfile(runs,'debug_blank.yml'),testSite(),true,"");
            tc.verifyEqual(c.answer_source,"none");
        end
        function scoresHitsFalseAlarmsAndDPrime(tc)
            % Y-yes hit, Y-no miss, N-yes false alarm, N-no correct rejection,
            % plus one picture shown but not answered (run stopped).
            events = TestMemoryPerformance.events(["Y" "Y" "N" "N"],["yes" "no" "yes" "no"],1);
            c = struct('answer_source',"session_video_schedules",'answer_schedules',strings(10,1));
            perf = ephys.memoryPerformance(events,c);
            tc.verifyEqual(perf.status,"scored");
            tc.verifyEqual([perf.presented perf.answered perf.unanswered perf.scored],[5 4 1 4]);
            tc.verifyEqual([perf.hits perf.misses perf.false_alarms perf.correct_rejections],[1 1 1 1]);
            tc.verifyEqual([perf.accuracy perf.hit_rate perf.false_alarm_rate],[.5 .5 .5]);
            tc.verifyEqual(perf.d_prime,0,'AbsTol',1e-12);
            tc.verifyEqual(perf.median_rt_s,0.65,'AbsTol',1e-12);
            % Perfect performance keeps a finite d' (log-linear correction).
            events = TestMemoryPerformance.events(["Y" "Y" "Y" "N" "N" "N"], ...
                ["yes" "yes" "yes" "no" "no" "no"],0);
            perf = ephys.memoryPerformance(events,c);
            tc.verifyEqual(perf.accuracy,1);
            tc.verifyEqual(perf.d_prime,2*1.150349380376008,'AbsTol',1e-9);
            text = evalc('ephys.printMemoryPerformance(perf)');
            % The block is framed by separator lines.
            lines = splitlines(strtrim(string(text)));
            tc.verifyEqual(lines(1),string(repmat('=',1,78)));
            tc.verifyEqual(lines(2)," MEMORY PERFORMANCE");
            tc.verifyEqual(lines(end),string(repmat('=',1,78)));
            tc.verifySubstring(text,'Memory: 6 pictures shown, 6 answered (yes 3, no 3)');
            tc.verifySubstring(text,'Accuracy 100.0% (6/6). Hits 3/3 (100.0%), false alarms 0/3 (0.0%), d'' 2.30.');
            tc.verifySubstring(text,'this session''s 10 video runs');
        end
        function withoutAnAnswerKeyAccuracyStaysUnknown(tc)
            events = TestMemoryPerformance.events(["" ""],["yes" "no"],0);
            perf = ephys.memoryPerformance(events,struct('answer_source',"none"));
            tc.verifyEqual(perf.status,"no_answer_key");
            tc.verifyTrue(isnan(perf.accuracy));
            tc.verifyTrue(isnan(perf.d_prime));
            text = evalc('ephys.printMemoryPerformance(perf)');
            tc.verifySubstring(text,'Accuracy unknown');
            perf = ephys.memoryPerformance(repmat(ephys.emptyEvent(),0,1),struct());
            tc.verifyEqual(perf.status,"no_responses");
        end
        function runOutputSavesAndPrintsTheScores(tc)
            root = ephys.projectRoot();
            [c,p] = ephys.loadConfig("video",fullfile(root,'config','runs','debug_blank.yml'), ...
                testSite(),true,"");
            c.task_kind = "memory";
            c.answer_source = "session_video_schedules";
            c.answer_schedules = strings(10,1);
            folder = tempname; mkdir(folder);
            guard = onCleanup(@() rmdir(folder,'s')); %#ok<NASGU>
            p.files = {}; p.sha256 = {};
            events = TestMemoryPerformance.events(["Y" "N"],["yes" "no"],0);
            frame = ephys.emptyFlip(); frame.flip_seq = 1;
            s = struct('OutputDir',folder,'RunId',"memory_scores",'Config',c, ...
                'Provenance',p,'StartTime',0,'StopTime',1, ...
                'DisplayTiming',struct(),'EffectiveSkipSync',0, ...
                'IFI',1/60,'IFISamples',NaN,'IFIStddev',NaN, ...
                'Eye',struct('LocalPath',""),'Inventory',struct([]), ...
                'Log',struct('flipRecords',@() frame,'eventRecords',@() events));
            s.Triggers = ephys.TriggerOutput(c.markers,ephys.DummyTriggerBackend(@() 0),1,@() 0);
            triggerGuard = onCleanup(@() delete(s.Triggers)); %#ok<NASGU>
            text = evalc('ephys.writeOutput(s,"complete","")');
            tc.verifySubstring(text,'Accuracy 100.0% (2/2)');
            manifest = jsondecode(fileread(fullfile(folder,'memory_scores_manifest.json')));
            tc.verifyEqual(string(manifest.memory_performance.status),"scored");
            tc.verifyEqual(manifest.memory_performance.accuracy,1);
        end
    end
    methods (Static)
        function pictures = pictures(schedule)
            doc = ephys.readYaml(schedule);
            pictures = ephys.validatePictureSchedule(doc.stimuli.picture_files);
        end
        function [site,guard] = siteWithPictures(schedule)
            % The isolated test site with placeholder pictures for one schedule.
            settings = ephys.readYaml(testSite());
            folder = tempname; mkdir(folder);
            guard = onCleanup(@() rmdir(folder,'s'));
            settings.paths.picture_root = fullfile(folder,'pictures');
            mkdir(settings.paths.picture_root);
            for name = TestMemoryPerformance.pictures(schedule)'
                fid = fopen(fullfile(settings.paths.picture_root,name),'w'); fclose(fid);
            end
            site = fullfile(folder,'site.yml');
            yaml.dumpFile(site,settings,'block');
        end
        function events = events(expected,answers,unanswered)
            % One onset per picture and one response per answer; RTs 0.5, 0.6, ...
            events = repmat(ephys.emptyEvent(),0,1);
            for k = 1:numel(answers)+unanswered
                onset = ephys.emptyEvent();
                onset.event_type = "memory_stimulus_onset"; onset.trial_nr = k;
                events(end+1,1) = onset; %#ok<AGROW>
                if k > numel(answers), continue; end
                response = ephys.emptyEvent();
                response.event_type = "memory_response"; response.trial_nr = k;
                response.response_type = answers(k);
                response.expected_answer = expected(k);
                response.rt_s = 0.4+0.1*k;
                events(end+1,1) = response; %#ok<AGROW>
            end
        end
    end
end
