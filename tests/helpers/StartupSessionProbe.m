classdef StartupSessionProbe < ephys.Session
    %STARTUPSESSIONPROBE Stop at device acquisition and observe startup priority.
    properties
        PriorityAtOpen=NaN
        OpenCount=0
    end
    methods
        function obj=StartupSessionProbe(config,provenance,runId)
            obj@ephys.Session(config,provenance,runId,ephys.DummyTriggerBackend());
        end
        function open(obj)
            obj.OpenCount=obj.OpenCount+1;
            obj.PriorityAtOpen=Priority;
            error('test:DeviceOpen','Injected stop before opening real devices.');
        end
        function status=finish(~,status,varargin)
            % Keep cleanup real; suppress disk reports for the device-free probe.
        end
    end
end
