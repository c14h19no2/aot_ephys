# Trigger timing and the offset report

Every run writes `<run_id>_trigger_offsets.pdf` and prints a three-line summary
such as:

```text
Trigger offsets (audio - visual): N=86, median=+7.695 ms, SD=0.598 ms.
Range=[+3.715, +7.763] ms; absolute-offset P95=7.746 ms; software/driver estimates.
Beyond median +/-2 ms (trial QC rule): 2/86 (2.3%); beyond +/-2 ms of zero: 86/86.
```

(A steady-mode run on the Windows test laptop. The two triggers beyond the
median are run start and run end; see section 6.)

This page explains where both numbers come from, how the trigger time is
predicted, and what the report can and cannot tell you.

> **In short.** For each trigger, the offset is
> *PsychPortAudio's reported audio start* minus *Psychtoolbox's reported
> visual onset of the matching Flip*. Both are software estimates on the
> computer's clock. Neither is a measurement of light on the screen or of the
> pulse on the cable. A small SD means every trigger kept the same relation to
> its frame request. The median value itself depends on how the computer
> reports Flip times; it is not the physical delay between picture and pulse.
> That delay must be measured once with a photodiode (see
> [Measuring the real delay](#9-measuring-the-real-delay)).

## 1. Clock and terms

All times are absolute seconds on Psychtoolbox's `GetSecs` clock, the same
clock for audio and video. Log columns end in `_getsecs`.

| Term | Meaning | Where it is logged |
| --- | --- | --- |
| Refresh interval (IFI) | Time between screen refreshes, measured by PTB when the window opens (16.6635 ms in the example run, about 60 Hz). | manifest `scheduling_ifi_s` |
| Planned onset | When the schedule wants the stimulus. For a video or blank: the pre-fixation onset plus the configured pre-fixation duration (1.0 s). | not logged separately; it sets the request below |
| Flip request time | The `when` passed to `Screen('Flip', window, when)`: half a refresh before the planned onset. PTB shows the frame at the first refresh after this time. | flips `requested_deadline_getsecs` |
| Predicted onset | The refresh at which that Flip is expected to appear, counted in whole refreshes from the previous logged Flip (section 3). | markers `predicted_visual_getsecs` |
| Planned audio time | The time the trigger WAV is scheduled for. It is always the predicted onset. | markers `planned_audio_getsecs` |
| Reported visual onset | `StimulusOnsetTime` returned by the onset Flip. | flips `stimulus_onset_getsecs`, copied to markers `associated_flip_getsecs` |
| Reported audio start | `StartTime` reported by PsychPortAudio for that WAV. | markers `audio_start_getsecs` |
| Offset | Reported audio start minus reported visual onset. Positive: audio reported after the picture. | markers `audio_visual_delta_s`; PDF y-axis in ms |

`request_getsecs` in the markers file is a different time: when the audio
reservation was made, not the Flip request.

## 2. How one video onset is scheduled

Each video (and blank) trial starts with a pre-fixation Flip. The steps below
describe held mode (`display.steady_flip: false`). Steady mode, the default,
differs in steps 1, 4 and 5: fixation keeps being refreshed until the onset
and the onset frame is drawn just before its Flip (see
[section 10](#10-held-and-steady-onset-modes)). From the pre-fixation Flip on:

1. **Draw the first frame.** The first movie frame (or the blank screen),
   fixation and optional photodiode patch are drawn into the back buffer. The
   fixation stays on screen while the new frame waits
   (`+ephys/@Session/onsetFlip.m`).
2. **Fix the Flip request time.**
   `request = max(lastVBL + IFI/2, plannedOnset - IFI/2)`, where `lastVBL` is
   the time logged for the previous Flip
   (`Session.computeFlipRequestTime`). For a video trial this is
   `plannedOnset - IFI/2`: half a refresh early, so that the frame is due at
   the refresh nearest the planned onset.
3. **Predict the onset** from the request (section 3).
4. **Reserve the audio** for exactly the predicted onset
   (`ephys.submitPreparedOnset` → `TriggerOutput.schedule` →
   `WavTriggerBackend.submit`, which calls
   `PsychPortAudio('Start', slave, 1, predictedOnset)`). This happens about
   0.2-1 s before the onset (markers `audio_lead_s`; at least 0.1 s is
   required, `markers.wav.minimum_lead_s`).
5. **Call `Screen('Flip', window, request)`** straight away. The call waits
   inside PTB until the request time and then swaps the buffers. Nothing else
   is drawn or loaded in between.
6. **Associate.** The Flip's reported onset is attached to the trigger's
   marker row, and the offset is computed (`TriggerOutput.associate`).

The audio is never moved after it is reserved. If a Flip comes late, the
trigger still plays at the predicted time, and the offset shows the
difference.

## 3. How the onset is predicted

`ephys.predictVisualOnset` uses the same rule as Psychtoolbox's
`PredictVisualOnsetForTime`, applied to the Session's own log:

```text
predictedOnset = lastVBL + (floor((request - lastVBL) / IFI) + 1) * IFI + vblDuration
```

In words: starting from the time logged for the previous Flip, count whole
refresh intervals, and take the first refresh boundary after the request
time. `vblDuration` is PTB's blanking correction. It is 0 when PTB cannot
measure the blanking period, as on the Windows test laptop (manifest
`display_timing.vbl_duration_s`).

Two details matter:

- The prediction is anchored to the **logged** previous Flip, not to PTB's
  internal "last Flip" value. On the Windows test laptop that internal value
  changed depending on when it was read, which moved some triggers by 7-13 ms.
  Using the log keeps every trigger in the same relation to its request.
- The refresh grid is built from PTB's own timestamps. If those timestamps
  are shifted from the real screen refreshes, the predicted onset is shifted
  the same way.

## 4. How the two reported times are obtained

**Visual onset.** `[vbl, onset, returned] = Screen('Flip', window, request)`.
PTB fills `onset` with its estimate of when the new frame started to appear.
When the graphics driver lets PTB read the screen's scan position, PTB
corrects the time to the start of the refresh. On the Windows test laptop
(Intel HD Graphics 520) that reading is broken, so PTB uses *basic
timestamping*: it reads the clock as soon as it sees the buffer swap reported
as complete. In the example run, `onset` equals `vbl`, and `Screen('Flip')`
returned 0.02-0.03 ms later.

**Audio start.** After scheduling, the backend asks
`PsychPortAudio('GetStatus', slave)` for `StartTime`: PsychPortAudio's
estimate of when the first sample of the WAV leaves the sound card, based on
its schedule and the latency the audio driver reports (10 ms for WASAPI on the
test laptop). When playback starts on schedule, this equals the requested
time. In the held-mode run of section 5 it matched the planned audio time to
0.000 ms for all 86 triggers. So the reported audio start is the plan; it does not measure
the analog output.

## 5. Worked example

Trial 1 of a held-mode run of `sub-zhangsan_ses-01_run-01_task-video` on the
Windows test laptop (2026-10-27, morning). Times are in ms after the
pre-fixation Flip (`lastVBL`).

| Step | Time (ms) | Log column |
| --- | ---: | --- |
| Pre-fixation Flip (`lastVBL`) | 0.000 | flips `vbl_getsecs` |
| Audio reserved | 13.4 | markers `request_getsecs` |
| Onset Flip called (waits inside PTB) | 23.754 | flips `flip_submit_getsecs` |
| Planned onset (pre-fixation + 1.0 s) | 1000.000 | - |
| Flip request = planned − IFI/2 | 991.668 | flips `requested_deadline_getsecs` |
| **Reported visual onset** | **992.637** | flips `stimulus_onset_getsecs` |
| Flip returned | 992.659 | flips `flip_return_getsecs` |
| Predicted onset = 60 × 16.6635 ms | 999.809 | markers `predicted_visual_getsecs` |
| **Reported audio start** (= planned audio time) | **999.809** | markers `audio_start_getsecs` |
| **Offset** | **+7.172** | markers `audio_visual_delta_s` |

The prediction: `(991.668 − 0) / 16.6635 = 59.5` refreshes, rounded down to
59, plus 1 gives refresh 60, at 999.809 ms. It is 0.19 ms earlier than the
nominal 1000 ms because the measured refresh interval is slightly shorter
than 1/60 s.

## 6. Why the offset is about +7 ms on the Windows test laptop

The offset can be split into two parts:

```text
offset = (predicted onset − request) − (reported visual onset − request)
```

- **Predicted onset − request** is where the request falls within the
  refresh cycle. For videos and blanks it is about half a refresh (8.14 ms
  median), because the request is placed half a refresh before the planned
  onset.
- **Reported visual onset − request**: PTB reported the onset Flip as
  complete only about 0.7 ms (median) after the request time, not at the next
  refresh.

So `8.14 − 0.70 ≈ 7.44 ms`, the median for all 84 video and blank onsets of
the held-mode run (SD 0.34 ms). A full steady-mode run on the same laptop the
same evening gave the same picture: the onset Flip was reported 0.63 ms after
its request, video onsets +7.71 ms (SD 0.33 ms), blanks +7.12 ms (SD 0.09 ms).
The likely reason for the early report is the Windows desktop
compositor: it can accept the new frame before the screen actually refreshes,
and PTB's basic timestamp marks that acceptance. If so, the reported visual
onset is early, and the picture appears at the predicted refresh or later.
The logs alone cannot confirm this.

The run-start and run-end triggers are single points with different values
(+10.738 ms and +0.061 ms in the held-mode run; +3.715 ms and +5.093 ms in
the steady-mode run). Their planned time is "now + at least 0.1 s
+ 3 refreshes" rather than a point on the trial schedule, so their request
falls at a different place in the refresh cycle (in the held-mode run 12.46 ms
and 1.64 ms before the predicted refresh). The same rule then gives a
different offset. They are not drift, and the trial QC (section 7) does not
include them.

On a Mac with an external display (`submission_mode` =
`macos_external_target`), the Flip is held back until the predicted onset
before it is submitted, so offsets there have a different typical value.

## 7. What the offset can and cannot show

It **can** show:

- whether every trigger kept the same relation to its frame request
  (small SD, no drift over time on page 1);
- outliers: a trial whose Flip was reported late or whose audio did not start
  on schedule;
- failures recorded during the run (red circles in the PDF).

It **cannot** show:

- when the picture actually changed on the screen;
- when the analog pulse actually left the sound card or reached the
  recording system;
- therefore, the real delay between picture and trigger.

**Trial QC.** The ±2 ms reference (`markers.wav.max_sync_error_s`) applies
to the spread of the offsets, not to their size. A trigger counts as a sync
issue only when its offset differs from the **run's median offset** by more
than 2 ms. A constant offset, such as the +7.4 ms on the Windows test laptop,
is therefore not an issue: it is one fixed relation, which a photodiode
measurement turns into a correction (section 9). A trial whose offset jumps
away from the others is an issue.

- The median is taken over the same triggers as the PDF (section 8),
  including run start and run end. It is saved in the manifest as
  `run_qc.audio_visual_median_s`. If no trigger has both timestamps, the
  median is unknown and no offset is judged.
- Per trial, `trial_qc.tsv` gives `audio_sync_issue_count`,
  `max_abs_audio_visual_delta_s` (largest offset from zero) and
  `max_abs_delta_from_run_median_s` (largest distance from the median).
  `run_qc.audio_sync_issue_count` is the sum over trials.
- A sync issue sets `software_marker_issue`, so the trial's `quality_state`
  is `timing_anomaly_detected`. It never stops a run.
- Run start and run end are not trials, so they are not in the trial QC,
  but they are in the console and PDF counts.

`sync_status` in the markers file is still `within_tolerance` or
`out_of_tolerance` relative to zero, because the median is only known after
the run. The trial QC does not use `out_of_tolerance`; only the failure
states `failed`, `late` and `missing_timestamp` still count directly.

## 8. Reading the PDF

The report has two pages with the same header and footer.

**Header.** Run name and page title, then `N` (plotted triggers), median,
SD, range, how many lie more than 2 ms from the median (the trial QC rule,
section 7) and how many lie beyond ±2 ms of zero.

**Page 1: Offset over time.**
x-axis: seconds from the run-start Flip (or from the first plotted Flip when
there is no run-start pair). y-axis: audio start − visual Flip, in ms. The
green band and dashed lines mark ±2 ms around zero; the trial QC uses ±2 ms
around the median instead. Markers by event: video onset (blue
circles), blank onset (green squares), run start (orange diamond), run end
(red cross), video offset (purple triangles, off by default). A large red
circle marks an event that failed but still has both timestamps.

Look for: a flat, narrow band (good); a step or slope (the relation changed
during the run); isolated points (single trials to check in the flips and
markers files).

**Page 2: Offset distribution.** Histogram of the same values for video and
blank onsets; run start and run end are drawn as vertical lines. A single
narrow peak means a stable relation.

**Footer.** Run status (complete or aborted), total events, how many were
excluded, how many failed events are plotted, and a reminder that these are
estimates.

**Which triggers are plotted.** A trigger is included when its status is
`complete` or `failed` and it has both a reported audio start and an
associated Flip. Cancelled reservations (for example after Q), dummy markers
(memory task) and triggers without both timestamps are excluded and counted
in the footer. No value is ever filled in or simulated.

The same numbers are saved in the manifest under `trigger_offset_report`, and
per trigger in the markers file.

## 9. Measuring the real delay

To know when the stimulus appeared relative to the trigger in your recording:

1. Enable the photodiode patch (`photodiode.enabled` in the site file) and fix
   a photodiode over it.
2. Record the photodiode and the trigger output on two channels of the
   **same** recording system.
3. For each onset, compute trigger edge − photodiode edge.

If that difference is constant, use the triggers recorded in your
electrophysiology data and correct every onset by this one constant. On the
Windows test laptop expect it to differ from the software offset in the PDF,
possibly by about one refresh (16.7 ms), because of the compositor and triple
buffering. See [hardware_validation.md](hardware_validation.md).

## 10. Held and steady onset modes

`display.steady_flip` (video task) chooses how each WAV-marked onset is
presented. It is `true` in `config/experiment.yml`, so steady is the default;
a site file can set `false`. Both modes use the same planned onset, Flip
request rule, onset prediction and audio lead.

| | Held (`steady_flip: false`) | Steady (`steady_flip: true`, default) |
| --- | --- | --- |
| Pre-fixation | One Flip at its onset; the next movie loads; then the screen is not refreshed again before the onset. | One Flip at its onset; the next movie loads; then fixation is refreshed on every grid slot up to the onset. |
| Onset frame | Drawn right after loading and held in the back buffer for up to about 1 s. | Drawn after the last held refresh, about 3-4 ms before its Flip. |
| Audio reservation | Just before the onset Flip call, 0.2-1 s ahead. | As soon as the onset slot is known, before the refresh stream, 0.2-1 s ahead. Reserving inside the stream would cost a refresh: one reservation takes 1-25 ms. |
| Onset `submission_mode` | `direct` | `steady_direct` |
| Manifest `display_timing.onset_flip_mode` | `held` | `steady` |

The run-end pulse follows the mode: in steady mode the final baseline is
refreshed every frame up to its end slot. The run-start pulse is presented the
same way in both modes. Q during the refresh stream cancels the reserved
pulse, as in held mode.

**What the Windows test laptop logs showed** (8 trials of run 8 per mode,
full screen, 2026-10-27). Held: software offset median +7.38 ms, SD 0.31 ms.
Steady: the refresh stream was continuous in every trial after loading, and
each onset was reported at the same point relative to its request as the
refreshes just before it; median +7.68 ms, but one trial at −0.42 ms
(SD 2.85 ms). Where a Flip is reported relative to its request changed between
trials (about 1.2 ms or 8.9 ms after it), because it depends on where the
request falls within the screen's real refresh cycle, which the software
cannot see. A full steady-mode run of all 84 trials (same evening) had a
continuous refresh stream in 80 trials and the same offsets as the full
held-mode run (video onsets +7.71 vs +7.44 ms median, SD 0.33 vs 0.34 ms).
The software offsets therefore cannot decide between the modes; the
photodiode can.

**Comparing both modes in one photodiode session**

1. Enable the patch in the site file: `photodiode.enabled: true`,
   `photodiode.approved_placement: true` and a corner rectangle, for example
   `rect_px: [0, 0, 60, 60]`. It is white during every movie and black
   otherwise, so each movie onset gives a rising edge. Blanks have no patch.
2. Record the photodiode and the trigger output on two channels of the same
   recording system.
3. Run once with `display.steady_flip: false` and once with `true`, as
   separate recordings (use another run or recording number, or Overwrite).
   Check `display_timing.onset_flip_mode` in each manifest.
4. For every movie onset, compute trigger edge − photodiode edge. Compare the
   spread (SD, range, outliers) between the modes, and keep the mode with the
   smaller spread. Its median is the constant to correct in analysis.

## Code references

| Step | File |
| --- | --- |
| Request time | `+ephys/@Session/Session.m` (`computeFlipRequestTime`) |
| Prediction | `+ephys/predictVisualOnset.m`, `+ephys/blankingDuration.m` |
| Draw, reserve, Flip | `+ephys/@Session/onsetFlip.m`, `+ephys/submitPreparedOnset.m`, `+ephys/@Session/submitOnsetFlip.m` |
| Steady onset mode | `+ephys/@Session/steadyOnsetFlip.m`, `+ephys/@Session/repeatFixation.m` |
| Audio schedule and start time | `+ephys/WavTriggerBackend.m` (`submit`, `observedStart`) |
| Association and `sync_status` | `+ephys/TriggerOutput.m` (`associate`, `checkSync`) |
| Summary and PDF | `+ephys/triggerOffsetSummary.m`, `+ephys/printTriggerOffsetSummary.m`, `+ephys/writeTriggerOffsetReport.m` |
