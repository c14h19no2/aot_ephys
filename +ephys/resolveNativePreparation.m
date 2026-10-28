function request=resolveNativePreparation(varargin)
%RESOLVENATIVEPREPARATION Select all source MP4s or one saved video schedule.
% Shared by prepare_aot_ephys_native_media and verify_aot_ephys_media.
root=ephys.projectRoot();
% A text first argument is a subject label when a session number follows it.
if nargin==0 || ((ischar(varargin{1}) || isstring(varargin{1})) && ...
        (nargin<2 || ~isnumeric(varargin{2})))
    parser=inputParser;
    addParameter(parser,'Site',"", ...
        @(x) ischar(x) || (isstring(x) && isscalar(x)));
    parse(parser,varargin{:});
    [sitePath,selectionPath]=ephys.resolveSitePath(parser.Results.Site);
    parserDir=fullfile(root,'third_party','yaml');
    if ~contains(path,parserDir), addpath(parserDir); end
    schema=ephys.readYaml(fullfile(root,'config','experiment.yml'));
    site=ephys.readYaml(sitePath);
    ephys.checkSchema(site,schema);
    c=ephys.mergeConfig(schema,site);
    % Offline preparation needs media paths, independent of acquisition setup.
    ephys.nativeMediaRoot(c.playback);
    assert(ischar(c.paths.video_root) || isstring(c.paths.video_root), ...
        'ephys:VideoRoot','Set paths.video_root to the original video directory in the site YAML.');
    videoRoot=strtrim(string(c.paths.video_root));
    assert(isscalar(videoRoot) && ~ismissing(videoRoot) && ...
        strlength(videoRoot)>0 && isfolder(videoRoot), ...
        'ephys:VideoRoot','Original video directory is missing: %s. Set paths.video_root in the site YAML.',videoRoot);
    entries=dir(videoRoot); entries=entries(~[entries.isdir]);
    names=sort(string({entries.name})');
    % Skip hidden files such as macOS "._name.mp4" sidecars from copied folders.
    names=names(endsWith(lower(names),'.mp4') & ~startsWith(names,"."));
    assert(~isempty(names),'ephys:NativePreparationNoVideos', ...
        'No MP4 files found in paths.video_root: %s.',videoRoot);
    sources=fullfile(videoRoot,names);
    mode="all videos";
else
    assert(nargin>=3,'ephys:NativePreparationArguments', ...
        'Call it without arguments for all videos, or supply subject, session and run.');
    run=ephys.resolveRunRequest(varargin{:});
    assert(run.task=="video",'ephys:NativePreparationTask', ...
        'Native media preparation and verification accept the video task only.');
    [c,~]=ephys.loadConfig("video",run.schedule_path,run.site_path, ...
        run.options.Debug,"",run.site_selection_path);
    sitePath=run.site_path;
    selectionPath=run.site_selection_path;
    videoRoot=string(c.paths.video_root);
    sources=fullfile(videoRoot,unique(c.schedule(c.schedule~="blank"),'stable'));
    mode="saved schedule";
end
request=struct('sources',sources,'playback',c.playback,'mode',mode, ...
    'video_root',videoRoot,'site_path',sitePath,'site_selection_path',selectionPath);
end
