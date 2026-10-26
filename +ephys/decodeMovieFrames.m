function [map,rawPath] = decodeMovieFrames(path,playback,folder,expectedHash)
%DECODEMOVIEFRAMES Decode the entire source from its start, without seeks.
assert(string(ephys.sha256(path))==string(expectedHash),'ephys:MediaChanged', ...
    'Source movie changed since preflight: %s',path);
rawPath=fullfile(folder,'frames.rgb');
args={playback.ffmpeg_path,'-nostdin','-hide_banner','-loglevel','info','-xerror', ...
    '-y','-copyts','-noautorotate','-i',char(path),'-map','0:v:0', ...
    '-an','-sn','-dn','-vf','format=rgb24,showinfo', ...
    '-fps_mode','passthrough','-c:v','rawvideo','-threads:v','1', ...
    '-f','rawvideo',rawPath};
logText=ephys.runMediaProcess(args);
file=dir(rawPath);
assert(~isempty(file),'ephys:FrameMap','No decoded RGB output.');
map=ephys.parseDecodedFrames(logText,file.bytes);
assert(string(ephys.sha256(path))==string(expectedHash),'ephys:MediaChanged', ...
    'Source movie changed during decode: %s',path);
map.source_file=char(path);
map.source_sha256=char(expectedHash);
map.rgb_stream_sha256=ephys.sha256(rawPath);
map.ffmpeg_version=strtrim(ephys.runMediaProcess({playback.ffmpeg_path,'-version'}));
map.decode_arguments=args(2:end-1); % Temporary raw output path is not provenance.
map.mapping_method='Same-pass FFmpeg display-order RGB frames and showinfo integer PTS; no seek, trim, frame-rate conversion or scaling';
end
