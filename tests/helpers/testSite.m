function site = testSite(action)
%TESTSITE Isolated test configuration with placeholder assets, never local data.
persistent folder cleanup
if nargin>0 && string(action)=="cleanup"
    cleanup=[]; folder=[]; site="";
    return;
end
if isempty(folder) || ~isfolder(folder)
    folder=tempname; mkdir(folder);
    cleanup=onCleanup(@() removeFolder(folder));
    root=ephys.projectRoot();
    settings=ephys.readYaml(fullfile(root,'tests','fixtures','site.test.yml'));
    settings.paths=struct('video_root',fullfile(folder,'originals'), ...
        'picture_root',fullfile(folder,'pictures'),'output_root',fullfile(folder,'outputs'));
    settings.playback=struct('native_media_root',fullfile(folder,'copies'));
    for directory=[string(struct2cell(settings.paths));string(settings.playback.native_media_root)]'
        mkdir(directory);
    end
    % File existence is enough for config validation; decoders use their own
    % synthetic maps/texture callbacks and never open these placeholders.
    names=strings(0,1);
    for run=[1 8]
        filename=sprintf('experiment_settings_sub_01_ses_01_run_%02d.yml',run);
        schedule=ephys.readYaml(fullfile(root,'config','runs','main',filename));
        names=[names;string(schedule.stimuli.movie_files(:))]; %#ok<AGROW>
    end
    names=unique(names(names~="blank"));
    for name=names'
        fid=fopen(fullfile(settings.paths.video_root,name),'w');
        assert(fid>=0,'test:FixtureWrite','Could not create placeholder.');
        fprintf(fid,'configuration fixture, not a playable movie'); fclose(fid);
    end
    yaml.dumpFile(fullfile(folder,'site.yml'),settings,'block');
end
site=string(fullfile(folder,'site.yml'));
end

function removeFolder(folder)
if isfolder(folder), rmdir(folder,'s'); end
end
