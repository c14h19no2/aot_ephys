# Trigger timing and the offset report

Every run writes `<run_id>_trigger_offsets.pdf` and prints a three-line summary
such as:

```text
Trigger offsets (audio - visual): N=86, median=+7.444 ms, SD=0.929 ms.
Range=[+0.061, +10.738] ms; absolute-offset P95=7.519 ms.
Beyond +/-2 ms reference: 85/86 (98.8%); software/driver estimates.
```

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

Each video (and blank) trial starts with a pre-fixation Flip. From then on:

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
time. In the example run it matched the planned audio time to 0.000 ms for
all 86 triggers. So the reported audio start is the plan; it does not measure
the analog output.

## 5. Worked example

Trial 1 of `2026-10-27/sub-zhangsan_ses-01_run-01_task-video`, Windows test
laptop. Times are in ms after the pre-fixation Flip (`lastVBL`).

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
- **Reported visual onset − request**: after the static pre-fixation screen,
  PTB reported the onset Flip as complete only 0.7 ms (median) after the
  request time, not at the next refresh.

So `8.14 − 0.70 ≈ 7.44 ms`, the median for all 84 video and blank onsets
(SD 0.34 ms). The likely reason for the early report is the Windows desktop
compositor: it can accept the new frame before the screen actually refreshes,
and PTB's basic timestamp marks that acceptance. If so, the reported visual
onset is early, and the picture appears at the predicted refresh or later.
The logs alone cannot confirm this.

The run-start and run-end triggers are single points with different values
(+10.738 ms and +0.061 ms here). Their planned time is "now + at least 0.1 s
+ 3 refreshes" rather than a point on the trial schedule, so their request
falls at a different place in the refresh cycle: 12.46 ms and 1.64 ms before
the predicted refresh. The same rule then gives a different offset. They are
not drift.

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

The ±2 ms reference (`markers.wav.max_sync_error_s`) is for reporting only.
Values outside it do not stop a run and, on the Windows test laptop, are
expected. `sync_status` in the markers file is `within_tolerance` or
`out_of_tolerance` relative to this reference.

## 8. Reading the PDF

The report has two pages with the same header and footer.

**Header.** Run name and page title, then `N` (plotted triggers), median,
SD, range, and how many lie beyond the ±2 ms reference.

**Page 1: Offset over time.**
x-axis: seconds from the run-start Flip (or from the first plotted Flip when
there is no run-start pair). y-axis: audio start − visual Flip, in ms. The
green band and dashed lines mark ±2 ms. Markers by event: video onset (blue
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

## Code references

| Step | File |
| --- | --- |
| Request time | `+ephys/@Session/Session.m` (`computeFlipRequestTime`) |
| Prediction | `+ephys/predictVisualOnset.m`, `+ephys/blankingDuration.m` |
| Draw, reserve, Flip | `+ephys/@Session/onsetFlip.m`, `+ephys/submitPreparedOnset.m`, `+ephys/@Session/submitOnsetFlip.m` |
| Audio schedule and start time | `+ephys/WavTriggerBackend.m` (`submit`, `observedStart`) |
| Association and `sync_status` | `+ephys/TriggerOutput.m` (`associate`, `checkSync`) |
| Summary and PDF | `+ephys/triggerOffsetSummary.m`, `+ephys/printTriggerOffsetSummary.m`, `+ephys/writeTriggerOffsetReport.m` |
