function sites = siteChoices(configDir)
%SITECHOICES Site files in config/ and the one selected in active_site.yml.
% names are the file names without "site." and the extension, files the file
% names and paths the full paths. active is the index of the selected site, or
% 0 when active_site.yml is missing or invalid (activeError gives the reason).
% A selected site outside configDir is added at the end. site.example.yml is
% the template, not a site.
if nargin<1, configDir = fullfile(ephys.projectRoot(),'config'); end
configDir = string(configDir);
entries = [dir(fullfile(configDir,'site.*.yml')); dir(fullfile(configDir,'site.*.yaml'))];
files = sort(string({entries(~[entries.isdir]).name}))';
files = files(~ismember(lower(files),["site.example.yml","site.example.yaml"]));
paths = strings(0,1);
if ~isempty(files), paths = fullfile(configDir,files); end
names = regexprep(files,'^site\.|\.ya?ml$','');
active = 0;
activeError = "";
try
    activePath = ephys.resolveSitePath("",fullfile(configDir,'active_site.yml'));
    active = find(ephys.samePath(paths,activePath),1);
    if isempty(active)
        [~,stem,ext] = fileparts(activePath);
        files(end+1,1) = stem+ext;
        names(end+1,1) = stem+ext;
        paths(end+1,1) = activePath;
        active = numel(paths);
    end
catch cause
    active = 0;
    activeError = string(cause.message);
end
sites = struct('names',names,'files',files,'paths',paths, ...
    'active',active,'activeError',activeError);
end
