function initialize(obj,config,provenance,runId,backend)
%INITIALIZE Resolve media, allocate logs, and create the output folder before opening PTB.
    if config.task_kind == "video" && string(config.playback.backend) == "frames" && ...
            any(config.schedule ~= "blank")
        config.playback = ephys.resolveVideoTools(config.playback);
    end
    obj.Config = config;
    obj.Provenance = provenance;
    obj.RunId = string(runId);
    obj.RunContext = ephys.context(config.task_kind,0,"");
    obj.TrialContexts = arrayfun(@(nr) ephys.context(config.task_kind,nr, ...
        config.schedule(nr)),1:numel(config.schedule),'UniformOutput',false);
    obj.Inventory = ephys.mediaInventory(config);
    [maxFlips,maxEvents,maxMarkers] = ephys.logCapacity(config);
    obj.Log = ephys.TimelineLog(maxFlips,maxEvents);
    % Load the refresh-guard decision path before any device opens.
    ephys.refreshGuard(0,"initial_fixation",1,1/60,1);
    obj.RefreshGuard = ephys.refreshGuard();
    if isempty(backend)
        selected = string(config.markers.backend);
        if config.task_kind == "memory"
            selected = string(config.markers.memory_backend);
        end
        if selected == "wav"
            backend = ephys.WavTriggerBackend();
        else
            backend = ephys.DummyTriggerBackend();
        end
    end
    obj.Triggers = ephys.TriggerOutput(config.markers,backend,maxMarkers);
    obj.Eye = ephys.EyeLinkAdapter(config);
    % The answer key is built here, before the display opens.
    obj.Answers = containers.Map('KeyType','char','ValueType','char');
    if config.task_kind == "memory" && strlength(config.answer_path) > 0
        obj.Answers = ephys.loadAnswers(config.answer_path,config.schedule);
    elseif config.task_kind == "memory" && isfield(config,'answer_schedules') && ...
            ~isempty(config.answer_schedules)
        obj.Answers = ephys.memoryAnswerKey(config.answer_schedules,config.schedule);
    end
    if isfield(config,'run_output')
        % Acquisition runs are grouped by collection date.
        [obj.OutputDir,replaced] = ephys.prepareOutputFolder(config.paths.output_root, ...
            config.run_output.collection_date,runId,config.run_output.overwrite);
        obj.Config.run_output.replaced_output = replaced;
    else
        obj.OutputDir = ephys.prepareOutputFolder(config.paths.output_root,"",runId,false);
    end
    if config.task_kind == "video" && string(config.playback.backend) == "native"
        mapDir = fullfile(obj.OutputDir,'frame_maps');
        mkdir(mapDir);
        for k = 1:numel(obj.Inventory)
            [~,stem] = fileparts(obj.Inventory(k).name);
            destination = fullfile(mapDir,stem+".json");
            fid = fopen(destination,'w');
            assert(fid >= 0,'ephys:FrameMap','Cannot save native provenance.');
            mapGuard = onCleanup(@() fclose(fid));
            fprintf(fid,'%s\n',jsonencode(obj.Inventory(k).native_map,'PrettyPrint',true));
            clear mapGuard
        end
    end
end
