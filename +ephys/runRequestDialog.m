function choice = runRequestDialog(varargin)
%RUNREQUESTDIALOG Ask for subject, session, run, task and Overwrite.
% Returns a struct with subject, session, run, task and overwrite, or [] when
% cancelled. Each entry is checked with ephys.previewRunRequest, which also
% receives any extra name-value arguments (Site, SubjectMap). Start stays
% disabled until the request is valid and its output folder is free today.
% The window is deleted before returning, so it never overlaps the PTB window.
options = varargin;
choice = [];
fig = uifigure('Name','AOT ephys run','Position',[100 100 500 320]);
movegui(fig,'center');
grid = uigridlayout(fig,[7 2],'ColumnWidth',{70,'1x'}, ...
    'RowHeight',{24,24,24,24,24,'1x',28},'RowSpacing',6);
uilabel(grid,'Text','Subject');
subjectField = uieditfield(grid,'text','Placeholder','e.g. 3 or patientname','Tag','subject');
uilabel(grid,'Text','Session');
sessionField = uispinner(grid,'Limits',[1 Inf],'Value',1,'RoundFractionalValues','on', ...
    'ValueDisplayFormat','%d','HorizontalAlignment','left','Tag','session');
uilabel(grid,'Text','Run');
runField = uispinner(grid,'Limits',[1 Inf],'Value',1,'RoundFractionalValues','on', ...
    'ValueDisplayFormat','%d','HorizontalAlignment','left','Tag','run');
uilabel(grid,'Text','Task');
taskField = uidropdown(grid,'Items',{'video','memory'},'Value','video','Tag','task');
uilabel(grid,'Text','');
overwriteField = uicheckbox(grid,'Tag','overwrite', ...
    'Text','Overwrite (the existing folder is kept, renamed _replaced-<time>)');
previewLabel = uilabel(grid,'Text','','WordWrap','on', ...
    'VerticalAlignment','top','Tag','preview');
previewLabel.Layout.Column = [1 2];
buttons = uigridlayout(grid,[1 3],'ColumnWidth',{'1x',100,100},'Padding',0);
buttons.Layout.Column = [1 2];
uilabel(buttons,'Text','');
uibutton(buttons,'Text','Cancel','Tag','cancel','ButtonPushedFcn',@(~,~) delete(fig));
startButton = uibutton(buttons,'Text','Start','Tag','start','Enable','off', ...
    'ButtonPushedFcn',@(~,~) start());
subjectField.ValueChangingFcn = @(~,event) refresh(event.Value);
subjectField.ValueChangedFcn = @(~,~) refresh();
for field = {sessionField,runField,taskField,overwriteField}
    field{1}.ValueChangedFcn = @(~,~) refresh();
end
fig.CloseRequestFcn = @(~,~) delete(fig);
refresh();
try
    focus(subjectField); % R2022a or later; typing still works without it.
catch
end
% Start, Cancel and the close button all delete the window; waitfor also
% returns when that happened before it was reached.
waitfor(fig);
drawnow;

    function [preview,values] = refresh(subjectText)
        % Show the output folder and schedule for the current entries.
        if nargin<1, subjectText = subjectField.Value; end
        values = struct('subject',strtrim(string(subjectText)), ...
            'session',sessionField.Value,'run',runField.Value, ...
            'task',string(taskField.Value),'overwrite',overwriteField.Value);
        preview = struct('ok',false);
        startButton.Enable = false;
        if strlength(values.subject)==0
            show("Enter a subject number (3 becomes sub-003) or a label such as patientname.",'note');
            return;
        end
        preview = ephys.previewRunRequest(values.subject,values.session,values.run, ...
            'Task',values.task,'Overwrite',values.overwrite,options{:});
        if strlength(preview.error)>0
            show(preview.error,'error');
            return;
        end
        [~,scheduleName,scheduleExt] = fileparts(preview.schedule_path);
        source = "own number";
        if startsWith(preview.schedule_set_source,"subject map")
            source = "subject map";
        end
        [dateFolder,runName] = fileparts(preview.output_folder);
        [outputRoot,dateName] = fileparts(dateFolder);
        lines = ["Output:  "+fullfile(dateName,runName); "In:  "+outputRoot; ...
            "Schedule:  "+scheduleName+scheduleExt+"  (set "+preview.schedule_set+ ...
            ", "+source+")"];
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
        if ~isempty(preview.other_dates)
            lines(end+1) = "The same run name was also recorded on " + ...
                strjoin(preview.other_dates,", ")+". Check the session number.";
            if level=="note", level = 'warning'; end
        end
        show(lines,level);
        startButton.Enable = preview.ok;
    end

    function show(text,level)
        colors = struct('note',[0.15 0.15 0.15],'warning',[0.75 0.4 0],'error',[0.75 0 0]);
        previewLabel.Text = text;
        previewLabel.FontColor = colors.(level);
    end

    function start()
        [preview,values] = refresh();
        if ~preview.ok, return; end
        choice = values;
        delete(fig);
    end
end
