classdef TestNativeRuntime < matlab.unittest.TestCase
    methods (Test)
        function readsPortableMapsWithUnavailableTools(tc)
            [c,map,~,guard]=TestNativeRuntime.fixture(); %#ok<ASGLU>
            inventory=ephys.mediaInventory(c);
            tc.verifyNumElements(inventory,1);
            tc.verifyEqual(inventory.width_px,2);
            tc.verifyEqual(inventory.height_px,2);
            tc.verifyEqual(inventory.duration_s,.12);
            tc.verifyEqual(inventory.fps,25,'AbsTol',1e-12);
            tc.verifyEqual(inventory.source_pts_s,[1 1.04 1.08]);
            tc.verifyEqual(inventory.display_rect_px,[270 0 1170 900]);
            tc.verifyEqual(string(inventory.native_map.source), ...
                string(fullfile(c.paths.video_root,'test_fw.mp4')));
            tc.verifyEqual(string(inventory.native_map.path), ...
                string(fullfile(c.playback.native_media_root,'test_fw.mp4')));
            tc.verifyEqual(inventory.native_map.conversion_source,map.source);
        end

        function sessionConstructorSkipsToolResolution(tc)
            [fixture,~,folder,guard]=TestNativeRuntime.fixture(); %#ok<ASGLU>
            [c,p]=TestNativeRuntime.sessionConfig(fixture,folder);
            job=ephys.Session(c,p,"native_runtime",ephys.DummyTriggerBackend());
            cleanup=onCleanup(@() job.close());
            tc.verifyEqual(job.Config.playback.ffmpeg_path,fixture.playback.ffmpeg_path);
            tc.verifyEqual(job.Config.playback.ffprobe_path,fixture.playback.ffprobe_path);
            tc.verifyNumElements(job.Inventory,1);
            tc.verifyTrue(isfile(fullfile(job.OutputDir,'frame_maps','test_fw.json')));
            job.stopPresentation();
            job.finish("aborted","Constructor-only dependency test; no presentation");
        end

        function originalsAreOptionalForNativeRuns(tc)
            [fixture,~,folder,guard]=TestNativeRuntime.fixture(); %#ok<ASGLU>
            [c,p]=TestNativeRuntime.sessionConfig(fixture,folder);
            inventory=ephys.mediaInventory(c);
            tc.verifyTrue(inventory.original_present);
            tc.verifyEqual(inventory.size_bytes,numel('original fixture bytes'));
            original=fullfile(c.paths.video_root,'test_fw.mp4');
            delete(original);
            ephys.validateConfig(c);   % native playback reads only the copies
            inventory=ephys.mediaInventory(c);
            tc.verifyFalse(inventory.original_present);
            tc.verifyTrue(isnan(inventory.size_bytes));   % unknown, not zero
            tc.verifyTrue(isfile(inventory.native_path));
            % The frames backend decodes the originals, so it still needs them.
            frames=c; frames.playback.backend='frames';
            tc.verifyError(@() ephys.validateConfig(frames),'ephys:MissingVideo');
            frames.paths.video_root='';
            tc.verifyError(@() ephys.validateConfig(frames),'ephys:VideoRoot');
            % With no original folder at all, a session still starts.
            c.paths.video_root='';
            ephys.validateConfig(c);
            job=ephys.Session(c,p,"native_runtime",ephys.DummyTriggerBackend());
            cleanup=onCleanup(@() job.close());
            tc.verifyFalse(job.Inventory.original_present);
            tc.verifyTrue(isfile(fullfile(job.OutputDir,'frame_maps','test_fw.json')));
            job.stopPresentation();
            job.finish("aborted","Constructor-only test without originals; no presentation");
        end

        function missingMediaStopsSessionWithoutCleanupWarnings(tc)
            [fixture,~,folder,guard]=TestNativeRuntime.fixture(); %#ok<ASGLU>
            [c,p]=TestNativeRuntime.sessionConfig(fixture,folder);
            delete(fullfile(c.playback.native_media_root,'test_fw.json'));
            % The half-built Session is cleaned up before the error reaches the caller.
            identifier=tc.verifyWarningFree(@() TestNativeRuntime.errorIdentifier( ...
                @() ephys.Session(c,p,"native_runtime",ephys.DummyTriggerBackend())));
            tc.verifyEqual(identifier,'ephys:NativeMediaMissing');
            tc.verifyFalse(isfolder(c.paths.output_root));
        end

        function missingMediaFailsButVideoBytesAreNotHashed(tc)
            [c,map,~,guard]=TestNativeRuntime.fixture(); %#ok<ASGLU>
            file=fullfile(c.playback.native_media_root,'test_fw.json');
            delete(file);
            tc.verifyError(@() ephys.mediaInventory(c),'ephys:NativeMediaMissing');
            TestNativeRuntime.writeMap(c,map);
            % Changed bytes are found by verify_aot_ephys_media, not at run start.
            source=fullfile(c.paths.video_root,'test_fw.mp4');
            fid=fopen(source,'a'); fwrite(fid,uint8(1)); fclose(fid);
            native=fullfile(c.playback.native_media_root,'test_fw.mp4');
            fid=fopen(native,'a'); fwrite(fid,uint8(1)); fclose(fid);
            inventory=ephys.mediaInventory(c);
            tc.verifyEqual(inventory.sha256,"");
            tc.verifyFalse(isfield(inventory,'native_sha256'));
            tc.verifyEqual(string(inventory.native_map.sha256),string(map.sha256));
            tc.verifyEqual(string(inventory.native_map.source_sha256),string(map.source_sha256));
            delete(native);
            tc.verifyError(@() ephys.mediaInventory(c),'ephys:NativeMediaMissing');
        end

        function invalidMetadataAndShortSlotsRemainRejected(tc)
            [c,map,~,guard]=TestNativeRuntime.fixture(); %#ok<ASGLU>
            invalid={rmfield(map,'width_px'), ...
                setfield(map,'width_px',0), ... %#ok<SFLD>
                setfield(map,'frame_count',0), ... %#ok<SFLD>
                setfield(map,'relative_pts_s',[0 .08 .04]), ... %#ok<SFLD>
                setfield(map,'source_pts_s',[1 1.04 1.09]), ... %#ok<SFLD>
                setfield(map,'duration_s',.04), ... %#ok<SFLD>
                setfield(map,'lossless_yuv_equal',false)}; %#ok<SFLD>
            for k=1:numel(invalid)
                TestNativeRuntime.writeMap(c,invalid{k});
                tc.verifyError(@() ephys.mediaInventory(c),'ephys:NativeMap');
            end
            TestNativeRuntime.writeMap(c,map);
            c.protocol.video_duration_s=.2;
            tc.verifyError(@() ephys.mediaInventory(c),'ephys:ShortVideo');
            c.protocol.video_duration_s=.12;
            c.photodiode=struct('enabled',true,'rect_px',{{280,100,300,120}});
            tc.verifyError(@() ephys.mediaInventory(c),'ephys:PhotodiodeOverlap');
            c.photodiode.approved_placement=true;
            tc.verifyNumElements(ephys.mediaInventory(c),1);
        end

        function offlinePreparationStillRequiresTools(tc)
            [c,~,folder,guard]=TestNativeRuntime.fixture(); %#ok<ASGLU>
            site=fullfile(folder,'site.yml');
            yaml.dumpFile(site,struct('paths',c.paths,'playback',c.playback),'block');
            tc.verifyError(@() prepare_aot_ephys_native_media('Site',site),'ephys:MediaToolMissing');
        end
    end

    methods (Static)
        function [c,map,folder,guard]=fixture()
            folder=tempname; mkdir(folder);
            guard=onCleanup(@() rmdir(folder,'s'));
            originals=fullfile(folder,'originals with spaces'); mkdir(originals);
            copies=fullfile(folder,'copies with spaces'); mkdir(copies);
            source=fullfile(originals,'test_fw.mp4');
            fid=fopen(source,'w'); fwrite(fid,'original fixture bytes'); fclose(fid);
            native=fullfile(copies,'test_fw.mp4');
            fid=fopen(native,'w'); fwrite(fid,'native fixture bytes'); fclose(fid);
            map=struct('schema_version',1,'source','Z:\old\original.mp4', ...
                'path','Z:\old\native.mp4','sha256',ephys.sha256(native), ...
                'source_sha256',ephys.sha256(source),'frame_count',3, ...
                'width_px',2,'height_px',2,'duration_s',.12, ...
                'source_pts_s',[1 1.04 1.08],'relative_pts_s',[0 .04 .08], ...
                'decoded_yuv_md5',{{'a','b','c'}},'lossless_yuv_equal',true,'pts_equal',true);
            c=struct('task_kind',"video",'schedule',["test_fw.mp4";"blank";"test_fw.mp4"], ...
                'paths',struct('video_root',originals), ...
                'playback',struct('backend','native','native_media_root',copies, ...
                    'ffmpeg_path',fullfile(folder,'missing_ffmpeg.exe'), ...
                    'ffprobe_path',fullfile(folder,'missing_ffprobe.exe')), ...
                'protocol',struct('video_duration_s',.12), ...
                'display',struct('resolution_px',{{1440,900}}), ...
                'stimulus',struct('movie_scale',1));
            TestNativeRuntime.writeMap(c,map);
        end

        function [c,p]=sessionConfig(fixture,folder)
            root=ephys.projectRoot();
            [c,p]=ephys.loadConfig("video",fullfile(root,'config','runs','debug_blank.yml'), ...
                testSite(),false,"");
            c.schedule=fixture.schedule;
            c.paths.video_root=fixture.paths.video_root;
            c.paths.output_root=fullfile(folder,'output');
            c.playback=ephys.mergeConfig(c.playback,fixture.playback);
            c.protocol.video_duration_s=.12;
            ephys.validateConfig(c);
        end

        function identifier=errorIdentifier(fn)
            identifier='';
            try
                fn();
            catch cause
                identifier=cause.identifier;
            end
        end

        function writeMap(c,map)
            fid=fopen(fullfile(c.playback.native_media_root,'test_fw.json'),'w');
            guard=onCleanup(@() fclose(fid));
            fprintf(fid,'%s\n',jsonencode(map));
        end
    end
end
