classdef TestSiteSelection < matlab.unittest.TestCase
    methods (Test)
        function relativeSelectionDoesNotDependOnCurrentFolder(tc)
            [folder,selector,site,guard] = TestSiteSelection.fixture(); %#ok<ASGLU>
            tc.applyFixture(matlab.unittest.fixtures.CurrentFolderFixture(tempdir));
            [selected,source] = ephys.resolveSitePath("",selector);
            tc.verifyEqual(selected,string(site));
            tc.verifyEqual(source,string(selector));
        end

        function absoluteSelectionAndExplicitOverrideWork(tc)
            [~,selector,site,guard] = TestSiteSelection.fixture(); %#ok<ASGLU>
            TestSiteSelection.write(selector,sprintf('site_file: ''%s''\n',site));
            tc.verifyEqual(ephys.resolveSitePath("",selector),string(site));
            % An explicit Site bypasses the selector, even if it is missing.
            delete(selector);
            [selected,source] = ephys.resolveSitePath("custom.yml",selector);
            tc.verifyEqual(selected,"custom.yml");
            tc.verifyEqual(source,"");
        end

        function editingSelectionTakesEffectOnNextCall(tc)
            [folder,selector,first,guard] = TestSiteSelection.fixture(); %#ok<ASGLU>
            second = fullfile(folder,'second.yml');
            copyfile(first,second);
            tc.verifyEqual(ephys.resolveSitePath("",selector),string(first));
            TestSiteSelection.write(selector,sprintf('site_file: second.yml\n'));
            tc.verifyEqual(ephys.resolveSitePath("",selector),string(second));
        end

        function emptyInvalidAndUnknownFieldsFailClearly(tc)
            [~,selector,~,guard] = TestSiteSelection.fixture(); %#ok<ASGLU>
            for value = ["null","none","''","'   '","[]","[a.yml, b.yml]","false","123"]
                TestSiteSelection.write(selector,"site_file: "+value+newline);
                tc.verifyError(@() ephys.resolveSitePath("",selector),'ephys:SiteSelection');
            end
            TestSiteSelection.write(selector,sprintf('site: site.local.yml\n'));
            tc.verifyError(@() ephys.resolveSitePath("",selector),'ephys:SiteSelection');
            TestSiteSelection.write(selector,sprintf('site_file: x.yml\nextra: 1\n'));
            tc.verifyError(@() ephys.resolveSitePath("",selector),'ephys:SiteSelection');
        end

        function missingFilesNeverFallBackToAnotherSite(tc)
            [~,selector,site,guard] = TestSiteSelection.fixture(); %#ok<ASGLU>
            delete(site);
            tc.verifyError(@() ephys.resolveSitePath("",selector),'ephys:SelectedSiteMissing');
            delete(selector);
            tc.verifyError(@() ephys.resolveSitePath("",selector),'ephys:SiteSelectionMissing');
        end

        function selectedDisplayAndSelectorAreRecorded(tc)
            [~,selector,site,guard] = TestSiteSelection.fixture(); %#ok<ASGLU>
            [sitePath,selectionPath] = ephys.resolveSitePath("",selector);
            settings = ephys.readYaml(site);
            settings.display.resolution_px = {1024,768};
            yaml.dumpFile(site,settings,'block');
            schedule = fullfile(ephys.projectRoot(),'config','runs','debug_blank.yml');
            [config,provenance] = ephys.loadConfig("video",schedule, ...
                sitePath,false,"",selectionPath);
            resolution = cell2mat(config.display.resolution_px);
            tc.verifyEqual(resolution(:)',[1024,768]);
            tc.verifyEqual(config.site_path,string(site));
            tc.verifyEqual(config.site_selection_path,string(selector));
            match = strcmp(provenance.files,selector);
            tc.verifyEqual(sum(match),1);
            tc.verifyEqual(string(provenance.sha256{match}),string(ephys.sha256(selector)));
        end
    end

    methods (Static)
        function [folder,selector,site,guard] = fixture()
            folder = [tempname ' site selection'];
            mkdir(folder);
            mkdir(fullfile(folder,'profiles'));
            guard = onCleanup(@() rmdir(folder,'s'));
            site = fullfile(folder,'profiles','site lab.yml');
            copyfile(testSite(),site);
            selector = fullfile(folder,'active_site.yml');
            TestSiteSelection.write(selector,sprintf('site_file: profiles/site lab.yml\n'));
        end

        function write(path,source)
            fid = fopen(path,'w');
            assert(fid>0);
            guard = onCleanup(@() fclose(fid));
            fprintf(fid,'%s',source);
        end
    end
end
