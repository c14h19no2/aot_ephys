classdef TestSiteChoice < matlab.unittest.TestCase
    % Site list, active-site selection and site lines for the run dialog.
    properties
        Folder
    end
    methods (TestMethodSetup)
        function useTemporaryConfig(tc)
            tc.Folder=string(tempname); mkdir(tc.Folder);
            tc.addTeardown(@() rmdir(tc.Folder,'s'));
            for name=["site.b_lab.yml","site.a_laptop.yml","site.example.yml"]
                TestSiteChoice.write(fullfile(tc.Folder,name),"display:"+newline+"  screen_index: 0");
            end
            TestSiteChoice.write(fullfile(tc.Folder,'active_site.yml'), ...
                "# Keep this comment."+newline+"site_file: site.b_lab.yml");
        end
    end
    methods (Test)
        function listsSitesAndMarksTheActiveOne(tc)
            sites=ephys.siteChoices(tc.Folder);
            tc.verifyEqual(sites.names,["a_laptop";"b_lab"]);
            tc.verifyEqual(sites.files,["site.a_laptop.yml";"site.b_lab.yml"]);
            tc.verifyEqual(sites.active,2);
            tc.verifyEqual(sites.activeError,"");
            delete(fullfile(tc.Folder,'active_site.yml'));
            sites=ephys.siteChoices(tc.Folder);
            tc.verifyEqual(sites.active,0);
            tc.verifyGreaterThan(strlength(sites.activeError),0);
        end
        function choosingASiteRewritesOnlyItsLine(tc)
            selection=fullfile(tc.Folder,'active_site.yml');
            chosen=fullfile(tc.Folder,'site.a_laptop.yml');
            tc.verifyTrue(ephys.setActiveSite(chosen,tc.Folder));
            text=string(fileread(selection));
            tc.verifyTrue(contains(text,"# Keep this comment."));
            tc.verifyTrue(contains(text,"site_file: site.a_laptop.yml"));
            tc.verifyFalse(contains(text,"b_lab"));
            tc.verifyEqual(ephys.resolveSitePath("",selection),chosen);
            before=dir(selection);
            tc.verifyFalse(ephys.setActiveSite(chosen,tc.Folder));
            tc.verifyEqual(dir(selection).datenum,before.datenum);
            tc.verifyEqual(ephys.siteChoices(tc.Folder).active,1);
        end
        function missingSelectionIsCreatedAndOutsideSitesUseFullPaths(tc)
            selection=fullfile(tc.Folder,'active_site.yml');
            delete(selection);
            chosen=fullfile(tc.Folder,'site.b_lab.yml');
            tc.verifyTrue(ephys.setActiveSite(chosen,tc.Folder));
            tc.verifyEqual(ephys.resolveSitePath("",selection),chosen);
            outside=fullfile(tc.Folder,'other place'); mkdir(outside);
            external=fullfile(outside,'site.remote.yml');
            TestSiteChoice.write(external,"display:"+newline+"  screen_index: 1");
            tc.verifyTrue(ephys.setActiveSite(external,tc.Folder));
            tc.verifyEqual(ephys.resolveSitePath("",selection),external);
            sites=ephys.siteChoices(tc.Folder);
            tc.verifyEqual(sites.active,3);
            tc.verifyEqual(sites.paths(3),external);
            tc.verifyError(@() ephys.setActiveSite(fullfile(tc.Folder,'site.none.yml'),tc.Folder), ...
                'ephys:SelectedSiteMissing');
        end
        function siteLinesShowScreenAndApproval(tc)
            s=struct('error',"",'screen_size_cm',[30.99 17.43],'resolution_px',[1920 1080], ...
                'refresh_hz',60,'approved',true);
            [text,level]=ephys.siteSummaryText(s);
            tc.verifyEqual(level,'note');
            tc.verifyNumElements(text,1);
            tc.verifyTrue(contains(text,"30.99") && contains(text,"17.43 cm"));
            tc.verifyTrue(contains(text,"1920") && contains(text,"1080 px"));
            tc.verifyTrue(contains(text,"60 Hz"));
            s.approved=false; s.screen_size_cm=[NaN NaN];
            [text,level]=ephys.siteSummaryText(s);
            tc.verifyEqual(level,'warning');
            tc.verifyTrue(contains(text(1),"size not set"));
            tc.verifyTrue(contains(text(2),"approved_for_acquisition"));
            s.error="bad file";
            [text,level]=ephys.siteSummaryText(s);
            tc.verifyEqual(level,'error');
            tc.verifyTrue(contains(text,"bad file"));
        end
    end
    methods (Static)
        function write(path,text)
            fid=fopen(path,'w'); fprintf(fid,'%s\n',text); fclose(fid);
        end
    end
end
