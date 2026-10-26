function created = initializeLocalConfig(configDir)
%INITIALIZELOCALCONFIG Create missing local files without replacing user edits.
created = strings(0,1);
for pair = ["site.example.yml","site.local.yml"; ...
        "active_site.example.yml","active_site.yml"; ...
        "subjects.example.yml","subjects.local.yml"]'
    source = fullfile(configDir,pair(1));
    destination = fullfile(configDir,pair(2));
    assert(isfile(source),'ephys:SetupTemplate','Missing setup template: %s',source);
    if isfile(destination), continue; end
    assert(~isfolder(destination),'ephys:SetupConfig','Expected a file: %s',destination);
    [ok,message] = copyfile(source,destination);
    assert(ok,'ephys:SetupConfig','Cannot create local configuration: %s',message);
    created(end+1,1) = string(destination); %#ok<AGROW>
end
end
