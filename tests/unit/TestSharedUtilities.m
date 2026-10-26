classdef TestSharedUtilities < matlab.unittest.TestCase
    methods (Test)
        function schedulesAndGeometrySurvivePackageMove(tc)
            root=ephys.projectRoot();
            settings=fullfile(root,'config','runs');
            source=ephys.readYaml(fullfile(settings,'main', ...
                'experiment_settings_sub_01_ses_01_run_01.yml'));
            schedule=ephys.validateSchedule(source.stimuli.movie_files);
            tc.verifyNumElements(schedule,84);
            tc.verifyEqual(schedule(1:7),["0973_fw.mp4";"0755_rv.mp4"; ...
                "1078_fw.mp4";"1372_fw.mp4";"1326_rv.mp4";"0472_rv.mp4";"blank"]);
            tc.verifyEqual(find(schedule=="blank")',[7 13 21 29 34 42 49 57 63 70 78 84]);
            c=struct('display',struct('resolution_px',{{1920,1080}}), ...
                'stimulus',struct('movie_canvas_px',{{1536,1080}},'movie_scale',1));
            tc.verifyEqual(ephys.movieRect(c),[0 0 1920 1080]);
            c.stimulus.movie_scale=0.8;
            tc.verifyEqual(ephys.movieRect(c),[192 108 1728 972],'AbsTol',1e-10);
            tc.verifyEqual(which('ephys.movieRect'),fullfile(root,'+ephys','movieRect.m'));
            tc.verifyFalse(isfolder(fullfile(root,'+aot')));
            tc.verifyFalse(isfolder(fullfile(root,'config','ephys')));
        end
        function strictYamlAndSchemaSurvivePackageMove(tc)
            root=ephys.projectRoot();
            [c,~]=ephys.loadConfig("video",fullfile(root,'config','runs', ...
                'debug_blank.yml'),testSite(),true,"");
            tc.verifyFalse(isfield(c,'design'));
            tc.verifyFalse(isfield(c.eyelink,'edf_prefix'));
            tc.verifyFalse(isfield(c.stimulus.fixation,'fringe_fraction'));
            file=[tempname '.yml'];
            cleanup=onCleanup(@() delete(file)); %#ok<NASGU>
            fid=fopen(file,'w'); fprintf(fid,'display:\n  bogus: 1\n'); fclose(fid);
            tc.verifyError(@() ephys.loadConfig("video",fullfile(root,'config', ...
                'runs','debug_blank.yml'),file,true,""),'aot:UnknownConfigField');
            fid=fopen(file,'w'); fprintf(fid,'protocol:\n  video_duration_s: 2\n  video_duration_s: 3\n'); fclose(fid);
            tc.verifyError(@() ephys.readYaml(file),'aot:DuplicateYAMLKey');
            tc.verifyError(@() ephys.checkSchema( ...
                struct('eyelink',struct('edf_prefix','AOT')),c),'aot:UnknownConfigField');
        end
        function eyeLinkMockLifecycle(tc)
            c = ephys.loadConfig("video",fullfile(ephys.projectRoot(), ...
                'config','runs','debug_blank.yml'), ...
                testSite(),true,"");
            c.eyelink.enabled = true;
            folder = tempname; mkdir(folder);
            cleanup = onCleanup(@() rmdir(folder,'s')); %#ok<NASGU>
            calls = strings(0,1);
            eye = ephys.EyeLinkAdapter(c,@fakeEye,@(~) struct(),@(~) noteSetup());
            eye.open(1,folder);
            eye.calibrate();
            eye.start();
            eye.mark('phase',2,'movie',10);
            eye.stopAndTransfer();
            eye.close();
            tc.verifyEqual(calls(1:3)', ...
                ["SetAddress";"Initialize";"Command"]);
            tc.verifyTrue(any(calls == "Setup"));
            tc.verifyTrue(any(calls == "StartRecording"));
            tc.verifyTrue(any(calls == "ReceiveFile"));
            tc.verifyTrue(any(calls == "Shutdown"));
            function result = fakeEye(command, varargin)
                calls(end+1) = string(command);
                result = 0;
                if strcmp(command,'ReceiveFile')
                    fid2 = fopen(varargin{2},'w');
                    fwrite(fid2, uint8(1:10));
                    fclose(fid2);
                    result = 10;
                end
            end
            function noteSetup()
                calls(end+1) = "Setup";
            end
        end
        function eyeLinkTransferFailureShutsDown(tc)
            c = ephys.loadConfig("video",fullfile(ephys.projectRoot(), ...
                'config','runs','debug_blank.yml'), ...
                testSite(),true,"");
            c.eyelink.enabled = true;
            folder = tempname; mkdir(folder);
            cleanup = onCleanup(@() rmdir(folder,'s'));
            calls = strings(0,1);
            eye = ephys.EyeLinkAdapter(c,@fakeEye,@(~) struct(),@(~) []);
            eye.open(1,folder);
            eye.start();
            tc.verifyError(@() eye.close(), 'aot:EyeLinkTransfer');
            tc.verifyFalse(eye.Connected);
            tc.verifyEqual(calls(end),"Shutdown");
            function result = fakeEye(command, varargin) %#ok<INUSD>
                calls(end+1) = string(command);
                result = 0;
                if strcmp(command,'ReceiveFile'), result = -1; end
            end
        end
    end
end
