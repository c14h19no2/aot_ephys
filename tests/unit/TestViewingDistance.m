classdef TestViewingDistance < matlab.unittest.TestCase
    % Eye-to-screen distance for the target movie angle (14.42 x 8.14 deg).
    methods (Test)
        function squarePixelsGiveTheTargetAngleOnBothAxes(tc)
            c=TestViewingDistance.config({30,16.875},1);
            v=ephys.viewingDistance(c);
            tc.verifyEqual(v.status,"ok");
            % The 16:9 movie fills the 1920 x 1080 window: 30 cm wide.
            tc.verifyEqual(v.movie_px(1),1920,'AbsTol',1e-9);
            tc.verifyEqual(v.movie_cm(1),30,'AbsTol',1e-9);
            tc.verifyEqual(v.distance_cm,15/tand(14.42/2),'RelTol',1e-3);
            tc.verifyEqual(v.size_deg,[14.42 8.14],'AbsTol',.01);
            tc.verifyLessThan(abs(diff(v.axis_distance_cm))/v.distance_cm,1e-3);
            [text,level]=ephys.viewingDistanceText(v);
            tc.verifyEqual(level,'note');
            tc.verifyTrue(contains(text,sprintf('%.1f cm',v.distance_cm)));
            tc.verifyTrue(contains(text,"14.42"));
        end
        function movieScaleShortensTheDistance(tc)
            full=ephys.viewingDistance(TestViewingDistance.config({30,16.875},1));
            half=ephys.viewingDistance(TestViewingDistance.config({30,16.875},.5));
            tc.verifyEqual(half.distance_cm,full.distance_cm/2,'RelTol',1e-9);
            tc.verifyEqual(half.size_deg,full.size_deg,'AbsTol',1e-9);
        end
        function screenAspectMismatchIsReported(tc)
            v=ephys.viewingDistance(TestViewingDistance.config({30,19},1));
            tc.verifyEqual(v.status,"ok");
            tc.verifyGreaterThan(abs(diff(v.axis_distance_cm)),1);
            [text,level]=ephys.viewingDistanceText(v);
            tc.verifyEqual(level,'warning');
            tc.verifyTrue(contains(text,"Check display.screen_size_cm"));
        end
        function missingSizesStayUnknown(tc)
            v=ephys.viewingDistance(TestViewingDistance.config([],1));
            tc.verifyEqual(v.status,"no_screen_size");
            tc.verifyTrue(isnan(v.distance_cm));
            [text,level]=ephys.viewingDistanceText(v);
            tc.verifyEqual(level,'warning');
            tc.verifyTrue(contains(text,"set display.screen_size_cm"));
            c=TestViewingDistance.config({30,16.875},1);
            c.stimulus.target_size_deg=[];
            v=ephys.viewingDistance(c);
            tc.verifyEqual(v.status,"no_target_size");
            tc.verifyEqual(ephys.viewingDistanceText(v),"");
            tc.verifyEqual(ephys.viewingDistance(struct()).status,"no_target_size");
        end
        function invalidSizesAreRejected(tc)
            for bad={{-1,10},{30},{30,NaN},{'30',10}}
                c=TestViewingDistance.config(bad{1},1);
                tc.verifyError(@() ephys.viewingDistance(c),'ephys:ScreenSize');
            end
            c=TestViewingDistance.config({30,16.875},1);
            for bad={{180,8},{14.42,0},{14.42}}
                c.stimulus.target_size_deg=bad{1};
                tc.verifyError(@() ephys.viewingDistance(c),'ephys:TargetSize');
            end
            v=struct('status',"invalid",'message',"bad value");
            [text,level]=ephys.viewingDistanceText(v);
            tc.verifyEqual(level,'error');
            tc.verifyTrue(contains(text,"bad value"));
        end
        function siteSummaryNeedsNoRunRequest(tc)
            folder=tempname; mkdir(folder);
            guard=onCleanup(@() rmdir(folder,'s')); %#ok<NASGU>
            settings=ephys.readYaml(testSite());
            site=fullfile(folder,'site.yml');
            yaml.dumpFile(site,settings,'block');
            s=ephys.siteSummary(site);
            tc.verifyEqual(s.error,"");
            tc.verifyEqual(s.resolution_px,[1440 900]);
            tc.verifyEqual(s.refresh_hz,60);
            tc.verifyEqual(s.viewing.status,"no_screen_size");
            tc.verifyTrue(all(isnan(s.screen_size_cm)));
            % A 16:10 window (1440 x 900): the 16:9 movie spans the full 30 cm width.
            settings.display.screen_size_cm={30,18.75};
            yaml.dumpFile(site,settings,'block');
            s=ephys.siteSummary(site);
            tc.verifyEqual(s.screen_size_cm,[30 18.75]);
            tc.verifyEqual(s.viewing.status,"ok");
            tc.verifyEqual(s.viewing.movie_cm(1),30,'AbsTol',1e-9);
            tc.verifyEqual(s.viewing.distance_cm,15/tand(14.42/2),'RelTol',1e-3);
            settings.display.screen_size_cm={30};
            yaml.dumpFile(site,settings,'block');
            s=ephys.siteSummary(site);
            tc.verifyEqual(s.error,"");
            tc.verifyEqual(s.viewing.status,"invalid");
            tc.verifyTrue(contains(s.viewing.message,"screen_size_cm"));
            s=ephys.siteSummary(fullfile(folder,'missing.yml'));
            tc.verifyGreaterThan(strlength(s.error),0);
        end
        function runConfigurationIsValidated(tc)
            root=ephys.projectRoot();
            [c,~]=ephys.loadConfig("video",fullfile(root,'config','runs','debug_blank.yml'), ...
                testSite(),true,"");
            tc.verifyEqual(reshape(cell2mat(c.stimulus.target_size_deg),1,[]),[14.42 8.14]);
            ephys.validateConfig(c);
            c.display.screen_size_cm={0,10};
            tc.verifyError(@() ephys.validateConfig(c),'ephys:ScreenSize');
        end
    end
    methods (Static)
        function c=config(screen,scale)
            c=struct('display',struct('resolution_px',{{1920,1080}},'screen_size_cm',{screen}), ...
                'stimulus',struct('movie_scale',scale,'target_size_deg',{{14.42,8.14}}));
        end
    end
end
