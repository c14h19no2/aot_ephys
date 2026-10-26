function [folder,replaced] = prepareOutputFolder(root,collectionDate,runId,overwrite)
%PREPAREOUTPUTFOLDER Create <root>/<yyyy-mm-dd>/<runId> for one recording.
% An empty collectionDate creates <root>/<runId> (diagnostic tools).
% An existing folder stops the run unless overwrite is true. It is then
% renamed to <runId>_replaced-<HHMMSS> in the same folder, never deleted.
collectionDate = string(collectionDate);
if strlength(collectionDate)==0
    folder = string(fullfile(char(root),char(runId)));
else
    assert(~isempty(regexp(collectionDate,'^\d{4}-\d{2}-\d{2}$','once')), ...
        'ephys:OutputDate','Collection date must be yyyy-mm-dd, got "%s".',collectionDate);
    folder = string(fullfile(char(root),char(collectionDate),char(runId)));
end
replaced = "";
if isfolder(folder) || isfile(folder)
    assert(overwrite,'ephys:OutputExists',['Output already exists: %s. Use another ' ...
        'run or recording number, or Overwrite to keep the old folder under a ' ...
        '_replaced name.'],folder);
    stamp = folder+"_replaced-"+string(datetime('now','Format','HHmmss'));
    replaced = stamp;
    n = 1;
    while isfolder(replaced) || isfile(replaced)
        n = n+1;
        replaced = stamp+"-"+n;
    end
    [ok,message] = movefile(folder,replaced);
    assert(ok,'ephys:OutputReplace','Cannot rename existing output %s: %s',folder,message);
    fprintf('Existing output kept as %s\n',replaced);
end
[ok,message] = mkdir(folder);
assert(ok,'ephys:OutputCreate','Cannot create output: %s',message);
end
