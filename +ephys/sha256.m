function hash = sha256(path)
%SHA256 File checksum for source provenance; called outside the render loop.
fid = fopen(char(path), 'r');
assert(fid > 0, 'aot:FileOpen', 'Cannot open %s', path);
guard = onCleanup(@() fclose(fid));
digest = java.security.MessageDigest.getInstance('SHA-256');
while true
    chunk = fread(fid, 65536, '*uint8');
    if isempty(chunk), break; end
    digest.update(typecast(chunk, 'int8'));
end
bytes = typecast(digest.digest(), 'uint8');
hash = lower(reshape(dec2hex(bytes, 2).', 1, []));
end
