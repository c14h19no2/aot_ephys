function memoryTrial(obj,trialNr,pictureName)
%MEMORYTRIAL Present one picture and record the first valid timestamped response.
    config = obj.Config;
    context = obj.TrialContexts{trialNr};
    obj.CurrentContext = context;
    picturePath = fullfile(string(obj.Config.paths.picture_root),pictureName);
    pixels = imread(char(picturePath));
    texture = Screen('MakeTexture',obj.Window,pixels);
    textureCleanup = onCleanup(@() Screen('Close',texture));
    if obj.QueueActive
        KbQueueFlush(obj.Config.input_device_index);
    end
    background = cell2mat(obj.Config.stimulus.background_rgb255);
    Screen('FillRect',obj.Window,background);
    pictureRect = ephys.movieRect(config,[size(pixels,2), size(pixels,1)]);
    Screen('DrawTexture',obj.Window,texture,[],pictureRect);
    ephys.drawFixation(obj.Window,obj.Config);
    ephys.drawPhotodiode(obj.Window,obj.Config,"off");
    frame = ephys.noFrame("picture");
    frame.texture_handle = double(texture);
    plannedOnset = NaN;
    if config.markers.memory_onset_enabled
        plannedOnset = obj.Triggers.nextAllowedRequestTime()+obj.IFI/2;
    end
    onsetFlip = obj.flip(context,"picture",1,frame,"off",plannedOnset);
    marker = [];
    if config.markers.memory_onset_enabled
        marker = obj.Triggers.emit("memory_stimulus_onset",context, ...
            obj.markerFlip(onsetFlip),NaN,"");
    end
    event = obj.Log.event(context,"memory_stimulus_onset","picture", ...
        onsetFlip.stimulus_onset_getsecs,onsetFlip);
    if ~isempty(marker)
        event.marker_event_id = marker.event_id;
        obj.Log.updateLastEvent(event);
    end
    while true
        obj.Triggers.poll();
        [key,inputTime] = obj.nextKey();
        if key == lower(string(obj.Config.input.quit_key))
            obj.abortFromKey(context,"picture",key,inputTime);
        end
        responseType = "";
        if key == lower(string(obj.Config.input.memory_yes_key))
            responseType = "yes";
        elseif key == lower(string(obj.Config.input.memory_no_key))
            responseType = "no";
        end
        if strlength(responseType)>0 && inputTime >= onsetFlip.stimulus_onset_getsecs
            marker = obj.Triggers.emit("memory_response",context,[], ...
                inputTime,responseType);
            event = obj.Log.event(context,"memory_response","picture",inputTime,[]);
            event.response = key;
            event.response_type = responseType;
            event.rt_s = inputTime-onsetFlip.stimulus_onset_getsecs;
            event.input_getsecs = inputTime;
            event.simulated = obj.Config.debug_simulated_input_only;
            [event.expected_answer,event.correct] = ...
                ephys.scoreMemory(obj.Answers,pictureName,responseType);
            event.marker_event_id = marker.event_id;
            obj.Log.updateLastEvent(event);
            break;
        elseif strlength(key)>0
            obj.logKey(context,"picture",key,inputTime,"invalid_key");
        end
        WaitSecs(0.005);
    end
    obj.fixationFlip(context,"memory_clear",1,NaN,"off");
end
