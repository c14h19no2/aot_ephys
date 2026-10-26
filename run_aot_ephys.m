function [outputDir,status] = run_aot_ephys(subject,sessionNumber,runNumber,varargin)
%RUN_AOT_EPHYS Run scanner-free AOT with named WAV triggers and timing logs.
% Default Site comes from config/active_site.yml; explicit Site overrides it.
% out = run_aot_ephys() asks for subject, session, run, task and Overwrite.
% out = run_aot_ephys(sub,ses,run[,recordingNumber],'Name',value,...)
% Example: run_aot_ephys(1,1,8,2) repeats run 8 into a record-02 folder.
% Output: <paths.output_root>/<yyyy-mm-dd>/sub-001_ses-01_run-08_task-video...
% status is "complete", "aborted" (Q pressed; no error is raised) or
% "cancelled" (dialog closed). Other failures raise an error after saving.
if nargin==0
    choice = ephys.runRequestDialog();
    outputDir = "";
    status = "cancelled";
    if isempty(choice)
        fprintf('Run cancelled before start.\n');
        return;
    end
    [outputDir,status] = run_aot_ephys(choice.subject,choice.session,choice.run, ...
        'Task',choice.task,'Overwrite',choice.overwrite);
    return;
end
request = ephys.resolveRunRequest(subject,sessionNumber,runNumber,varargin{:});
p = request.options;
task = request.task;
schedulePath = request.schedule_path;
[config,provenance] = ephys.loadConfig(task,schedulePath, ...
    request.site_path,p.Debug,p.Answers,request.site_selection_path);
config.run_identity = request.identity;
config.run_output = struct('collection_date',request.collection_date, ...
    'overwrite',p.Overwrite,'replaced_output',"");
if task == "memory"
    if contains(schedulePath,"memory_main_complete")
        config.task.memory_variant = "main_memory_mainexp_complete";
    elseif contains(schedulePath,"memory_main")
        config.task.memory_variant = "archived_memory_main";
    else
        config.task.memory_variant = "explicit_custom_schedule";
    end
end
config.debug_simulated_input_only = p.DebugSimulatedInputOnly;
if p.DebugSkipSyncTests
    config.display.skip_sync_tests = true;
    warning('ephys:DebugSyncOverride', ...
        'PTB synchronization checks are disabled for this debug run.');
end
if p.DebugSimulatedInputOnly
    warning('ephys:DebugSimulatedInput', ...
        'Keyboard input is simulated for this debug run.');
end
ephys.validateConfig(config);
ephys.assertSessionImplementation();
job = ephys.Session(config,provenance,request.run_id,p.Backend);
guard = onCleanup(@() job.close()); %#ok<NASGU>
[outputDir,status] = ephys.runSession(job);
end
