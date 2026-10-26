classdef WavTriggerBackend < ephys.TriggerBackend
    %WAVTRIGGERBACKEND Scheduled analog pulses from one master and four slaves.
    % Audio timestamps are driver estimates; physical onset remains unmeasured.
    properties (SetAccess=private)
        Settings=struct()
        Metadata=struct()
        DeviceInfo=struct()
        Waves=struct([])
        Master=[]
        Slaves=[]
        IsOpen=false
        AudioFcn
        ClockFcn
        WaitFcn
        InitializeFcn
        Pending=struct('receipt',{},'slave',{},'previous_start',{},'master_xruns',{})
        Completed=repmat(ephys.emptyTriggerReceipt(),0,1)
        % Collision checks need only [planned start, observed start, pulse
        % width, cancelled] per reservation; small rows keep polls cheap.
        ReservationTimes=zeros(0,4)
        ReservationIndex
    end
    methods
        function obj=WavTriggerBackend(audioFcn,clockFcn,waitFcn,initializeFcn)
            if nargin<1 || isempty(audioFcn), audioFcn=@PsychPortAudio; end
            if nargin<2 || isempty(clockFcn), clockFcn=@GetSecs; end
            if nargin<3 || isempty(waitFcn), waitFcn=@(s) WaitSecs('YieldSecs',s); end
            if nargin<4 || isempty(initializeFcn), initializeFcn=@() InitializePsychSound(1); end
            obj.AudioFcn=audioFcn; obj.ClockFcn=clockFcn;
            obj.WaitFcn=waitFcn; obj.InitializeFcn=initializeFcn;
            obj.ReservationIndex=containers.Map('KeyType','char','ValueType','double');
        end
        function configure(obj,settings)
            assert(~obj.IsOpen,'ephys:TriggerState','Cannot configure open audio output.');
            obj.Settings=settings; obj.Waves=ephys.loadTriggerWaveforms(settings);
        end
        function open(obj)
            if obj.IsOpen, return; end
            assert(~isempty(obj.Waves),'ephys:TriggerState','Configure WAV triggers before opening.');
            try
                obj.InitializeFcn(); s=obj.Settings.wav;
                device=obj.resolveDevice();
                obj.Master=obj.AudioFcn('Open',device,9,s.latency_class,s.sample_rate_hz,s.channels);
                obj.AudioFcn('Volume',obj.Master,s.gain);
                % A running master emits silence until a slave is scheduled.
                obj.AudioFcn('Start',obj.Master,0,0,1);
                status=obj.AudioFcn('GetStatus',obj.Master);
                assert(isfield(status,'SampleRate') && abs(status.SampleRate-s.sample_rate_hz)<.01, ...
                    'ephys:TriggerSampleRate','Audio device did not open at the configured sample rate.');
                assert(isfield(status,'OutDeviceIndex'),'ephys:TriggerDevice', ...
                    'Audio driver did not identify the selected output device.');
                devices=obj.AudioFcn('GetDevices',[],status.OutDeviceIndex);
                ix=find([devices.DeviceIndex]==status.OutDeviceIndex);
                assert(isscalar(ix),'ephys:TriggerDevice','Cannot resolve the selected audio output device.');
                obj.DeviceInfo=devices(ix);
                for k=1:numel(obj.Waves)
                    slave=obj.AudioFcn('OpenSlave',obj.Master,1,s.channels);
                    obj.Slaves(end+1)=slave;
                    obj.AudioFcn('FillBuffer',slave,obj.Waves(k).data);
                end
                metadata=obj.Waves;
                if ~isempty(metadata), metadata=rmfield(metadata,'data'); end
                obj.Metadata=struct('settings',s,'master_status',status,'device_info',obj.DeviceInfo, ...
                    'waveforms',metadata,'timestamp_basis', ...
                    "PsychPortAudio driver estimates; not measured electrical or optical onsets");
                obj.IsOpen=true;
            catch cause
                obj.releaseHandles();
                rethrow(cause);
            end
        end
        function receipt=submit(obj,key,eventId,when)
            assert(obj.IsOpen,'ephys:TriggerState','WAV trigger backend is not open.');
            obj.advance();
            k=find(string({obj.Waves.trigger_key})==string(key));
            assert(isscalar(k),'ephys:TriggerWaveform','No waveform configured for event %s.',key);
            slave=obj.Slaves(k); now=obj.ClockFcn();
            assert(~any([obj.Pending.slave]==slave),'ephys:TriggerCollision', ...
                'The waveform already has a pending reservation.');
            scheduled=isfinite(when);
            if ~scheduled, when=now; end
            assert(~isKey(obj.ReservationIndex,char(eventId)), ...
                'ephys:MarkerId','Audio reservation IDs must be unique.');
            width=obj.Waves(k).duration_s; low=obj.Settings.wav.minimum_low_s;
            times=obj.ReservationTimes;
            starts=times(:,2); unknown=~isfinite(starts); starts(unknown)=times(unknown,1);
            separated=when>=starts+times(:,3)+low-1e-9 | starts>=when+width+low-1e-9;
            assert(all(separated(times(:,4)==0)),'ephys:TriggerCollision', ...
                'Audio reservations would mix or violate the minimum low interval.');
            receipt=ephys.emptyTriggerReceipt(eventId); w=obj.Waves(k);
            receipt.planned_audio_getsecs=when; receipt.waveform_file=w.file;
            receipt.waveform_sha256=w.sha256; receipt.source_sample_rate_hz=w.source_sample_rate_hz;
            receipt.output_sample_rate_hz=w.output_sample_rate_hz;
            receipt.waveform_samples=w.samples; receipt.pulse_width_s=w.duration_s;
            receipt.output_channel=w.output_channel;
            old=obj.AudioFcn('GetStatus',slave); master=obj.AudioFcn('GetStatus',obj.Master);
            previous=obj.value(old,'StartTime',0);
            obj.AudioFcn('Start',slave,1,double(scheduled)*when,0);
            receipt.write_getsecs=obj.ClockFcn();
            if scheduled
                receipt.audio_lead_shortfall_s=max(0, ...
                    obj.Settings.wav.minimum_lead_s-(when-receipt.write_getsecs));
                if receipt.audio_lead_shortfall_s>1e-9
                    receipt.audio_qc_flags="insufficient_audio_lead";
                end
            end
            obj.ReservationTimes(end+1,:)=[when NaN w.duration_s 0];
            obj.ReservationIndex(char(eventId))=size(obj.ReservationTimes,1);
            obj.Pending(end+1)=struct('receipt',receipt,'slave',slave, ...
                'previous_start',previous,'master_xruns',obj.value(master,'XRuns',0));
        end
        function receipts=poll(obj)
            obj.advance(); receipts=obj.Completed;
            obj.Completed=repmat(ephys.emptyTriggerReceipt(),0,1);
        end
        function receipt=cancel(obj,eventId)
            obj.advance();
            ix=find(arrayfun(@(p) p.receipt.event_id==string(eventId),obj.Pending));
            if isempty(ix)
                ix=find(string({obj.Completed.event_id})==string(eventId),1,'last');
                assert(~isempty(ix),'ephys:MarkerReceipt','Unknown WAV reservation to cancel.');
                receipt=obj.Completed(ix); receipt.cancellation_status="already_completed";
                receipt.cancel_request_getsecs=obj.ClockFcn(); obj.enqueue(receipt); return;
            end
            assert(isscalar(ix),'ephys:MarkerReceipt','Duplicate WAV reservation IDs.');
            p=obj.Pending(ix); receipt=p.receipt; now=obj.ClockFcn();
            receipt.cancel_request_getsecs=now;
            status=obj.AudioFcn('GetStatus',p.slave);
            started=obj.observedStart(status,p);
            if isfinite(started) || now>=receipt.planned_audio_getsecs
                receipt.cancellation_status="already_started";
                if isfinite(started) && now<started, receipt.cancellation_status="already_buffered"; end
                if isfinite(started), receipt.audio_start_getsecs=started; end
                p.receipt=receipt; obj.Pending(ix)=p; obj.enqueue(receipt); return;
            end
            % Stop outputs are undefined when blockUntilStopped is zero.
            % Observe State instead, with a finite cleanup-only deadline.
            obj.AudioFcn('Stop',p.slave,0,0);
            began=obj.ClockFcn(); timer=tic; observed=NaN;
            while true
                status=obj.AudioFcn('GetStatus',p.slave);
                observed=obj.observedStart(status,p);
                if isfinite(observed), break; end
                if ~isfield(status,'State')
                    receipt.status="failed"; receipt.cancellation_status="cancellation_unverified";
                    receipt.error="Audio driver did not report State for cancellation acknowledgement.";
                    break;
                end
                if status.State==0, break; end
                if obj.ClockFcn()-began>=obj.Settings.wav.completion_timeout_s || ...
                        toc(timer)>=obj.Settings.wav.completion_timeout_s
                    receipt.status="failed"; receipt.cancellation_status="cancellation_timeout";
                    receipt.error="Audio reservation cancellation was not acknowledged before timeout.";
                    break;
                end
                obj.WaitFcn(.001);
            end
            if isfinite(observed)
                receipt.audio_start_getsecs=observed;
                stop=obj.value(status,'EstimatedStopTime',NaN);
                if isfinite(stop) && stop>=observed, receipt.audio_stop_getsecs=stop; end
                receipt.status="failed"; receipt.cancellation_status="started_during_cancel";
                receipt.error="Waveform started while its future reservation was being cancelled.";
                p.receipt=receipt; obj.Pending(ix)=p;
            else
                if receipt.status~="failed"
                    receipt.status="cancelled"; receipt.cancellation_status="cancelled_before_start";
                end
                receipt.completion_getsecs=obj.ClockFcn(); obj.Pending(ix)=[];
            end
            obj.enqueue(receipt);
        end
        function close(obj)
            if ~obj.IsOpen && isempty(obj.Master), return; end
            cause=[];
            try
                began=obj.ClockFcn(); timer=tic; timeout=obj.Settings.wav.completion_timeout_s;
                while ~isempty(obj.Pending)
                    obj.advance(); if isempty(obj.Pending), break; end
                    if obj.ClockFcn()-began>=timeout || toc(timer)>=timeout
                        for k=1:numel(obj.Pending)
                            p=obj.Pending(k);
                            obj.AudioFcn('Stop',p.slave,0,0);
                            r=obj.unconfirmed(p.receipt, ...
                                "Audio completion was not observed before close timeout.");
                            obj.enqueue(r);
                        end
                        obj.Pending=struct('receipt',{},'slave',{},'previous_start',{},'master_xruns',{});
                        break;
                    end
                    obj.WaitFcn(.001);
                end
            catch caught
                cause=caught;
                for k=1:numel(obj.Pending)
                    r=obj.Pending(k).receipt; r.status="failed";
                    r.qc_only_failure=false;
                    r.error=string(caught.message); r.completion_getsecs=obj.ClockFcn();
                    obj.enqueue(r); obj.updateReservation(r);
                end
                obj.Pending=struct('receipt',{},'slave',{},'previous_start',{},'master_xruns',{});
            end
            obj.releaseHandles(); obj.IsOpen=false;
            if ~isempty(cause), rethrow(cause); end
        end
    end
    methods (Access=private)
        function device=resolveDevice(obj)
            s=obj.Settings.wav; device=s.device_index; name=string(s.device_name);
            if strlength(name)==0, return; end
            devices=obj.AudioFcn('GetDevices');
            matches=find(string({devices.DeviceName})==name & [devices.NrOutputChannels]>=s.channels);
            if ~isempty(device), matches=matches([devices(matches).DeviceIndex]==device); end
            assert(isscalar(matches),'ephys:TriggerDevice', ...
                'Audio device name/index must identify exactly one output device.');
            device=devices(matches).DeviceIndex;
        end
        function advance(obj)
            if isempty(obj.Pending), return; end
            master=obj.AudioFcn('GetStatus',obj.Master); done=false(size(obj.Pending));
            for k=1:numel(obj.Pending)
                p=obj.Pending(k); r=p.receipt; s=obj.AudioFcn('GetStatus',p.slave);
                start=obj.observedStart(s,p);
                if isfinite(start), r.audio_start_getsecs=start; end
                r.audio_xruns=max(0,obj.value(master,'XRuns',0)-p.master_xruns)+obj.value(s,'XRuns',0);
                if r.audio_xruns>0
                    r.audio_qc_flags=obj.addFlag(r.audio_qc_flags,"audio_underrun");
                end
                active=logical(obj.value(s,'Active',0));
                drained=NaN;
                if isfinite(r.audio_start_getsecs)
                    stop=obj.value(s,'EstimatedStopTime',NaN);
                    drained=r.audio_start_getsecs+r.pulse_width_s;
                    if isfinite(stop) && stop>=r.audio_start_getsecs
                        r.audio_stop_getsecs=stop; drained=max(drained,stop);
                    end
                end
                % A short pulse may already be in the hardware buffer while
                % Active is zero. Keep the master alive through its offset.
                if isfinite(drained) && ~active && obj.ClockFcn()>=drained
                    r.completion_getsecs=obj.ClockFcn();
                    if r.status~="failed", r.status="complete"; end
                    done(k)=true;
                elseif r.status=="failed" && ~isfinite(drained)
                    done(k)=true; r.completion_getsecs=obj.ClockFcn();
                elseif obj.ClockFcn()>r.planned_audio_getsecs+obj.Settings.wav.completion_timeout_s
                    r=obj.unconfirmed(r,"Audio start/completion was not observed before timeout.");
                    % Do not leave a stale reservation active when its driver
                    % timestamps are unavailable. Device-call errors still fail.
                    obj.AudioFcn('Stop',p.slave,0,0);
                    r.completion_getsecs=obj.ClockFcn(); done(k)=true;
                end
                p.receipt=r; obj.Pending(k)=p;
                % Snapshot every poll so a Flip association can be checked while active.
                obj.enqueue(r);
            end
            obj.Pending(done)=[];
        end
        function updateReservation(obj,receipt)
            if ~isKey(obj.ReservationIndex,char(receipt.event_id)), return; end
            ix=obj.ReservationIndex(char(receipt.event_id));
            obj.ReservationTimes(ix,2)=receipt.audio_start_getsecs;
            obj.ReservationTimes(ix,4)=double(receipt.status=="cancelled");
        end
        function enqueue(obj,receipt)
            obj.updateReservation(receipt);
            ix=find(string({obj.Completed.event_id})==receipt.event_id,1);
            if isempty(ix), obj.Completed(end+1,1)=receipt; else, obj.Completed(ix)=receipt; end
        end
        function start=observedStart(obj,status,p)
            start=obj.value(status,'StartTime',NaN);
            if ~(isfinite(start) && start>0 && start~=p.previous_start), start=NaN; end
        end
        function receipt=unconfirmed(obj,receipt,message)
            receipt.status="failed"; receipt.error=message;
            receipt.qc_only_failure=true;
            receipt.audio_qc_flags=obj.addFlag(receipt.audio_qc_flags,"audio_completion_unobserved");
            receipt.completion_getsecs=obj.ClockFcn();
        end
        function releaseHandles(obj)
            for k=numel(obj.Slaves):-1:1
                try, obj.AudioFcn('Close',obj.Slaves(k)); catch, end
            end
            obj.Slaves=[];
            if ~isempty(obj.Master)
                try, obj.AudioFcn('Stop',obj.Master,0,0); catch, end
                try, obj.AudioFcn('Close',obj.Master); catch, end
                obj.Master=[];
            end
        end
    end
    methods (Static,Access=private)
        function flags=addFlag(flags,value)
            if strlength(flags)==0, flags=value;
            elseif ~any(split(flags,"|")==value), flags=flags+"|"+value;
            end
        end
        function v=value(s,field,default)
            v=default; if isfield(s,field), v=s.(field); end
        end
    end
end
