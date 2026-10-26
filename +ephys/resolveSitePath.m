function [sitePath,selectionPath] = resolveSitePath(siteOverride,selectionPath)
%RESOLVESITEPATH Use an explicit Site or read config/active_site.yml.
% Relative selected paths are based on the selection file, never MATLAB's cwd.
% selectionPath optionally selects another YAML, default config/active_site.yml.
% Explicit Site paths retain their existing cwd-relative/absolute semantics.
if nargin < 1
    siteOverride = "";
end
assert(validText(siteOverride),'ephys:SiteSelection','Site must be a scalar path.');
sitePath = string(siteOverride);
if strlength(strtrim(sitePath)) > 0
    selectionPath = "";
    return;
end
root = ephys.projectRoot();
if nargin < 2
    selectionPath = fullfile(root,'config','active_site.yml');
end
selectionPath = string(selectionPath);
assert(validText(selectionPath) && isfile(selectionPath), ...
    'ephys:SiteSelectionMissing', ...
    'Missing site selection YAML: %s. Set site_file or pass an explicit Site.',selectionPath);
parserDir = fullfile(root,'third_party','yaml');
if ~contains(path,parserDir)
    addpath(parserDir);
end
selection = ephys.readYaml(selectionPath);
assert(isequal(fieldnames(selection),{'site_file'}) && validText(selection.site_file), ...
    'ephys:SiteSelection', ...
    'Set exactly one field, site_file, to a site YAML path in %s.',selectionPath);
sitePath = strtrim(string(selection.site_file));
assert(strlength(sitePath) > 0 && ~any(lower(sitePath) == ["none","null","~"]), ...
    'ephys:SiteSelection', ...
    'site_file must name a site YAML in %s; empty, null and none are invalid.',selectionPath);
absolute = startsWith(sitePath,filesep) || ...
    (ispc && ~isempty(regexp(char(sitePath),'^[A-Za-z]:[\\/]','once')));
if ~absolute
    sitePath = fullfile(fileparts(selectionPath),sitePath);
end
assert(isfile(sitePath),'ephys:SelectedSiteMissing', ...
    'Selected site YAML does not exist: %s. Update site_file in %s.',sitePath,selectionPath);
end

function valid = validText(value)
valid = (ischar(value) && (isrow(value) || isempty(value))) || ...
    (isstring(value) && isscalar(value) && ~ismissing(value));
end
