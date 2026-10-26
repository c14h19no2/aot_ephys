function value = readYaml(path)
%READYAML Read a project YAML file and reject duplicate simple mapping keys.
% The source schedules and project configuration use block mappings/sequences.
% Rejecting anchors, aliases, and tags keeps the preflight grammar auditable.
path = char(path);
assert(isfile(path), 'aot:MissingYAML', 'Missing YAML: %s', path);
source = fileread(path);
assert(isempty(regexp(source, '(^|\s)[&*!][A-Za-z]', 'once')), ...
    'aot:UnsupportedYAML', 'YAML anchors, aliases, and tags are unsupported: %s', path);
lines = regexp(source, '\r\n|\n|\r', 'split');
depths = [];
keys = {};
for i = 1:numel(lines)
    line = lines{i};
    if contains(line, sprintf('\t'))
        error('aot:YamlTab', 'Tab indentation at %s:%d', path, i);
    end
    match = regexp(line, '^( *)([A-Za-z_][A-Za-z0-9_-]*):(?:\s|$)', 'tokens', 'once');
    if isempty(match), continue; end
    depth = numel(match{1});
    while ~isempty(depths) && depths(end) > depth
        depths(end) = [];
        keys(end) = [];
    end
    key = match{2};
    if ~isempty(depths) && depths(end) == depth
        used = strsplit(keys{end}, '|');
        if any(strcmp(used, key))
            error('aot:DuplicateYAMLKey', 'Duplicate YAML key %s at %s:%d', key, path, i);
        end
        keys{end} = [keys{end} '|' key];
    else
        depths(end+1) = depth;
        keys{end+1} = key;
    end
end
value = yaml.loadFile(string(path));
assert(isstruct(value) && isscalar(value), 'aot:YamlRoot', ...
    'YAML root must be a mapping: %s', path);
end
