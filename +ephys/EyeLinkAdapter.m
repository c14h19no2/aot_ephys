classdef EyeLinkAdapter < handle
    %EYELINKADAPTER Optional continuous PTB EyeLink recording for a run.
    % All device calls are injectable for deterministic lifecycle tests.
    properties (SetAccess = private)
        Enabled
        Connected = false
        Recording = false
        RemoteName = ""
        LocalPath = ""
        Invoker
        DefaultsFcn
        SetupFcn
        Mocked = false
    end
    properties (Access = private)
        Config
        FileOpen = false
    end
    methods
        function obj = EyeLinkAdapter(config, invoker, defaultsFcn, setupFcn)
            obj.Config = config;
            obj.Enabled = config.eyelink.enabled;
            if nargin >= 2 && ~isempty(invoker), obj.Mocked = true; end
            if nargin < 2 || isempty(invoker)
                invoker = @(command, varargin) Eyelink(command, varargin{:});
            end
            if nargin < 3 || isempty(defaultsFcn)
                defaultsFcn = @(window) EyelinkInitDefaults(window);
            end
            if nargin < 4 || isempty(setupFcn)
                setupFcn = @(defaults) EyelinkDoTrackerSetup(defaults);
            end
            obj.Invoker = invoker;
            obj.DefaultsFcn = defaultsFcn;
            obj.SetupFcn = setupFcn;
        end
        function open(obj, window, outputDir)
            if ~obj.Enabled, return; end
            assert(obj.Mocked || exist('Eyelink','file') > 0, 'aot:EyeLinkMissing', ...
                'PTB EyeLink support is unavailable.');
            result = obj.Invoker('SetAddress', char(obj.Config.eyelink.address));
            obj.requireZero(result, 'SetAddress');
            result = obj.Invoker('Initialize', 'PsychEyelinkDispatchCallback');
            obj.requireZero(result, 'Initialize');
            obj.Connected = true;
            resolution = cell2mat(obj.Config.display.resolution_px);
            obj.command('screen_pixel_coords = 0 0 %d %d', ...
                resolution(1)-1, resolution(2)-1);
            obj.command('calibration_type = %s', char(obj.Config.eyelink.calibration_type));
            obj.command('calibration_area_proportion = %s', ...
                char(obj.Config.eyelink.calibration_area_proportion));
            obj.command('validation_area_proportion = %s', ...
                char(obj.Config.eyelink.validation_area_proportion));
            obj.command('sample_rate = %d', obj.Config.eyelink.sample_rate_hz);
            % EDF names have an eight-character tracker-side stem. A random
            % stem limits collision risk because OpenFile can overwrite a
            % pre-existing tracker file and cannot atomically refuse it.
            while true
                id = char(java.util.UUID.randomUUID());
                obj.RemoteName = upper(string(id(1:8))) + ".EDF";
                obj.LocalPath = string(fullfile(outputDir, char(obj.RemoteName)));
                if ~isfile(obj.LocalPath), break; end
            end
            result = obj.Invoker('OpenFile', char(obj.RemoteName));
            obj.requireZero(result, 'OpenFile');
            obj.FileOpen = true;
            obj.Config.eyelink.defaults = obj.DefaultsFcn(window);
        end
        function calibrate(obj)
            if ~obj.Enabled, return; end
            assert(obj.Connected && obj.FileOpen, 'aot:EyeLinkState', ...
                'EyeLink must be open before calibration.');
            obj.SetupFcn(obj.Config.eyelink.defaults);
        end
        function start(obj)
            if ~obj.Enabled, return; end
            assert(obj.Connected && obj.FileOpen, 'aot:EyeLinkState', ...
                'EyeLink must be open before recording.');
            result = obj.Invoker('StartRecording');
            obj.requireZero(result, 'StartRecording');
            obj.Recording = true;
        end
        function mark(obj, kind, trialNr, phase, time)
            if ~obj.Enabled || ~obj.Recording, return; end
            message = sprintf('AOT %s trial=%d phase=%s getsecs=%.6f', ...
                char(kind), trialNr, char(string(phase)), time);
            result = obj.Invoker('Message', message);
            obj.requireZero(result, 'Message');
        end
        function stopAndTransfer(obj)
            if ~obj.Enabled || ~obj.Connected, return; end
            if obj.Recording
                obj.Invoker('StopRecording');
                obj.Recording = false;
            end
            if obj.FileOpen
                result = obj.Invoker('CloseFile');
                obj.requireZero(result, 'CloseFile');
                obj.FileOpen = false;
                bytes = obj.Invoker('ReceiveFile', char(obj.RemoteName), ...
                    char(obj.LocalPath), 0);
                assert(bytes > 0, 'aot:EyeLinkTransfer', ...
                    'EyeLink EDF transfer failed (%d).', bytes);
                assert(isfile(obj.LocalPath), 'aot:EyeLinkTransfer', ...
                    'EyeLink reported transfer without a local EDF file.');
            end
        end
        function close(obj)
            if ~obj.Enabled || ~obj.Connected, return; end
            try
                obj.stopAndTransfer();
            catch cause
                obj.Invoker('Shutdown');
                obj.Connected = false;
                rethrow(cause);
            end
            obj.Invoker('Shutdown');
            obj.Connected = false;
        end
        function delete(obj)
            if obj.Connected
                try
                    obj.close();
                catch cause
                    warning('aot:EyeLinkCleanup', '%s', cause.message);
                end
            end
        end
    end
    methods (Access = private)
        function command(obj, format, varargin)
            result = obj.Invoker('Command', sprintf(format, varargin{:}));
            obj.requireZero(result, 'Command');
        end
        function requireZero(~, result, label)
            assert(isequal(result, 0), 'aot:EyeLinkCommand', ...
                'EyeLink %s failed (status %g).', label, result);
        end
    end
end
