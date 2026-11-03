function folder=prepare_aot_ephys_native_media(varargin)
%PREPARE_AOT_EPHYS_NATIVE_MEDIA Verify lossless native PTB copies; reuse valid cache.
% prepare_aot_ephys_native_media() prepares all MP4 files in paths.video_root.
% The default Site is selected in config/active_site.yml.
% prepare_aot_ephys_native_media('Site',sitePath) prepares all files for that site.
% prepare_aot_ephys_native_media(sub,ses,run,...) prepares a saved schedule only.
% prepare_aot_ephys_native_media('Task','practice') prepares the practice clips.
request=ephys.resolveNativePreparation(varargin{:});
playback=ephys.resolveVideoTools(request.playback);
folder=ephys.nativeMediaRoot(playback);
temporary=tempname; mkdir(temporary);
guard=onCleanup(@() rmdir(temporary,'s')); %#ok<NASGU>
sources=request.sources;
sourceFile=fullfile(temporary,'sources.json');
fid=fopen(sourceFile,'w'); fprintf(fid,'%s',jsonencode(cellstr(sources))); fclose(fid);
python=char(playback.python_path);
if isempty(python), python='python3'; end
args={python,fullfile(ephys.projectRoot(),'tools','prepare_native_media.py'), ...
    '--sources',sourceFile,'--out',char(folder), ...
    '--ffmpeg',char(playback.ffmpeg_path),'--ffprobe',char(playback.ffprobe_path)};
list=java.util.ArrayList();
for k=1:numel(args), list.add(java.lang.String(args{k})); end
builder=java.lang.ProcessBuilder(list);
builder.redirectErrorStream(true);
logFile=fullfile(temporary,'preparation.log');
builder.redirectOutput(java.io.File(logFile));
process=builder.start();
processGuard=onCleanup(@() process.destroy()); %#ok<NASGU>
unit=javaMethod('valueOf','java.util.concurrent.TimeUnit','MILLISECONDS');
printed=0;
fprintf('Preparing %d videos (%s) outside experiment timing...\n', ...
    numel(sources),request.mode);
while ~process.waitFor(int64(250),unit)
    printed=showProgress(logFile,printed);
end
showProgress(logFile,printed);
assert(process.exitValue()==0,'ephys:NativePreparation','Native media preparation failed.');
fprintf('Ready: %s\n',folder);
end
function count=showProgress(path,count)
if ~isfile(path), return; end
value=fileread(path);
if numel(value)>count, fprintf('%s',value(count+1:end)); end
count=numel(value);
end
