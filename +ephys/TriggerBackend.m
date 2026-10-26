classdef TriggerBackend < handle
    %TRIGGERBACKEND Named-event, nonblocking waveform reservation contract.
    % submit reserves audio at when (NaN means immediate). poll observes the
    % device without waiting. cancel must preserve any pulse already started.
    methods
        function configure(~,~)
        end
        function open(~)
        end
        function receipt=submit(~,~,~,~) %#ok<STOUT>
            error('ephys:BackendNotImplemented','Implement a named-event trigger backend.');
        end
        function receipts=poll(~)
            receipts=repmat(ephys.emptyTriggerReceipt(),0,1);
        end
        function receipt=cancel(~,~) %#ok<STOUT>
            error('ephys:BackendNotImplemented','Backend does not support cancelling reservations.');
        end
        function close(~)
        end
    end
end
