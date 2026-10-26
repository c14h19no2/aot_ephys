classdef TestMediaDecoding < matlab.unittest.TestCase
    methods (Test)
        function actualFFmpegBFrameDecode(tc)
            playback=ephys.resolveVideoTools(struct('ffmpeg_path','','ffprobe_path',''));
            folder=tempname; mkdir(folder);
            cleanup=onCleanup(@() rmdir(folder,'s')); %#ok<NASGU>
            path=fullfile(folder,'numbered timeline.mp4');
            ephys.runMediaProcess({playback.ffmpeg_path,'-nostdin','-y', ...
                '-f','lavfi','-i','testsrc2=size=16x16:rate=24:duration=0.25', ...
                '-c:v','libx264','-bf','2','-g','24',path});
            [map,raw]=ephys.decodeMovieFrames(path,playback,folder,ephys.sha256(path));
            tc.verifyEqual(map.frame_count,6);
            tc.verifyEqual(map.source_frame_index,(0:5)');
            tc.verifyEqual(map.source_pts_s,(0:5)'/24,'AbsTol',1e-9);
            tc.verifyEqual(dir(raw).bytes,6*16*16*3);
            meta=ephys.probeMovie(path,playback);
            tc.verifyEqual(meta.duration,.25,'AbsTol',1e-9);
        end
    end
end
