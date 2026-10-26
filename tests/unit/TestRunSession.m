classdef TestRunSession < matlab.unittest.TestCase
    % How run_aot_ephys ends a run: Q returns quietly, other errors raise.
    methods (Test)
        function quitSavesAbortedRunWithoutError(tc)
            job = ScriptedSessionJob();
            job.RunError = MException('ephys:UserAbort','Participant/operator pressed quit.');
            outputDir = ""; status = "";
            printed = evalc('[outputDir,status] = ephys.runSession(job);');
            tc.verifyEqual(outputDir,"scripted_output");
            tc.verifyEqual(status,"aborted");
            tc.verifyEqual(job.Calls,["run";"stopPresentation";"finish:aborted"]);
            tc.verifyTrue(contains(printed,"Run stopped with Q."));
            tc.verifyTrue(contains(printed,"Saved as aborted in: scripted_output"));
            tc.verifyEqual(count(printed,repmat('=',1,60)),2);
        end
        function otherErrorsAreSavedAndRaised(tc)
            job = ScriptedSessionJob();
            job.RunError = MException('ephys:SyncFailure','Display sync test failed.');
            tc.verifyError(@() ephys.runSession(job),'ephys:SyncFailure');
            tc.verifyEqual(job.Calls,["run";"stopPresentation";"finish:aborted"]);
        end
        function completeRunReturnsComplete(tc)
            job = ScriptedSessionJob();
            [outputDir,status] = ephys.runSession(job);
            tc.verifyEqual(outputDir,"scripted_output");
            tc.verifyEqual(status,"complete");
            tc.verifyEqual(job.Calls,["run";"stopPresentation";"finish:complete"]);
        end
        function incompleteSaveStillRaises(tc)
            job = ScriptedSessionJob();
            job.FinalStatus = "aborted";
            tc.verifyError(@() ephys.runSession(job),'ephys:RunIncomplete');
        end
    end
end
