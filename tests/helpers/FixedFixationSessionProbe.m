classdef FixedFixationSessionProbe < ephys.Session
    %FIXEDFIXATIONSESSIONPROBE Keep runtime refresh tests free of disk reports.
    methods
        function obj=FixedFixationSessionProbe(config,provenance,runId,inputFcn)
            obj@ephys.Session(config,provenance,runId,ephys.DummyTriggerBackend(),inputFcn);
        end
        function status=finish(~,status,varargin)
            % Exercise real close/cleanup without exporting a participant report.
        end
    end
end
