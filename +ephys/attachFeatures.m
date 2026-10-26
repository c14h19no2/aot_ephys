function intervals = attachFeatures(videoFlips,featureMap,inventory,ptsToleranceS)
%ATTACHFEATURES Join validated video/PTS features to actual flip intervals.
% A map must have been validated against exact media bytes and PTS values.
if nargin < 4, ptsToleranceS = 1e-6; end
if istable(videoFlips), videoFlips = table2struct(videoFlips); end
if istable(featureMap), featureMap = table2struct(featureMap); end
if istable(inventory), inventory = table2struct(inventory); end
assert(all(isfield(featureMap,{'video_file','media_sha256','pts_s', ...
    'feature_value','validated'})), 'ephys:FeatureMap', ...
    'Feature map must identify validated media hash and source PTS.');
assert(all([featureMap.validated]),'ephys:FeatureUnvalidated', ...
    'Feature-to-PTS mapping must be independently validated.');
intervals = repmat(struct('trial_id',"",'video_file',"", ...
    'flip_seq',NaN,'source_pts_s',NaN,'interval_start_getsecs',NaN, ...
    'interval_end_getsecs',NaN,'feature_value',NaN),numel(videoFlips),1);
for i = 1:numel(videoFlips)
    f = videoFlips(i);
    assert(string(f.phase)=="video" && ...
        isfinite(f.source_pts_s) && isfinite(f.interval_end_getsecs), ...
        'ephys:FeatureInterval','Video flip needs PTS and a closing flip.');
    media = inventory(string({inventory.name})==string(f.video_file));
    assert(numel(media)==1,'ephys:FeatureMedia', ...
        'Exact video metadata are unavailable.');
    matches = find(string({featureMap.video_file})==string(f.video_file) & ...
        string({featureMap.media_sha256})==string(media.sha256) & ...
        abs([featureMap.pts_s]-f.source_pts_s)<=ptsToleranceS);
    assert(isscalar(matches),'ephys:FeatureAmbiguous', ...
        'PTS/media join is missing or ambiguous for flip %d.',f.flip_seq);
    intervals(i).trial_id = string(f.trial_id);
    intervals(i).video_file = string(f.video_file);
    intervals(i).flip_seq = f.flip_seq;
    intervals(i).source_pts_s = f.source_pts_s;
    intervals(i).interval_start_getsecs = f.stimulus_onset_getsecs;
    intervals(i).interval_end_getsecs = f.interval_end_getsecs;
    intervals(i).feature_value = featureMap(matches).feature_value;
end
end
