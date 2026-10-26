function report=writeTriggerOffsetReport(folder,stem,markers,events,limit,status)
%WRITETRIGGEROFFSETREPORT Export post-run WAV/Flip plots as a two-page PDF.
% Raw logs and acquisition decisions are never changed by this report.
if nargin<5 || isempty(limit), limit=.002; end
if nargin<6, status="unknown"; end
[summary,points]=ephys.triggerOffsetSummary(markers,events,limit);
file=string(stem)+"_trigger_offsets.pdf";
destination=fullfile(folder,file);
temporary=string(tempname(folder))+".pdf";
fileGuard=onCleanup(@() removeTemporary(temporary)); %#ok<NASGU>
fig=figure('Visible','off','Color','w','Units','pixels', ...
    'Position',[100 100 1200 680],'IntegerHandle','off');
figureGuard=onCleanup(@() close(fig)); %#ok<NASGU>
groups=["video_onset","blank_onset","run_start","run_end","video_offset","other"];
labels=["Video onset","Blank onset","Run start","Run end","Video offset","Other observed event"];
colors=[.14 .39 .66;.16 .51 .35;.73 .46 .05;.70 .28 .30;.45 .35 .70;.45 .45 .45];
symbols={'o','s','d','x','^','o'};
types=string({points.event_type});
limitMs=1000*limit;
values=[points.delta_ms];
times=[points.time_s];

ax=makePage(fig,stem,status,summary,"Offset over time",1);
if isempty(points)
    noObservations(ax);
else
    xBounds=[min([0 times]) max([0 times])];
    if diff(xBounds)==0, xBounds=xBounds+[-.5 .5]; end
    xBounds=xBounds+[-1 1]*max(.5,.025*diff(xBounds));
    patch(ax,xBounds([1 2 2 1]),[-limitMs -limitMs limitMs limitMs], ...
        [.88 .93 .88],'EdgeColor','none', ...
        'DisplayName',sprintf('+/- %.3g ms reference',limitMs));
    hold(ax,'on');
    for k=1:numel(groups)
        ix=selectGroup(types,groups,k);
        if any(ix)
            scatter(ax,times(ix),values(ix),34,colors(k,:),symbols{k}, ...
                'LineWidth',1,'DisplayName',labels(k));
        end
    end
    failed=string({points.status})=="failed";
    if any(failed)
        scatter(ax,times(failed),values(failed),95,'r','o', ...
            'LineWidth',1.2,'DisplayName','Failed event with observed timestamps');
    end
    yline(ax,limitMs,'--','Color',[.35 .45 .35],'HandleVisibility','off');
    yline(ax,-limitMs,'--','Color',[.35 .45 .35],'HandleVisibility','off');
    yline(ax,0,'-','Color',[.5 .5 .5],'HandleVisibility','off');
    xlim(ax,xBounds);
    yBounds=[min([-limitMs values]) max([limitMs values])];
    ylim(ax,yBounds+[-1 1]*max(.1,.08*diff(yBounds)));
    if startsWith(summary.origin_kind,"run_start")
        xlabel(ax,'Time from reported run-start visual onset (s)');
    else
        xlabel(ax,'Time from first observed visual onset (s)');
    end
    ylabel(ax,'Audio start - visual Flip (ms)');
    legend(ax,'Location','southoutside','NumColumns',3,'Box','off', ...
        'TextColor',[.1 .1 .1],'Interpreter','none');
end
% Avoid Padding, which is unavailable in local MATLAB releases before R2025a.
exportgraphics(fig,temporary,'ContentType','vector','BackgroundColor','white');

clf(fig);
ax=makePage(fig,stem,status,summary,"Offset distribution",2);
if isempty(points)
    noObservations(ax);
