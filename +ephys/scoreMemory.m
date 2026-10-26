function [expected,correct] = scoreMemory(answers,pictureFile,responseType)
%SCOREMEMORY Preserve J=yes and K=no; unknown key means unknown score.
expected = ""; correct = NaN;
if answers.Count == 0, return; end
[~,stem] = fileparts(string(pictureFile));
if ~isKey(answers,char(stem)), return; end
expected = string(answers(char(stem)));
correct = double((expected=="Y" && string(responseType)=="yes") || ...
    (expected=="N" && string(responseType)=="no"));
end
