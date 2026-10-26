function checkSchema(value, schema)
%CHECKSCHEMA Reject unknown configuration fields before display setup.
for name = string(fieldnames(value))'
    key = char(name);
    if ~isfield(schema, key)
        error('aot:UnknownConfigField', 'Unknown configuration field: %s', key);
    end
    if isstruct(value.(key))
        if ~isstruct(schema.(key))
            error('aot:ConfigType', 'Wrong mapping type for %s', key);
        end
        ephys.checkSchema(value.(key), schema.(key));
    end
end
end
