# Runtime architecture

[`run_aot_ephys.m`](../run_aot_ephys.m) resolves the saved schedule and site,
loads/validates configuration, constructs `ephys.Session`, then calls
`run -> stopPresentation -> finish`. An `onCleanup` guard handles every exit.

| Component | Responsibility |
| --- | --- |
| `resolveRunRequest`, `resolveSitePath`, `loadConfig` | Identities, local selection, configuration and schedule provenance |
| `subjectLabel`, `scheduleSet`, `previewRunRequest`, `runRequestDialog`, `prepareOutputFolder` | Subject labels, local schedule-set map, the no-argument dialog and dated output folders |
| [`+ephys/@Session`](../+ephys/@Session/README.md) | Experiment order, display/input lifecycle and trial orchestration |
| `NativeMovieQueue`, `NativeMoviePlayer` | Current/next independent movie handles, held first textures, PTS scheduling and frame QC |
| `TriggerOutput`, `WavTriggerBackend` | Named analog waveforms, reservations, cancellation and observed audio/Flip association |
| `TimelineLog`, `writeOutput` | Buffered observations, raw persistence, post-run QC and PDF report |
| `reconstructRecords`, `reconstructTimeline` | Derive observed intervals and quality states from saved observations |
| `prepare_aot_ephys_native_media`, `tools/prepare_native_media.py` | Offline conversion and frame/content verification |

## Timing contracts

- `run()` resets scheduling to `Priority(0)` before opening devices. Startup
  movie loading and the Space wait stay at normal priority. Acquisition raises
  priority after Space and before `beginRun()`; Debug stays at normal priority.
  Presentation cleanup returns scheduling to normal on every exit path.
- Absolute timestamps use the GetSecs clock in seconds. Keep raw Flip and
  audio-driver observations separate from requested targets.
- Static fixation/blank refreshes use one phase origin: observed first onset
  plus refresh index times the opened display's IFI. Expired slots are skipped
  without moving that origin or the phase boundary. The final filler leaves
  the caller's audio reservation window intact. Ordinary backends receive a
  timed Flip directly; the Mac external backend retains its target-time guard.
- Predict the common onset from the Session's own logged Flip timeline
  (`ephys.predictVisualOnset`, PTB's rule), never PTB's internal last-Flip
  state, so each pulse keeps one relation to its Flip request.
- Draw the first texture before reserving the common audio/visual onset.
  No movie fetch, fixation Flip or drawing belongs between reservation and
  the prepared onset submission. Preserve the macOS external-backend policy.
- Keep the actual `Screen('Flip')` call in a method without nested functions;
  the macOS imaging hooks need a non-static caller workspace.
- Native frame identity is inferred from a unique offline PTS match. Unknown
  identity remains NaN. Recoverable anomalies stay visible in logs/QC.
- No file writes, hashing, full decode, environment checks or PDF generation
  belong in video refresh/onset submission paths.
- Run-time records use `ephys.ChunkedRows` (timeline 128-row chunks, markers
  32-row chunks) so that a write never copies a whole log, even when MATLAB does
  not update a property in place. Refresh and onset paths read the timeline only
  through `lastFlip`, `lastEvent` and `flipValues`, and find markers through the
  ID map; `Flips`, `Events` and `records()` assemble every row for post-run use.
  `WavTriggerBackend` keeps numeric reservation times for its collision check.
- Q cancellation and run-end handling must retain their one-attempt semantics.
  `runSession` saves a Q stop as aborted and returns; any other error is
  rethrown after the same save.
- After the initial fixation, the refresh guard compares presented with
  available fixed-grid slots from in-memory rows. A shortfall stops the run
  before trial 1 through the ordinary abort path; it is a precondition, unlike
  recoverable QC findings, which never stop the schedule.
- The fourth recording number changes only the output identity.
- Subject labels come from `subjectLabel` (numbers padded to three digits,
  names kept); `scheduleSet` maps a label to its saved schedule set through
  the untracked `config/subjects.local.yml`, and an unmapped name stops the
  request. `previewRunRequest` and the no-argument dialog use the same
  resolution without creating anything.
- `run_aot_ephys` sets `config.run_output`; `Session.initialize` then creates
  `<output_root>/<yyyy-mm-dd>/<run_id>` through `prepareOutputFolder`, which
  renames an existing folder only when Overwrite is set and never deletes.
  Sessions without `run_output` (diagnostic tools) keep a flat folder.

## Repository boundaries

Common design, schedules, waveforms, implementation and automated tests are
versioned. Local device profiles/selectors, subject maps, raw experiment output
and diagnostic results are excluded.

The earlier `frames` backend remains available for explicit legacy use. Its
FFmpeg dependency is separate from native acquisition playback. See
[dependencies](dependencies.md), [testing](testing.md) and
[configuration](configuration.md).
