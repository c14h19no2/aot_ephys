function names = validatePictureSchedule(raw)
%VALIDATEPICTURESCHEDULE Preserve Python picture order without path escapes.
assert(iscell(raw) && ~isempty(raw),'ephys:PictureSchedule', ...
    'picture_files must be a nonempty YAML sequence.');
names = strings(numel(raw),1);
for i = 1:numel(raw)
    name = string(raw{i});
    assert(isscalar(name) && strlength(name) > 0 && ...
        ~any(contains(name,["/","\",".."])) && ...
        endsWith(lower(name),'.png'), ...
        'ephys:PictureSchedule','Invalid picture name at position %d.',i);
    names(i) = name;
end
end
