classdef TestFrameMoviePlayer < matlab.unittest.TestCase
    methods (Test)
        function parserPreservesTicksAndRejectsMissingFrames(tc)
            log=sprintf(['config in time_base: 1/1000, frame_rate: 25/1\n' ...
                'n: 0 pts: 1000 pts_time:1 fmt:rgb24 s:2x2 checksum:ABCDEF01\n' ...
                'n: 1 pts: 1040 pts_time:1.04 fmt:rgb24 s:2x2 checksum:ABCDEF02\n' ...
                'n: 2 pts: 1120 pts_time:1.12 fmt:rgb24 s:2x2 checksum:ABCDEF03\n']);
            map=ephys.parseDecodedFrames(log,36);
            tc.verifyEqual(map.source_frame_index,[0;1;2]);
            tc.verifyEqual(map.source_pts_s,[1;1.04;1.12],'AbsTol',1e-12);
            tc.verifyEqual(map.relative_pts_s,[0;.04;.12],'AbsTol',1e-12);
            tc.verifyError(@() ephys.parseDecodedFrames(log,24),'ephys:FrameMap');
            bad=strrep(log,'n: 1 pts: 1040','n: 2 pts: 1040');
            tc.verifyError(@() ephys.parseDecodedFrames(bad,36),'ephys:FrameMap');
        end
        function sourceZeroFirstAndVariablePTSScheduling(tc)
            folder=tempname; mkdir(folder);
            cleanup=onCleanup(@() rmdir(folder,'s')); %#ok<NASGU>
            inventory=struct('path','test.mp4','sha256','testhash', ...
                'duration_s',.3,'width_px',2,'height_px',2);
            playback=struct('max_texture_bytes',1024);
            uploaded={}; drawn=[]; closed=[];
            player=ephys.FrameMoviePlayer(1,playback,inventory,folder,@screen,@() 10,@decode);
            player.prepare('test.mp4',.3);
            tc.verifyEqual(numel(uploaded),4);
            tc.verifyEqual(squeeze(uploaded{1}(1,1,:)),uint8([1;11;21]));
            player.draw([0 0 2 2],1000); % Wall time cannot consume preloaded frame zero.
            tc.verifyEqual(player.info().source_frame_index,0);
            tc.verifyEqual(player.info().pts,1); % Original nonzero source PTS is retained.
            player.start(10);
            player.draw([0 0 2 2],10.039);
            tc.verifyEqual(player.info().source_frame_index,0);
            player.draw([0 0 2 2],10.04);
            tc.verifyEqual(player.info().source_frame_index,1);
            player.draw([0 0 2 2],10.119);
            tc.verifyEqual(player.info().source_frame_index,1);
            player.draw([0 0 2 2],10.20);
            tc.verifyEqual(player.info().source_frame_index,3);
            tc.verifyEqual(player.info().status,"source_frame_skip");
            tc.verifyEqual(drawn,[101 101 102 102 104]);
            player.close();
            tc.verifyEqual(closed,101:104);
            tc.verifyTrue(isfile(fullfile(folder,'test.json')));
            function [map,rawPath]=decode(~,~,temporary,~)
                rawPath=fullfile(temporary,'frames.rgb'); fid=fopen(rawPath,'wb');
                for k=1:4
                    fwrite(fid,repmat(uint8([k;k+10;k+20]),4,1),'uint8');
                end
                fclose(fid);
                map=struct('frame_count',4,'width_px',2,'height_px',2, ...
                    'source_pts_s',[1;1.04;1.12;1.20],'relative_pts_s',[0;.04;.12;.20]);
            end
            function varargout=screen(command,varargin)
                switch command
                    case 'MakeTexture'
                        uploaded{end+1}=varargin{2};
                        varargout={100+numel(uploaded)};
                    case 'DrawTexture'
                        drawn(end+1)=varargin{2}; varargout={};
                    case 'Close'
                        closed=[closed varargin{1}]; varargout={};
                    otherwise
                        error('Test:UnexpectedPTBCall','Unexpected call %s',command);
                end
            end
        end
    end
end
