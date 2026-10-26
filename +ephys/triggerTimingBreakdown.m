function rows = triggerTimingBreakdown(markers)
%TRIGGERTIMINGBREAKDOWN Separate audio scheduling from visual prediction errors.
% All values are software/driver estimates. Missing observations stay NaN;
% failed and cancelled reservations remain visible instead of being omitted.
fields = {'marker_nr','trial_nr','event_type','trigger_key','status', ...
    'output_channel','request_getsecs','write_getsecs', ...
    'planned_audio_getsecs','predicted_visual_getsecs', ...
    'audio_start_getsecs','associated_flip_getsecs'};
if isempty(markers)
    markers = repmat(ephys.emptyMarker(),0,1);
end
rows = struct2table(markers(:));
% Historical logs have no prepared-frame/submission observations.
for name=["frame_ready_getsecs","flip_submit_getsecs","flip_return_getsecs"]
    if ~ismember(name,string(rows.Properties.VariableNames))
        rows.(name)=nan(height(rows),1);
    end
end
if ~ismember('submission_mode',rows.Properties.VariableNames)
    rows.submission_mode=strings(height(rows),1);
end
fields=[fields,{'frame_ready_getsecs','flip_submit_getsecs', ...
    'flip_return_getsecs','submission_mode'}];
rows = rows(:,fields);
rows.reservation_lead_ms = 1000*(rows.planned_audio_getsecs-rows.write_getsecs);
rows.audio_from_write_ms = 1000*(rows.audio_start_getsecs-rows.write_getsecs);
rows.audio_schedule_error_ms = 1000*(rows.audio_start_getsecs-rows.planned_audio_getsecs);
rows.visual_prediction_error_ms = 1000*(rows.associated_flip_getsecs-rows.predicted_visual_getsecs);
rows.audio_visual_delta_ms = 1000*(rows.audio_start_getsecs-rows.associated_flip_getsecs);
rows.target_difference_ms = 1000*(rows.planned_audio_getsecs-rows.predicted_visual_getsecs);
rows.draw_to_request_ms = 1000*(rows.request_getsecs-rows.frame_ready_getsecs);
rows.submission_gap_ms = 1000*(rows.flip_submit_getsecs-rows.write_getsecs);
rows.flip_call_lead_ms = 1000*(rows.predicted_visual_getsecs-rows.flip_submit_getsecs);
rows.flip_block_ms = 1000*(rows.flip_return_getsecs-rows.flip_submit_getsecs);
end
