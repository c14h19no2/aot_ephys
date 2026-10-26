classdef DummyTriggerBackend < ephys.TriggerBackend
    %DUMMYTRIGGERBACKEND Simulate named reservations without any analog output.
    properties (SetAccess=private)
        IsOpen=false
        SubmitCount=0
        ClockFcn
        WaitFcn
        FailOnSubmit=NaN
        Settings=struct()
        Waves=struct([])
        Pending=repmat(ephys.emptyTriggerReceipt(),0,1)
        Completed=repmat(ephys.emptyTriggerReceipt(),0,1)
    end
    methods
        function obj=DummyTriggerBackend(clockFcn,failOnSubmit,waitFcn)
            if nargin<1 || isempty(clockFcn), clockFcn=@GetSecs; end
            if nargin<2 || isempty(failOnSubmit), failOnSubmit=NaN; end
            if nargin<3 || isempty(waitFcn), waitFcn=@(s) WaitSecs('YieldSecs',s); end
            obj.ClockFcn=clockFcn; obj.FailOnSubmit=failOnSubmit; obj.WaitFcn=waitFcn;
        end
        function configure(obj,settings)
            obj.Settings=settings;
            if isfield(settings,'waveforms'), obj.Waves=ephys.loadTriggerWaveforms(settings); end
        end
        function open(obj), obj.IsOpen=true; end
        function receipt=submit(obj,key,eventId,when)
            if nargin<4, when=NaN; end
            assert(obj.IsOpen,'ephys:TriggerState','Dummy trigger backend is not open.');
            obj.SubmitCount=obj.SubmitCount+1;
            if obj.SubmitCount==obj.FailOnSubmit
                error('ephys:DummyTriggerFailure','Injected dummy marker failure.');
            end
            now=obj.ClockFcn(); receipt=ephys.emptyTriggerReceipt(eventId);
            receipt.write_getsecs=now;
            if ~isfinite(when), when=now; end
            receipt.planned_audio_getsecs=when;
            ix=find(string({obj.Waves.trigger_key})==string(key),1);
            if ~isempty(ix)
                w=obj.Waves(ix); receipt.waveform_file=w.file; receipt.waveform_sha256=w.sha256;
                receipt.source_sample_rate_hz=w.source_sample_rate_hz;
                receipt.output_sample_rate_hz=w.output_sample_rate_hz;
                receipt.waveform_samples=w.samples; receipt.pulse_width_s=w.duration_s;
                receipt.output_channel=w.output_channel;
            end
            if when<=now
                receipt.status="dummy"; receipt.completion_getsecs=now;
            else
                obj.Pending(end+1)=receipt; obj.Pending=obj.Pending(:);
            end
        end
        function receipts=poll(obj)
            now=obj.ClockFcn(); done=false(size(obj.Pending));
            for k=1:numel(obj.Pending)
                r=obj.Pending(k); width=r.pulse_width_s;
                if ~isfinite(width), width=0; end
                if now>=r.planned_audio_getsecs+width
                    r.status="dummy"; r.completion_getsecs=now;
                    obj.Completed(end+1,1)=r; done(k)=true;
                end
            end
            obj.Pending(done)=[]; obj.Pending=obj.Pending(:); receipts=obj.Completed;
            obj.Completed=repmat(ephys.emptyTriggerReceipt(),0,1);
        end
        function receipt=cancel(obj,eventId)
            ix=find(string({obj.Pending.event_id})==string(eventId));
            assert(isscalar(ix),'ephys:MarkerReceipt','Unknown pending dummy reservation.');
            receipt=obj.Pending(ix); now=obj.ClockFcn(); receipt.cancel_request_getsecs=now;
            if now<receipt.planned_audio_getsecs
                receipt.status="cancelled"; receipt.cancellation_status="cancelled_before_start";
                receipt.completion_getsecs=now; obj.Pending(ix)=[]; obj.Pending=obj.Pending(:);
            else
                receipt.cancellation_status="already_started"; obj.Pending(ix)=receipt;
            end
        end
        function close(obj)
            if ~obj.IsOpen, return; end
            timeout=2; if isfield(obj.Settings,'wav'), timeout=obj.Settings.wav.completion_timeout_s; end
            started=obj.ClockFcn(); timer=tic;
            while ~isempty(obj.Pending)
                receipts=obj.poll(); obj.Completed=[obj.Completed;receipts];
                if isempty(obj.Pending), break; end
                if obj.ClockFcn()-started>=timeout || toc(timer)>=timeout
                    obj.IsOpen=false;
                    error('ephys:TriggerPending','Dummy reservations did not finish before close timeout.');
                end
                obj.WaitFcn(min(.001,timeout));
            end
            obj.IsOpen=false;
        end
    end
end
