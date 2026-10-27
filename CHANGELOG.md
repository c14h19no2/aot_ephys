# Changes

## 2026-10-27 — Steady onset mode

- New setting `display.steady_flip` (video task), `true` by default in
  `config/experiment.yml`; a site file can set `false`. When `true`, fixation
  is refreshed on every grid slot up to each WAV-marked onset (video, blank
  and run end) instead of holding the drawn onset frame, so the display
  pipeline is in the same continuous state at every onset. The WAV is
  reserved as soon as the onset slot is known, before the refresh stream; the
  onset uses the same prediction and Flip request rule as held mode
  (`false`), which was the only behaviour before this change.
- The manifest records `display_timing.onset_flip_mode` (`held` or `steady`);
  steady onsets have `submission_mode` `steady_direct`.
- On the Windows test laptop the refresh stream was continuous after loading
  (80 of 84 trials in a full steady run), and the software offsets did not
  separate the modes (video onsets +7.44 ms held vs +7.71 ms steady, SD
  0.34 vs 0.33 ms). docs/trigger_timing.md describes how to compare them with
  a photodiode.
- Verified 222 unit tests on MATLAB R2022b Update 10, including steady-mode
  Session runs on a simulated display (continuous refresh, onset slot, Q after
  the reservation, run end and the Mac external-backend wait).

## 2026-10-26 — First version of aot_ephys

New repository. The earlier development history is kept outside it.

- Presents saved video (forward, reverse, blank) and memory schedules with
  named analog WAV triggers (PsychPortAudio, 48000 Hz, channel 2), per-Flip
  timing logs, event and marker logs, and post-run QC with a trigger-offset PDF.
- `run_aot_ephys()` opens a dialog for subject, session, run, task and
  Overwrite, with a live preview of the output folder and schedule.
- Subject labels: numbers are zero-padded to three digits (`sub-003`) and use
  their own schedule set; letters-and-digits names take theirs from the
  untracked `config/subjects.local.yml`.
- Each run is saved in `<output_root>/<yyyy-mm-dd>/<run_id>`. Overwrite
  renames an existing same-day folder to `_replaced-<HHMMSS>`; nothing is
  deleted, and a refused repeat never writes into an existing recording.
- Onset and offset pulses are scheduled from the Session's logged Flip
  timeline, so each pulse keeps a fixed relation to its frame request.
- Fixation and blank refreshes follow a fixed onset + n × IFI grid; the
  initial-fixation refresh guard stops a run before the first trial when the
  display loop presents too few refreshes.
- Pressing Q saves the observed part as aborted, attempts the one run-end
  pulse and prints a "Run stopped with Q." banner instead of an error.
- Timeline and trigger logs use bounded-write chunked storage, so the first
  run in a fresh MATLAB session keeps the full refresh rate.
- Verified 216 unit tests on MATLAB R2022b Update 10.
