function output = runMediaProcess(arguments)
%RUNMEDIAPROCESS Execute argument vectors without shell interpretation.
folder = tempname; mkdir(folder);
guard = onCleanup(@() rmdir(folder,'s')); %#ok<NASGU>
args = java.util.ArrayList();
for k=1:numel(arguments), args.add(java.lang.String(char(arguments{k}))); end
builder = java.lang.ProcessBuilder(args);
builder.redirectErrorStream(true);
logPath = fullfile(folder,'process.log');
builder.redirectOutput(java.io.File(logPath));
process = builder.start();
processGuard = onCleanup(@() process.destroy()); %#ok<NASGU>
unit = javaMethod('valueOf','java.util.concurrent.TimeUnit','SECONDS');
finished = process.waitFor(int64(120),unit);
if ~finished
    process.destroyForcibly();
    error('ephys:MediaTimeout','Media process exceeded 120 seconds: %s',arguments{1});
end
output = fileread(logPath);
assert(process.exitValue()==0,'ephys:MediaProcess', ...
    'Media process failed (%s): %s',arguments{1},output);
end
