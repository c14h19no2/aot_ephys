function preview = previewRunRequest(subject,sessionNumber,runNumber,varargin)
%PREVIEWRUNREQUEST Output folder and schedule that run_aot_ephys would use.
% Takes run_aot_ephys's arguments and changes nothing. Invalid requests are
% reported in preview.error instead of thrown, so a dialog can show them.
% ok is true when the request is valid and its output folder is free today,
% or Overwrite is set. viewing is ephys.viewingDistance for the selected site;
% invalid screen or target sizes give status "invalid" and do not affect ok.
preview = struct('ok',false,'error',"",'run_id',"",'subject',"", ...
    'schedule_set',[],'schedule_set_source',"",'schedule_path',"", ...
    'collection_date',"",'output_folder',"",'exists',false, ...
    'other_dates',strings(0,1),'viewing',ephys.viewingDistance(struct()));
try
    request = ephys.resolveRunRequest(subject,sessionNumber,runNumber,varargin{:});
    [root,config] = outputRoot(request);
catch cause
    preview.error = string(cause.message);
    return;
end
try
    preview.viewing = ephys.viewingDistance(config);
catch cause
    preview.viewing.status = "invalid";
    preview.viewing.message = string(cause.message);
end
preview.run_id = request.run_id;
preview.subject = request.identity.subject;
preview.schedule_set = request.identity.schedule_set;
preview.schedule_set_source = request.identity.schedule_set_source;
preview.schedule_path = request.schedule_path;
preview.collection_date = request.collection_date;
preview.output_folder = string(fullfile(root,request.collection_date,request.run_id));
preview.exists = isfolder(preview.output_folder) || isfile(preview.output_folder);
preview.other_dates = otherDates(root,request.collection_date,request.run_id);
preview.ok = ~preview.exists || request.options.Overwrite;
end

function [root,config] = outputRoot(request)
% Same precedence as ephys.loadConfig: experiment.yml, site, then debug.
projectRoot = ephys.projectRoot();
schema = ephys.readYaml(fullfile(projectRoot,'config','experiment.yml'));
config = schema;
if strlength(request.site_path)>0
    site = ephys.readYaml(request.site_path);
    ephys.checkSchema(site,schema);
    config = ephys.mergeConfig(config,site);
end
if request.options.Debug
    debugOverride = ephys.readYaml(fullfile(projectRoot,'config','debug.yml'));
    config = ephys.mergeConfig(config,debugOverride);
    if strlength(string(config.paths.output_root))==0
        config.paths.output_root = fullfile(projectRoot,'outputs','ephys_debug');
    end
end
root = string(config.paths.output_root);
assert(strlength(root)>0,'ephys:OutputRoot', ...
    'Set paths.output_root in the site YAML %s.',request.site_path);
end

function dates = otherDates(root,today,runId)
% Earlier collection dates that already hold this run ID.
dates = strings(0,1);
if ~isfolder(root), return; end
entries = dir(root);
names = string({entries([entries.isdir]).name});
datePattern = digitsPattern(4)+"-"+digitsPattern(2)+"-"+digitsPattern(2);
names = names(matches(names,datePattern) & names~=today);
for name = names
    if isfolder(fullfile(root,name,runId)), dates(end+1,1) = name; end %#ok<AGROW>
end
end
