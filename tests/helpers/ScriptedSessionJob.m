classdef ScriptedSessionJob < handle
    %SCRIPTEDSESSIONJOB Stand-in for ephys.Session in entry-point tests.
    % run() throws RunError when set; finish() keeps the first saved status,
    % as ephys.Session does once it is finalized.
    properties
        RunError = []
        OutputDir = "scripted_output"
        Calls = strings(0,1)
        FinalStatus = ""
    end
    methods
        function run(obj)
            obj.Calls(end+1,1) = "run";
            if ~isempty(obj.RunError), throw(obj.RunError); end
        end
        function stopPresentation(obj)
            obj.Calls(end+1,1) = "stopPresentation";
        end
        function status = finish(obj,status,~)
            obj.Calls(end+1,1) = "finish:"+status;
            if strlength(obj.FinalStatus)==0, obj.FinalStatus = string(status); end
            status = obj.FinalStatus;
        end
    end
end
