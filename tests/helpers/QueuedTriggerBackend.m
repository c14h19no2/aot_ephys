classdef QueuedTriggerBackend < ephys.TriggerBackend
    % Test backend that never acknowledges scheduled playback completion.
    properties
        IsOpen = false
    end
    methods
        function configure(~,~)
        end
        function open(obj)
            obj.IsOpen = true;
        end
        function receipt = submit(~,~,~,varargin)
            receipt = struct('write_getsecs',1, ...
                'completion_getsecs',NaN,'audio_start_getsecs',NaN, ...
                'audio_stop_getsecs',NaN,'physical_onset_getsecs',NaN, ...
                'status',"queued",'error',"");
        end
        function close(obj)
            obj.IsOpen = false;
        end
    end
end
