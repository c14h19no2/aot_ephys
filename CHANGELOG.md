# Changes

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
