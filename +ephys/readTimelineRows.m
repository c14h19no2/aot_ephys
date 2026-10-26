function rows=readTimelineRows(path,template)
%READTIMELINEROWS Keep schema types when early phases contain empty columns.
options=detectImportOptions(path,'FileType','text','Delimiter','\t', ...
    'VariableNamingRule','preserve');
names=string(fieldnames(template));
present=ismember(names,string(options.VariableNames));
names=names(present);
textNames=names(arrayfun(@(name) isstring(template.(name)) || ischar(template.(name)),names));
numericNames=names(~ismember(names,textNames));
if ~isempty(textNames), options=setvartype(options,cellstr(textNames),'string'); end
if ~isempty(numericNames), options=setvartype(options,cellstr(numericNames),'double'); end
rows=readtable(path,options);
for name=textNames'
    % Written empty strings are empty strings, not missing trial identities.
    missing=ismissing(rows.(name));
    rows.(name)(missing)="";
end
end
