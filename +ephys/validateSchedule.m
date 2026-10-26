function names = validateSchedule(raw)
%VALIDATESCHEDULE Normalize an ordered YAML list without changing identities.
assert(iscell(raw) && ~isempty(raw), 'aot:ScheduleType', ...
    'stimuli.movie_files must be a nonempty YAML sequence.');
names = strings(numel(raw), 1);
for i = 1:numel(raw)
    item = raw{i};
    assert((isstring(item) && isscalar(item)) || ischar(item), ...
        'aot:ScheduleType', 'Slot %d must be a filename.', i);
    name = string(item);
    assert(name == "blank" || ...
        (~any(contains(name, ["/", "\", ".."])) && endsWith(lower(name), '.mp4')), ...
        'aot:ScheduleName', 'Invalid movie name at slot %d: %s', i, name);
    names(i) = name;
end
end
