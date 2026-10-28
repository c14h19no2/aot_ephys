# Session implementation

`ephys.Session` uses MATLAB's class-folder layout. Add `aot_ephys` to the
MATLAB path; MATLAB resolves the class and its separate method files from
`+ephys/@Session`. The constructor and public lifecycle method signatures are
unchanged. The internal end-attempt flag is now named `RunEndHandled` instead
of `RunEndEmitted` so its name does not imply confirmed audio output.

Do not add a flat `+ephys/Session.m` beside this class folder: MATLAB would
resolve that file first. The formal runner checks the selected class path and
cached method set before construction.

## Reading order

Start with [`Session.m`](Session.m), particularly `run()`. It contains the run
sequence, lifecycle state, and the declarations of the separate methods.
Small, shared drawing, input, and scheduling helpers are grouped by responsibility
in the same class file.

| File | Responsibility |
| --- | --- |
| [`initialize.m`](initialize.m) | Resolve media, allocate records, and create output/provenance files before opening PTB. |
| [`open.m`](open.m) | Open audio, display, media cache, keyboard queue, and EyeLink. |
| [`preloadStartup.m`](preloadStartup.m) | Prepare the initial movie batch on the loading screen. |
| [`instruction.m`](instruction.m) | Wait for Space or Q on the instruction screen. |
| [`prepareVideo.m`](prepareVideo.m) | Select an occurrence and hold its first source frame. |
| [`videoTrial.m`](videoTrial.m) | Present pre-fixation, video/blank, and post-fixation. |
| [`memoryTrial.m`](memoryTrial.m) | Present a picture and record a valid response. |
| [`runFixation.m`](runFixation.m) | Present an initial or final baseline with explicit boundary Flips. |
| [`repeatFixation.m`](repeatFixation.m), [`fixationRefresh.m`](fixationRefresh.m) | Schedule static-phase refreshes on the original onset + n × IFI grid, skip expired slots and record actual timing. |
| [`onsetFlip.m`](onsetFlip.m) | Draw a video/blank/run boundary before consecutive WAV reservation and timed Flip submission. |
| [`steadyOnsetFlip.m`](steadyOnsetFlip.m) | `display.steady_flip`: reserve the WAV, refresh fixation on every slot up to the onset, then draw and flip the onset on its slot. |
| [`submitOnsetFlip.m`](submitOnsetFlip.m) | Invoke Screen from a non-nested workspace and record submission/return timing. |
| [`flip.m`](flip.m) | Submit a prepared framebuffer and record PTB timestamps. |
| [`nextKey.m`](nextKey.m) | Read a timestamped key event or debug input callback. |
| [`endRun.m`](endRun.m) | Handle one end-trigger attempt for completion or abort. |
| [`stopPresentation.m`](stopPresentation.m) | Cancel future audio and release presentation resources. |

## Timing contract

- Absolute times use the `GetSecs` clock, in seconds. Movie-relative PTS stays
  inside the player; the video display clock starts at the actual frame-zero Flip.
- Native initialization reads metadata/PTS from prepared JSON maps and hashes
  both original and native files. It never resolves or launches FFmpeg/ffprobe;
  offline preparation and the legacy frames backend retain those dependencies.
- `plannedVideoOnset` and `plannedVideoOffset` are desired visual boundaries.
- With `display.steady_flip` (video task; on by default), `steadyOnsetFlip()` replaces
  `onsetFlip()` for video/blank onsets and the run end. It predicts and
  reserves the WAV as soon as the onset slot is known, then refreshes fixation
  on every grid slot before it (`repeatFixation`), draws the onset frame after
  the last refresh and submits it through `submitOnsetFlip`. The reservation
  stays outside the refresh stream because it takes 1-25 ms. The Mac external
  guard applies unchanged; `submission_mode` gains a `steady_` prefix.
- `onsetFlip()` draws the first frame and calls `DrawingFinished` before
  predicting/reserving WAV onset. `submitPreparedOnset` then dispatches the
  frozen visual request immediately after audio scheduling. No fixation
  refresh, media preparation or drawing separates those calls.
- Windows/ordinary backends use a direct synchronous timed Flip. Queued Q is
  handled on return, after logging the actual frame and associating the audio.
  The macOS external sink retains a guard because local distant-Flips
  presented early. It waits for the same predicted onset reserved for audio,
  not the earlier half-IFI request threshold, polling Q/audio without redrawing.
  `submission_mode` distinguishes `direct` from `macos_external_target`.
  This bounds early dispatch on that backend; dispatch/presentation latency
  remains in the raw observations and is not corrected with a fitted bias.
- Frame-drawn, actual Screen call and return times are recorded independently.
  Frame readiness here describes CPU drawing commands, not optical validation.
- Keep the actual `Screen('Flip')` invocation in `submitOnsetFlip.m` without
  nested functions. The macOS imaging pipeline injects variables into its
  caller, which fails in a nested function's static MATLAB workspace.
- `reserveMarker()` remains the helper for the optional video-offset path;
  it predicts a future visual onset and schedules the audio
  waveform for that prediction. The prediction is not a measured onset.
