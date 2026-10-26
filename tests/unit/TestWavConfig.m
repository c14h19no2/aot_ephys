classdef TestWavConfig < matlab.unittest.TestCase
    methods (Test)
        function activeConfigUsesNamedWaveforms(tc)
            [c,p]=TestWavConfig.config();
            tc.verifyEqual(string(c.markers.backend),"wav");
            tc.verifyEqual(string(c.markers.memory_backend),"dummy");
            tc.verifyFalse(any(isfield(c.markers,{'codes','profile','pulse'})));
            tc.verifyFalse(c.markers.video_offset_enabled);
            tc.verifyTrue(c.markers.blank_enabled);
            tc.verifyTrue(c.markers.run_boundary_enabled);
            tc.verifyEqual(string(c.markers.waveforms.run_start),"TrigP08.wav");
            tc.verifyEqual(string(c.markers.waveforms.run_end),"TrigN08.wav");
            tc.verifyEqual(string(c.markers.waveforms.video_onset),"TrigP16.wav");
            tc.verifyEqual(string(c.markers.waveforms.video_offset),"TrigN16.wav");
            tc.verifyEqual(string(c.markers.wav.directory),"assets/triggers");
            tc.verifyEmpty(c.markers.wav.device_index);
            tc.verifyEqual(c.markers.wav.output_channel,2);
            tc.verifyEqual(sum(endsWith(string(p.files),".wav")),4);
        end
        function originalSamplesArePreservedAtConfiguredOutputRate(tc)
            c=TestWavConfig.config();
            for channel=1:2
                c.markers.wav.output_channel=channel;
                waves=ephys.loadTriggerWaveforms(c.markers);
                tc.verifyNumElements(waves,4);
                for wave=waves
                    original=fullfile(ephys.projectRoot(),'assets','triggers',wave.file);
                    [samples,rate]=audioread(original);
                    % Pin the original assets so sample checks remain independent
                    % of the implementation without requiring trigger_example/.
                    expected=struct( ...
                        'TrigP08',"c8898d5b05bc20ad7d735281a65e375cb22658d2dc32c797f40683735dbc4059", ...
                        'TrigN08',"1f3beb699291e6ae84cdc7f1f1572921ae1fc38a3616899f7fc8a8dabbbc140a", ...
                        'TrigP16',"4aa7eb855dcb8dc7a282b92a2e054cd9ea9394834ee191a3b2669e165564d3b9", ...
                        'TrigN16',"db8e97ea7b600736af0344ff019beb984cff295ab47d70c169b03f885d6e0332");
                    [~,stem]=fileparts(wave.file);
                    tc.verifyEqual(string(ephys.sha256(original)),expected.(stem));
                    tc.verifyEqual(wave.data(channel,:),samples(:,1).');
                    tc.verifyEqual(wave.data(3-channel,:),zeros(1,100));
                    tc.verifyEqual(wave.output_channel,channel);
                    tc.verifyEqual(wave.source_sample_rate_hz,rate);
                    tc.verifyEqual(wave.source_sample_rate_hz,22050);
                    tc.verifyEqual(wave.output_sample_rate_hz,48000);
                    tc.verifyEqual(wave.samples,100);
                    tc.verifyEqual(wave.duration_s,100/48000,'AbsTol',1e-12);
                    tc.verifyEqual(wave.sha256,string(ephys.sha256(original)));
                end
            end
        end
        function siteYamlSelectsTheOutputChannel(tc)
            root=ephys.projectRoot();
            site=ephys.readYaml(testSite());
            site.markers.wav.output_channel=1;
            file=[tempname '.yml'];
            cleanup=onCleanup(@() delete(file));
            yaml.dumpFile(file,site,'block');
            c=ephys.loadConfig("video",fullfile(root,'config','runs','debug_blank.yml'), ...
                file,true,"");
            tc.verifyEqual(c.markers.wav.output_channel,1);
        end
        function rejectsLegacyIntegerConfiguration(tc)
            c=TestWavConfig.config();
            for field=["codes","profile","pulse"]
                bad=c; bad.markers.(field)=struct();
                tc.verifyError(@() ephys.validateConfig(bad),'ephys:LegacyTriggerConfig');
            end
            bad=c; bad.markers.backend='eeg';
            tc.verifyError(@() ephys.validateConfig(bad),'ephys:BackendSelection');
            bad=c; bad.markers.memory_backend='wav';
            tc.verifyError(@() ephys.validateConfig(bad),'ephys:MemoryTriggerBackend');
        end
        function validatesAudioSettingsWithoutOpeningADevice(tc)
            c=TestWavConfig.config();
            for value={-1,NaN,1.5,'default'}
                bad=c; bad.markers.wav.device_index=value{1};
                tc.verifyError(@() ephys.validateConfig(bad),'ephys:TriggerAudioDevice');
            end
            bad=c; bad.markers.wav.device_name=[];
            tc.verifyError(@() ephys.validateConfig(bad),'ephys:TriggerAudioDevice');
            for field=["sample_rate_hz","channels"]
                bad=c; bad.markers.wav.(field)=1;
                tc.verifyError(@() ephys.validateConfig(bad),'ephys:TriggerAudioFormat');
            end
            for value={0,3,1.5,NaN,Inf,'2',[1 2],true}
                bad=c; bad.markers.wav.output_channel=value{1};
                tc.verifyError(@() ephys.validateConfig(bad),'ephys:TriggerAudioChannel');
                tc.verifyError(@() ephys.loadTriggerWaveforms(bad.markers),'ephys:TriggerAudioChannel');
            end
            for value=[0,-1,NaN,1.1]
                bad=c; bad.markers.wav.gain=value;
                tc.verifyError(@() ephys.validateConfig(bad),'ephys:TriggerAudioGain');
            end
            for field=["minimum_lead_s","minimum_low_s", ...
                    "completion_timeout_s","max_sync_error_s"]
                bad=c; bad.markers.wav.(field)=0;
                tc.verifyError(@() ephys.validateConfig(bad),'ephys:TriggerAudioTiming');
            end
            bad=c; bad.markers.wav.latency_class=1.5;
            tc.verifyError(@() ephys.validateConfig(bad),'ephys:TriggerAudioLatency');
        end
        function rejectsMissingDuplicateOrUnsupportedEvents(tc)
            c=TestWavConfig.config();
            bad=c; bad.markers.waveforms.run_end=bad.markers.waveforms.run_start;
            tc.verifyError(@() ephys.validateConfig(bad),'ephys:TriggerWaveform');
            bad=c; bad.markers.waveforms.video_onset='does_not_exist.wav';
            tc.verifyError(@() ephys.validateConfig(bad),'ephys:TriggerWaveform');
            bad=c; bad.markers.waveforms.video_onset=16;
            tc.verifyError(@() ephys.validateConfig(bad),'ephys:TriggerWaveform');
            bad=c; bad.markers.wav.directory='none';
            tc.verifyError(@() ephys.validateConfig(bad),'ephys:TriggerWaveDirectory');
            bad=c; bad.markers.fixation_onset_enabled=true;
            tc.verifyError(@() ephys.validateConfig(bad),'ephys:TriggerWaveEvent');
            bad=c; bad.markers.wav.minimum_lead_s=c.protocol.video_pre_fixation_s+1;
            tc.verifyError(@() ephys.validateConfig(bad),'ephys:TriggerLead');
        end
        function capacityCountsOnsetsAndRunBoundaries(tc)
            c=TestWavConfig.config();
            c.schedule=repmat("blank",84,1);
            [~,~,capacity]=ephys.logCapacity(c);
            tc.verifyEqual(capacity,86+100);
            c.markers.video_offset_enabled=true;
            [~,~,capacity]=ephys.logCapacity(c);
            tc.verifyEqual(capacity,170+100);
            c.markers.blank_enabled=false;
            [~,~,capacity]=ephys.logCapacity(c);
            tc.verifyEqual(capacity,2+100);
        end
        function reservationWindowsMustFitThePhase(tc)
            c=TestWavConfig.config();
            bad=c; bad.protocol.video_final_fixation_s=.05;
            tc.verifyError(@() ephys.validateConfig(bad),'ephys:TriggerLead');
            bad=c; bad.protocol.video_pre_fixation_s=c.markers.wav.minimum_lead_s;
            tc.verifyError(@() ephys.validateConfig(bad),'ephys:TriggerLead');
            bad=c; bad.protocol.video_final_fixation_s=0;
            ephys.validateConfig(bad);
            bad=c; bad.markers.video_offset_enabled=true;
            bad.protocol.video_duration_s=.05;
            tc.verifyError(@() ephys.validateConfig(bad),'ephys:TriggerSpacing');
        end
    end
    methods (Static)
        function [c,p]=config()
            root=ephys.projectRoot();
            [c,p]=ephys.loadConfig("video", ...
                fullfile(root,'config','runs','debug_blank.yml'), ...
                testSite(),true,"");
        end
    end
end
