function perf = memoryPerformance(events,config)
%MEMORYPERFORMANCE Recognition scores from a memory run's onset and response events.
% Only answered pictures with a Y/N answer are scored; without an answer key
% the scores stay unknown (NaN). Y pictures answered yes are hits, N pictures
% answered yes are false alarms. d' uses the log-linear correction (0.5 added
% to the hit and false-alarm counts, 1 to each denominator) so that perfect
% rates stay finite.
perf = struct('status',"",'answer_source',"none",'answer_schedule_count',0, ...
    'presented',0,'answered',0,'unanswered',0,'yes',0,'no',0,'scored',0, ...
    'correct',NaN,'accuracy',NaN,'old_pictures',NaN,'new_pictures',NaN, ...
    'hits',NaN,'misses',NaN,'false_alarms',NaN,'correct_rejections',NaN, ...
    'hit_rate',NaN,'false_alarm_rate',NaN,'d_prime',NaN, ...
    'median_rt_s',NaN,'simulated',false);
if isfield(config,'answer_source'), perf.answer_source = string(config.answer_source); end
if isfield(config,'answer_schedules')
    perf.answer_schedule_count = numel(config.answer_schedules);
end
onsets = 0; responses = struct([]);
if ~isempty(events)
    type = string({events.event_type});
    onsets = sum(type=="memory_stimulus_onset");
    responses = events(type=="memory_response");
end
perf.presented = onsets;
perf.answered = numel(responses);
perf.unanswered = perf.presented-perf.answered;
if perf.answered == 0
    perf.status = "no_responses";
    return;
end
answer = string({responses.response_type});
expected = string({responses.expected_answer});
perf.yes = sum(answer=="yes");
perf.no = sum(answer=="no");
perf.simulated = any([responses.simulated]);
perf.median_rt_s = median([responses.rt_s],'omitnan');
old = expected=="Y"; new = expected=="N";
perf.scored = sum(old|new);
if perf.scored == 0
    perf.status = "no_answer_key";
    return;
end
perf.status = "scored";
perf.old_pictures = sum(old);
perf.new_pictures = sum(new);
perf.hits = sum(old & answer=="yes");
perf.misses = sum(old & answer=="no");
perf.false_alarms = sum(new & answer=="yes");
perf.correct_rejections = sum(new & answer=="no");
perf.correct = perf.hits+perf.correct_rejections;
perf.accuracy = perf.correct/perf.scored;
if perf.old_pictures > 0, perf.hit_rate = perf.hits/perf.old_pictures; end
if perf.new_pictures > 0, perf.false_alarm_rate = perf.false_alarms/perf.new_pictures; end
if perf.old_pictures > 0 && perf.new_pictures > 0
    perf.d_prime = z((perf.hits+0.5)/(perf.old_pictures+1)) - ...
        z((perf.false_alarms+0.5)/(perf.new_pictures+1));
end
end

function value = z(p)
% Inverse standard normal without the Statistics Toolbox.
value = -sqrt(2)*erfcinv(2*p);
end
