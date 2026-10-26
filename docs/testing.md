# Testing and validation

## Unit suite: the default

```matlab
addpath('/path/to/aot_ephys');
results = run_tests();
```

The unit suite uses temporary site files, placeholder assets, synthetic frame
maps and simulated display/audio callbacks. It needs MATLAB with a JVM and the
bundled YAML library. It does not need local site/selector files, real movies,
Psychtoolbox, FFmpeg or Python. No real display/audio device is opened.
It includes the full 84-slot run-8 fault-injection continuation test.
Fixed-fixation tests cover multiple refresh rates, late drawing, oversleep,
unchanged phase deadlines, skipped target accounting and raw timestamp logging.

`run_tests` restores the MATLAB path and removes its shared temporary fixture.
It never creates or rewrites the user's local device files. Tests can also be
discovered in `tests/unit`, with `tests/helpers` and the YAML library on path.

## Generated-media integration suite

```matlab
results = run_tests('integration'); % FFmpeg/ffprobe required.
results = run_tests('all');         % Unit + generated-media integration.
```

Integration tests generate small clips in a temporary directory and inspect
decoded frames/PTS. They do not open PTB windows or use participant movies.
FFmpeg/ffprobe can be on PATH or discoverable by `ephys.resolveVideoTools`.

## Optional real-media regression

```matlab
setenv('AOT_TEST_VIDEO_ROOT','/path/to/original/movies');
results = run_tests('local_media');
```

This opt-in suite checks `1056_rv.mp4` and `1834_fw.mp4` using FFmpeg/ffprobe.
It is intentionally outside the default and `all` suites. Missing requested
media make this explicit suite incomplete/failing rather than silently passing.

## Device checks

See [`tests/hardware/README.md`](../tests/hardware/README.md). Device checks are
manual, use a configured site, and can open full-screen windows/output WAVs.
They are never discovered by the default automated suite. Preserve raw output
outside Git and commit the concise validation report and relevant versions.

After changes to playback/trigger control, include normal completion and Q
during a pending onset/end reservation. New QC findings must remain recorded
while recoverable cases continue. Physical optical/electrical validation is a
separate measurement described in [hardware_validation.md](hardware_validation.md).

## CI entry point

The portable MATLAB batch command is:

```text
matlab -batch "addpath(pwd); results=run_tests(); assert(all([results.Passed]));"
```

A CI service must provide a licensed MATLAB environment. The default command
does not require the experiment computer's files or peripherals.
