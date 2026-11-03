function choice = runRequestDialog(varargin)
%RUNREQUESTDIALOG Ask for site, subject, session, run, task and Overwrite.
% The first row selects a site file in config/ (default: the one selected in
% config/active_site.yml) and shows its screen size, resolution, refresh rate
% and the viewing distance for the target movie size. Start writes a different
% chosen site to config/active_site.yml, so the run uses it; Cancel changes
% nothing. Returns a struct with site, subject, session, run, task and
% overwrite, or [] when cancelled. Each entry is checked with
% ephys.previewRunRequest, which also receives any extra name-value arguments
% (SubjectMap); a Site argument preselects that site. Start stays disabled until
% the site file is valid and the request is valid. A run that already has an
% output folder, today or on an earlier day, also needs Overwrite; the tick is
% cleared whenever the entries name a different run. Memory schedules exist
% only as run 1 of each session, so the memory task fixes Run at 1.
% The window is deleted before returning, so it never overlaps the PTB window.
[site,options] = takeSite(varargin);
choice = [];
siteReady = false;
previewRunId = "";   % run named by the latest preview
confirmedRunId = ""; % run for which Overwrite was ticked
videoRun = 1;        % run number restored when switching back to video
sites = ephys.siteChoices();
selected = max(sites.active,1);
if strlength(site)>0
    selected = find(ephys.samePath(sites.paths,site),1);
    if isempty(selected)
        [~,stem,ext] = fileparts(site);
        sites.names(end+1,1) = stem+ext;
        sites.paths(end+1,1) = site;
        selected = numel(sites.paths);
    end
end
fig = uifigure('Name','AOT ephys run','Position',[100 100 560 360]);
movegui(fig,'center');
% Rows 3-4 (viewing distance, site notes) are sized to their text in changeSite.
grid = uigridlayout(fig,[12 2],'ColumnWidth',{64,'1x'}, ...
    'RowHeight',{22,16,16,0,4,22,22,22,22,22,'1x',26},'RowSpacing',4, ...
    'Padding',[10 8 10 8]);
uilabel(grid,'Text','Site');
siteField = uidropdown(grid,'Tag','site');
siteInfo = uilabel(grid,'Text','','Tag','site_info');
siteInfo.Layout.Column = 2;
viewingLabel = uilabel(grid,'Text','','WordWrap','on','VerticalAlignment','top', ...
    'FontWeight','bold','Tag','viewing');
viewingLabel.Layout.Column = 2;
siteNotes = uilabel(grid,'Text','','WordWrap','on','VerticalAlignment','top','Tag','site_notes');
siteNotes.Layout.Column = 2;
spacer = uilabel(grid,'Text','');
spacer.Layout.Column = [1 2];
uilabel(grid,'Text','Subject');
subjectField = uieditfield(grid,'text','Placeholder','e.g. 3 or patientname','Tag','subject');
uilabel(grid,'Text','Session');
sessionField = uispinner(grid,'Limits',[1 Inf],'Value',1,'RoundFractionalValues','on', ...
    'ValueDisplayFormat','%d','HorizontalAlignment','left','Tag','session');
uilabel(grid,'Text','Run');
runField = uispinner(grid,'Limits',[1 Inf],'Value',1,'RoundFractionalValues','on', ...
    'ValueDisplayFormat','%d','HorizontalAlignment','left','Tag','run');
uilabel(grid,'Text','Task');
taskField = uidropdown(grid,'Items',{'video','memory','practice'},'Value','video','Tag','task');
uilabel(grid,'Text','');
overwriteField = uicheckbox(grid,'Tag','overwrite', ...
    'Text','Overwrite (record this run again; existing folders are kept)');
previewLabel = uilabel(grid,'Text','','WordWrap','on', ...
    'VerticalAlignment','top','Tag','preview');
previewLabel.Layout.Column = [1 2];
buttons = uigridlayout(grid,[1 3],'ColumnWidth',{'1x',100,100},'Padding',0);
buttons.Layout.Column = [1 2];
uilabel(buttons,'Text','');
uibutton(buttons,'Text','Cancel','Tag','cancel','ButtonPushedFcn',@(~,~) delete(fig));
startButton = uibutton(buttons,'Text','Start','Tag','start','Enable','off', ...
    'ButtonPushedFcn',@(~,~) start());
