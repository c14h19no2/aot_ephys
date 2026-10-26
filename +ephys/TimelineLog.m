classdef TimelineLog < handle
    %TIMELINELOG Preallocated, joinable records of submitted display flips.
    % Rows live in ephys.ChunkedRows stores, so a write never copies the whole
    % log even when MATLAB does not update a property in place. Intervals are
    % derived from consecutive onsets when records are read.
    properties (Constant)
        ChunkSize = 128
    end
    properties (SetAccess = private)
        FlipStore
        EventStore
    end
    properties (Dependent)
        FlipCount
        EventCount
        Flips % Rows 1:FlipCount, assembled on read; not for refresh loops.
        Events % Rows 1:EventCount, assembled on read.
    end
    methods
        function obj = TimelineLog(maxFlips,maxEvents)
            obj.FlipStore = ephys.ChunkedRows(ephys.emptyFlip(),maxFlips,obj.ChunkSize);
            obj.EventStore = ephys.ChunkedRows(ephys.emptyEvent(),maxEvents,obj.ChunkSize);
        end
        function row = flip(obj,context,phase,phaseSeq,raw,deadline,frame,diode)
            row = ephys.emptyFlip();
            row.trial_id = context.trial_id;
            row.trial_nr = context.trial_nr;
            row.task = context.task;
            row.phase = string(phase);
            row.video_file = context.video_file;
            row.picture_file = context.picture_file;
            row.condition = context.condition;
            row.flip_seq = obj.FlipStore.Count+1;
            row.phase_flip_seq = phaseSeq;
            row.requested_deadline_getsecs = deadline;
            row.vbl_getsecs = raw.vbl;
            row.stimulus_onset_getsecs = raw.stimulus;
            row.flip_return_getsecs = raw.returned;
            row.missed_s = raw.missed;
            for name = ["frame_ready_getsecs","flip_submit_getsecs","submission_mode", ...
                    "refresh_target_getsecs","refresh_index","refresh_skipped_slots","refresh_error_s"]
                if isfield(raw,name), row.(name) = raw.(name); end
            end
            row.texture_handle = frame.texture_handle;
            row.decoded_frame_sequence = frame.decoded_sequence;
            row.source_frame_index = frame.source_frame_index;
            row.source_pts_s = frame.pts;
            if isfield(frame,'raw_pts')
                row.decoder_pts_s = frame.raw_pts;
                row.pts_origin_offset_s = frame.pts_offset;
            end
            row.frame_status = string(frame.status);
            if isfield(frame,'qc_flags'), row.frame_qc_flags=frame.qc_flags; end
            row.photodiode_state = string(diode);
            obj.FlipStore.append(row);
        end
        function row = event(obj,context,kind,phase,time,flip)
            if nargin < 6 || isempty(flip), flip = struct('flip_seq',NaN); end
            row = ephys.emptyEvent();
            row.trial_id = context.trial_id;
            row.trial_nr = context.trial_nr;
            row.task = context.task;
            row.event_type = string(kind);
            row.phase = string(phase);
            row.video_file = context.video_file;
            row.picture_file = context.picture_file;
            row.condition = context.condition;
            row.onset_getsecs = time;
            row.associated_flip_seq = flip.flip_seq;
            obj.EventStore.append(row);
        end
        function updateLastEvent(obj,row)
            obj.EventStore.replace(obj.EventStore.Count,row);
        end
        function row = lastFlip(obj)
            % Cheap read of the most recent row for use inside refresh loops.
            row = obj.FlipStore.at(obj.FlipStore.Count);
        end
        function row = lastEvent(obj)
            row = obj.EventStore.at(obj.EventStore.Count);
        end
        function values = flipValues(obj,field,first,last)
            % One field of flips first:last as a row vector, without copying rows.
            values = obj.FlipStore.column(field,first,last);
        end
        function rows = flipRange(obj,first,last)
            % Rows first:last; each interval ends at the next logged onset.
            rows = obj.FlipStore.range(first,min(last+1,obj.FlipStore.Count));
            if numel(rows) > 1
                next = [rows(2:end).stimulus_onset_getsecs];
                ends = num2cell(next);
                lengths = num2cell(next-[rows(1:end-1).stimulus_onset_getsecs]);
                [rows(1:end-1).interval_end_getsecs] = ends{:};
                [rows(1:end-1).interval_s] = lengths{:};
            end
            rows = rows(1:max(0,last-first+1));
        end
        function rows = flipRecords(obj)
            rows = obj.flipRange(1,obj.FlipStore.Count);
        end
        function rows = eventRecords(obj)
            rows = obj.EventStore.range(1,obj.EventStore.Count);
        end
        function value = get.FlipCount(obj)
            value = obj.FlipStore.Count;
        end
        function value = get.EventCount(obj)
            value = obj.EventStore.Count;
        end
        function rows = get.Flips(obj)
            rows = obj.flipRecords();
        end
        function rows = get.Events(obj)
            rows = obj.eventRecords();
        end
    end
end
