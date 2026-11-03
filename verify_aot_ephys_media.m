function varargout=verify_aot_ephys_media(varargin)
%VERIFY_AOT_EPHYS_MEDIA Check originals and native copies against their maps.
% Runs do not hash video files. Run this after preparing or copying media, or
% before a session, to confirm each file still matches the SHA-256 values that
% preparation recorded in its native map. It reads every file once.
% verify_aot_ephys_media() checks every MP4 in paths.video_root of the active site.
% verify_aot_ephys_media('Site',sitePath) checks every MP4 for that site.
% verify_aot_ephys_media(sub,ses,run,...) checks the videos of one saved schedule.
% verify_aot_ephys_media('Task','practice') checks the practice clips.
% results=verify_aot_ephys_media(...) also returns one table row per video.
request=ephys.resolveNativePreparation(varargin{:});
count=numel(request.sources);
fprintf('Verifying %d videos (%s) against their native maps...\n',count,request.mode);
began=tic;
step=max(1,round(count/10));
results=ephys.verifyNativeMedia(request.sources,request.playback, ...
    @(k,n) showProgress(k,n,step,began));
problems=results(~results.ok,:);
if isempty(problems)
    fprintf('All %d videos match their native maps (%.0f s).\n',count,toc(began));
else
    for k=1:height(problems)
        fprintf('  %s: %s\n',problems.name(k),strrep(problems.issues(k),"|",", "));
    end
    warning('ephys:MediaVerification', ...
        ['%d of %d videos do not match their native maps. Copy them again, ' ...
        'or re-run prepare_aot_ephys_native_media.'],height(problems),count);
end
if nargout>0, varargout{1}=results; end
end

function showProgress(k,count,step,began)
if k==count || mod(k,step)==0
    fprintf('  %d / %d checked (%.0f s)\n',k,count,toc(began));
end
end
