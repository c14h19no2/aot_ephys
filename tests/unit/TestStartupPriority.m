classdef TestStartupPriority < matlab.unittest.TestCase
    properties
        Folder
    end
    methods (TestMethodSetup)
        function isolateSchedulingFunctions(tc)
            fixture=tc.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            tc.Folder=fixture.Folder;
            TestStartupPriority.writeStub(tc.Folder,'Priority',[
                "function old=Priority(level)"
                "persistent current"
                "if isempty(current), current=0; end"
                "old=current;"
                "if nargin>0, current=level; end"
                "end"]);
            TestStartupPriority.writeStub(tc.Folder,'MaxPriority',[
                "function value=MaxPriority(varargin)"
                "value=1;"
                "end"]);
            TestStartupPriority.writeStub(tc.Folder,'GetSecs',[
                "function value=GetSecs"
                "value=10;"
                "end"]);
            tc.applyFixture(matlab.unittest.fixtures.PathFixture(tc.Folder));
            TestStartupPriority.clearStubs();
            tc.addTeardown(@TestStartupPriority.clearStubs);
        end
    end
    methods (Test)
        function acquisitionClearsInheritedPriorityBeforeDeviceInitialization(tc)
            job=tc.createJob(false);
            Priority(1); % Simulate an earlier script leaving elevated scheduling.
            tc.verifyError(@() job.run(),'test:DeviceOpen');
            tc.verifyEqual(job.OpenCount,1);
            tc.verifyEqual(job.PriorityAtOpen,0);
            tc.verifyEqual(Priority,0);
            tc.verifyFalse(job.RunStarted);
            job.close();
            tc.verifyEqual(Priority,0);
            tc.verifyTrue(job.Closed);
        end
        function debugAlsoInitializesDevicesAtNormalPriority(tc)
            job=tc.createJob(true);
            Priority(1);
            tc.verifyError(@() job.run(),'test:DeviceOpen');
            tc.verifyEqual(job.PriorityAtOpen,0);
            tc.verifyEqual(Priority,0);
            job.close();
            tc.verifyEqual(Priority,0);
        end
        function interruptedStartupCleanupRestoresNormalPriorityOnce(tc)
            job=tc.createJob(false);
            tc.verifyError(@() job.run(),'test:DeviceOpen');
            Priority(1);
            job.stopPresentation();
            tc.verifyEqual(Priority,0);
            tc.verifyTrue(job.PresentationStopped);
            job.close();
            tc.verifyEqual(Priority,0);
            tc.verifyTrue(job.Closed);
        end
    end
    methods (Access=private)
        function job=createJob(tc,debug)
            schedule=fullfile(ephys.projectRoot(),'config','runs','debug_blank.yml');
            [c,p]=ephys.loadConfig("video",schedule,testSite(),debug,"");
            c.schedule="blank";
            c.protocol.video_initial_fixation_s=0;
            c.protocol.video_final_fixation_s=0;
            c.paths.output_root=tempname(tc.Folder);
            job=StartupSessionProbe(c,p,"startup_priority");
            tc.addTeardown(@() delete(job));
        end
    end
    methods (Static,Access=private)
        function writeStub(folder,name,lines)
            fid=fopen(fullfile(folder,[name '.m']),'w');
            guard=onCleanup(@() fclose(fid)); %#ok<NASGU>
            fprintf(fid,'%s\n',char(join(lines,newline)));
        end
        function clearStubs()
            clear Priority MaxPriority GetSecs
        end
    end
end
