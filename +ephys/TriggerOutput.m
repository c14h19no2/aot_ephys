classdef TriggerOutput < handle
    %TRIGGEROUTPUT Reserve named waveforms and associate their observed Flips.
    % Rows live in a ephys.ChunkedRows store and are found through an ID map,
    % so post-onset polls stay cheap even when MATLAB copies on every write.
    properties (SetAccess=private)
        Settings
        Backend
        ClockFcn
        IdFcn
        RowStore
        RowIndex
        Opened=false
        Closed=false
        CloseError=""
    end
    properties (Dependent)
        Count
    end
    methods
        function obj=TriggerOutput(settings,backend,capacity,clockFcn,idFcn)
            if nargin<2 || isempty(backend), backend=ephys.DummyTriggerBackend(); end
            if nargin<3 || isempty(capacity), capacity=10000; end
            if nargin<4 || isempty(clockFcn), clockFcn=@GetSecs; end
            if nargin<5 || isempty(idFcn), idFcn=@() string(char(java.util.UUID.randomUUID())); end
            assert(isa(backend,'ephys.TriggerBackend'),'ephys:TriggerBackend', ...
                'Backend must implement TriggerBackend.');
            assert(isnumeric(capacity) && isscalar(capacity) && capacity==floor(capacity) && capacity>0, ...
                'ephys:TriggerCapacity','Invalid marker capacity.');
            obj.Settings=settings; obj.Backend=backend;
            obj.ClockFcn=clockFcn; obj.IdFcn=idFcn;
            obj.RowStore=ephys.ChunkedRows(ephys.emptyMarker(),capacity,32);
            obj.RowIndex=containers.Map('KeyType','char','ValueType','double');
        end
        function value=get.Count(obj), value=obj.RowStore.Count; end
        function open(obj)
            if obj.Opened, return; end
            try
                obj.Backend.configure(obj.Settings); obj.Backend.open();
            catch cause
                try, obj.Backend.close(); catch, end
                rethrow(cause);
            end
            obj.Opened=true;
        end
        function row=schedule(obj,eventType,context,predictedOnset,inputTime,responseType)
            if nargin<5, inputTime=NaN; end
            if nargin<6, responseType=""; end
            assert(isscalar(predictedOnset) && isfinite(predictedOnset), ...
                'ephys:TriggerSchedule','Scheduled triggers require a finite predicted onset.');
            row=obj.submit(eventType,context,predictedOnset,inputTime,responseType);
        end
        function row=associate(obj,eventId,flip)
            ix=obj.index(eventId); row=obj.RowStore.at(ix);
            assert(~isfinite(row.associated_flip_seq),'ephys:MarkerAssociation', ...
                'A trigger reservation can only be associated with one Flip.');
            assert(isstruct(flip) && isfinite(flip.seq) && isfinite(flip.stimulus), ...
                'ephys:MarkerAssociation','Association requires an actual stimulus Flip timestamp.');
            row.associated_flip_seq=flip.seq; row.associated_flip_getsecs=flip.stimulus;
            for name=["frame_ready_getsecs","flip_submit_getsecs","flip_return_getsecs","submission_mode"]
                if isfield(flip,name), row.(name)=flip.(name); end
            end
            obj.RowStore.replace(ix,obj.checkSync(row)); obj.poll();
            row=obj.RowStore.at(ix); obj.raiseFailure(row);
        end
        function row=emit(obj,eventType,context,flip,inputTime,responseType)
            % Immediate events are reserved for nonvisual cleanup or dummy tasks.
            if nargin<4, flip=[]; end
            if nargin<5, inputTime=NaN; end
            if nargin<6, responseType=""; end
            row=obj.submit(eventType,context,NaN,inputTime,responseType);
            if ~isempty(flip), row=obj.associate(row.event_id,flip); end
        end
        function poll(obj)
            if ~obj.Opened || obj.Closed, return; end
            receipts=obj.Backend.poll();
            failure=[];
            for k=1:numel(receipts)
                ix=obj.index(receipts(k).event_id);
                row=obj.merge(obj.RowStore.at(ix),receipts(k)); row=obj.checkSync(row);
                obj.RowStore.replace(ix,row);
                if isempty(failure) && row.status=="failed" && ~row.qc_only_failure
                    failure=row;
                end
            end
            if ~isempty(failure), obj.raiseFailure(failure); end
        end
        function cancelPending(obj,exceptEventId)
            if nargin<2, exceptEventId=""; end
            if ~obj.Opened || obj.Closed, return; end
            failure=[];
            % Attempt every cancellation even when one reservation has failed.
            for k=find(obj.RowStore.column("status",1,obj.Count)=="queued")
                row=obj.RowStore.at(k);
                if row.event_id==string(exceptEventId), continue; end
                try
                    receipt=obj.Backend.cancel(row.event_id);
                    row=obj.merge(row,receipt);
                    if row.status=="cancelled", row.sync_status="cancelled"; end
                    obj.RowStore.replace(k,row);
                    if row.status=="failed" && ~row.qc_only_failure && isempty(failure)
                        failure=row;
                    end
                catch cause
                    row.status="failed"; row.error=string(cause.message); obj.RowStore.replace(k,row);
                    if isempty(failure), failure=row; end
                end
            end
            if ~isempty(failure), obj.raiseFailure(failure); end
        end
        function time=nextAllowedRequestTime(obj)
            time=-Inf; low=0;
            if isfield(obj.Settings,'wav'), low=obj.Settings.wav.minimum_low_s; end
            [starts,widths,active]=obj.reservedPulses(obj.Count);
            active=active & isfinite(starts);
            if any(active), time=max(starts(active)+widths(active)+low); end
        end
        function result=records(obj), result=obj.RowStore.range(1,obj.Count); end
        function drain(obj), obj.close(); end
        function close(obj)
            if obj.Closed, return; end
            if obj.Opened
                try
                    obj.Backend.close(); obj.poll();
                    states=obj.RowStore.column("status",1,obj.Count);
                    qcFailures=obj.RowStore.column("qc_only_failure",1,obj.Count);
                    assert(all(ismember(states,["dummy","complete","cancelled"]) | ...
                        (states=="failed" & qcFailures)), ...
                        'ephys:TriggerPending','One or more audio reservations did not finish or cancel.');
                catch cause
                    obj.CloseError=string(cause.message);
                    try, obj.Backend.close(); catch, end
                    try, obj.poll(); catch, end
                end
            end
            obj.Closed=true;
            if strlength(obj.CloseError)>0
                error('ephys:TriggerFailure','Trigger close failed: %s',obj.CloseError);
            end
        end
        function delete(obj)
            try, obj.close(); catch, end
        end
    end
    methods (Access=private)
        function row=submit(obj,eventType,context,when,inputTime,responseType)
            assert(obj.Opened && ~obj.Closed,'ephys:TriggerState','Trigger output is not open.');
            key=ephys.markerKey(eventType,responseType);
            row=ephys.emptyMarker(); row.event_id=string(obj.IdFcn());
            assert(strlength(row.event_id)>0 && ~isKey(obj.RowIndex,char(row.event_id)), ...
                'ephys:MarkerId','Trigger IDs must be nonempty and unique.');
            row.marker_nr=obj.Count+1; row.event_type=string(eventType); row.trigger_key=key;
            row.trial_id=string(context.trial_id); row.trial_nr=context.trial_nr;
            row.video_file=string(context.video_file); row.picture_file=string(context.picture_file);
            row.condition=string(context.condition); row.response_type=string(responseType);
            if isfield(obj.Settings,'waveforms') && isfield(obj.Settings.waveforms,char(key)) && ...
                    isfield(obj.Settings,'wav') && isfield(obj.Settings.wav,'output_channel')
                row.output_channel=obj.Settings.wav.output_channel;
            end
            row.input_getsecs=inputTime; row.request_getsecs=obj.ClockFcn();
            row.planned_audio_getsecs=when; row.predicted_visual_getsecs=when;
            row.sync_status="nonvisual";
            if isfinite(when), row.sync_status="pending"; end
            ix=obj.RowStore.append(row); obj.RowIndex(char(row.event_id))=ix;
            try
                if isfield(obj.Settings,'waveforms') && isfield(obj.Settings.waveforms,char(key))
                    proposed=when; if ~isfinite(proposed), proposed=row.request_getsecs; end
                    width=100/obj.Settings.wav.sample_rate_hz;
                    low=obj.Settings.wav.minimum_low_s;
                    [starts,widths,active]=obj.reservedPulses(ix-1);
                    separated=proposed>=starts+widths+low-1e-9 | starts>=proposed+width+low-1e-9;
                    assert(all(separated(active)),'ephys:TriggerCollision', ...
                        'Waveforms would overlap or violate the minimum low interval.');
                end
                receipt=obj.Backend.submit(key,row.event_id,when);
                row=obj.merge(row,receipt);
                if isfinite(when), row.audio_lead_s=when-row.write_getsecs; end
                obj.RowStore.replace(ix,row); obj.raiseFailure(row);
            catch cause
                row.status="failed"; row.error=string(cause.message); row.qc_only_failure=false;
                obj.RowStore.replace(ix,row);
                error('ephys:TriggerFailure','Trigger %d (%s) failed: %s',row.marker_nr,key,cause.message);
            end
        end
        function ix=index(obj,eventId)
            assert(isKey(obj.RowIndex,char(eventId)),'ephys:MarkerReceipt', ...
                'Unknown or duplicate trigger event ID.');
            ix=obj.RowIndex(char(eventId));
        end
        function [starts,widths,active]=reservedPulses(obj,last)
            % Pulse starts (observed, else planned) of rows 1:last that occupy output.
            starts=obj.RowStore.column("audio_start_getsecs",1,last);
            planned=obj.RowStore.column("planned_audio_getsecs",1,last);
            widths=obj.RowStore.column("pulse_width_s",1,last);
            status=obj.RowStore.column("status",1,last);
            unknown=~isfinite(starts); starts(unknown)=planned(unknown);
            active=status~="cancelled" & isfinite(widths);
        end
        function row=merge(~,row,receipt)
            previousFailure=row.status=="failed";
            previousError=row.error;
            previousQCOnly=row.qc_only_failure;
            fields=fieldnames(receipt);
            for k=1:numel(fields)
                field=fields{k};
                if isfield(row,field), row.(field)=receipt.(field); end
            end
            if previousFailure
                if ~isfield(receipt,'status') || string(receipt.status)~="failed"
                    row.error=previousError; row.qc_only_failure=previousQCOnly;
                else
                    row.qc_only_failure=previousQCOnly && row.qc_only_failure;
                    if ~previousQCOnly, row.error=previousError; end
                end
                row.status="failed";
            end
            assert(any(row.status==["queued","dummy","complete","cancelled","failed"]), ...
                'ephys:TriggerReceipt','Backend returned an unknown trigger status.');
        end
        function row=checkSync(obj,row)
            if isa(obj.Backend,'ephys.DummyTriggerBackend')
                row.sync_status="simulated"; return;
            end
            if row.status=="cancelled", row.sync_status="cancelled"; return; end
            if ~isfinite(row.associated_flip_getsecs), return; end
            if isfinite(row.audio_start_getsecs)
                row.audio_visual_delta_s=row.audio_start_getsecs-row.associated_flip_getsecs;
                if abs(row.audio_visual_delta_s)<=obj.Settings.wav.max_sync_error_s
                    row.sync_status="within_tolerance";
                else
                    % The configured value is a reporting reference, not an
                    % abort threshold. Preserve the backend completion state.
                    row.sync_status="out_of_tolerance";
                end
            end
        end
        function raiseFailure(~,row)
            if (row.status=="failed" || strlength(row.error)>0) && ~row.qc_only_failure
                error('ephys:TriggerFailure','Trigger %d (%s): %s',row.marker_nr,row.trigger_key,row.error);
            end
        end
    end
end
