function root = projectRoot()
%PROJECTROOT Absolute path to this MATLAB implementation.
root = fileparts(fileparts(mfilename('fullpath')));
end
