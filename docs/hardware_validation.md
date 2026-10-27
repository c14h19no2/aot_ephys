# Electrophysiology acquisition validation checklist

No physical recording-system trigger or display synchronization has been validated. Before participant acquisition, record the acquisition computer, OS, MATLAB/PTB/GStreamer versions, display and trigger-device models/firmware, exact media hashes, tester, date, raw measurements, thresholds, and pass/fail decisions. Set numerical scientific acceptance limits before observing study data.

| Check | Measurement and decision |
| --- | --- |
| Electrical interface | Confirm the actual output device, input connector, voltage, polarity, pulse width, inter-pulse interval, code encoding, safe reset, initialization, and cleanup with the acquisition-system engineer. Implement these values in the site backend only after confirmation. |
| Event recognition | Send each configured WAV, repeated same-waveform events and controlled failures. Verify waveform classification, ordering, omissions, duplicates, baseline return, and event UUID/sequence correspondence; memory dummy events are not physical outputs. |
| Trigger latency and jitter | Record backend request/write/completion and independently measured TTL edges. Quantify mean, spread, drift, outliers, and behavior under load. Do not equate a software completion timestamp with the edge without measurement. |
| PTB display | Verify actual resolution, sync-test pass, measured IFI and stable refresh under representative media load. Compare requested deadlines, VBL/stimulus timestamps, `Missed`, and independent photodiode/high-speed-camera observations. |
| First and last video frames | Use clips with identifiable first/last frames. Confirm preparation does not show a frame early; scheduled onset audio must correspond to the Flip showing source frame zero. Measure the actual electrical-to-optical difference. Offset audio is off by default; test the optional waveform separately. |
| Frame sequence | Test forward and separately encoded reverse clips, normal 60-to-120 Hz repeats, decoder underruns, PTS gaps, true skips, wrong first frame, and premature end. Validate an offline source-frame-to-PTS map against exact hashed assets before using frame-level feature vectors. |
| Photodiode placement | Approve its corner rectangle and visual confound on the scientific stimulus. Compare same-framebuffer photodiode transitions with TTL and PTB flip estimates. Account for vertical scanout position and pixel-response latency. |
| Timebase fit | Establish independent event correspondence across the entire run; detect missing, duplicate, and ambiguous TTLs. With at least three reliable anchors, fit PTB reported audio start time to recording-system time and assess drift, residuals, and uncertainty. Calibrate trigger latency and photodiode delay before mapping visual intervals. |
| Visual and behavioral parity | Compare fixation geometry, movie rectangle, color/gamma, schedule identity/order, memory pictures, J/K response handling, and scoring to the chosen Python protocol. Confirm the intended 180- versus 360-picture memory schedule. |
| Long-run stability | Run full video and memory sessions with actual media and output storage. Inspect QC for every trial, backend queue/pulse reset, decoder resources, input event loss, EyeLink transfer if enabled, abort/recovery, and output overwrite protection. |

Software QC states such as `software_checks_valid_hardware_unverified` do not certify the display photons or the TTL edge. Interpret `Missed` only where its backend semantics apply; a low count alone cannot prove that the intended frames appeared. Physical onset accuracy, acceptable jitter, feature-alignment precision, and clock residual limits require study-specific thresholds and measured evidence.

## Named WAV protocol

Video tasks use `PsychPortAudio` to output named analog waveforms. The active
configuration and marker rows contain `trigger_key` and `waveform_file`, with
no numeric event-code mapping or integer TTL encoding. A completed run 8 should
output 86 waveforms: 72 movie onsets, 12 blank onsets, run start and run end.

| Named event | Waveform | Boundary |
| --- | --- | --- |
| `run_start` | `TrigP08.wav` | Space-confirmed start boundary before the initial baseline. |
| `video_onset` | `TrigP16.wav` | Movie frame zero or blank stimulus-period onset. |
| `run_end` | `TrigN08.wav` | Normal final baseline end, or once after Q abort. |
| `video_offset` | `TrigN16.wav` | Disabled by default; actual visual offset is still logged. |

