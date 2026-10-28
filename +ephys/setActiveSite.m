function changed = setActiveSite(sitePath,configDir)
%SETACTIVESITE Point config/active_site.yml at sitePath, keeping its comments.
% A site in configDir is written by file name, any other by its full path.
% The selection file is created when missing. changed is false when it already
% selected sitePath; the file is then left untouched.
if nargin<2, configDir = fullfile(ephys.projectRoot(),'config'); end
sitePath = string(sitePath);
configDir = string(configDir);
assert(isfile(sitePath),'ephys:SelectedSiteMissing','Site YAML does not exist: %s',sitePath);
selection = fullfile(configDir,'active_site.yml');
try
    if ephys.samePath(ephys.resolveSitePath("",selection),sitePath)
        changed = false;
        return;
    end
catch
    % A missing or invalid selection is replaced below.
end
[folder,stem,ext] = fileparts(sitePath);
value = sitePath;
if ephys.samePath(folder,configDir), value = stem+ext; end
if isempty(regexp(value,'^[A-Za-z0-9._-]+$','once'))
    value = "'"+strrep(value,"'","''")+"'";
end
line = "site_file: "+value;
if isfile(selection)
    lines = splitlines(string(fileread(selection)));
    selected = startsWith(lines,"site_file:");
    if any(selected)
        lines(selected) = line;
    else
        lines(end+1) = line;
    end
    text = join(lines,newline);
else
    text = join(["# Default site for experiment runs, native-media preparation, and display checks."; ...
        "# Relative paths resolve from this file's directory; absolute paths also work."; ...
        line; ""],newline);
end
fid = fopen(selection,'w');
assert(fid>=0,'ephys:SiteSelection','Cannot write %s.',selection);
closer = onCleanup(@() fclose(fid));
fprintf(fid,'%s',text);
clear closer
assert(ephys.samePath(ephys.resolveSitePath("",selection),sitePath), ...
    'ephys:SiteSelection','Could not select %s in %s.',sitePath,selection);
changed = true;
end
