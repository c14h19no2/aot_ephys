function open(obj)
%OPEN Acquire audio, display, media-cache, keyboard, and EyeLink resources.
    assert(exist('Screen','file')>0 && ...
        (obj.Config.debug_simulated_input_only || ...
        exist('KbEventGet','file')>0), 'ephys:PTBMissing', ...
        'Psychtoolbox Screen and keyboard functions are required.');
    obj.Triggers.open();
    c = obj.Config;
    if c.display.skip_sync_tests
        assert(c.debug,'ephys:SkipSyncAcquisition', ...
            'SkipSyncTests is permitted only in debug mode.');
    end
    % Do not inherit a stale global PTB preference from an earlier
    % debug session. Request PTB checks; an external display backend
    % may internally use different calibration/timestamping methods.
    obj.SavedSkipSync = Screen('Preference','SkipSyncTests', ...
        double(c.display.skip_sync_tests));
    obj.EffectiveSkipSync = Screen('Preference','SkipSyncTests');
    assert(isequal(double(obj.EffectiveSkipSync), ...
        double(c.display.skip_sync_tests)), ...
        'ephys:SyncPreference', ...
        'PTB SkipSyncTests preference is %g after requesting %g.', ...
        obj.EffectiveSkipSync,double(c.display.skip_sync_tests));
    background = cell2mat(c.stimulus.background_rgb255);
    rect = [];
    if ~c.display.full_screen
        dims = cell2mat(c.display.resolution_px);
        rect = [0 0 dims(:)'];
    end
    availableScreens = Screen('Screens');
    assert(any(availableScreens == c.display.screen_index), ...
        'ephys:ScreenIndex', ...
        'Configured screen_index %d is unavailable; PTB screens: %s. Update display.screen_index in %s.', ...
        c.display.screen_index,mat2str(availableScreens),char(c.site_path));
    obj.Window = Screen('OpenWindow',c.display.screen_index, ...
        background,rect);
    actual = Screen('Rect',obj.Window);
    expected = cell2mat(c.display.resolution_px);
    observed = round(actual(3:4));
    assert(isequal(observed,expected(:)'), ...
        'ephys:DisplayResolution', ...
        'Configured resolution [%d %d], opened [%d %d]. Update display.resolution_px in %s.', ...
        expected(1),expected(2),observed(1),observed(2), ...
        char(c.site_path));
    windowInfo = Screen('GetWindowInfo',obj.Window);
    debugFallback = c.debug && c.display.skip_sync_tests;
    if debugFallback
        obj.IFI = 1/c.display.expected_refresh_hz;
    else
        [obj.IFI,obj.IFISamples,obj.IFIStddev] = ...
            Screen('GetFlipInterval',obj.Window,100);
    end
    obj.DisplayTiming = ephys.assessDisplayTiming(obj.IFI, ...
        obj.IFISamples,obj.IFIStddev,windowInfo,debugFallback);
    obj.IFIEstimated = ~obj.DisplayTiming.interval_is_measured;
    if strlength(obj.DisplayTiming.warning_message)>0
        warning('ephys:RefreshIntervalUnverified','%s', ...
            obj.DisplayTiming.warning_message);
    end
    % Onset predictions use the logged Flip timeline plus PTB's blanking rule.
    obj.VBLDuration = ephys.blankingDuration(windowInfo,obj.IFI);
    obj.DisplayTiming.onset_prediction_basis = "last logged Flip VBL timestamp";
    obj.DisplayTiming.vbl_duration_s = obj.VBLDuration;
    % "held": onset frame drawn early and held; "steady": refreshed until onset.
    obj.DisplayTiming.onset_flip_mode = "held";
    if obj.usesSteadyFlip(), obj.DisplayTiming.onset_flip_mode = "steady"; end
    obj.DisplayTiming.expected_refresh_hz = c.display.expected_refresh_hz;
    obj.DisplayTiming.refresh_mismatch_hz = 1/obj.IFI-c.display.expected_refresh_hz;
    obj.DisplayTiming.refresh_outside_reference = ...
        abs(obj.DisplayTiming.refresh_mismatch_hz)>c.display.refresh_tolerance_hz;
    if obj.DisplayTiming.refresh_outside_reference
        warning('ephys:RefreshMismatch', ...
            'PTB scheduling refresh %.3f Hz differs from expected %.3f Hz; continuing with the PTB interval and per-flip logs.', ...
            1/obj.IFI,c.display.expected_refresh_hz);
    end
    HideCursor;
    if string(c.playback.backend) == "native"
        obj.MovieCache = ephys.NativeMovieQueue(obj.Window,c.playback,obj.Inventory,c.schedule);
    else
        obj.MovieCache = ephys.PreparedMovieCache(obj.Window,c.playback, ...
            obj.Inventory,fullfile(obj.OutputDir,'frame_maps'));
    end
    if ~c.debug_simulated_input_only
        KbName('UnifyKeyNames');
        keys = {c.input.instruction_continue_key, ...
            c.input.memory_yes_key,c.input.memory_no_key,c.input.quit_key};
        for i = 1:numel(keys)
            code = KbName(char(keys{i}));
            assert(isscalar(code) && code>0 && code <= 256, ...
                'ephys:KeyMapping','Invalid key %s',string(keys{i}));
        end
        KbQueueCreate(c.input_device_index,ones(1,256),0,10000);
        KbQueueStart(c.input_device_index);
        obj.QueueActive = true;
    end
    obj.Eye.open(obj.Window,obj.OutputDir);
end
