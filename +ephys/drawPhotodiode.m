function drawPhotodiode(window,config,state)
%DRAWPHOTODIODE The selected luminance is in the stimulus framebuffer.
if ~config.photodiode.enabled, return; end
if string(state) == "on"
    color = cell2mat(config.photodiode.on_rgb255);
else
    color = cell2mat(config.photodiode.off_rgb255);
end
Screen('FillRect',window,color,cell2mat(config.photodiode.rect_px));
end
