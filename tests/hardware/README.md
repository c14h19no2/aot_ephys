# Manual display/audio checks

These checks open real devices. Configure the local site and run `setup_aot`
with an installed Psychtoolbox before starting. Keep the display unlocked.

```matlab
displayReport = diagnose_aot_ephys_display_timing();
audioVisualReport = diagnose_aot_ephys_trigger_timing();
```

The display diagnostic keeps PTB sync checks on. The trigger diagnostic's
options and output are described in its MATLAB help and the project docs.
Use an explicit `Site` argument when testing another device profile.

After changes to the runtime control paths, check normal completion, Q with
a pending video onset, Q with a pending run-end event, and Q before Space.
Count completed and cancelled reservations separately. A cancelled future
reservation is not an emitted waveform. Save raw logs and the offset PDF in
the configured output directory, which is excluded from Git.

Successful device execution and driver timestamp estimates do not measure
photons or electrical edges. Physical signal measurement is documented in
[`docs/hardware_validation.md`](../../docs/hardware_validation.md).
