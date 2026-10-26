function instruction(obj)
%INSTRUCTION Show the start screen and wait for a timestamped Space or Q.
    ctx = ephys.context(obj.Config.task_kind,0,"");
    obj.CurrentContext = ctx;
    obj.CurrentRunPhase = "instruction";
    obj.drawInstructions();
    first = obj.flip(ctx,"instruction",1,ephys.noFrame("instruction"),"off",NaN);
    obj.Log.event(ctx,"instruction_onset","instruction", ...
        first.stimulus_onset_getsecs,first);
    if obj.QueueActive
        KbQueueFlush(obj.Config.input_device_index);
    end
    while true
        [key,time] = obj.nextKey();
        if key == lower(string(obj.Config.input.quit_key))
            obj.abortFromKey(ctx,"instruction",key,time);
        end
        if key == lower(string(obj.Config.input.instruction_continue_key)) && ...
                time >= first.stimulus_onset_getsecs
            ev = obj.Log.event(ctx,"instruction_response","instruction",time,[]);
            ev.response = key;
            ev.input_getsecs = time;
            ev.simulated = obj.Config.debug_simulated_input_only;
            obj.Log.updateLastEvent(ev);
            break;
        elseif strlength(key)>0
            obj.logKey(ctx,"instruction",key,time,"invalid_key");
        end
        WaitSecs(0.005);
    end
    obj.CurrentContext = [];
    obj.CurrentRunPhase = "";
end
