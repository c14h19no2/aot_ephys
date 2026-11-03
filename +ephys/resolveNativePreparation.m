function request=resolveNativePreparation(varargin)
%RESOLVENATIVEPREPARATION Select all source MP4s, the practice clips, or one saved schedule.
% Shared by prepare_aot_ephys_native_media and verify_aot_ephys_media.
% Without subject/session/run: every MP4 in paths.video_root, or with
% 'Task','practice' the clips of the shared practice schedule in
% paths.practice_video_root, whose copies go to playback.practice_native_media_root.
% With subject, session and run: that schedule's videos ('Task','practice'
% also works there). For a schedule, video_root may be empty: verification
% then checks the native copies only, and preparation stops.
root=ephys.projectRoot();
% A text first argument is a subject label when a session number follows it.
if nargin==0 || ((ischar(varargin{1}) || isstring(varargin{1})) && ...
        (nargin<2 || ~isnumeric(varargin{2})))
    parser=inputParser;
    addParameter(parser,'Site',"", ...
        @(x) ischar(x) || (isstring(x) && isscalar(x)));
    addParameter(parser,'Task',"video",@(x) ischar(x) || (isstring(x) && isscalar(x)));
    parse(parser,varargin{:});
    task=string(parser.Results.Task);
    assert(any(task==["video","practice"]),'ephys:NativePreparationTask', ...
        'Native media preparation and verification accept the video and practice tasks only.');
    [sitePath,selectionPath]=ephys.resolveSitePath(parser.Results.Site);
    parserDir=fullfile(root,'third_party','yaml');
    if ~contains(path,parserDir), addpath(parserDir); end
    schema=ephys.readYaml(fullfile(root,'config','experiment.yml'));
    site=ephys.readYaml(sitePath);
    ephys.checkSchema(site,schema);
    c=ephys.mergeConfig(schema,site);
    % Offline preparation needs media paths, independent of acquisition setup.
    if task=="practice"
        % Practice copies have their own folder, apart from the main copies.
        ephys.nativeMediaRoot(c.playback,'practice_native_media_root');
        c.playback.native_media_root=c.playback.practice_native_media_root;
    else
        ephys.nativeMediaRoot(c.playback);
    end
    field='video_root';
    if task=="practice", field='practice_video_root'; end
    videoRoot="";
    if ~isempty(c.paths.(field))
        assert(ischar(c.paths.(field)) || isstring(c.paths.(field)), ...
            'ephys:VideoRoot','Set paths.%s to the original video directory in the site YAML.',field);
        videoRoot=strtrim(string(c.paths.(field)));
    end
    if task=="practice"
        % The schedule lists the clips, so verifying copies needs no
        % originals; preparation checks for them itself.
        schedule=ephys.readYaml(fullfile(root,'config','runs','practice','practice_videos.yml'));
        names=ephys.validateSchedule(schedule.stimuli.movie_files);
        names=unique(names(names~="blank"),'stable');
        mode="practice schedule";
    else
        % Listing every MP4 needs the original folder.
        assert(isscalar(videoRoot) && ~ismissing(videoRoot) && ...
            strlength(videoRoot)>0 && isfolder(videoRoot), ...
            'ephys:VideoRoot','Original video directory is missing: %s. Set paths.%s in the site YAML.', ...
            videoRoot,field);
        entries=dir(videoRoot); entries=entries(~[entries.isdir]);
        names=sort(string({entries.name})');
        % Skip hidden files such as macOS "._name.mp4" sidecars from copied folders.
        names=names(endsWith(lower(names),'.mp4') & ~startsWith(names,"."));
        assert(~isempty(names),'ephys:NativePreparationNoVideos', ...
            'No MP4 files found in paths.video_root: %s.',videoRoot);
        mode="all videos";
    end
    sources=fullfile(videoRoot,names);
else
    assert(nargin>=3,'ephys:NativePreparationArguments', ...
        'Call it without arguments for all videos, or supply subject, session and run.');
    run=ephys.resolveRunRequest(varargin{:});
    assert(any(run.task==["video","practice"]),'ephys:NativePreparationTask', ...
        'Native media preparation and verification accept the video and practice tasks only.');
    [c,~]=ephys.loadConfig(run.task,run.schedule_path,run.site_path, ...
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
