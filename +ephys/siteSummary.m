function s = siteSummary(sitePath)
%SITESUMMARY Display settings and viewing distance of one site, for the dialog.
% Merges config/experiment.yml with the site file, as a run does without Debug.
% error is empty when the site file is readable and matches the schema. viewing
% is ephys.viewingDistance; a bad screen or target size gives status "invalid".
% The site needs no subject or run, so the dialog can show this at once.
s = struct('path',string(sitePath),'error',"",'screen_size_cm',[NaN NaN], ...
    'resolution_px',[NaN NaN],'refresh_hz',NaN,'approved',false, ...
    'viewing',ephys.viewingDistance(struct()));
try
    root = ephys.projectRoot();
    schema = ephys.readYaml(fullfile(root,'config','experiment.yml'));
    values = ephys.readYaml(sitePath);
    ephys.checkSchema(values,schema);
    config = ephys.mergeConfig(schema,values);
    s.resolution_px = reshape(cell2mat(config.display.resolution_px),1,[]);
    s.refresh_hz = config.display.expected_refresh_hz;
    s.approved = isequal(config.protocol.approved_for_acquisition,true);
catch cause
    s.error = string(cause.message);
    return;
end
try
    s.viewing = ephys.viewingDistance(config);
    if s.viewing.status=="ok", s.screen_size_cm = s.viewing.screen_size_cm; end
catch cause
    s.viewing.status = "invalid";
    s.viewing.message = string(cause.message);
end
end
