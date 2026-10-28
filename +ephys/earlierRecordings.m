function dates = earlierRecordings(root,collectionDate,runId)
%EARLIERRECORDINGS Other collection dates that already hold this run ID.
% Returns the yyyy-mm-dd folders of root, other than collectionDate, that
% contain a runId folder (a column of strings, empty when there are none).
dates = strings(0,1);
root = string(root);
if ~isscalar(root) || strlength(root)==0 || ~isfolder(root), return; end
entries = dir(root);
names = string({entries([entries.isdir]).name});
datePattern = digitsPattern(4)+"-"+digitsPattern(2)+"-"+digitsPattern(2);
names = names(matches(names,datePattern) & names~=string(collectionDate));
for name = names
    if isfolder(fullfile(root,name,runId)), dates(end+1,1) = name; end %#ok<AGROW>
end
end
