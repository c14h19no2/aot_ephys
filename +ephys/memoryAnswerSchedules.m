function paths = memoryAnswerSchedules(schedulePath)
%MEMORYANSWERSCHEDULES Video schedules that define a saved memory schedule's answers.
% A saved memory schedule (config/runs/memory_main_complete or memory_main,
% experiment_settings_sub_XX_ses_YY_run_01.yml) tests the pictures of one
% session: a picture is old (Y) when its clip was in that session's video
% runs, config/runs/main/experiment_settings_sub_XX_ses_YY_run_*.yml. Returns
% those paths in run order, or an empty list for any other schedule.
paths = strings(0,1);
[folder,name,ext] = fileparts(string(schedulePath));
[runsFolder,setFolder] = fileparts(folder);
tokens = regexp(name+ext, ...
    '^experiment_settings_sub_(\d+)_ses_(\d+)_run_\d+\.yml$','tokens','once');
if isempty(tokens) || ~any(setFolder == ["memory_main_complete","memory_main"])
    return;
end
found = dir(fullfile(runsFolder,'main', ...
    sprintf('experiment_settings_sub_%s_ses_%s_run_*.yml',tokens{1},tokens{2})));
if isempty(found)
    return;
end
paths = sort(string(fullfile({found.folder},{found.name}))');
end
