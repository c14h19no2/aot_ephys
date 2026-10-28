classdef TestFixationGeometry < matlab.unittest.TestCase
    % Fixation sizes in degrees, converted for the window, and its texture.
    methods (Test)
        function anglesBecomePixelsAtTheSuggestedDistance(tc)
            g = ephys.fixationGeometry(TestFixationGeometry.config([1920 1080],1));
            % The 1920-pixel movie spans 14.42 degrees.
            distance = 960/tand(14.42/2);
            tc.verifyEqual(g.distance_px,distance,'RelTol',1e-12);
            tc.verifyEqual(g.surround_diameter_px,2*distance*tand(0.18270/2),'RelTol',1e-12);
            tc.verifyEqual(g.dot_diameter_px,2*distance*tand(0.03654/2),'RelTol',1e-12);
            tc.verifyEqual(g.outline_width_px,2*distance*tand(0.00788/2),'RelTol',1e-12);
            tc.verifyEqual(g.line_width_px,g.outline_width_px,'RelTol',1e-12);
            tc.verifyEqual(g.surround_diameter_px,24.20,'AbsTol',.01);
            tc.verifyEqual(g.dot_diameter_px,4.84,'AbsTol',.01);
            tc.verifyEqual(g.line_width_px,1.04,'AbsTol',.01);
            tc.verifyEqual(g.center_px,[960 540]);
        end
        function sameAnglesOnASmallerWindow(tc)
            large = ephys.fixationGeometry(TestFixationGeometry.config([1920 1080],1));
            small = ephys.fixationGeometry(TestFixationGeometry.config([1440 900],1));
            % A 16:10 window: the movie is 1440 pixels wide.
            tc.verifyEqual(small.dot_diameter_px,large.dot_diameter_px*1440/1920,'RelTol',1e-9);
            half = ephys.fixationGeometry(TestFixationGeometry.config([1920 1080],.5));
            tc.verifyEqual(half.surround_diameter_px,large.surround_diameter_px/2,'RelTol',1e-9);
        end
        function textureFollowsTheDrawingOrder(tc)
            g = ephys.fixationGeometry(TestFixationGeometry.config([1920 1080],1));
            [x,y] = meshgrid(g.texture_rect(1)+(0:size(g.dot_image,2)-1)+.5, ...
                g.texture_rect(2)+(0:size(g.dot_image,1)-1)+.5);
            r = hypot(x-g.center_px(1),y-g.center_px(2));
            dot = g.dot_diameter_px/2; ring = g.outline_width_px/2;
            % Dot texture: black dot, white outline on its edge, clear elsewhere.
            [colour,alpha] = TestFixationGeometry.split(g.dot_image);
            tc.verifyEqual(unique(colour(r<dot-ring-1)),0);
            tc.verifyTrue(all(alpha(r<dot-ring-1)==1));
            outline = abs(r-dot)<.5;
            tc.verifyGreaterThan(max(mean(colour(outline),2)),200);
            tc.verifyTrue(all(alpha(r>dot+ring+1)==0));
            % Surround texture: opaque gray, raised-cosine edge over the outer 30%.
            [colour,alpha] = TestFixationGeometry.split(g.surround_image);
            radius = g.surround_diameter_px/2;
            inner = r<0.7*radius-1;
            tc.verifyEqual(unique(colour(inner)),128);
            tc.verifyTrue(all(alpha(inner)==1));
            fringe = r>0.7*radius+.75 & r<radius-.75;
            t = (r(fringe)-0.7*radius)/(0.3*radius);
            tc.verifyEqual(alpha(fringe),0.5*(1+cos(pi*t)),'AbsTol',.05);
            tc.verifyTrue(all(alpha(r>radius+1)==0));
            tc.verifyEqual(unique(colour(fringe)),128);
        end
        function zeroOutlineLeavesAPlainBlackDot(tc)
            c = TestFixationGeometry.config([1920 1080],1);
            c.stimulus.fixation.outline_width_deg = 0;
            g = ephys.fixationGeometry(c);
            tc.verifyEqual(g.outline_width_px,0);
            [x,y] = meshgrid(g.texture_rect(1)+(0:size(g.dot_image,2)-1)+.5, ...
                g.texture_rect(2)+(0:size(g.dot_image,1)-1)+.5);
            r = hypot(x-g.center_px(1),y-g.center_px(2));
            [colour,alpha] = TestFixationGeometry.split(g.dot_image);
            % Only black, opaque inside the full dot radius, clear outside it.
            tc.verifyEqual(unique(colour(alpha>0)),0);
            dot = g.dot_diameter_px/2;
            tc.verifyTrue(all(alpha(r<dot-.75)==1));
            tc.verifyTrue(all(alpha(r>dot+.75)==0));
        end
        function invalidFixationSettingsAreRejected(tc)
            root = ephys.projectRoot();
            [c,~] = ephys.loadConfig("video",fullfile(root,'config','runs','debug_blank.yml'), ...
                testSite(),true,"");
            ephys.validateConfig(c);
            tc.verifyEqual(c.stimulus.fixation.outline_width_deg,0);
            bad = c; bad.stimulus.fixation.outline_width_deg = 0.05;
            tc.verifyError(@() ephys.validateConfig(bad),'ephys:FixationGeometry');
            bad = c; bad.stimulus.fixation.outline_width_deg = -0.001;
            tc.verifyError(@() ephys.validateConfig(bad),'ephys:FixationGeometry');
            good = c; good.stimulus.fixation.outline_width_deg = 0.00788;
            ephys.validateConfig(good);
            bad = c; bad.stimulus.fixation.surround_fringe = 1.5;
            tc.verifyError(@() ephys.validateConfig(bad),'ephys:FixationGeometry');
            bad = c; bad.stimulus.fixation.dot_diameter_deg = [];
            tc.verifyError(@() ephys.validateConfig(bad),'ephys:FixationGeometry');
            bad = c; bad.stimulus.target_size_deg = [];
            tc.verifyError(@() ephys.validateConfig(bad),'ephys:FixationGeometry');
        end
    end
    methods (Static)
        function [colour,alpha] = split(image)
            % colour(mask) gives the RGB rows of the masked pixels; alpha is in [0,1].
            image = double(image);
            alpha = image(:,:,4)/255;
            colour = @(mask) reshape(image(repmat(mask,1,1,3)),[],3);
        end
        function f = fixation()
            f = struct('surround_diameter_deg',0.18270,'surround_fringe',0.3, ...
                'dot_diameter_deg',0.03654,'outline_width_deg',0.00788, ...
                'line_width_deg',0.00788,'line_rgb255',{{255,255,255}}, ...
                'outline_rgb255',{{255,255,255}},'dot_rgb255',{{0,0,0}}, ...
                'surround_rgb255',{{128,128,128}});
        end
        function c = config(resolution,scale)
            c = struct('display',struct('resolution_px',{num2cell(resolution)}), ...
                'stimulus',struct('movie_scale',scale,'target_size_deg',{{14.42,8.14}}, ...
                'fixation',TestFixationGeometry.fixation()));
        end
    end
end
