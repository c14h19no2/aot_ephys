function printMemoryPerformance(perf)
%PRINTMEMORYPERFORMANCE Print the memory scores after the run.
% Separator lines set the block apart for the experimenter.
rule = repmat('=',1,78);
fprintf('\n%s\n MEMORY PERFORMANCE\n%s\n',rule,rule);
fprintf('Memory: %d pictures shown, %d answered (yes %d, no %d)', ...
    perf.presented,perf.answered,perf.yes,perf.no);
if isfinite(perf.median_rt_s)
    fprintf('; median RT %.2f s',perf.median_rt_s);
end
fprintf('.\n');
if perf.unanswered > 0
    fprintf('%d shown picture(s) were not answered (run stopped); they are not scored.\n', ...
        perf.unanswered);
end
switch perf.status
    case "scored"
        fprintf('Accuracy %s (%d/%d). Hits %d/%d (%s), false alarms %d/%d (%s), d'' %s.\n', ...
            percent(perf.accuracy),perf.correct,perf.scored, ...
            perf.hits,perf.old_pictures,percent(perf.hit_rate), ...
            perf.false_alarms,perf.new_pictures,percent(perf.false_alarm_rate), ...
            number(perf.d_prime));
        if perf.answer_source == "session_video_schedules"
            fprintf(['Answer key: "seen" = clip shown in this session''s %d video runs ' ...
                '(saved schedules).\n'],perf.answer_schedule_count);
        elseif perf.answer_source == "answer_file"
            fprintf('Answer key: the Answers file.\n');
        end
        if perf.scored < perf.answered
            fprintf('%d answered picture(s) have no answer and are not scored.\n', ...
                perf.answered-perf.scored);
        end
    case "no_answer_key"
        fprintf(['Accuracy unknown: this schedule has no answer key. Pass ''Answers'' ' ...
            'with a Y/N TSV to score it.\n']);
end
if perf.simulated
    fprintf('Responses were simulated (Debug), not from a participant.\n');
end
fprintf('%s\n\n',rule);
end

function text = percent(value)
text = 'n/a';
if isfinite(value), text = sprintf('%.1f%%',100*value); end
end

function text = number(value)
text = 'n/a';
if isfinite(value), text = sprintf('%.2f',value); end
end
