function [key,inputTime] = nextKey(obj)
%NEXTKEY Read one raw keyboard event or the configured debug input callback.
    key = "";
    inputTime = NaN;
    if ~isempty(obj.InputFcn)
        [key,inputTime] = obj.InputFcn(obj);
        key = lower(string(key));
        return;
    end
    if obj.Config.debug_simulated_input_only
        if GetSecs-obj.LastVBL >= 0.4
            inputTime = GetSecs;
            picture = false;
            if obj.Config.task_kind == "memory" && obj.Log.FlipCount > 0
                last = obj.Log.lastFlip();
                picture = last.phase == "picture";
            end
            if picture
                key = lower(string(obj.Config.input.memory_yes_key));
            else
                key = lower(string(obj.Config.input.instruction_continue_key));
            end
        end
        return;
    end
    [keyEvent,remainingEvents] = KbEventGet(obj.Config.input_device_index,0);
    if remainingEvents>9000
        error('ephys:InputOverflow','Keyboard queue nearly full.');
    end
    if ~isempty(keyEvent) && keyEvent.Pressed
        key = lower(string(KbName(keyEvent.Keycode)));
        inputTime = keyEvent.Time;
    end
end
