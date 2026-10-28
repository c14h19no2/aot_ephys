classdef TestNativeMoviePlayer < matlab.unittest.TestCase
    methods(Test)
        function heldZeroAndNoRestartAtOnset(tc)
            [p,snapshot,guard]=TestNativeMoviePlayer.fixture([0 .04 .08]); %#ok<ASGLU>
            p.prepare(.1);
            p.draw([0 0 2 2],1000); tc.verifyEqual(p.info().source_frame_index,0);
            tc.verifyEqual(snapshot().rates,1);
            p.start(10); tc.verifyEqual(snapshot().rates,1);
            p.draw([0 0 2 2],10.04);
            tc.verifyEqual(p.info().source_frame_index,1);
            tc.verifyEqual(p.info().pts,1.04);
            tc.verifyEqual(p.info().raw_pts,.04);
            tc.verifyEqual(p.info().pts_offset,1);
            p.closeCurrent();
            tc.verifyEmpty(snapshot().live);
            tc.verifyEqual(snapshot().rates,[1 0]);
        end
        function anomalousPTSContinuesWithTruthfulIdentityAndReleasesTextures(tc)
            streams={[.04 .08],[0 0],[0 .08],[0 NaN]};
            expectedFirst=[1 0 0 0]; expectedLast=[2 0 2 NaN];
            for k=1:numel(streams)
                stream=streams{k};
                [p,snapshot,guard]=TestNativeMoviePlayer.fixture(stream); %#ok<ASGLU>
                p.prepare(.1); tc.verifyEqual(p.info().source_frame_index,expectedFirst(k));
                p.start(10); p.draw([0 0 2 2],10.08);
                tc.verifyEqual(p.info().source_frame_index,expectedLast(k));
                tc.verifyEqual(p.info().raw_pts,stream(end));
                tc.verifyTrue(any(string({p.QCIssues.kind})=="pts_sequence_mismatch"));
                if isnan(expectedLast(k)), tc.verifyTrue(isnan(p.info().pts)); end
                p.closeCurrent(); tc.verifyEmpty(snapshot().live);
                clear guard
            end
        end
        function underrunAndEarlyEOSHoldTheLastTexture(tc)
            [p,snapshot,guard]=TestNativeMoviePlayer.fixture([0 Inf -Inf]); %#ok<ASGLU>
            p.prepare(.1); p.start(10);
            p.draw([0 0 2 2],10.04);
            tc.verifyEqual(p.Status,"decoder_underrun");
            tc.verifyEqual(snapshot().fetches,2);
            p.draw([0 0 2 2],10.08);
            tc.verifyEqual(p.Status,"end_of_stream");
            tc.verifyEqual(p.info().source_frame_index,0);
            tc.verifyTrue(contains(p.info().qc_flags,"early_end_of_stream"));
            tc.verifyEqual(snapshot().live,p.Texture);
        end
        function sourceSkipRecordedFromDisplayClock(tc)
            [p,~,guard]=TestNativeMoviePlayer.fixture([0 .04 .08]); %#ok<ASGLU>
            p.prepare(.1); p.start(10); p.draw([0 0 2 2],10.08);
            tc.verifyEqual(p.Status,"source_frame_skip");
            tc.verifyEqual(p.summary().display_skipped_source_indices,1);
            tc.verifyEqual(p.summary().decoded_source_indices,0:2);
        end
        function deadlineAndCancellationCleanAllResources(tc)
            [p,snapshot,guard]=TestNativeMoviePlayer.fixture([0 .04 .08]); %#ok<ASGLU>
            p.prepare(.1,[],9);
            tc.verifyEqual(p.PreparationOverrun,1);
            tc.verifyTrue(any(string({p.QCIssues.kind})=="load_deadline_overrun"));
            tc.verifyNotEmpty(p.Movie); p.closeCurrent(); tc.verifyEmpty(snapshot().live);
            clear guard
            [p,snapshot,guard]=TestNativeMoviePlayer.fixture([0 .04 .08]); %#ok<ASGLU>
            tc.verifyError(@() p.prepare(.1,@() error('test:Quit','Quit')), 'test:Quit');
            tc.verifyEmpty(snapshot().live); tc.verifyEmpty(p.Movie);
        end
        function repeatedFilenameUsesIndependentOccurrences(tc)
            [p,~,guard]=TestNativeMoviePlayer.fixture([0 .04 .08]); %#ok<ASGLU>
            media=struct('name',"test_fw.mp4",'native_map',p.Map);
            playback=struct('max_texture_bytes',96);
            created=0;
            queue=ephys.NativeMovieQueue(1,playback,media, ...
                ["test_fw.mp4","blank","test_fw.mp4","test_fw.mp4"],@factory);
            cleanup=onCleanup(@() queue.close()); %#ok<NASGU>
            queue.preload(1,.1); queue.preload(3,.1);
            tc.verifyEqual(created,2); tc.verifyEmpty(queue.nextToPrepare(1));
            [first,hit]=queue.prepare(1,.1); tc.verifyTrue(hit);
            first.start(10);
            pending=queue.snapshot();
            tc.verifyEqual([pending.trial_nr],[1 3]);
            tc.verifyEqual(pending(1).first_flip_getsecs,10);
            tc.verifyTrue(isnan(pending(2).first_flip_getsecs));
            tc.verifyEqual(pending(2).decoded_source_indices,0);
            queue.release(1);
            tc.verifyEqual(queue.nextToPrepare(2),4);
            [repeat,hit]=queue.prepare(3,.1); tc.verifyTrue(hit);
            tc.verifyEqual(repeat.info().source_frame_index,0);
            tc.verifyEqual(queue.TextureBytes,48);
            tc.verifyEqual(queue.snapshot().trial_nr,3);
            tc.verifyTrue(queue.preload(4,.1,[],9));
            tc.verifyEqual(queue.TextureBytes,96);
            pending=queue.snapshot(); tc.verifyEqual(pending(2).preparation_overrun_s,1);
            function value=factory(~)
                created=created+1;
                [value,~,~]=TestNativeMoviePlayer.fixture([0 .04 .08],false);
            end
        end
        function lookaheadUsesTheSameTrialIdentity(tc)
            [c,provenance]=ephys.loadConfig("video",fullfile(ephys.projectRoot(), ...
                'config','runs','debug_blank.yml'), ...
                testSite(),true,"");
            folder=tempname; mkdir(folder);
            cleanupFolder=onCleanup(@() rmdir(folder,'s')); %#ok<NASGU>
            c.paths.output_root=folder;
            job=ephys.Session(c,provenance,"context_test");
            cleanup=onCleanup(@() job.close()); %#ok<NASGU>
            ctx=job.TrialContexts{2};
            job.Log.event(ctx,"native_lookahead_ready","pre_fixation",10,[]);
            raw=struct('vbl',11,'stimulus',11,'returned',11,'missed',0);
            job.Log.flip(job.TrialContexts{2},"blank",1,raw,11,ephys.noFrame("blank"),"off");
            job.Log.event(job.TrialContexts{2},"blank_onset","blank",11,[]);
            r=ephys.reconstructRecords(job.Log.flipRecords(),job.Log.eventRecords(), ...
                repmat(ephys.emptyMarker(),0,1));
            tc.verifyEqual(r.run_qc.trial_count,1);
            tc.verifyEqual(r.trials.trial_nr,2);
            ids=cellfun(@(x) x.trial_id,job.TrialContexts);
            tc.verifyEqual(numel(unique(ids)),4);
            job.stopPresentation(); job.finish("aborted","Identity regression only; no display opened");
        end
        function cachePathsResolveLocallyAndMissingCopiesAreRejected(tc)
            folder=tempname; mkdir(folder);
            guard=onCleanup(@() rmdir(folder,'s')); %#ok<NASGU>
            source=fullfile(folder,'test_fw.mp4');
            fid=fopen(source,'w'); fprintf(fid,'original fixture bytes'); fclose(fid);
            sourceHash=string(ephys.sha256(source));
            copies=fullfile(folder,'copies'); mkdir(copies);
            native=fullfile(copies,'test_fw.mp4');
            fid=fopen(native,'w'); fprintf(fid,'native fixture bytes'); fclose(fid);
            map=struct('schema_version',1,'source','/old/site/original.mp4', ...
                'path','/old/site/native.mp4','sha256',ephys.sha256(native), ...
                'source_sha256',sourceHash,'frame_count',3,'width_px',2,'height_px',2, ...
                'duration_s',.12,'source_pts_s',[1 1.04 1.08], ...
                'relative_pts_s',[0 .04 .08],'decoded_yuv_md5',{{'a','b','c'}}, ...
                'lossless_yuv_equal',true,'pts_equal',true);
            fid=fopen(fullfile(copies,'test_fw.json'),'w');
            fprintf(fid,'%s',jsonencode(map)); fclose(fid);
            media=struct('kind',"video",'name',"test_fw.mp4",'path',string(source), ...
                'sha256',sourceHash,'width_px',2,'height_px',2,'duration_s',.12);
            playback=struct('native_media_root',copies);
            resolved=ephys.nativeInventory(media,playback);
            tc.verifyEqual(string(resolved.native_map.path),string(native));
            tc.verifyEqual(string(resolved.native_map.source),string(source));
            tc.verifyEqual(resolved.source_pts_s,[1 1.04 1.08]);
            tc.verifyEqual(resolved.native_map_path,string(fullfile(copies,'test_fw.json')));
            % Bytes are checked by verify_aot_ephys_media, not when maps are read.
            fid=fopen(native,'a'); fprintf(fid,' changed'); fclose(fid);
            resolved=ephys.nativeInventory(media,playback);
            tc.verifyEqual(string(resolved.native_map.sha256),string(map.sha256));
            delete(native);
            tc.verifyError(@() ephys.nativeInventory(media,playback),'ephys:NativeMediaMissing');
        end
        function nativeCopyDirectoryMustBeExplicit(tc)
            tc.verifyError(@() ephys.nativeMediaRoot(struct()),'ephys:NativeMediaRoot');
            for value={[], '', "", '   ', 'none', 'None', 'NONE', 'null', '~', NaN, ["a","b"]}
                playback=struct('native_media_root',value{1});
                tc.verifyError(@() ephys.nativeMediaRoot(playback),'ephys:NativeMediaRoot');
            end
            [c,~]=ephys.loadConfig("video",fullfile(ephys.projectRoot(), ...
                'config','runs','debug_blank.yml'), ...
                testSite(),true,"");
            for value={[], '', 'none'}
                bad=c; bad.playback.native_media_root=value{1};
                tc.verifyError(@() ephys.validateConfig(bad),'ephys:NativeMediaRoot');
            end
        end
    end
    methods(Static)
        function [p,snapshot,guard]=fixture(stream,makeGuard)
            if nargin<2, makeGuard=true; end
            map=struct('source','test_fw.mp4','path','native.mp4','duration_s',.12, ...
                'frame_count',3,'width_px',2,'height_px',2, ...
                'source_pts_s',[1 1.04 1.08],'relative_pts_s',[0 .04 .08]);
            playback=struct('native_buffer_s',3,'native_prepare_timeout_s',5);
            delivered=0; live=[]; rates=[];
            p=ephys.NativeMoviePlayer(1,playback,map,@screen,@() 10);
            snapshot=@state;
            guard=[];
            if makeGuard, guard=onCleanup(@() p.closeCurrent()); end
            function value=state()
                value=struct('rates',rates,'live',live,'fetches',delivered);
            end
            function varargout=screen(command,varargin)
                switch command
                    case 'OpenMovie'
                        assert(varargin{3}==4 && varargin{5}==2); varargout={20};
                    case 'GetMovieImage'
                        assert(varargin{3}==0); delivered=delivered+1;
                        if delivered>numel(stream) || stream(delivered)==-Inf, varargout={-1,NaN};
                        elseif stream(delivered)==Inf, varargout={0,NaN};
                        else
                            live(end+1)=100+delivered;
                            varargout={100+delivered,stream(delivered)};
                        end
                    case 'PlayMovie', rates(end+1)=varargin{2}; varargout={0};
                    case 'PreloadTextures', varargout={1};
                    case 'Close'
                        assert(ismember(varargin{1},live));
                        live(live==varargin{1})=[]; varargout={};
                    otherwise, varargout={};
                end
            end
        end
    end
end
