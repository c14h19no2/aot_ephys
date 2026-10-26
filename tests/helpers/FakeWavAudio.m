classdef FakeWavAudio < handle
    %FAKEWAVAUDIO Deterministic device model for scheduled playback tests.
    properties
        Now=10
        Devices=struct('DeviceIndex',7,'DeviceName','Test analog output','NrOutputChannels',2)
        Handles=struct('handle',{},'master',{},'samples',{},'when',{},'start',{},'stop',{},'active',{})
        Calls={}
        FailOpen=false
        SampleRate=48000
        StartDelay=0
        XRuns=0
        MasterXRuns=0
        NeverStart=false
        CancelRace=false
        RenderAhead_s=0
    end
    methods
        function advance(obj,seconds), obj.Now=obj.Now+seconds; end
        function varargout=call(obj,command,varargin)
            obj.Calls{end+1}=[{command},varargin];
            switch command
                case 'GetDevices'
                    varargout{1}=obj.Devices;
                case 'Open'
                    if obj.FailOpen, error('test:AudioOpen','Injected device-open failure.'); end
                    obj.addHandle(true); varargout{1}=numel(obj.Handles);
                case 'OpenSlave'
                    obj.addHandle(false); varargout{1}=numel(obj.Handles);
                case 'FillBuffer'
                    obj.Handles(varargin{1}).samples=varargin{2};
                case 'Volume'
                case 'Start'
                    ix=varargin{1}; h=obj.Handles(ix);
                    when=varargin{3}; if when==0, when=obj.Now; end
                    h.when=when; h.start=0; h.stop=0; h.active=true;
                    obj.Handles(ix)=h;
                    if nargout>0, varargout{1}=when; end
                case 'GetStatus'
                    ix=varargin{1}; h=obj.update(ix);
                    xruns=obj.XRuns; if h.master, xruns=obj.MasterXRuns; end
                    varargout{1}=struct('SampleRate',obj.SampleRate,'OutDeviceIndex',7, ...
                        'StartTime',h.start,'EstimatedStopTime',h.stop, ...
                        'Active',double(h.active && h.start>0),'State',obj.state(h),'XRuns',xruns);
                case 'Stop'
                    ix=varargin{1}; h=obj.update(ix);
                    if obj.CancelRace && ~h.master && h.start==0
                        h.start=obj.Now; h.stop=obj.Now; obj.CancelRace=false;
                    end
                    h.active=false; h.when=NaN; obj.Handles(ix)=h;
                    values={h.start,0,0,h.stop};
                    for k=1:nargout, varargout{k}=values{k}; end
                case 'Close'
                    obj.Handles(varargin{1}).active=false;
                otherwise
                    error('test:AudioCommand','Unexpected audio command %s.',command);
            end
        end
    end
    methods (Access=private)
        function addHandle(obj,master)
            h=struct('handle',numel(obj.Handles)+1,'master',master,'samples',[], ...
                'when',NaN,'start',0,'stop',0,'active',false);
            obj.Handles(end+1)=h;
        end
        function value=state(~,h)
            value=0;
            if h.active
                value=1; if h.start>0, value=2; end
            end
        end
        function h=update(obj,ix)
            h=obj.Handles(ix);
            if h.active && ~obj.NeverStart && obj.Now+obj.RenderAhead_s>=h.when+obj.StartDelay
                h.start=h.when+obj.StartDelay;
                if ~h.master
                    h.stop=h.start+size(h.samples,2)/obj.SampleRate;
                    if obj.Now+obj.RenderAhead_s>=h.stop, h.active=false; end
                end
            end
            obj.Handles(ix)=h;
        end
    end
end
