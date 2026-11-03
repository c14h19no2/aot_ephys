classdef TestPracticeTask < matlab.unittest.TestCase
    % Practice task: the video task with one shared schedule and clip folder.
    methods (Test)
        function sharedScheduleFollowsItsRules(tc)
            names = TestPracticeTask.schedule();
            tc.verifyNumElements(names,19);
            % Three blanks, never first or last, at least 5 trials apart.
            blanks = find(names=="blank");
            tc.verifyNumElements(blanks,3);
            tc.verifyGreaterThan(blanks(1),1);
            tc.verifyLessThan(blanks(end),numel(names));
            tc.verifyGreaterThanOrEqual(min(diff(blanks)),5);
            videos = names(names~="blank");
            clips = unique(videos);
            tc.verifyNumElements(videos,16);
            tc.verifyNumElements(clips,16);                     % each clip once
            direction = arrayfun(@ephys.condition,videos);
            tc.verifyEqual(sum(direction=="forward"),8);
            tc.verifyEqual(sum(direction=="backward"),8);
            tc.verifyTrue(all(startsWith(videos(direction=="forward"),"S_")));
            tc.verifyTrue(all(startsWith(videos(direction=="backward"),"R_S_")));
            % At most two videos in a row share a direction.
            runs = diff([0;find(direction(1:end-1)~=direction(2:end));numel(direction)]);
            tc.verifyLessThanOrEqual(max(runs),2);
            % No clip is shown in both directions.
            source = erase(erase(clips,textBoundary("start")+"R_"),textBoundary("start")+"S_");
            tc.verifyNumElements(unique(source),16);
        end
        function requestUsesTheSharedSchedule(tc)
            r = ephys.resolveRunRequest(1,1,1,'Task','practice','Site',testSite());
            tc.verifyEqual(r.schedule_path,string(fullfile(ephys.projectRoot(), ...
                'config','runs','practice','practice_videos.yml')));
            tc.verifyEqual(r.run_id,"sub-001_ses-01_run-01_task-practice");
            tc.verifyEqual(r.identity.task,"practice");
            tc.verifyEmpty(r.identity.schedule_set);
            tc.verifyEqual(r.identity.schedule_set_source,"shared practice schedule");
            % A named subject needs no subject-map entry for practice.
            map = string(fullfile(ephys.projectRoot(),'tests','fixtures','subjects.test.yml'));
            r = ephys.resolveRunRequest("newperson",1,1,'Task','practice', ...
                'Site',testSite(),'SubjectMap',map);
            tc.verifyEqual(r.run_id,"sub-newperson_ses-01_run-01_task-practice");
            tc.verifyError(@() ephys.resolveRunRequest("newperson",1,1, ...
                'Site',testSite(),'SubjectMap',map),'ephys:ScheduleSet');
        end
        function configLoadsAsVideoFromThePracticeFolder(tc)
            r = ephys.resolveRunRequest(1,1,1,'Task','practice','Site',testSite());
            [c,~] = ephys.loadConfig(r.task,r.schedule_path,r.site_path,false,"");
            tc.verifyEqual(c.task_kind,"video");
            tc.verifyEqual(string(c.paths.video_root),string(c.paths.practice_video_root));
            % Practice copies are read from their own folder, not the main one.
            tc.verifyEqual(string(c.playback.native_media_root), ...
                string(c.playback.practice_native_media_root));
            main = ephys.resolveRunRequest(1,1,1,'Site',testSite());
            [v,~] = ephys.loadConfig(main.task,main.schedule_path,main.site_path,false,"");
            tc.verifyNotEqual(string(c.playback.native_media_root), ...
                string(v.playback.native_media_root));
            tc.verifyNotEqual(string(c.paths.video_root),string(v.paths.video_root));
            tc.verifyEqual(c.schedule,TestPracticeTask.schedule());
            p = ephys.previewRunRequest(1,1,1,'Task','practice','Site',testSite());
            tc.verifyEqual(p.error,"");
            tc.verifyEqual(p.schedule_path,r.schedule_path);
        end
        function preparationAndVerificationListTheSixteenClips(tc)
            r = ephys.resolveNativePreparation('Task','practice','Site',testSite());
            tc.verifyEqual(r.mode,"practice schedule");
            tc.verifyNumElements(r.sources,16);
            [c,~] = ephys.loadConfig("practice",fullfile(ephys.projectRoot(),'config','runs', ...
                'practice','practice_videos.yml'),testSite(),false,"");
            tc.verifyTrue(all(startsWith(r.sources,string(c.paths.practice_video_root))));
            saved = ephys.resolveNativePreparation(1,1,1,'Task','practice','Site',testSite());
            tc.verifyEqual(sort(saved.sources),sort(r.sources));
            % Both forms prepare and verify into the practice copy folder.
            copies = string(c.playback.practice_native_media_root);
            tc.verifyEqual(ephys.nativeMediaRoot(r.playback),copies);
            tc.verifyEqual(ephys.nativeMediaRoot(saved.playback),copies);
            tc.verifyError(@() ephys.resolveNativePreparation('Task','memory','Site',testSite()), ...
                'ephys:NativePreparationTask');
        end
        function practiceNeedsItsOwnCopyFolder(tc)
            settings = ephys.readYaml(testSite());
            settings.playback = rmfield(settings.playback,'practice_native_media_root');
            folder = tempname; mkdir(folder);
            guard = onCleanup(@() rmdir(folder,'s')); %#ok<NASGU>
            site = fullfile(folder,'site.yml');
            yaml.dumpFile(site,settings,'block');
            schedule = fullfile(ephys.projectRoot(),'config','runs','practice','practice_videos.yml');
            for attempt = {@() ephys.loadConfig("practice",schedule,site,false,""), ...
                    @() ephys.resolveNativePreparation('Task','practice','Site',site)}
                try
                    attempt{1}();
                    tc.verifyFail('Practice ran without playback.practice_native_media_root.');
                catch cause
                    tc.verifyEqual(cause.identifier,'ephys:NativeMediaRoot');
                    tc.verifySubstring(cause.message,'practice_native_media_root');
                end
            end
            % The main video task does not need the practice setting.
            main = ephys.resolveRunRequest(1,1,1,'Site',site);
            [c,~] = ephys.loadConfig(main.task,main.schedule_path,main.site_path,false,"");
            tc.verifyEqual(c.task_kind,"video");
        end
    end
    methods (Static)
        function names = schedule()
            doc = ephys.readYaml(fullfile(ephys.projectRoot(),'config','runs','practice','practice_videos.yml'));
            names = ephys.validateSchedule(doc.stimuli.movie_files);
        end
    end
end
