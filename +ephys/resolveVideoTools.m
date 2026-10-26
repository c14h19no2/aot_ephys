function playback = resolveVideoTools(playback)
%RESOLVEVIDEOTOOLS Resolve FFmpeg/ffprobe before opening a display.
for field = ["ffmpeg_path","ffprobe_path"]
    tool = erase(field,"_path");
    configured = string(playback.(field));
    if strlength(configured)>0
        assert(isfile(configured),'ephys:MediaToolMissing','Missing executable: %s',configured);
        continue;
    end
    folders = string(strsplit(getenv('PATH'),pathsep));
    if tool=="ffprobe" && strlength(string(playback.ffmpeg_path))>0
        folders = [string(fileparts(playback.ffmpeg_path)),folders];
    end
    folders = [folders,"/opt/homebrew/bin","/usr/local/bin", ...
        string(fullfile(getenv('HOME'),'fsl','bin'))];
    name = tool;
    if ispc, name = name+".exe"; end
    found = "";
    for folder=folders
        candidate = fullfile(folder,name);
        if isfile(candidate), found=candidate; break; end
    end
    assert(strlength(found)>0,'ephys:MediaToolMissing', ...
        'Install %s or set playback.%s to its executable path in the site YAML.',tool,field);
    playback.(field) = char(found);
end
end
