classdef TestNativePreparation < matlab.unittest.TestCase
    methods (Test)
        function allDirectoryIncludesOnlyMP4Files(tc)
            [folder,site,guard]=TestNativePreparation.fixture(); %#ok<ASGLU>
            originals=fullfile(folder,'originals');
            for name=["0002_rv.MP4","0001_fw.mp4","notes.txt","._0001_fw.mp4"]
                fid=fopen(fullfile(originals,name),'w'); fclose(fid);
            end
            mkdir(fullfile(originals,'folder.mp4'));
            r=ephys.resolveNativePreparation('Site',site);
            tc.verifyEqual(r.mode,"all videos");
            tc.verifyEqual(r.sources,fullfile(string(originals),["0001_fw.mp4";"0002_rv.MP4"]));
            tc.verifyEqual(ephys.nativeMediaRoot(r.playback),string(fullfile(folder,'copies')));
        end
        function explicitSiteAndSavedScheduleModes(tc)
            r=ephys.resolveNativePreparation('Site',testSite());
            [sitePath,selectionPath]=ephys.resolveSitePath(testSite());
            tc.verifyEqual(r.site_path,sitePath);
            tc.verifyEqual(r.site_selection_path,selectionPath);
            tc.verifyEqual(r.mode,"all videos");
            r=ephys.resolveNativePreparation(1,1,8,'Site',testSite());
            tc.verifyEqual(r.mode,"saved schedule");
            tc.verifyEqual(r.site_path,sitePath);
            tc.verifyEqual(r.site_selection_path,selectionPath);
            tc.verifyNumElements(r.sources,67);
            tc.verifyEqual(numel(unique(r.sources)),67);
            tc.verifyFalse(any(endsWith(r.sources,"blank")));
        end
        function absentOrEmptyVideoDirectoryFailsBeforeConversion(tc)
            [folder,site,guard]=TestNativePreparation.fixture(); %#ok<ASGLU>
            tc.verifyError(@() prepare_aot_ephys_native_media('Site',site), ...
                'ephys:NativePreparationNoVideos');
            rmdir(fullfile(folder,'originals'));
            tc.verifyError(@() prepare_aot_ephys_native_media('Site',site),'ephys:VideoRoot');
        end
        function incompleteIDsAndMemoryTaskAreRejected(tc)
            tc.verifyError(@() prepare_aot_ephys_native_media(1),'ephys:NativePreparationArguments');
            tc.verifyError(@() prepare_aot_ephys_native_media(1,1),'ephys:NativePreparationArguments');
            tc.verifyError(@() prepare_aot_ephys_native_media(1,1,1,'Task','memory','Site',testSite()), ...
                'ephys:NativePreparationTask');
        end
    end
    methods (Static)
        function [folder,site,guard]=fixture()
            folder=tempname; mkdir(folder); mkdir(fullfile(folder,'originals'));
            guard=onCleanup(@() rmdir(folder,'s'));
            site=fullfile(folder,'site.yml');
            c=struct('paths',struct('video_root',fullfile(folder,'originals')), ...
                'playback',struct('native_media_root',fullfile(folder,'copies')));
            yaml.dumpFile(site,c,'block');
        end
    end
end
