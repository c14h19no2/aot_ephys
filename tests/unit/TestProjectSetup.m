classdef TestProjectSetup < matlab.unittest.TestCase
    methods (Test)
        function setupCreatesLocalFilesAndPreservesUserChanges(tc)
            root=ephys.projectRoot(); folder=tempname; mkdir(folder);
            cleanup=onCleanup(@() rmdir(folder,'s')); %#ok<NASGU>
            for name=["site.example.yml","active_site.example.yml","subjects.example.yml"]
                copyfile(fullfile(root,'config',name),fullfile(folder,name));
            end
            created=ephys.initializeLocalConfig(folder);
            tc.verifyNumElements(created,3);
            tc.verifyTrue(isfile(fullfile(folder,'subjects.local.yml')));
            [site,selector]=ephys.resolveSitePath("",fullfile(folder,'active_site.yml'));
            tc.verifyEqual(site,string(fullfile(folder,'site.local.yml')));
            tc.verifyEqual(selector,string(fullfile(folder,'active_site.yml')));
            siteBytes=string(fileread(site))+newline+"# user edit"+newline;
            fid=fopen(site,'w'); fprintf(fid,'%s',siteBytes); fclose(fid);
            before=ephys.sha256(site);
            tc.verifyEmpty(ephys.initializeLocalConfig(folder));
            tc.verifyEqual(ephys.sha256(site),before);
        end
        function runtimeDefaultsDoNotMergeTheExampleProfile(tc)
            root=ephys.projectRoot(); shared=ephys.readYaml(fullfile(root,'config','experiment.yml'));
            settings=ephys.readYaml(testSite()); settings=rmfield(settings,'display');
            folder=tempname; mkdir(folder); cleanup=onCleanup(@() rmdir(folder,'s')); %#ok<NASGU>
            site=fullfile(folder,'site.yml'); yaml.dumpFile(site,settings,'block');
            [config,provenance]=ephys.loadConfig("video", ...
                fullfile(root,'config','runs','debug_blank.yml'),site,false,"");
            tc.verifyEqual(config.display.screen_index,shared.display.screen_index);
            tc.verifyEqual(config.display.expected_refresh_hz,shared.display.expected_refresh_hz);
            tc.verifyFalse(any(endsWith(string(provenance.files),'site.example.yml')));
        end
        function setupCanBeUsedWithoutDeviceConfiguration(tc)
            before=path; cleanup=onCleanup(@() path(before)); %#ok<NASGU>
            info=setup_aot('CreateLocalConfig',false);
            tc.verifyEqual(info.project_root,string(ephys.projectRoot()));
            tc.verifyEmpty(info.created_local_files);
            tc.verifyTrue(contains(path,fullfile(ephys.projectRoot(),'third_party','yaml')));
        end
        function sourceTreeContainsOneSupportedEntrypoint(tc)
            root=ephys.projectRoot();
            tc.verifyFalse(isfile(fullfile(root,'run_aot.m')));
            tc.verifyFalse(isfile(fullfile(root,'tests','TestAOT.m')));
            tc.verifyTrue(isfile(fullfile(root,'run_aot_ephys.m')));
            tc.verifyTrue(isfile(fullfile(root,'config','active_site.example.yml')));
        end
    end
end
