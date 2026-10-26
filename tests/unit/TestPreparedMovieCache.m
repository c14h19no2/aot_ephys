classdef TestPreparedMovieCache < matlab.unittest.TestCase
    methods (Test)
        function reuseAndRepeatBeginAtSourceZeroWithoutRedecoding(tc)
            [cache,snapshot,guard]=TestPreparedMovieCache.fixture(128); %#ok<ASGLU>
            tc.verifyTrue(cache.preload('a.mp4',.1));
            tc.verifyTrue(cache.preload('b.mp4',.1));
            tc.verifyTrue(cache.ensureResident());
            tc.verifyEqual(snapshot().resident_requests,snapshot().live);
            [player,hit]=cache.prepare('a.mp4',.1);
            tc.verifyTrue(hit);
            player.start(10); player.draw([0 0 2 2],10.12); player.stop();
            tc.verifyEqual(player.info().source_frame_index,3);
            [again,hit]=cache.prepare('a.mp4',.1);
            tc.verifyTrue(hit);
            tc.verifyEqual(again.info().source_frame_index,0);
            tc.verifyEqual(again.info().pts,1);
            tc.verifyFalse(again.Running);
            tc.verifyTrue(isnan(again.StartFlip));
            tc.verifyEqual(snapshot().decode_count,2);
            tc.verifyEqual(cache.TextureBytes,128);
            tc.verifyEqual(numel(snapshot().live),8);
            cache.close();
            tc.verifyEmpty(snapshot().live);
        end
        function aggregateBudgetRetainsTheLoadedMovie(tc)
            [cache,snapshot,guard]=TestPreparedMovieCache.fixture(96); %#ok<ASGLU>
            tc.verifyTrue(cache.preload('a.mp4',.1));
            tc.verifyFalse(cache.preload('b.mp4',.1)); % Each fits 96, both exceed it.
            tc.verifyTrue(cache.contains('a.mp4'));
            tc.verifyFalse(cache.contains('b.mp4'));
            tc.verifyEqual(cache.TextureBytes,64);
            tc.verifyEqual(numel(snapshot().live),4);
            tc.verifyEmpty(snapshot().closed);
            cache.close();
            tc.verifyEmpty(snapshot().live);
        end
        function cacheMissReleasesTheBatchBeforeAllocatingAnother(tc)
            [cache,snapshot,guard]=TestPreparedMovieCache.fixture(128); %#ok<ASGLU>
            cache.preload('a.mp4',.1); cache.preload('b.mp4',.1);
            [player,hit]=cache.prepare('c.mp4',.1);
            tc.verifyFalse(hit);
            tc.verifyFalse(cache.contains('a.mp4'));
            tc.verifyTrue(cache.contains('c.mp4'));
            tc.verifyEqual(player.info().source_frame_index,0);
            tc.verifyEqual(cache.TextureBytes,64);
            tc.verifyEqual(numel(snapshot().closed),8);
            tc.verifyEqual(numel(snapshot().live),4);
            tc.verifyEqual(snapshot().peak_live,8);
            cache.close();
            tc.verifyEmpty(snapshot().live);
        end
        function interruptedUploadReleasesPartialTextures(tc)
            [cache,snapshot,guard]=TestPreparedMovieCache.fixture(512); %#ok<ASGLU>
            cache.preload('a.mp4',.1);
            tc.verifyError(@() cache.preload('large.mp4',.1,@abort), 'ephys:UserAbort');
            tc.verifyEqual(cache.TextureBytes,64);
            tc.verifyTrue(cache.contains('a.mp4'));
            tc.verifyFalse(cache.contains('large.mp4'));
            tc.verifyEqual(numel(snapshot().live),4);
            tc.verifyEqual(numel(snapshot().closed),8);
            cache.close(); cache.close();
            tc.verifyEmpty(snapshot().live);
            function abort(fraction)
                if fraction>0, error('ephys:UserAbort','Cancel loading.'); end
            end
        end
        function firstMovieCannotExceedBudget(tc)
            [cache,snapshot,guard]=TestPreparedMovieCache.fixture(32); %#ok<ASGLU>
            tc.verifyError(@() cache.preload('a.mp4',.1),'ephys:TextureBudget');
            tc.verifyEqual(cache.TextureBytes,0);
            tc.verifyEmpty(snapshot().live);
        end
        function preloadCountIsConfigurableAndValidated(tc)
            [c,~]=ephys.loadConfig("video",fullfile(ephys.projectRoot(), ...
                'config','runs','debug_blank.yml'), ...
                testSite(),true,"");
            tc.verifyEqual(c.playback.startup_preload_movies,2);
            c.playback.backend='frames';
            for value=[0,1,4]
                c.playback.startup_preload_movies=value;
                ephys.validateConfig(c);
            end
            for value=[-1,.5,NaN,Inf]
                c.playback.startup_preload_movies=value;
                tc.verifyError(@() ephys.validateConfig(c),'ephys:StartupPreload');
            end
        end
    end
    methods (Static)
        function [cache,snapshot,guard]=fixture(limit)
            folder=tempname; mkdir(folder);
            names=["a.mp4","b.mp4","c.mp4","large.mp4"];
            inventory=repmat(struct('path',"",'sha256',"",'duration_s',1, ...
                'width_px',2,'height_px',2),4,1);
            for k=1:4
                inventory(k).path=names(k); inventory(k).sha256="hash"+string(k);
            end
            nextTexture=100; live=[]; closed=[]; decodeCount=0; peakLive=0; residentRequests=[];
            factory=@(window,playback,media,mapDir) ephys.FrameMoviePlayer( ...
                window,playback,media,mapDir,@screen,@() 10,@decode);
            cache=ephys.PreparedMovieCache(1,struct('max_texture_bytes',limit), ...
                inventory,folder,factory);
            snapshot=@snapshotState;
            guard=onCleanup(@() TestPreparedMovieCache.cleanupFixture(cache,folder));
            function value=snapshotState()
                value=struct('decode_count',decodeCount,'live',live, ...
                    'closed',closed,'peak_live',peakLive,'resident_requests',residentRequests);
            end
            function [map,rawPath]=decode(path,~,temporary,~)
                decodeCount=decodeCount+1;
                count=4;
                if string(path)=="large.mp4", count=16; end
                rawPath=fullfile(temporary,'frames.rgb');
                fid=fopen(rawPath,'wb');
                fwrite(fid,uint8(ones(count*12,1)),'uint8'); fclose(fid);
                pts=(0:count-1)'*.04;
                map=struct('frame_count',count,'width_px',2,'height_px',2, ...
                    'source_pts_s',pts+1,'relative_pts_s',pts);
            end
            function varargout=screen(command,varargin)
                switch command
                    case 'MakeTexture'
                        nextTexture=nextTexture+1; live(end+1)=nextTexture;
                        peakLive=max(peakLive,numel(live)); varargout={nextTexture};
                    case 'Close'
                        ids=varargin{1};
                        assert(all(ismember(ids,live)),'Test:DoubleClose','Invalid texture close.');
                        closed=[closed ids]; live=live(~ismember(live,ids)); varargout={};
                    case 'DrawTexture'
                        assert(ismember(varargin{2},live)); varargout={};
                    case 'PreloadTextures'
                        assert(all(ismember(varargin{2},live)));
                        residentRequests=[residentRequests varargin{2}]; varargout={1};
                    otherwise
                        error('Test:UnexpectedScreen','Unexpected command %s',command);
                end
            end
        end
        function cleanupFixture(cache,folder)
            cache.close(); rmdir(folder,'s');
        end
    end
end
