function revision = gitRevision(folder)
%GITREVISION Read a checkout's current commit without a shell subprocess.
revision = '';
gitDir = fullfile(char(folder), '.git');
if ~isfolder(gitDir), return; end
headPath = fullfile(gitDir, 'HEAD');
if ~isfile(headPath), return; end
head = strtrim(fileread(headPath));
if ~startsWith(head, 'ref: ')
    revision = head;
    return;
end
reference = strtrim(extractAfter(string(head), 'ref: '));
refPath = fullfile(gitDir, char(reference));
if isfile(refPath)
    revision = strtrim(fileread(refPath));
    return;
end
packed = fullfile(gitDir, 'packed-refs');
if ~isfile(packed), return; end
lines = splitlines(string(fileread(packed)));
for i = 1:numel(lines)
    parts = split(strtrim(lines(i)));
    if numel(parts) == 2 && parts(2) == reference
        revision = char(parts(1));
        return;
    end
end
end
