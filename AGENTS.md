# aot_ephys: AOT electrophysiology project

- Read README.md and docs/architecture.md before editing the experiment.
- The supported entry point is run_aot_ephys.m.
- Preserve saved schedule order, trial counts, shared durations, waveforms and
  output-channel selection unless the user requests a protocol change.
- Keep actual Screen('Flip') calls in a method without nested functions.
  Preserve the documented Mac external-display submission policy.
- Keep file IO, full decoding, hashing and report generation outside critical
  video/onset paths. Unknown observations/identities must remain unknown.
- Recoverable runtime QC findings are logged and do not stop the schedule.
  Keep Q cancellation and one run-end attempt correct on every exit path.
- Use English source/YAML comments. Operator documentation may be Chinese.
- Run run_tests() for normal changes. Relevant media/device checks are listed
  in docs/testing.md. Unit tests must use isolated configuration and fixtures.
- Never commit local site files/selectors, recordings, derived movies or raw
  diagnostic output. Preserve user data when reorganizing source files.
- Keep the working copy at its current location unless the user requests a move.
