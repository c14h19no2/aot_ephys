function result = diagnose_aot_ephys_display_timing(varargin)
%DIAGNOSE_AOT_EPHYS_DISPLAY_TIMING Full-screen PTB preflight with sync tests on.
% result = diagnose_aot_ephys_display_timing('Output', '/absolute/report.json')
% Uses the selected site's display settings. No TTL device is opened, no
% physical signal is recorded, and no experiment configuration is changed.
% It describes the backend's interval source, not physical timing validity.

root = fileparts(mfilename('fullpath'));
addpath(fullfile(root,'third_party','yaml'));
parser = inputParser;
addParameter(parser,'Site',"");
addParameter(parser,'Output',fullfile(tempdir, ...
    ['aot_display_preflight_' char(datetime('now','Format','yyyyMMdd_HHmmss')) '.json']));
parse(parser,varargin{:});
[sitePath,selectionPath] = ephys.resolveSitePath(parser.Results.Site);
site = ephys.readYaml(sitePath);
base = ephys.readYaml(fullfile(root,'config','experiment.yml'));
c = ephys.mergeConfig(base,site);
output = char(parser.Results.Output);
assert(~isfile(output),'ephys:OutputExists','Output exists: %s',output);
assert(isfolder(fileparts(output)),'ephys:OutputDirectory', ...
    'Output must have an existing absolute parent directory: %s',output);

result = struct('started_local',char(datetime('now')), ...
    'matlab_version',version,'computer',computer, ...
    'site_path',char(sitePath),'site_selection_path',selectionPath, ...
    'site_sha256',ephys.sha256(sitePath), ...
    'screen_index',c.display.screen_index, ...
    'configured_resolution_px',cell2mat(c.display.resolution_px), ...
    'expected_refresh_hz',c.display.expected_refresh_hz, ...
    'full_screen',true,'skip_sync_requested',0,'skip_sync_effective',NaN, ...
    'ptb_path',which('Screen'),'ptb_version',PsychtoolboxVersion, ...
    'available_screens',[],'screen_mode',struct(), ...
    'window_rect',[],'resolution_matches_site',false, ...
    'window_info',struct(),'ifi_s',NaN,'valid_samples',NaN,'stddev_s',NaN, ...
    'display_timing',struct(),'software_calibration_applicable',false, ...
    'software_calibration_passed',NaN, ...
    'physical_timing_validated',false,'external_signals_recorded',false, ...
    'ttl_output',"none",'status',"not_started", ...
    'error_identifier',"",'error_message',"");
window = [];
oldSkip = Screen('Preference','SkipSyncTests',0);
preferenceGuard = onCleanup(@() Screen('Preference','SkipSyncTests',oldSkip)); %#ok<NASGU>
try
    result.skip_sync_effective = Screen('Preference','SkipSyncTests');
    assert(result.skip_sync_effective==0,'ephys:SyncPreference', ...
        'PTB did not enable sync tests.');
    result.available_screens = Screen('Screens');
    assert(ismember(c.display.screen_index,result.available_screens), ...
        'ephys:ScreenIndex','Configured screen is unavailable.');
    result.screen_mode = Screen('Resolution',c.display.screen_index);
    window = Screen('OpenWindow',c.display.screen_index, ...
        cell2mat(c.stimulus.background_rgb255));
    windowGuard = onCleanup(@() closeWindow(window)); %#ok<NASGU>
    result.window_rect = Screen('Rect',window);
    result.window_info = Screen('GetWindowInfo',window);
    result.resolution_matches_site = isequal( ...
        round(result.window_rect(3:4)-result.window_rect(1:2)), ...
        result.configured_resolution_px(:)');
    [result.ifi_s,result.valid_samples,result.stddev_s] = ...
        Screen('GetFlipInterval',window,100,0.00005,10);
    result.display_timing = ephys.assessDisplayTiming(result.ifi_s, ...
        result.valid_samples,result.stddev_s,result.window_info);
    result.software_calibration_applicable = ...
        result.display_timing.sample_statistics_applicable;
    if result.software_calibration_applicable
        result.software_calibration_passed = ...
            result.display_timing.sample_statistics_status=="within_reference_limits";
    end
    if ~result.resolution_matches_site
        result.status = "site_resolution_mismatch";
    elseif abs(1/result.ifi_s-c.display.expected_refresh_hz)>c.display.refresh_tolerance_hz
        result.status = "site_refresh_mismatch";
    elseif ~result.software_calibration_applicable
        result.status = "backend_interval_available_external_unmeasured";
    elseif ~result.software_calibration_passed
        result.status = "calibration_statistics_warning";
    else
        result.status = "software_preflight_passed_external_unmeasured";
    end
catch cause
    result.status = "ptb_preflight_error";
    result.error_identifier = string(cause.identifier);
    result.error_message = string(cause.message);
end
clear windowGuard preferenceGuard
result.finished_local = char(datetime('now'));
fid = fopen(output,'w');
assert(fid>=0,'ephys:OutputCreate','Cannot write %s',output);
fileGuard = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',jsonencode(result,'PrettyPrint',true));
fprintf('Display preflight: %s; samples=%g; stddev=%.6f s; SkipSyncTests=%g\n', ...
    result.status,result.valid_samples,result.stddev_s,result.skip_sync_effective);
fprintf('Physical signals recorded: no. TTL output: none. Report: %s\n',output);

end

function closeWindow(window)
try, Screen('Close',window); catch, end
end
