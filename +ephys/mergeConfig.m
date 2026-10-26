function result = mergeConfig(base, override)
%MERGECONFIG Recursive override; additions are rejected by the caller's schema.
result = base;
for name = string(fieldnames(override))'
    field = char(name);
    if isfield(result, field) && isstruct(result.(field)) && isstruct(override.(field))
        result.(field) = ephys.mergeConfig(result.(field), override.(field));
    else
        result.(field) = override.(field);
    end
end
end
