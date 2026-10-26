function [outputDir,status] = runSession(job)
%RUNSESSION Present, save and report one Session for run_aot_ephys.
% Any error saves the observed part as aborted and is rethrown. Q
% (ephys:UserAbort) is an intended stop: the same aborted record is saved,
% including the run-end attempt, and the output folder is returned without
% an error. The caller still owns job.close().
try
    job.run();
    job.stopPresentation();
    status = job.finish("complete","");
    assert(status=="complete",'ephys:RunIncomplete', ...
        'Run ended with a trigger or EyeLink completion failure.');
catch cause
    try, job.stopPresentation();
    catch cleanupCause
        warning('ephys:PresentationCleanup','%s',cleanupCause.message);
    end
    try, job.finish("aborted",cause.message);
    catch saveCause
        warning('ephys:PartialOutput', ...
            'Aborted run could not be saved fully: %s',saveCause.message);
    end
    if ~strcmp(cause.identifier,'ephys:UserAbort')
        rethrow(cause);
    end
    status = "aborted";
    % A banner, not an error: it is the last thing printed after the save.
    rule = repmat('=',1,60);
    fprintf('\n%s\nRun stopped with Q.\nSaved as aborted in: %s\n%s\n\n',rule,job.OutputDir,rule);
end
outputDir = job.OutputDir;
end
