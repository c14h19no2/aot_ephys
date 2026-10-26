function label = subjectLabel(value)
%SUBJECTLABEL Output subject label: numbers zero-padded to three digits.
% 3, "3" and "003" give "003"; 17 gives "017"; a name such as "patientname" is
% kept as typed. A leading "sub-" is accepted and removed. Labels contain
% only letters and digits, so they cannot change folder structure.
message = 'Subject must be a positive integer or a label of letters and digits, e.g. 3 or patientname.';
if isnumeric(value)
    assert(isscalar(value) && isreal(value) && isfinite(value) && ...
        value>0 && value==floor(value),'ephys:RunIdentity','%s',message);
    label = string(sprintf('%03d',value));
    return;
end
assert((ischar(value) && (isrow(value) || isempty(value))) || ...
    (isstring(value) && isscalar(value) && ~ismissing(value)), ...
    'ephys:RunIdentity','%s',message);
text = strtrim(string(value));
if startsWith(text,"sub-"), text = extractAfter(text,4); end
assert(strlength(text)>0 && ~isempty(regexp(text,'^[A-Za-z0-9]+$','once')), ...
    'ephys:RunIdentity','%s Got "%s".',message,text);
if isempty(regexp(text,'^[0-9]+$','once'))
    label = text;
    return;
end
number = str2double(text);
assert(number>0 && number<1e6,'ephys:RunIdentity','%s Got "%s".',message,text);
label = string(sprintf('%03d',number));
end