else
    bounds=[min([-limitMs values]) max([limitMs values])];
    spread=max(diff(bounds),.2);
    edges=linspace(bounds(1)-.04*spread,bounds(2)+.04*spread, ...
        min(24,max(8,ceil(sqrt(numel(values)))))+1);
    hold(ax,'on');
    for k=1:numel(groups)
        ix=selectGroup(types,groups,k);
        if ~any(ix), continue; end
        if groups(k)=="run_start" || groups(k)=="run_end"
            for value=values(ix)
                xline(ax,value,'Color',colors(k,:),'LineWidth',1.5, ...
                    'DisplayName',labels(k));
            end
        else
            histogram(ax,values(ix),edges,'DisplayStyle','stairs', ...
                'EdgeColor',colors(k,:),'LineWidth',1.7,'DisplayName',labels(k));
        end
    end
    xline(ax,limitMs,'--','Color',[.35 .45 .35], ...
        'DisplayName',sprintf('+/- %.3g ms reference',limitMs));
    xline(ax,-limitMs,'--','Color',[.35 .45 .35],'HandleVisibility','off');
    xlim(ax,[edges(1) edges(end)]);
    xlabel(ax,'Audio start - visual Flip (ms)');
    ylabel(ax,'Stimulus-onset count');
    legend(ax,'Location','southoutside','NumColumns',3,'Box','off', ...
        'TextColor',[.1 .1 .1],'Interpreter','none');
end
exportgraphics(fig,temporary,'ContentType','vector','BackgroundColor','white', ...
    'Append',true);
[ok,message]=movefile(temporary,destination,'f');
assert(ok,'ephys:OffsetReportWrite','Cannot save offset PDF: %s',message);
report=summary;
report.status="created";
report.file=file;
report.page_count=2;
report.timestamp_basis="PsychPortAudio and Flip estimates; not electrical or optical measurements";
report.error_id=""; report.error="";
end

function ax=makePage(fig,stem,status,s,heading,page)
% Retain the full page and its margins with the default tight PDF crop.
annotation(fig,'rectangle',[0 0 1 1],'Color','white');
ax=axes(fig,'Position',[.09 .28 .88 .52],'FontSize',11,'Box','off', ...
    'Color','white','XColor',[.1 .1 .1],'YColor',[.1 .1 .1],'GridColor',[.3 .3 .3]);
grid(ax,'on'); ax.GridAlpha=.15;
titleLine=string(stem)+" | "+heading;
annotation(fig,'textbox',[.09 .88 .88 .09],'String',titleLine, ...
    'Interpreter','none','FontSize',16,'FontWeight','bold', ...
    'Color',[.1 .1 .1],'EdgeColor','none');
if s.plotted_marker_count==0
    statsLine='N=0 | No observed audio/visual offset available';
else
    sd='n/a'; if isfinite(s.stddev_s), sd=sprintf('%.3f',1000*s.stddev_s); end
    statsLine=sprintf('N=%d | median=%.3f ms | SD=%s ms | range=[%.3f, %.3f] ms | beyond +/-%.3g ms reference: %d', ...
        s.plotted_marker_count,1000*s.median_s,sd, ...
        1000*s.min_s,1000*s.max_s,1000*s.reference_limit_s,s.outside_reference_count);
end
annotation(fig,'textbox',[.09 .81 .88 .06],'String',statsLine, ...
    'Interpreter','none','FontSize',11,'Color',[.1 .1 .1],'EdgeColor','none');
footer={sprintf('Run status: %s | %d total events; %d excluded; %d plotted failed events | Page %d/2', ...
    string(status),s.total_marker_count,s.excluded_marker_count,s.failed_marker_count,page), ...
    'Positive offset: reported audio starts after reported visual onset. Observed estimates only.', ...
    'No independent electrical or optical timing measurement. Dummy, cancelled and unconfirmed pairs are excluded.'};
annotation(fig,'textbox',[.09 .025 .88 .10],'String',footer, ...
    'Interpreter','none','FontSize',10,'Color',[.1 .1 .1],'EdgeColor','none');
end

function ix=selectGroup(types,groups,k)
if groups(k)=="other", ix=~ismember(types,groups(1:end-1));
else, ix=types==groups(k); end
end

function noObservations(ax)
axis(ax,'off');
text(ax,.5,.6,{'No observed WAV/Flip timestamp pairs.', ...
    'No offset values have been substituted or simulated.'}, ...
    'Units','normalized','HorizontalAlignment','center','FontSize',14,'Color',[.1 .1 .1]);
end

function removeTemporary(path)
if isfile(path), delete(path); end
end