if isempty(sites.paths)
    siteField.Items = {'(no site file in config)'};
    siteField.Enable = false;
else
    labels = sites.names;
    if sites.active>0, labels(sites.active) = labels(sites.active)+"  (active)"; end
    siteField.Items = cellstr(labels);
    siteField.ItemsData = cellstr(sites.paths);
    siteField.Value = char(sites.paths(selected));
end
siteField.ValueChangedFcn = @(~,~) changeSite();
subjectField.ValueChangingFcn = @(~,event) refresh(event.Value);
subjectField.ValueChangedFcn = @(~,~) refresh();
for field = {sessionField,runField}
    field{1}.ValueChangedFcn = @(~,~) refresh();
end
taskField.ValueChangedFcn = @(~,~) changeTask();
overwriteField.ValueChangedFcn = @(~,~) confirmOverwrite();
fig.CloseRequestFcn = @(~,~) delete(fig);
changeSite();
try
    focus(subjectField); % R2022a or later; typing still works without it.
catch
end
% Start, Cancel and the close button all delete the window; waitfor also
% returns when that happened before it was reached.
waitfor(fig);
drawnow;

    function changeSite()
        % Show the chosen site's display settings, then recheck the request.
        siteReady = false;
        viewingLabel.Text = '';
        siteNotes.Text = '';
        siteInfo.FontColor = levelColor('note');
        if isempty(sites.paths)
            siteInfo.Text = "No site file in config/";
            siteNotes.Text = "Run setup_aot, then fill in config/site.local.yml.";
            siteNotes.FontColor = levelColor('error');
        else
            chosen = siteField.Value;
            summary = ephys.siteSummary(chosen);
            % A newer site choice made while this one was read shows its own lines.
            if ~strcmp(siteField.Value,chosen), return; end
            [lines,level] = ephys.siteSummaryText(summary);
            notes = lines(2:end);
            if strlength(summary.error)>0
                % Errors can be long: the info row keeps a short title.
                lines = "Site file error";
                notes = summary.error;
                siteInfo.FontColor = levelColor('error');
            end
            if sites.active==0 || ~ephys.samePath(sites.paths(sites.active),chosen)
                notes(end+1) = "Start makes this the active site (config/active_site.yml).";
            end
            siteInfo.Text = lines(1);
            siteNotes.Text = notes;
            siteNotes.FontColor = levelColor(level);
            [text,viewingLevel] = ephys.viewingDistanceText(summary.viewing);
            viewingLabel.Text = text;
            viewingLabel.FontColor = levelColor(viewingLevel);
            siteReady = strlength(summary.error)==0;
        end
        % Short lines take one row; longer warnings wrap onto a second one.
        grid.RowHeight{3} = textHeight(viewingLabel.Text,64);
        grid.RowHeight{4} = textHeight(siteNotes.Text,72);
        refresh();
    end

    function [preview,values] = refresh(subjectText)
        % Show the output folder and schedule for the current entries.
        if nargin<1, subjectText = subjectField.Value; end
        values = struct('site',"",'subject',strtrim(string(subjectText)), ...
            'session',sessionField.Value,'run',runField.Value, ...
            'task',string(taskField.Value),'overwrite',overwriteField.Value);
        if ~isempty(sites.paths), values.site = string(siteField.Value); end
        preview = struct('ok',false);
        startButton.Enable = false;
        previewRunId = "";
        if ~siteReady
            clearOverwrite();
            show("Choose a valid site first.",'error');
            return;
        end
        if strlength(values.subject)==0
            clearOverwrite();
            show("Enter a subject number (3 becomes sub-003) or a label such as patientname.",'note');
            return;
        end
        ask = @(overwrite) ephys.previewRunRequest(values.subject,values.session,values.run, ...
            'Task',values.task,'Overwrite',overwrite,'Site',values.site,options{:});
        preview = ask(values.overwrite);
        if strlength(preview.error)>0
            clearOverwrite();
            show(preview.error,'error');
            return;
        end
        previewRunId = preview.run_id;
        % A tick confirms only the run it was given for.
        if values.overwrite && preview.run_id~=confirmedRunId
            clearOverwrite();
            values.overwrite = false;
            preview = ask(false);
        end
        [~,scheduleName,scheduleExt] = fileparts(preview.schedule_path);
        source = "own number";
        if startsWith(preview.schedule_set_source,"subject map")
            source = "subject map";
        end
        scheduleOrigin = preview.schedule_set_source; % e.g. the shared practice schedule
        if ~isempty(preview.schedule_set)
            scheduleOrigin = "set "+preview.schedule_set+", "+source;
        end
        [dateFolder,runName] = fileparts(preview.output_folder);
        [outputRoot,dateName] = fileparts(dateFolder);
        lines = ["Output:  "+fullfile(dateName,runName); "In:  "+outputRoot; ...
            "Schedule:  "+scheduleName+scheduleExt+"  ("+scheduleOrigin+")"];
        level = 'note';
        if preview.exists && ~values.overwrite
            lines(end+1) = "This folder already exists today. Change the run, or tick " + ...
                "Overwrite to keep the old folder under a _replaced name.";
            level = 'error';
        elseif preview.exists
            lines(end+1) = "The existing folder will be renamed ..._replaced-<time>; " + ...
                "nothing is deleted.";
            level = 'warning';
        end
        if ~isempty(preview.other_dates) && ~values.overwrite
            lines(end+1) = "Already recorded on "+strjoin(preview.other_dates,", ")+ ...
                ". Check subject, session and run, or tick Overwrite to record it again.";
            level = 'error';
        elseif ~isempty(preview.other_dates)
            lines(end+1) = "Recording again: this run is also in "+ ...
                strjoin(preview.other_dates,", ")+"; that folder is not changed.";
            if level=="note", level = 'warning'; end
        end
        show(lines,level);
        startButton.Enable = preview.ok;
    end

    function changeTask()
        % The memory test has one schedule per session, saved as run 1, and
        % the practice task one shared schedule, recorded as run 1.
        if any(taskField.Value==["memory","practice"])
            if runField.Enable, videoRun = runField.Value; end
            runField.Value = 1;
            runField.Enable = false;
        else
            runField.Enable = true;
            runField.Value = videoRun;
        end
        refresh();
    end

    function confirmOverwrite()
        % Ticking confirms the run shown now; any other run needs a new tick.
        confirmedRunId = "";
        if overwriteField.Value, confirmedRunId = previewRunId; end
        refresh();
    end

    function clearOverwrite()
        overwriteField.Value = false;
        confirmedRunId = "";
    end

    function show(text,level)
        previewLabel.Text = text;
        previewLabel.FontColor = levelColor(level);
    end

    function start()
        [preview,values] = refresh();
        if ~preview.ok, return; end
        try
            ephys.setActiveSite(values.site);
        catch cause
            show("Could not select the site: "+string(cause.message),'error');
            return;
        end
        choice = values;
        delete(fig);
    end
end

function [site,rest] = takeSite(args)
% Separate a Site name-value pair from the other dialog arguments.
site = "";
rest = {};
k = 1;
while k<=numel(args)
    if k<numel(args) && (ischar(args{k}) || isstring(args{k})) && strcmpi(args{k},'Site')
        site = string(args{k+1});
    else
        rest = [rest,args(k:min(k+1,numel(args)))]; %#ok<AGROW>
    end
    k = k+2;
end
end

function height = textHeight(text,lineChars)
% Row height for label text: 16 px per line, assuming lineChars characters
% fit on a line of the dialog's second column. Empty text takes no row.
text = string(text);
text = text(strlength(text)>0);
lines = sum(max(1,ceil(strlength(text)/lineChars)));
height = 16*lines;
end

function color = levelColor(level)
% Text colour for 'note', 'warning' and 'error' lines.
colors = struct('note',[0.15 0.15 0.15],'warning',[0.75 0.4 0],'error',[0.75 0 0]);
color = colors.(level);
end
