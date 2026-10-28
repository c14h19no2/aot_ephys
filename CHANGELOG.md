# Changes

## 2026-10-28 — Fixation in degrees, as in the original Python task

- `stimulus.fixation` is now set in degrees of visual angle in
  `config/experiment.yml`: gray surround 0.18270° with a raised-cosine edge
  over its outer 30% (PsychoPy `raisedCosine`, `fringeWidth = 0.3`), black dot
  0.03654°, and two white 0.00788° lines at 45° and 135°. It stays at the
  window (movie) centre.
- The specification's 0.00788° white outline around the dot is optional:
  `outline_width_deg` is 0 (no outline) by default.
- Drawing order: surround, lines, then the dot (and outline, if set). The
  specification draws the lines last, but at a few pixels across they hide
  most of the black dot, which then looks white.
- `ephys.fixationGeometry` converts the angles to pixels from the movie's
  pixel width and `stimulus.target_size_deg` (the viewing distance at which the
  movie has its target angle), so they hold on any screen without per-site
  pixel values: on a 1920-pixel movie 24.20, 4.84 and 1.04 px. Surround and
  dot are 8 x 8 supersampled textures made at window open and drawn
  pixel-aligned; the lines are anti-aliased (`DrawLines`, smooth) with alpha
  blending enabled only for the fixation. The manifest saves the pixel
  geometry and the driver's smooth-line width range as `fixation`.
- Removed `dot_radius_px`, `surround_diameter_px` and `line_width_px`; site
  files that still set them stop with an unknown-field error.
- Verified 248 unit tests on MATLAB R2022b Update 10.

## 2026-10-28 — 60 Hz default refresh rate

- `display.expected_refresh_hz` in `config/experiment.yml` is now 60 (was 120),
  the rate of both current sites. A site with another rate sets it in its site
  file. Verified 243 unit tests on MATLAB R2022b Update 10.

## 2026-10-28 — Viewing distance for the target movie size

- New `stimulus.target_size_deg` in `config/experiment.yml`, default
  `[14.42, 8.14]` degrees, and new `display.screen_size_cm` (visible picture
  width and height in cm, default `null`) for the site file.
- `ephys.viewingDistance` computes the eye-to-screen distance at which the
  fitted movie (window fit with `movie_scale`, at the target's aspect) has the
  target angle: one distance per axis from the movie's size in cm, and their
  mean. If the measured screen aspect differs from the resolution's, the angle
  at that distance is reported as well.
- The run dialog (560 × 360 px) starts with a site row: a dropdown of
  `config/site.*.yml` (the site in `active_site.yml` preselected and marked
  "(active)"), then that site's screen size, resolution and refresh rate, the
  viewing distance in bold (or a request for `display.screen_size_cm`), and a
  warning when it is not approved for acquisition. Subject, session, run, task
  and Overwrite follow after a gap. Choosing another site and pressing Start
  writes it to `active_site.yml`, keeping its comments; Cancel changes nothing.
  New helpers: `ephys.siteChoices`, `ephys.setActiveSite`,
  `ephys.siteSummary`, `ephys.siteSummaryText`.
- The manifest saves the viewing distance as `viewing`. Invalid sizes stop a run
  in `validateConfig` (`ephys:ScreenSize`, `ephys:TargetSize`); the dialog
  shows them in red.
- Verified 243 unit tests on MATLAB R2022b Update 10.

## 2026-10-28 — No video hashing at run start

- A native video run no longer computes the SHA-256 of original videos and
  native copies before opening the window. It still requires each JSON map to
  be valid and each native copy to exist (`ephys:NativeMediaMissing`). Changed
  bytes are no longer detected at run start (`ephys:NativeMediaChanged` is gone).
- In the manifest, `media.sha256` is empty for native videos and the
  `native_sha256` field is no longer written; `native_map.source_sha256` and
  `native_map.sha256` are the values recorded at preparation, not checked
  during the run. Memory pictures and the legacy frames backend are still
  hashed; configuration files and trigger WAVs are hashed as before.
- New `verify_aot_ephys_media` checks originals and copies against their maps
  outside a run: all MP4s of the selected site, or one saved schedule with
  `(sub,ses,run)`. It reports `map_missing`, `map_invalid`, `original_missing`,
  `original_changed`, `native_missing` and `native_changed`, warns if any are
  found and needs neither FFmpeg nor Python.
- The all-videos mode of `prepare_aot_ephys_native_media` and the new check
  skip hidden files such as macOS `._name.mp4` sidecars.
- On the Windows test laptop, the run-start media check for run 8 (67 videos)
  fell from 12.3-13.5 s to 0.1-0.2 s. `verify_aot_ephys_media(1,1,8)` took
  12 s and found all 67 videos matching their maps.
- Verified 231 unit tests on MATLAB R2022b Update 10.

## 2026-10-27 — Cheaper trigger polling

- `WavTriggerBackend` still reads the master and slave status on every poll,
  but passes a receipt to the marker table only when it changed. Before, a
  pending reservation rewrote its marker row on every poll, about four times
  per refresh, through the whole pre-fixation and final fixation. Polling also
  no longer rebuilds the empty receipt template. Marker rows, timeouts,
  completion and Q cancellation are unchanged.
- In the last run on the Windows test laptop, refreshes with a pending
  reservation took a median 8.5-8.9 ms of MATLAB work against 3.1-3.3 ms
  without one. Benchmark of `TriggerOutput.poll` with a fake audio device on
  the same laptop: 544 to 157 us per poll with a pending reservation (about
  103 us of it is the fake device; a real status call takes about 17 us), and
  47 to 6 us per poll without one.
- In the next full run on that laptop, median MATLAB work per refresh fell
  from 8.5 to 4.5 ms in pre-fixation and from 8.9 to 3.9 ms in final fixation.
- Verified 227 unit tests on MATLAB R2022b Update 10.

## 2026-10-27 — Trigger offset QC relative to the run median

- The trial QC counts a trigger offset as a sync issue only when it differs
  from the run's median offset by more than `markers.wav.max_sync_error_s`
  (2 ms). A constant offset is no longer an issue; before, every offset
  beyond ±2 ms of zero (`sync_status` `out_of_tolerance`) was. The failure
  states `failed`, `late` and `missing_timestamp` still count. The median
  uses the same triggers as the offset PDF, including run start and run end;
  without any observed pair it is unknown and no offset is judged.
- New fields: `trial_qc.tsv` `max_abs_delta_from_run_median_s`;
  manifest `run_qc.audio_visual_median_s` and `run_qc.audio_sync_issue_count`.
  `sync_status` in the markers file is unchanged (relative to zero).
- The console summary and the PDF header also give the number of triggers
  more than 2 ms from the median, beside the count beyond ±2 ms of zero.
- Re-running the QC on the saved steady-mode run from the Windows test laptop
  (median +7.695 ms): timing anomalies fall from 84 trials to 6, all with
  missed deadlines; the largest trial distance from the median is 1.833 ms.
- Verified 225 unit tests on MATLAB R2022b Update 10.

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
