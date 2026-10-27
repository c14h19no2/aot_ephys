function printTriggerOffsetSummary(summary)
%PRINTTRIGGEROFFSETSUMMARY Print a compact post-run estimate summary.
n=summary.plotted_marker_count;
if n==0
    fprintf('Trigger offsets: 0 observed audio/visual pairs (%d total events).\n', ...
        summary.total_marker_count);
    fprintf('No offset statistics available; dummy, cancelled or unconfirmed pairs are excluded.\n');
    return;
end
sd='n/a';
if isfinite(summary.stddev_s), sd=sprintf('%.3f',1000*summary.stddev_s); end
fprintf('Trigger offsets (audio - visual): N=%d, median=%+.3f ms, SD=%s ms.\n', ...
    n,1000*summary.median_s,sd);
fprintf('Range=[%+.3f, %+.3f] ms; absolute-offset P95=%.3f ms; software/driver estimates.\n', ...
    1000*summary.min_s,1000*summary.max_s,1000*summary.p95_absolute_s);
limit=1000*summary.reference_limit_s;
fprintf('Beyond median +/-%.3g ms (trial QC rule): %d/%d (%.1f%%); beyond +/-%.3g ms of zero: %d/%d.\n', ...
    limit,summary.outside_median_reference_count,n, ...
    100*summary.outside_median_reference_count/n, ...
    limit,summary.outside_reference_count,n);
end
