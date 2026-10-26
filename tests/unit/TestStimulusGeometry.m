classdef TestStimulusGeometry < matlab.unittest.TestCase
    methods (Test)
        function localScreenShowsTheWholeWideMovie(tc)
            config = TestStimulusGeometry.config([1440,900]);
            tc.verifyEqual(ephys.movieRect(config),[0,0,1440,900],'AbsTol',1e-10);
            rect = ephys.movieRect(config,[1920,1080]);
            tc.verifyEqual(rect,[0,45,1440,855],'AbsTol',1e-10);
        end

        function everyAspectAndScaleFitsAndStaysCentered(tc)
            displays = [800,600;1440,900;1920,1080;2560,1440;900,1440];
            sources = [1920,1080;1080,1920;800,800;2048,512];
            for display = displays'
                config = TestStimulusGeometry.config(display');
                for scale = [1,0.8,0.5]
                    config.stimulus.movie_scale = scale;
                    windowBounds = ephys.movieRect(config);
                    for source = sources'
                        rect = ephys.movieRect(config,source');
                        tc.verifyGreaterThanOrEqual(rect(1:2),[-1e-10,-1e-10]);
                        tc.verifyLessThanOrEqual(rect(3:4),display'+1e-10);
                        tc.verifyGreaterThanOrEqual(rect(1:2),windowBounds(1:2)-1e-10);
                        tc.verifyLessThanOrEqual(rect(3:4),windowBounds(3:4)+1e-10);
                        tc.verifyEqual((rect(1:2)+rect(3:4))/2,display'/2,'AbsTol',1e-10);
                        dimensions = rect(3:4)-rect(1:2);
                        tc.verifyGreaterThan(dimensions,[0,0]);
                        tc.verifyEqual(dimensions(1)/source(1), ...
                            dimensions(2)/source(2),'AbsTol',1e-12);
                        % Fit must be maximal: one dimension reaches its bound.
                        tc.verifyEqual(max(dimensions./(display'*scale)),1,'AbsTol',1e-12);
                    end
                end
            end
        end

        function extraScalingReducesSizeWithoutShiftingCenter(tc)
            config = TestStimulusGeometry.config([1440,900]);
            full = ephys.movieRect(config,[1920,1080]);
            config.stimulus.movie_scale = 0.5;
            half = ephys.movieRect(config,[1920,1080]);
            tc.verifyEqual(half,[360,247.5,1080,652.5],'AbsTol',1e-10);
            tc.verifyEqual(half(3:4)-half(1:2), ...
                (full(3:4)-full(1:2))/2,'AbsTol',1e-10);
            config.display.resolution_px = {1440;900};
            tc.verifyEqual(ephys.movieRect(config,[1920;1080]),half,'AbsTol',1e-10);
        end

        function legacyCanvasCannotLimitTheWindowFit(tc)
            config = TestStimulusGeometry.config([1440,900]);
            config.stimulus.movie_canvas_px = {100,100};
            tc.verifyEqual(ephys.movieRect(config,[1920,1080]), ...
                [0,45,1440,855],'AbsTol',1e-10);
        end

        function fixationRemainsAtTheWindowCenter(tc)
            config = TestStimulusGeometry.config([1440,900]);
            config.stimulus.fixation = struct('surround_diameter_px',20, ...
                'dot_radius_px',2,'line_width_px',1, ...
                'surround_rgb255',{{128,128,128}},'dot_rgb255',{{0,0,0}}, ...
                'line_rgb255',{{255,255,255}});
            for scale = [1,0.5]
                config.stimulus.movie_scale = scale;
                commands = strings(0,1);
                drawArguments = {};
                ephys.drawFixation(7,config,@screen);
                tc.verifyEqual(commands,["FillOval";"FillOval";"DrawLine";"DrawLine"]);
                for k = 1:2
                    rect = drawArguments{k}{3};
                    tc.verifyEqual((rect(1:2)+rect(3:4))/2,[720,450]);
                end
                for k = 3:4
                    line = cell2mat(drawArguments{k}(3:6));
                    tc.verifyEqual((line(1:2)+line(3:4))/2,[720,450]);
                end
            end
            function screen(command,varargin)
                commands(end+1,1) = string(command);
                drawArguments{end+1} = varargin;
            end
        end

        function inventoryRecordsGeometryAndChecksPhotodiode(tc)
            config = TestStimulusGeometry.config([1440,900]);
            folder = tempname;
            mkdir(folder);
            guard = onCleanup(@() rmdir(folder,'s'));
            imwrite(zeros(9,16,3,'uint8'),fullfile(folder,'test.png'));
            config.task_kind = "memory";
            config.schedule = "test.png";
            config.paths.picture_root = folder;
            inventory = ephys.mediaInventory(config);
            tc.verifyEqual([inventory.width_px,inventory.height_px],[16,9]);
            tc.verifyEqual(inventory.display_rect_px,[0,45,1440,855],'AbsTol',1e-10);
            % A diode can use an actual gray border, but cannot cover the image.
            config.photodiode = struct('enabled',true,'rect_px',{{0,0,20,20}});
            inventory = ephys.mediaInventory(config);
            tc.verifyEqual(inventory.display_rect_px,[0,45,1440,855],'AbsTol',1e-10);
            config.photodiode.rect_px = {0,50,20,70};
            tc.verifyError(@() ephys.mediaInventory(config),'ephys:PhotodiodeOverlap');
        end

        function invalidSourceDimensionsFailBeforeDrawing(tc)
            config = TestStimulusGeometry.config([1440,900]);
            for invalid = {[0,1080],[-1,1080],[NaN,1080],[Inf,1080],1920, ...
                    [1920,1080,1],[1920+1i,1080],"1920x1080"}
                tc.verifyError(@() ephys.movieRect(config,invalid{1}),'ephys:MediaGeometry');
            end
        end
    end

    methods (Static)
        function config = config(resolution)
            config = struct('display',struct('resolution_px',{num2cell(resolution)}), ...
                'stimulus',struct('movie_scale',1));
        end
    end
end
