function [text,level] = viewingDistanceText(v)
%VIEWINGDISTANCETEXT One line for the run dialog from ephys.viewingDistance.
% level is 'note', 'warning' or 'error'. text is empty when no target angle
% is configured. The movie angle at the suggested distance is shown when it
% differs from the target by more than 0.05 degrees on either axis.
text = "";
level = 'note';
times = char(215); degree = char(176);
switch v.status
    case "ok"
        text = sprintf('Viewing distance:  %.1f cm (eye to screen; movie %.2f %s %.2f%s)', ...
            v.distance_cm,v.target_size_deg(1),times,v.target_size_deg(2),degree);
        if any(abs(v.size_deg-v.target_size_deg)>0.05)
            text = sprintf(['Viewing distance:  %.1f cm gives %.2f %s %.2f%s, not ' ...
                '%.2f %s %.2f%s. Check display.screen_size_cm.'],v.distance_cm, ...
                v.size_deg(1),times,v.size_deg(2),degree, ...
                v.target_size_deg(1),times,v.target_size_deg(2),degree);
            level = 'warning';
        end
    case "no_screen_size"
        text = 'Viewing distance:  set display.screen_size_cm in the site file.';
        level = 'warning';
    case "invalid"
        text = "Viewing distance:  "+string(v.message);
        level = 'error';
end
text = string(text);
end
