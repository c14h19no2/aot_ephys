function [summary,points] = triggerOffsetSummary(markers,events,limit)
%TRIGGEROFFSETSUMMARY Summarize observed audio/Flip timestamp differences.
% Keep failed observations so that a synchronization abort cannot hide its
% outlier. A reservation or a dummy marker is not an observed audio onset.
if nargin<1, markers=repmat(ephys.emptyMarker(),0,1); end
if nargin<2, events=repmat(ephys.emptyEvent(),0,1); end
if nargin<3, limit=.002; end
assert(isnumeric(limit) && isscalar(limit) && isreal(limit) && ...
    isfinite(limit) && limit>=0,'ephys:TriggerOffsetLimit', ...
    'The reference synchronization limit must be finite and nonnegative.');

point=struct('marker_nr',NaN,'trial_nr',NaN,'event_type',"", ...
    'trigger_key',"",'time_s',NaN,'delta_ms',NaN,'status',"");
points=repmat(point,0,1);
selected=false(numel(markers),1);
for k=1:numel(markers)
    row=markers(k);
    selected(k)=any(string(row.status)==["complete","failed"]) && ...
        isfinite(row.audio_start_getsecs) && ...
        isfinite(row.associated_flip_getsecs);
end

origin=NaN; originKind="unavailable";
for k=1:numel(markers)
    if string(markers(k).event_type)=="run_start" && ...
            isfinite(markers(k).associated_flip_getsecs)
        origin=markers(k).associated_flip_getsecs;
        originKind="run_start_flip";
        break;
    end
end
if ~isfinite(origin)
    for k=1:numel(events)
        if string(events(k).event_type)=="run_start" && ...
                isfinite(events(k).onset_getsecs)
            origin=events(k).onset_getsecs;
            originKind="run_start_event";
            break;
        end
    end
end
indices=find(selected);
if ~isfinite(origin) && ~isempty(indices)
    origin=markers(indices(1)).associated_flip_getsecs;
    originKind="first_observed_flip";
end

points=repmat(point,numel(indices),1);
delta=NaN(numel(indices),1);
for n=1:numel(indices)
    row=markers(indices(n));
    delta(n)=row.audio_start_getsecs-row.associated_flip_getsecs;
    points(n).marker_nr=row.marker_nr;
    points(n).trial_nr=row.trial_nr;
    points(n).event_type=string(row.event_type);
    points(n).trigger_key=string(row.trigger_key);
    points(n).time_s=row.associated_flip_getsecs-origin;
    points(n).delta_ms=1000*delta(n);
    points(n).status=string(row.status);
end

summary=struct('origin_getsecs',origin,'origin_kind',originKind, ...
    'reference_limit_s',limit,'total_marker_count',numel(markers), ...
    'plotted_marker_count',numel(points), ...
    'excluded_marker_count',numel(markers)-numel(points), ...
    'failed_marker_count',sum(string({points.status})=="failed"), ...
    'outside_reference_count',sum(abs(delta)>limit), ...
    'outside_median_reference_count',0, ...
    'min_s',NaN,'max_s',NaN,'mean_s',NaN,'median_s',NaN, ...
    'stddev_s',NaN,'p95_absolute_s',NaN);
if isempty(delta), return; end
summary.min_s=min(delta);
summary.max_s=max(delta);
summary.mean_s=mean(delta);
summary.median_s=median(delta);
% The trial QC rule: a constant offset is accepted, spread around it is not.
summary.outside_median_reference_count=sum(abs(delta-summary.median_s)>limit);
if numel(delta)>1, summary.stddev_s=std(delta); end
values=sort(abs(delta));
position=1+.95*(numel(values)-1);
low=floor(position); high=ceil(position);
summary.p95_absolute_s=values(low)+ ...
    (position-low)*(values(high)-values(low));
end
