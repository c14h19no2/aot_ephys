classdef TestLocalMovies < matlab.unittest.TestCase
    methods (Test)
        function realRegressionMovies(tc)
            root=getenv('AOT_TEST_VIDEO_ROOT');
            tc.assumeTrue(isfile(fullfile(root,'1056_rv.mp4')) && ...
                isfile(fullfile(root,'1834_fw.mp4')));
            playback=ephys.resolveVideoTools(struct('ffmpeg_path','','ffprobe_path',''));
            folder=tempname; mkdir(folder);
            cleanup=onCleanup(@() rmdir(folder,'s')); %#ok<NASGU>
            for name=["1056_rv.mp4","1834_fw.mp4"]
                path=fullfile(root,name);
                [map,~]=ephys.decodeMovieFrames(path,playback,folder,ephys.sha256(path));
                tc.verifyEqual(map.frame_count,61);
                tc.verifyEqual(map.source_frame_index,(0:60)');
                tc.verifyEqual(map.source_pts_s,(0:60)'/24,'AbsTol',1e-9);
                probe=jsondecode(ephys.runMediaProcess({playback.ffprobe_path, ...
                    '-v','error','-select_streams','v:0','-show_entries', ...
                    'frame=pts','-of','json',char(path)}));
                if iscell(probe.frames)
                    ticks=cellfun(@(frame) frame.pts,probe.frames);
                else
                    ticks=[probe.frames.pts];
                end
                tc.verifyEqual(map.source_pts_ticks,ticks(:));
            end
        end
    end
end
