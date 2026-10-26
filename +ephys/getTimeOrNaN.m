function value = getTimeOrNaN()
%GETTIMEORNAN Preserve partial output when PTB fails before startup.
value = NaN;
if exist('GetSecs','file')>0
    try, value = GetSecs; catch, end
end
end