Play the original 100 samples at 48000 Hz, with configured gain 0.5, without
resampling. The nominal pulse width is approximately 2.083 ms. Source WAV
sample-rate metadata is retained independently. Audio and electrophysiology sample rates
need not match and equal nominal rates do not establish clock synchronization.

The backend preloads waveforms, warms up silently, schedules playback before
the intended visual onset from the logged Flip timeline, and subsequently
associates actual Flip and reported audio start times. A late Flip does not
move already scheduled audio. Preserve late playback, missing timestamp, XRun,
cancellation and timeout failures. The configured 2 ms is a reference, not an
abort threshold: the trial QC flags an offset only when it differs from the
run's median offset by more than 2 ms, and the PDF and console summary report
the distribution.

On Q after run start, cancel future reservations and output run end once;
wait for that last pulse to complete before closing audio. A cancelled row is
not an emitted waveform. Memory events use an independent named dummy backend
and produce no audio or electrical signal.

Measure the analog waveform directly and, if a converter is used, also the final
signal received by the recording system. Verify polarity, both amplitude classes, width, idle
level, classification and no extra edges. Record the output and photodiode on
the same acquisition clock. PTB `audio_start_getsecs` is an estimate, not a
measured electrical edge; `physical_onset_getsecs` stays unknown until measured.
Set acceptance thresholds before measuring and report fixed offset, jitter,
P95/P99, worst error, drift, missed events and duplicates independently.

## Windows laptops with Intel graphics

On the Windows 10 test laptop (Intel HD Graphics 520, PTB 3.0.19):

- PTB's startup sync test failed intermittently at 150% display scaling and
  passed at 100% scaling (refresh-interval spread 0.21 ms → 0.05 ms). Keep
  Windows display scaling at 100% on acquisition laptops.
- Beam-position queries are broken on this driver, so PTB uses basic Flip
  timestamps, and the Windows desktop compositor stays active.
- The PTB welcome screen shakes horizontally at startup, PTB's documented sign
  of triple buffering (`help SyncTrouble`), which many Intel drivers on Windows
  enforce. The picture can then appear about one refresh later than the Flip
  timestamp used to schedule the trigger.

`VBLSyncTest` and `PerceptualVBLSyncTest` passing does not exclude that delay.
Only the photodiode measurement below shows whether the trigger-to-photon
offset is constant (acceptable as a fixed offset) or varies between trials.
`PerceptualVBLSyncTest` shows full-screen flicker; never run it with a
participant watching.

## Physical measurement

Provide the TTL output device/model and interface, its agreed electrical
settings, the intended monitor, and the photodiode plus oscilloscope/DAQ/recording system
recording arrangement. Record the photodiode and actual TTL on two channels of
the **same acquisition clock**. A backend write receipt is not a measured edge.

First check static patch transitions and waveform recognition, then use two
real clips under their unchanged pre-fixation, movie and post-fixation timing.
Draw the patch in the same framebuffer as movie onset and schedule the
configured WAV for the same target visual onset, as in `Session`. Test optional
offset separately. Patch location and waveform settings must match the intended
site. Texture readbacks should remain outside the timing measurements.

For each independently matched onset and offset, calculate
`delta_s = ttl_edge_s - photodiode_transition_s`. Positive values mean the TTL
edge follows the measured luminance transition. Analyze on/off transitions
separately, and retain pulse widths, edge counts, mean, standard deviation,
range, outliers and drift with the raw recording. Predefine the optical edge
threshold and study acceptance limits. Mark missing, duplicate or ambiguous
correspondences as failures rather than pairing events solely by row number.
Absolute software-request-to-edge latency needs an independently established
clock relation; a fit to the same TTL requests cannot separately establish its
constant latency. Until those recordings exist, physical display/TTL latency
and jitter remain **unmeasured**.

To repeat the software display preflight on an acquisition computer:

```matlab
report = diagnose_aot_ephys_display_timing();
disp(report.status)
```
