function key=markerKey(eventType,responseType)
%MARKERKEY Map semantic events to named waveforms without integer TTL labels.
if nargin<2, responseType=""; end
key=string(eventType);
if key=="blank_onset", key="video_onset"; end
if key=="blank_offset", key="video_offset"; end
if key=="memory_response"
    responseType=string(responseType);
    assert(isscalar(responseType) && any(responseType==["yes","no"]), ...
        'ephys:TriggerResponse','A memory response must be yes or no.');
    key=key+"_"+responseType;
end
end
