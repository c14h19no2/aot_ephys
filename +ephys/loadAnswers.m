function answers = loadAnswers(path,schedule)
%LOADANSWERS Optional archived Y/N key. Missing keys remain unscored.
answers = containers.Map('KeyType','char','ValueType','char');
if strlength(string(path)) == 0, return; end
rows = readtable(path,'FileType','text','Delimiter','\t', ...
    'ReadVariableNames',false,'TextType','string');
assert(width(rows)==2,'ephys:AnswerFormat','Answer TSV requires two columns.');
for i = 1:height(rows)
    key = char(string(rows{i,1}));
    value = upper(string(rows{i,2}));
    assert(isscalar(value) && any(value==["Y","N"]), ...
        'ephys:AnswerFormat','Answer must be Y or N.');
    assert(~isKey(answers,key),'ephys:AnswerDuplicate', ...
        'Duplicate answer key: %s',key);
    answers(key) = char(value);
end
for i = 1:numel(schedule)
    [~,stem] = fileparts(schedule(i));
    assert(isKey(answers,char(stem)),'ephys:AnswerMissing', ...
        'No answer key for scheduled picture %s.',schedule(i));
end
end
