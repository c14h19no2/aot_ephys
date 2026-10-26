classdef TestSubjectAndOutput < matlab.unittest.TestCase
    % Subject labels, the local schedule-set map and dated output folders.
    properties
        Folder
    end
    methods (TestMethodSetup)
        function useTemporaryFolder(tc)
            fixture=tc.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            tc.Folder=string(fixture.Folder);
        end
    end
    methods (Test)
        function numbersArePaddedAndNamesKept(tc)
            cases={3,"003";17,"017";1234,"1234";"3","003";'017',"017"; ...
                "sub-017","017";'patientname',"patientname";"sub-PatientName","PatientName";" patientname ","patientname"};
            for k=1:size(cases,1)
                tc.verifyEqual(ephys.subjectLabel(cases{k,1}),cases{k,2});
            end
            for bad={0,-1,1.5,NaN,Inf,[1 2],1+1i,true,"","sub-","0","patient name","patient_name", ...
                    "../x","a/b","patient"+char(233),string(missing),["a" "b"],{'a'}}
                tc.verifyError(@() ephys.subjectLabel(bad{1}),'ephys:RunIdentity');
            end
        end
        function mapSelectsNamedSetsAndNumbersKeepTheirOwn(tc)
            map=TestSubjectAndOutput.mapFixture();
            [number,source]=ephys.scheduleSet("patientname",map);
            tc.verifyEqual(number,1);
            tc.verifyTrue(startsWith(source,"subject map"));
            tc.verifyEqual(ephys.scheduleSet(7,map),7);
            tc.verifyEqual(ephys.scheduleSet("sub-007",map),7);
            [number,source]=ephys.scheduleSet(3,map);
            tc.verifyEqual(number,3);
            tc.verifyEqual(source,"subject number");
            tc.verifyError(@() ephys.scheduleSet("anna",map),'ephys:ScheduleSet');
            absent=fullfile(tc.Folder,'absent.yml');
            tc.verifyEqual(ephys.scheduleSet(12,absent),12);
            tc.verifyError(@() ephys.scheduleSet("patientname",absent),'ephys:ScheduleSet');
        end
        function invalidMapsStopBeforeAnyRun(tc)
            bad={["subjects:";"  - {label: 7, schedule_set: 7}";"  - {label: '007', schedule_set: 7}"]
                ["subjects:";"  - {label: 14, schedule_set: 2}"]
                ["subjects:";"  - {label: patientname, schedule_set: 1}";"  - {label: '003', schedule_set: 1}"]
                ["subjects:";"  - label: patientname";"    schedule_set: 1";"  - label: anna";"    schedule_set: 2"]
                ["subjects:";"  - {label: patientname, schedule_set: 0}"]
                ["subjects:";"  - {label: patientname, schedule_set: 1, note: x}"]
                ["subjects:";"  - {label: patient name, schedule_set: 1}"]
                ["subjects: []";"extra: 1"]};
            for k=1:numel(bad)
                file=fullfile(tc.Folder,sprintf('bad_%d.yml',k));
                tc.writeLines(file,bad{k});
                tc.verifyError(@() ephys.scheduleSet(3,file),'ephys:SubjectMap', ...
                    sprintf('Map %d was accepted.',k));
            end
        end
        function namedSubjectsUseTheirMappedSchedule(tc)
            map=TestSubjectAndOutput.mapFixture();
            r=ephys.resolveRunRequest("patientname",1,8,'Site',testSite(),'SubjectMap',map);
            tc.verifyEqual(r.run_id,"sub-patientname_ses-01_run-08_task-video");
            tc.verifyEqual(r.schedule_path,string(fullfile(ephys.projectRoot(), ...
                'config','runs','main','experiment_settings_sub_01_ses_01_run_08.yml')));
            tc.verifyEqual(r.identity.subject,"patientname");
            tc.verifyEqual(r.identity.schedule_set,1);
            numbered=ephys.resolveRunRequest(7,1,8,2,'Site',testSite(),'SubjectMap',map);
            tc.verifyEqual(numbered.run_id,"sub-007_ses-01_run-08_task-video_record-02");
            tc.verifyEqual(numbered.schedule_path,string(fullfile(ephys.projectRoot(), ...
                'config','runs','main','experiment_settings_sub_07_ses_01_run_08.yml')));
            tc.verifyEqual(numbered.identity.schedule_set,7);
            tc.verifyError(@() ephys.resolveRunRequest("anna",1,8,'Site',testSite(), ...
                'SubjectMap',map),'ephys:ScheduleSet');
            tc.verifyError(@() ephys.resolveRunRequest(99,1,1,'Site',testSite(), ...
                'SubjectMap',map),'ephys:ScheduleMissing');
            tc.verifyMatches(r.collection_date,"^\d{4}-\d{2}-\d{2}$");
        end
        function outputsAreGroupedByCollectionDate(tc)
            root=fullfile(tc.Folder,'outputs');
            [folder,replaced]=ephys.prepareOutputFolder(root,"2026-10-25","sub-003_run",false);
            tc.verifyEqual(folder,string(fullfile(root,'2026-10-25','sub-003_run')));
            tc.verifyTrue(isfolder(folder));
            tc.verifyEqual(replaced,"");
            tc.verifyError(@() ephys.prepareOutputFolder(root,"2026-10-25","sub-003_run",false), ...
                'ephys:OutputExists');
            flat=ephys.prepareOutputFolder(root,"","diagnostic",false);
            tc.verifyEqual(flat,string(fullfile(root,'diagnostic')));
            for bad=["25-10-2026","2026-10-25/x","today"]
                tc.verifyError(@() ephys.prepareOutputFolder(root,bad,"x",false),'ephys:OutputDate');
            end
        end
        function overwriteRenamesTheOldRecording(tc)
            root=fullfile(tc.Folder,'outputs');
            folder=ephys.prepareOutputFolder(root,"2026-10-25","sub-003_run",false);
            tc.writeLines(fullfile(folder,'old.tsv'),"recorded");
            [again,replaced]=ephys.prepareOutputFolder(root,"2026-10-25","sub-003_run",true);
            tc.verifyEqual(again,folder);
            tc.verifyEmpty(dir(fullfile(again,'*.tsv')));
            tc.verifyMatches(replaced,regexptranslate('escape',folder)+"_replaced-\d{6}(-\d+)?$");
            tc.verifyEqual(string(fileread(fullfile(replaced,'old.tsv'))),"recorded"+newline);
            [~,third]=ephys.prepareOutputFolder(root,"2026-10-25","sub-003_run",true);
            tc.verifyTrue(isfolder(replaced) && isfolder(third) && third~=replaced);
        end
        function previewMatchesTheRunWithoutCreatingAnything(tc)
            [site,root]=tc.siteWithOutput();
            map=TestSubjectAndOutput.mapFixture();
            args={'Site',site,'SubjectMap',map};
            p=ephys.previewRunRequest("patientname",1,8,args{:});
            tc.verifyTrue(p.ok);
            tc.verifyEqual(p.error,"");
            request=ephys.resolveRunRequest("patientname",1,8,args{:});
            [c,~]=ephys.loadConfig(request.task,request.schedule_path,request.site_path,false,"");
            tc.verifyEqual(p.output_folder,string(fullfile(c.paths.output_root, ...
                request.collection_date,request.run_id)));
            tc.verifyEqual(p.schedule_path,request.schedule_path);
            tc.verifyFalse(p.exists);
            tc.verifyEmpty(dir(fullfile(root,'*-*-*')));
            mkdir(p.output_folder);
            mkdir(fullfile(root,'2026-01-02',p.run_id));
            p=ephys.previewRunRequest("patientname",1,8,args{:});
            tc.verifyTrue(p.exists);
            tc.verifyFalse(p.ok);
            tc.verifyEqual(p.other_dates,"2026-01-02");
            replacing=ephys.previewRunRequest("patientname",1,8,args{:},'Overwrite',true);
            tc.verifyTrue(replacing.ok);
            tc.verifyTrue(replacing.exists);
            for bad={{"patient name",1,8},{"anna",1,8},{"patientname",0,8},{"patientname",1,99}}
                p=ephys.previewRunRequest(bad{1}{:},args{:});
                tc.verifyFalse(p.ok);
                tc.verifyGreaterThan(strlength(p.error),0);
            end
        end
        function setupCreatesAnEmptySubjectMap(tc)
            for name=["site.example.yml","active_site.example.yml","subjects.example.yml"]
                copyfile(fullfile(ephys.projectRoot(),'config',name),fullfile(tc.Folder,name));
            end
            ephys.initializeLocalConfig(tc.Folder);
            map=fullfile(tc.Folder,'subjects.local.yml');
            tc.verifyTrue(isfile(map));
            tc.verifyEqual(ephys.scheduleSet(5,map),5);
            tc.verifyError(@() ephys.scheduleSet("patientname",map),'ephys:ScheduleSet');
        end
    end
    methods (Access=private)
        function writeLines(~,file,lines)
            fid=fopen(file,'w');
            guard=onCleanup(@() fclose(fid)); %#ok<NASGU>
            fprintf(fid,'%s\n',lines);
        end
        function [site,root]=siteWithOutput(tc)
            settings=ephys.readYaml(testSite());
            root=fullfile(tc.Folder,'outputs');
            mkdir(root);
            settings.paths.output_root=root;
            site=fullfile(tc.Folder,'site.yml');
            yaml.dumpFile(site,settings,'block');
        end
    end
    methods (Static)
        function map=mapFixture()
            map=string(fullfile(ephys.projectRoot(),'tests','fixtures','subjects.test.yml'));
        end
    end
end
