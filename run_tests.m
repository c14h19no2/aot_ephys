function results = run_tests(suiteName)
%RUN_TESTS Run isolated unit tests, or explicitly selected media tests.
% run_tests()              MATLAB-only unit tests with synthetic fixtures.
% run_tests('integration') FFmpeg/ffprobe tests with generated clips.
% run_tests('all')         Unit and generated-media integration tests.
% run_tests('local_media') Optional real clips from AOT_TEST_VIDEO_ROOT.
% Real display/audio tests are manual; see tests/hardware/README.md.
if nargin<1, suiteName="unit"; end
suiteName=string(suiteName);
assert(isscalar(suiteName) && any(suiteName==["unit","integration","all","local_media"]), ...
    'ephys:TestSuite','Suite must be unit, integration, all, or local_media.');
root=fileparts(mfilename('fullpath'));
savedPath=path;
restorePath=onCleanup(@() path(savedPath)); %#ok<NASGU>
addpath(root,fullfile(root,'third_party','yaml'),fullfile(root,'tests','helpers'), ...
    fullfile(root,'tests','unit'));
cleanupSite=@testSite;
fixtureCleanup=onCleanup(@() cleanupSite('cleanup')); %#ok<NASGU>
folders=suiteName;
if suiteName=="all", folders=["unit","integration"]; end
suites=cell(1,numel(folders));
for index=1:numel(folders)
    folder=folders(index);
    directory=fullfile(root,'tests',folder);
    addpath(directory);
    suites{index}=matlab.unittest.TestSuite.fromFolder(directory, ...
        'IncludingSubfolders',false);
end
suite=[suites{:}];
results=run(suite);
assert(~any([results.Failed]) && ~any([results.Incomplete]), ...
    'ephys:TestsFailed','A test failed or was incomplete; see the test diagnostics.');
end
