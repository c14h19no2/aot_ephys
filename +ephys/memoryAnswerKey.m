function answers = memoryAnswerKey(videoSchedules,pictures)
%MEMORYANSWERKEY Y/N key: Y when the picture's clip is in the given video schedules.
% Same rule as the archived answer files: picture 0305_fw.png is Y exactly
% when 0305_fw.mp4 was scheduled in one of the session's video runs.
shown = strings(0,1);
for k = 1:numel(videoSchedules)
    doc = ephys.readYaml(char(videoSchedules(k)));
    names = ephys.validateSchedule(doc.stimuli.movie_files);
    shown = [shown; stems(names(names~="blank"))]; %#ok<AGROW>
end
answers = containers.Map('KeyType','char','ValueType','char');
pictureStems = stems(string(pictures));
for k = 1:numel(pictureStems)
    value = 'N';
    if any(shown == pictureStems(k)), value = 'Y'; end
    answers(char(pictureStems(k))) = value;
end
end

function names = stems(files)
names = regexprep(files(:),'\.[^.]*$','');
end
