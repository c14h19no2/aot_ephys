# Running the experiment

## Start on a configured computer

Change MATLAB's current folder to the project and run the experiment:

```matlab
cd('C:\path\to\aot_ephys');
run_aot_ephys();
```

The current folder is what lets MATLAB find `run_aot_ephys` and `+ephys`; the
bundled YAML library is added to the path when configuration is first read.

## Set up a new computer

Run `setup_aot` only on a new computer, or when Psychtoolbox is not on the
MATLAB path:

```matlab
setup_aot();                                            % New computer.
setup_aot('PsychtoolboxPath','C:\path\to\Psychtoolbox'); % Also add PTB.
```

Setup adds the project and YAML paths for the current session only, creates
missing local configuration files and preserves existing site/selector edits.
It does not open the display or audio device, convert media, or save the
global path.

Edit `config/site.local.yml` for this computer:

- `paths.video_root`: original movies.
- `playback.native_media_root`: prepared MP4/JSON pairs.
- `paths.output_root`: recordings; each run gets a new directory inside a
  folder named after the collection date (`yyyy-mm-dd`).
- `paths.picture_root`: memory pictures, when using the memory task.
- Display index, resolution, refresh reference, and fixation geometry.
- Audio device and `markers.wav.output_channel` (default 2).
- The site acquisition approval field, after the site's setup has been reviewed.

The common experiment timing stays in `config/experiment.yml`. The current
initial/final baselines are 5 s each; each video/blank has 1.0 s pre-fixation,
2.5 s stimulus and 0.1 s post-fixation. Read the YAML for the current values.

## Prepare media once

Native experiment playback needs MATLAB, Psychtoolbox and verified MP4/JSON
pairs. FFmpeg, ffprobe and Python are used only on the preparation computer:

```matlab
prepare_aot_ephys_native_media();        % All MP4 files in the selected video root.
prepare_aot_ephys_native_media(1,1,8);   % Alternatively, only movies from this run.
```

Preparation preserves original movies. Playback copies retain original
filenames in the configured external directory. Another acquisition computer
can reuse the MP4/JSON pairs without running conversion there. JSON paths are
relocated using the selected site.

A run does not hash video files; it checks only that each map is valid and its
copy exists. After preparing or copying media, or before a session, check that
originals and copies still match the SHA-256 values recorded in their maps.
This needs neither FFmpeg nor Python, and reads every file once:

```matlab
verify_aot_ephys_media(1,1,8);   % Movies of one run (67 files, about 12 s).
verify_aot_ephys_media();        % All MP4 files in the selected video root.
```

It prints each mismatch (`map_missing`, `map_invalid`, `original_missing`,
`original_changed`, `native_missing`, `native_changed`) and warns if any are
found; `results = verify_aot_ephys_media(...)` also returns one row per video.

## Start a run

```matlab
videoOut = run_aot_ephys();         % Dialog: subject, session, run, task, Overwrite.
videoOut = run_aot_ephys(1,1,8);
videoOut = run_aot_ephys(1,1,8,2);  % Another recording of the same schedule.
videoOut = run_aot_ephys('patientname',1,8);
memoryOut = run_aot_ephys(1,1,1,2,'Task','memory');
```

Subject, session and run choose the saved schedule. A numeric subject is
zero-padded to three digits (`sub-003`) and uses its own schedule set; a name
such as `patientname` (`sub-patientname`; letters and digits only, since
underscores separate the parts of the output name) must be listed in the local
`config/subjects.local.yml`, which maps labels to schedule sets. The optional
fourth ID only labels the output recording. Output goes to
`<output_root>/<yyyy-mm-dd>/<name>`. An existing output for the same day stops
the run before it starts, unless `'Overwrite',true` (or the dialog checkbox) is
given: the old folder is then renamed `<name>_replaced-<HHMMSS>` and kept.
The return value is the output directory. Schedules are stored in
[`config/runs`](../config/runs/README.md), inside this repository.

The first row of the dialog chooses the site: every `config/site.*.yml` except
the example, with the one in `config/active_site.yml` preselected and marked
"(active)". Under it the dialog shows that site's screen size, resolution and
refresh rate, and in bold the eye-to-screen distance that makes the movie
`stimulus.target_size_deg` wide and high (14.42 × 8.14°), once
`display.screen_size_cm` is set in the site file (see
[configuration](configuration.md)). Place the participant at that distance.
A site that is not approved for acquisition is flagged there. If you choose
another site, Start writes it to `config/active_site.yml` (comments are kept),
so this and later runs use it; Cancel changes nothing.

Below that, enter subject, session, run, task and Overwrite as before. The
dialog shows the output path and schedule while you type, and enables Start
only for a valid request. Labels appear in folder names and manifests; use
study codes rather than real names.

Loading precedes the Space instruction screen. After Space, the video task
presents the initial baseline, the saved sequence once, the final baseline and
the run-end event. Blank slots share video onset waveforms. Q aborts and saves
the observed portion; after a run starts, it also attempts exactly one run-end
waveform. Q before Space emits no run-boundary waveform. Q is not an error:
`run_aot_ephys` prints a short banner ("Run stopped with Q.") and returns the
output folder, with status
`"aborted"` as its optional second output. J/K are the memory
yes/no keys; accuracy remains unknown without an answer file.

Device initialization, initial video loading and the Space wait run at normal
scheduling priority. After Space, a non-Debug run raises priority before the
run-start event; completion and abort cleanup return it to normal. This startup
order supports cold video-engine initialization on Windows without first
running a separate movie experiment.

At the end of the initial baseline, the refresh guard checks that the display
loop presented at least `display.refresh_guard_min_fraction` (default 90%) of
the baseline's refreshes. If not, the run stops before the first trial with a
`ephys:RefreshGuard` message, the output is saved as aborted and one run-end
waveform is attempted. Before repeating with a new recording number (or with
Overwrite, which keeps the aborted folder under a `_replaced` name), close
screen sharing or remote-control tools and other demanding programs, use the
intended display mode and mains power, and confirm the PTB sync test passes.

Full input documentation is in [run_arguments.md](run_arguments.md).

## Change screens/sites

Create another local file such as `config/site.lab.yml`, then edit the local
selector `config/active_site.yml`:

```yaml
site_file: site.lab.yml
```

Its relative paths resolve from the selector's directory. An explicit
`'Site',sitePath` overrides the selector for one call. The configuration merge
order is common experiment, selected site, and Debug overrides when enabled.
The example site is a setup template. Video/image geometry preserves aspect
ratio and fits the actual window; any unused area uses the gray background.

## Debug and inspect output

```matlab
out = run_aot_ephys(1,1,8,3,'Debug',true,'DebugSkipSyncTests',true);
timeline = ephys.reconstructTimeline(out);
disp(timeline.trials)
```

Debug uses a smaller window and shorter trial phases, retaining shared baseline
durations. It still requires the selected movies unless a debug schedule is
explicitly used. Recoverable timing/decoder QC findings are recorded and the
schedule continues. See [output records and QC](log_format.md).

After updating loaded MATLAB classes, finish the current run, then execute
`clear classes; rehash` before the next run. Keep the computer unlocked during
display use. Software/driver timing estimates and successful playback do not
constitute physical display/electrical timing measurements.
