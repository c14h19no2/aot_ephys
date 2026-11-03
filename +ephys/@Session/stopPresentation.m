function stopPresentation(obj)
%STOPPRESENTATION Cancel pending audio, then release movie/display/input resources.
    % Stop visual/input activity before potentially slow output writes.
    if obj.PresentationStopped
        return;
    end
    obj.PresentationStopped = true;
    % Cancel before slow movie/display cleanup can pass a future onset.
    % Triggers is empty when construction failed before creating it.
    if ~obj.RunEndHandled && ~isempty(obj.Triggers)
        try
            obj.Triggers.cancelPending();
        catch cause
            obj.PresentationCleanupError = ...
                obj.PresentationCleanupError + "; audio cancellation: " + cause.message;
            warning('ephys:AudioCancellation','%s',cause.message);
        end
    end
    if ~isempty(obj.MovieCache)
        try
            if isa(obj.MovieCache,'ephys.NativeMovieQueue')
                obj.NativePendingTrials = obj.MovieCache.snapshot();
            end
            obj.MovieCache.close();
        catch cause
            obj.PresentationCleanupError = ...
                obj.PresentationCleanupError + "; movie: " + cause.message;
            warning('ephys:MovieCleanup','%s',cause.message);
        end
    end
    if obj.QueueActive
        try
            KbQueueStop(obj.Config.input_device_index);
            KbQueueRelease(obj.Config.input_device_index);
        catch cause
            obj.PresentationCleanupError = ...
                obj.PresentationCleanupError + "; keyboard: " + cause.message;
            warning('ephys:QueueCleanup','%s',cause.message);
        end
        obj.QueueActive = false;
    end
    if ~isempty(obj.Window)
        try
            if any(Screen('Windows') == obj.Window)
                Screen('Close',obj.Window);
            end
        catch cause
            obj.PresentationCleanupError = ...
                obj.PresentationCleanupError + "; display: " + cause.message;
            warning('ephys:DisplayCleanup','%s',cause.message);
        end
        obj.Window = [];
    end
    if exist('Priority','file')>0
        try
            Priority(0);
        catch cause
            obj.PresentationCleanupError = ...
                obj.PresentationCleanupError + "; priority: " + cause.message;
            warning('ephys:PriorityCleanup','%s',cause.message);
        end
    end
    if exist('ShowCursor','file')>0
        try
            ShowCursor;
        catch cause
            obj.PresentationCleanupError = ...
                obj.PresentationCleanupError + "; cursor: " + cause.message;
            warning('ephys:CursorCleanup','%s',cause.message);
        end
    end
    if ~isempty(obj.SavedSkipSync)
        try
            Screen('Preference','SkipSyncTests',obj.SavedSkipSync);
        catch cause
            obj.PresentationCleanupError = ...
                obj.PresentationCleanupError + "; sync preference: " + ...
                cause.message;
            warning('ephys:SyncCleanup','%s',cause.message);
        end
        obj.SavedSkipSync = [];
    end
end
