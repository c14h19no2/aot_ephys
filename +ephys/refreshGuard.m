function value = refreshGuard(flips,phase,duration,ifi,minimumFraction)
%REFRESHGUARD Fraction of a static phase's fixed-grid refresh slots presented.
% flips are Flip rows, or the number of presented grid slots when only the
% decision is needed: the live check passes that count so trial 1 keeps its
% refresh, and writeOutput adds the interval metrics after presentation.
% Slot n>=1 is available when its target leaves half an IFI before the phase
% end, as in nextFixationRefresh. Phases offering less than one second of
% slots are recorded but not evaluated; an empty minimumFraction disables the
% decision. With no arguments, returns the record for an unobserved phase.
value = struct('status',"not_run",'phase',"",'duration_s',NaN, ...
    'ifi_s',NaN,'min_fraction',NaN,'first_flip_seq',NaN,'last_flip_seq',NaN, ...
    'available_slots',NaN,'presented_slots',NaN,'presented_fraction',NaN, ...
    'max_skipped_slots',NaN,'interval_median_ms',NaN, ...
    'timestamp_grid_deviation_median_ifi',NaN,'detail',"",'message',"");
if nargin==0, return; end
value.phase = string(phase);
value.duration_s = duration;
value.ifi_s = ifi;
if ~isempty(minimumFraction), value.min_fraction = minimumFraction; end
label = strrep(value.phase,"_"," ");
if isnumeric(flips)
    value.presented_slots = flips;
else
    rows = flips;
    if ~isempty(rows), rows = rows(string({rows.phase})==value.phase); end
    if isempty(rows)
        value.detail = "No "+label+" refreshes were observed.";
        return;
    end
    [~,order] = sort([rows.flip_seq]);
    rows = rows(order);
    grid = rows(isfinite([rows.refresh_index]));
    times = [rows.stimulus_onset_getsecs];
    steps = diff(times)/ifi;
    value.first_flip_seq = rows(1).flip_seq;
    value.last_flip_seq = rows(end).flip_seq;
    value.presented_slots = numel(grid);
    value.max_skipped_slots = max([0 grid.refresh_skipped_slots]);
    value.interval_median_ms = 1000*median(diff(times));
    % Informational: distance of observed intervals from whole refresh multiples.
    value.timestamp_grid_deviation_median_ifi = median(abs(steps-round(steps)));
end
if ~(isfinite(duration) && isfinite(ifi) && ifi>0)
    value.status = "not_evaluated";
    value.detail = "No finite "+label+" duration or refresh interval.";
    return;
end
value.available_slots = max(0,ceil(duration/ifi-.5-1e-9)-1);
value.presented_fraction = value.presented_slots/value.available_slots;
summary = string(sprintf('%d of %d refresh slots (%.1f%%) were presented during the %s', ...
    value.presented_slots,value.available_slots,100*value.presented_fraction,label));
if isfinite(value.interval_median_ms)
    summary = summary+sprintf('; median refresh interval %.1f ms',value.interval_median_ms);
end
if isempty(minimumFraction)
    value.status = "disabled";
    value.detail = summary+"; refresh guard disabled.";
elseif value.available_slots<round(1/ifi)
    value.status = "not_evaluated";
    value.detail = summary+"; shorter than one second, not evaluated.";
elseif value.presented_fraction>=minimumFraction
    value.status = "passed";
    value.detail = summary+sprintf('; minimum %.0f%%.',100*minimumFraction);
else
    value.status = "failed";
    value.detail = summary+sprintf('; minimum %.0f%%.',100*minimumFraction);
    value.message = "Refresh guard: "+value.detail+" The display loop cannot sustain "+ ...
        "the refresh rate, so the run stopped before the first trial. Check the "+ ...
        "display mode, screen sharing or remote-control software, other running "+ ...
        "programs and power settings, then start a new recording.";
end
end
