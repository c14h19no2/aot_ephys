function value = condition(name)
%CONDITION Encoded forward/reverse assets remain distinct physical files.
name = lower(string(name));
if endsWith(name,"_fw.mp4") || endsWith(name,"_fw.png") || ...
        startsWith(name,"s_")
    value = "forward";
elseif endsWith(name,"_rv.mp4") || endsWith(name,"_rv.png") || ...
        startsWith(name,"r_s_")
    value = "backward";
elseif name == "blank"
    value = "blank";
else
    value = "unknown";
end
end
