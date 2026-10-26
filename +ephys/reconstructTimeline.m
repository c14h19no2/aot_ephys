function result = reconstructTimeline(outputDir,verifiedTTL)
%RECONSTRUCTTIMELINE Read run logs and derive observed visual intervals.
% verifiedTTL, if supplied, must contain independently verified event_id.
if nargin < 2, verifiedTTL = []; end
folder = string(outputDir);
files = dir(fullfile(folder,'*_manifest.json'));
assert(numel(files)==1,'ephys:RunFiles','Expected one manifest in run folder.');
manifest = jsondecode(fileread(fullfile(folder,files(1).name)));
stem = char(manifest.run_id);
flips = ephys.readTimelineRows(fullfile(folder,[stem '_flips.tsv']),ephys.emptyFlip());
events = ephys.readTimelineRows(fullfile(folder,[stem '_events.tsv']),ephys.emptyEvent());
markers = ephys.readTimelineRows(fullfile(folder,[stem '_markers.tsv']),ephys.emptyMarker());
config = jsondecode(fileread(fullfile(folder,[stem '_resolved_config.json'])));
if isfield(manifest,'display_timing')
    config.display_timing = manifest.display_timing;
end
for field=["native_trials","native_pending_trials"]
    if isfield(manifest,field), config.(field)=manifest.(field); end
end
result = ephys.reconstructRecords(flips,events,markers, ...
    manifest.media,config,verifiedTTL);
result.manifest = manifest;
end
