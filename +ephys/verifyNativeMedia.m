function results=verifyNativeMedia(sources,playback,progressFcn,checkOriginals)
%VERIFYNATIVEMEDIA Hash originals and native copies against their prepared maps.
% Runs read the maps without hashing video files; this check runs outside a run
% (verify_aot_ephys_media). One table row per source; issues lists every problem
% found, and a computed hash stays empty when its file could not be read.
% checkOriginals=false checks only the copies (no originals on this computer);
% original_sha256 then stays empty.
if nargin<3, progressFcn=[]; end
if nargin<4, checkOriginals=true; end
sources=string(sources); sources=sources(:);
folder=ephys.nativeMediaRoot(playback);
count=numel(sources);
name=strings(count,1); issues=strings(count,1);
original_sha256=strings(count,1); native_sha256=strings(count,1);
map_path=strings(count,1);
for k=1:count
    [~,stem,ext]=fileparts(sources(k));
    name(k)=stem+ext;
    map_path(k)=fullfile(folder,stem+".json");
    nativePath=fullfile(folder,name(k));
    found=strings(1,0);
    recorded=struct();
    if ~isfile(map_path(k))
        found(end+1)="map_missing"; %#ok<AGROW>
    else
        try
            recorded=jsondecode(fileread(map_path(k)));
            % Same structure and PTS checks as a run, without hashing.
            item=struct('name',name(k),'path',sources(k),'kind',"video", ...
                'width_px',NaN,'height_px',NaN,'duration_s',NaN);
            ephys.nativeInventory(item,playback);
        catch cause
            if ~strcmp(cause.identifier,'ephys:NativeMediaMissing')
                found(end+1)="map_invalid"; %#ok<AGROW>
            end
        end
        if ~isstruct(recorded) || ~isscalar(recorded), recorded=struct(); end
    end
    if ~checkOriginals
        % Not checked: the original's state stays unknown.
    elseif ~isfile(sources(k))
        found(end+1)="original_missing"; %#ok<AGROW>
    else
        original_sha256(k)=string(ephys.sha256(sources(k)));
        if isfield(recorded,'source_sha256') && ...
                original_sha256(k)~=string(recorded.source_sha256)
            found(end+1)="original_changed"; %#ok<AGROW>
        end
    end
    if ~isfile(nativePath)
        found(end+1)="native_missing"; %#ok<AGROW>
    else
        native_sha256(k)=string(ephys.sha256(nativePath));
        if isfield(recorded,'sha256') && native_sha256(k)~=string(recorded.sha256)
            found(end+1)="native_changed"; %#ok<AGROW>
        end
    end
    if ~isempty(found), issues(k)=join(found,"|"); end
    if ~isempty(progressFcn), progressFcn(k,count); end
end
ok=issues=="";
results=table(name,ok,issues,original_sha256,native_sha256,map_path);
end
