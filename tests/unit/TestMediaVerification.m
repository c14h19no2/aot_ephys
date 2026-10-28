classdef TestMediaVerification < matlab.unittest.TestCase
    % verify_aot_ephys_media: the offline check that replaced run-start hashing.
    methods (Test)
        function matchingFilesPassAndSidecarsAreSkipped(tc)
            [f,guard]=TestMediaVerification.fixture(); %#ok<ASGLU>
            output=evalc('results=verify_aot_ephys_media(''Site'',f.site);');
            tc.verifyEqual(height(results),1);
            tc.verifyEqual(results.name,"test_fw.mp4");
            tc.verifyTrue(results.ok);
            tc.verifyEqual(results.issues,"");
            tc.verifyEqual(results.original_sha256,string(f.map.source_sha256));
            tc.verifyEqual(results.native_sha256,string(f.map.sha256));
            tc.verifyTrue(contains(output,'All 1 videos match their native maps'));
        end
        function changedFilesAreReportedWithAWarning(tc)
            [f,guard]=TestMediaVerification.fixture(); %#ok<ASGLU>
            TestMediaVerification.append(f.native);
            results=tc.verifyWarning(@() verify_aot_ephys_media('Site',f.site), ...
                'ephys:MediaVerification');
            tc.verifyFalse(results.ok);
            tc.verifyEqual(results.issues,"native_changed");
            TestMediaVerification.append(f.original);
            results=ephys.verifyNativeMedia(f.original,f.playback);
            tc.verifyEqual(results.issues,"original_changed|native_changed");
            tc.verifyNotEqual(results.native_sha256,string(f.map.sha256));
        end
        function missingAndInvalidFilesAreReported(tc)
            [f,guard]=TestMediaVerification.fixture(); %#ok<ASGLU>
            delete(f.native);
            results=ephys.verifyNativeMedia(f.original,f.playback);
            tc.verifyEqual(results.issues,"native_missing");
            tc.verifyEqual(results.native_sha256,"");
            invalid=f.map; invalid.lossless_yuv_equal=false;
            TestMediaVerification.writeMap(f.mapPath,invalid);
            results=ephys.verifyNativeMedia(f.original,f.playback);
            tc.verifyEqual(results.issues,"map_invalid|native_missing");
            delete(f.mapPath);
            results=ephys.verifyNativeMedia(f.original,f.playback);
            tc.verifyEqual(results.issues,"map_missing|native_missing");
            results=ephys.verifyNativeMedia(fullfile(f.folder,'absent_fw.mp4'),f.playback);
            tc.verifyEqual(results.issues,"map_missing|original_missing|native_missing");
            tc.verifyFalse(results.ok);
        end
        function progressIsReportedForEveryFile(tc)
            [f,guard]=TestMediaVerification.fixture(); %#ok<ASGLU>
            seen=zeros(0,2);
            function record(k,n), seen(end+1,:)=[k n]; end
            ephys.verifyNativeMedia([f.original;f.original],f.playback,@record);
            tc.verifyEqual(seen,[1 2;2 2]);
        end
    end
    methods (Static)
        function [f,guard]=fixture()
            f.folder=tempname; mkdir(f.folder);
            guard=onCleanup(@() rmdir(f.folder,'s'));
            originals=fullfile(f.folder,'originals'); mkdir(originals);
            copies=fullfile(f.folder,'copies'); mkdir(copies);
            f.original=string(fullfile(originals,'test_fw.mp4'));
            TestMediaVerification.write(f.original,'original fixture bytes');
            % A macOS sidecar from a copied folder is not a video.
            TestMediaVerification.write(fullfile(originals,'._test_fw.mp4'),'sidecar');
            f.native=fullfile(copies,'test_fw.mp4');
            TestMediaVerification.write(f.native,'native fixture bytes');
            f.map=struct('schema_version',1,'source','Z:\old\original.mp4', ...
                'path','Z:\old\native.mp4','sha256',ephys.sha256(f.native), ...
                'source_sha256',ephys.sha256(f.original),'frame_count',3, ...
                'width_px',2,'height_px',2,'duration_s',.12, ...
                'source_pts_s',[1 1.04 1.08],'relative_pts_s',[0 .04 .08], ...
                'decoded_yuv_md5',{{'a','b','c'}},'lossless_yuv_equal',true,'pts_equal',true);
            f.mapPath=fullfile(copies,'test_fw.json');
            TestMediaVerification.writeMap(f.mapPath,f.map);
            f.playback=struct('backend','native','native_media_root',copies);
            f.site=fullfile(f.folder,'site.yml');
            yaml.dumpFile(f.site,struct('paths',struct('video_root',originals), ...
                'playback',f.playback),'block');
        end
        function write(path,text)
            fid=fopen(path,'w'); fwrite(fid,text); fclose(fid);
        end
        function append(path)
            fid=fopen(path,'a'); fwrite(fid,uint8(1)); fclose(fid);
        end
        function writeMap(path,map)
            fid=fopen(path,'w'); fprintf(fid,'%s\n',jsonencode(map)); fclose(fid);
        end
    end
end
