function same = samePath(a,b)
%SAMEPATH True where file paths a and b name the same location.
% Compares full paths textually: separators are unified, and case is ignored
% on Windows. a may be a string array; b is one path.
a = strrep(string(a),'/',filesep);
b = strrep(string(b),'/',filesep);
if ispc
    same = strcmpi(a,b);
else
    same = a==b;
end
end
