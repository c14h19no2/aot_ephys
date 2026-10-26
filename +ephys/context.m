function value = context(task,trialNr,name)
%CONTEXT Stable trial identity shared by flip, event, and marker tables.
name = string(name);
value = struct('trial_id',string(char(java.util.UUID.randomUUID())), ...
    'trial_nr',trialNr,'task',string(task),'video_file',"", ...
    'picture_file',"",'condition',ephys.condition(name));
if value.task == "video", value.video_file = name; end
if value.task == "memory", value.picture_file = name; end
end
