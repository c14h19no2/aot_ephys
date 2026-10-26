function info = setup_aot(varargin)
%SETUP_AOT Add project paths and create any missing local site/selector files.
% setup_aot('PsychtoolboxPath', '/path/to/Psychtoolbox') adds an installed PTB.
% Existing site files are preserved. No display/audio device is opened, no
% media conversion is performed, and no MATLAB path is saved globally.
root = fileparts(mfilename('fullpath'));
parser = inputParser;
addParameter(parser,'PsychtoolboxPath',"",@(x) ischar(x) || (isstring(x) && isscalar(x)));
addParameter(parser,'CreateLocalConfig',true,@(x) islogical(x) && isscalar(x));
parse(parser,varargin{:});
addpath(root,fullfile(root,'third_party','yaml'));
ptb = strtrim(string(parser.Results.PsychtoolboxPath));
if strlength(ptb)>0
    assert(isfolder(ptb),'ephys:PTBPath','Psychtoolbox folder does not exist: %s',ptb);
    addpath(genpath(char(ptb)));
    assert(exist('Screen','file')>0,'ephys:PTBPath','Screen is unavailable after adding %s.',ptb);
end
created = strings(0,1);
if parser.Results.CreateLocalConfig
    created = ephys.initializeLocalConfig(fullfile(root,'config'));
end
info = struct('project_root',string(root),'created_local_files',created, ...
    'psychtoolbox_available',exist('Screen','file')>0,'screen_path',string(which('Screen')));
fprintf('AOT project: %s\n',root);
if ~isempty(created)
    fprintf('Created local configuration. Set site paths/display values before running.\n');
end
fprintf('Psychtoolbox Screen available: %d.\n',info.psychtoolbox_available);
end