- Both paths predict with `ephys.predictVisualOnset`: PTB's
  `PredictVisualOnsetForTime` rule (first refresh after the request) applied
  to `LastVBL`, the VBL timestamp this Session logged for its last Flip, plus
  PTB's blanking correction cached at `open()`. PTB's internal `LastVBLTime`
  is not read: on the Windows test laptop it drifted from the returned
  timestamps with time since the Flip, which moved the audio target of
  after-blank trials by 7–13 ms. On the Mac both values were identical.
- `computeFlipRequestTime()` computes the earlier threshold passed to
  `Screen('Flip')`. Prepared onsets freeze it before audio prediction; ordinary
  unmarked refreshes compute it on entry to `flip()`. An already reserved audio
  time is not silently changed.
- `onsetFlip` and `offsetFlip` hold returned PTB observations. The actual onset
  is associated with the audio receipt after Flip, and the difference is reported.
- `repeatFixation()` covers initial/final baselines, pre/post fixation and blank
  slots. Its target grid is the phase's first observed onset plus n times IFI;
  returned timestamps never rebase it. `nextFixationRefresh()` skips slots that
  no longer have half an IFI of submission headroom. Drawing and oversleep are
  checked again before submitting, without catch-up bursts. Actual submission
  ordinals and planned slot indices are separate log fields.
- `fixationRefresh()` submits timed Flips immediately on ordinary backends.
  The Mac external-backend guard waits until the target, polling Q/audio; if
  dispatch overruns by half an IFI it selects another future slot. Skipped slots
  count unsubmitted targets, not measured physical display refreshes. Actual
  onset error remains observable even for targets that were submitted.
- Baselines retain explicit onset/end boundary Flips and the existing audio
  booking margin; their duration is not a sum of frame counts. Video texture
  refresh and first-frame/WAV onset policies are unchanged by this static-phase
  scheduler. It cannot guarantee stable physical display timing on a stalled OS.
- Marker settings and baseline durations are unchanged. The log schema adds
  preparation/submission observations while retaining historical field meanings.

## Lifecycle contract

`run_aot_ephys` calls `run()`, `stopPresentation()`, and `finish()` in that order.
Its cleanup guard calls `close()` on every exit.

`run()` explicitly resets scheduling to normal before opening devices, including
when an earlier script left elevated priority in the MATLAB process. Initial
movie loading and the Space wait use normal priority. Non-Debug runs raise
priority only after Space and before run-start handling. Cleanup returns to
normal priority after completion, loading failure or Q cancellation. This keeps
the first GStreamer initialization outside elevated scheduling on Windows.

| State or method | Meaning |
| --- | --- |
| `RunStarted` | Space has been accepted and run-boundary handling has begun. |
| `RunEndHandled` | The end attempt has been claimed, or boundary output is disabled. It does not prove physical output or successful completion; inspect the trigger receipt. |
| `stopPresentation()` / `PresentationStopped` | Cancel future audio before slow resource cleanup, then release movie, input, and display resources. |
| `finish()` / `Finalized` | Finish trigger/EyeLink collection and persist logs, QC, and the PDF report once. |
| `close()` / `Closed` | Guard final cleanup and save an unfinished session as aborted. |

Q cancels pending reservations and raises `ephys:UserAbort`; `ephys.runSession`
saves the run as aborted and returns without an error for it. After presentation
cleanup, `finish()` attempts the end waveform if a run has started and its end
attempt has not already been handled. Abort end markers do not invent a visual
association. An end attempt is never retried merely because a later cleanup step
fails.

## Initial-fixation refresh guard

`run()` calls `checkRefreshGuard()` after the initial fixation's boundary Flip
and before trial 1. It reads only the baseline rows' numeric slot indices
(about 1 ms) and passes the presented count to `ephys.refreshGuard`; interval
metrics are added by `writeOutput` after presentation. Below
`display.refresh_guard_min_fraction` it raises `ephys:RefreshGuard`: this is an
acquisition precondition, not a recoverable QC finding. The ordinary abort path
then saves the logs and attempts one run end. Baselines shorter than one second
of slots, or a `null` setting, are recorded without a decision. The guard does
not draw, flip, write files or change any phase boundary; the first
pre-fixation Flip keeps its existing request.

## Recoverable runtime QC

Timing and decoder quality findings are recorded without stopping the schedule.
`NativeMoviePlayer` retains raw PTS, uses unique offline PTS matches for source
identity, and holds the last drawable texture after early EOF. Unmatched source
identity stays NaN. Loading past a fixation deadline is recorded and may extend
fixation. The first-frame timeout still bounds the absence of a drawable frame.

`WavTriggerBackend` records lead shortfalls and underruns in `audio_qc_flags`.
It reads the master and slave status on every poll but passes a receipt to the
marker table only when the receipt changed, so a pending reservation does not
rewrite its marker row on every refresh.
An unobserved start/completion stops that reservation and records a failed,
QC-only receipt; subsequent events continue. Actual device-call errors still
propagate. `TimelineLog` and `TriggerOutput` grow their buffers when needed.

`writeOutput` saves raw logs and resolved configuration before post-run QC.
Analysis/report failures are recorded independently of the presentation status.
