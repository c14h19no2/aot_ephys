classdef TestOnsetPrediction < matlab.unittest.TestCase
    % PredictVisualOnsetForTime's rule, anchored to the logged last Flip.
    methods (Test)
        function firstRefreshAfterTheRequest(tc)
            ifi=1/60; last=10;
            tc.verifyEqual(ephys.predictVisualOnset(last,last+.25*ifi,ifi,0),last+ifi,'AbsTol',1e-12);
            tc.verifyEqual(ephys.predictVisualOnset(last,last+.5*ifi,ifi,0),last+ifi,'AbsTol',1e-12);
            tc.verifyEqual(ephys.predictVisualOnset(last,last+59.51*ifi,ifi,0),last+60*ifi,'AbsTol',1e-12);
            % A one-second pre-fixation requests half a refresh before the onset.
            onset=last+60*ifi;
            tc.verifyEqual(ephys.predictVisualOnset(last,onset-.5*ifi,ifi,0),onset,'AbsTol',1e-12);
        end
        function nonpositiveRequestMeansTheNextRefresh(tc)
            ifi=1/60;
            tc.verifyEqual(ephys.predictVisualOnset(10,0,ifi,0),10+ifi,'AbsTol',1e-12);
            tc.verifyEqual(ephys.predictVisualOnset(10,-1,ifi,0),10+ifi,'AbsTol',1e-12);
        end
        function blankingCorrectionIsAddedUnchanged(tc)
            ifi=1/60;
            tc.verifyEqual(ephys.predictVisualOnset(10,10+.5*ifi,ifi,.0015),10+ifi+.0015,'AbsTol',1e-12);
        end
        function missingPreviousFlipFails(tc)
            tc.verifyError(@() ephys.predictVisualOnset(NaN,11,1/60,0),'ephys:OnsetPrediction');
            tc.verifyError(@() ephys.predictVisualOnset(-1,11,1/60,0),'ephys:OnsetPrediction');
        end
        function blankingDurationFollowsThePtbRule(tc)
            ifi=1/60;
            info=struct('VBLStartline',1080,'VBLEndline',1125,'SpecialFlags',16);
            tc.verifyEqual(ephys.blankingDuration(info,ifi),45/1125*ifi,'AbsTol',1e-15);
            info.SpecialFlags=16+2^20; % Other flags do not matter.
            tc.verifyEqual(ephys.blankingDuration(info,ifi),45/1125*ifi,'AbsTol',1e-15);
            info.SpecialFlags=0;
            tc.verifyEqual(ephys.blankingDuration(info,ifi),0);
            % This laptop: beamposition disabled, endline equal to startline.
            tc.verifyEqual(ephys.blankingDuration(struct('VBLStartline',1080, ...
                'VBLEndline',1080,'SpecialFlags',16),ifi),0);
            tc.verifyEqual(ephys.blankingDuration(struct('VBLStartline',1080, ...
                'VBLEndline',-1,'SpecialFlags',16),ifi),0);
            tc.verifyEqual(ephys.blankingDuration(struct('ImagingMode',0),ifi),0);
        end
    end
end
