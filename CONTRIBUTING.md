# Development

Read the [README](README.md), [architecture](docs/architecture.md) and
[test guide](docs/testing.md) before changing the runtime.

## Local setup

Run `setup_aot` from the project root. The local site and selector are excluded
from Git and must remain specific to each acquisition computer. Setup preserves
existing files. Only use the active root/dependency paths; do not add the whole
repository with `genpath`, which would put test helpers and tools on the path.

## Change and verify

1. Keep a focused change. Describe any change to stimulus order, experimental
   duration, waveform routing, timestamp semantics or output schema explicitly.
2. Run `run_tests()` with independent fixtures. Run the relevant generated-media
   or device checks for decoding, scheduling or resource-lifecycle changes.
3. Preserve raw observations and report recoverable QC findings. Never replace
   a missing observation with its requested time or infer an unverified frame.
4. Review the Git diff, including configuration/schedules and file attributes.
5. Add a concise CHANGELOG/validation entry, then commit. Record the commit
   used for an experiment release.

No file IO, hashing, full decode or report generation belongs in the critical
video/onset paths. Keep the existing non-nested Screen call and Mac external
submission behavior until equivalent behavior has been verified on devices.

## Files and evidence

Track implementation, saved schedules/answers, tiny WAV assets, dependencies
and concise written validation summaries. Keep local site selectors, subject
maps, experiment output, derived movies and raw diagnostic results out of Git.

Imported `config/runs/**` files have byte-preserving Git attributes. Intentional
schedule edits should be reviewed as scientific-design changes; the import
manifest remains historical and per-run provenance records the selected file.

Keep the working copy outside cloud-synced folders such as OneDrive: syncing
competes with the display loop for CPU and would upload recordings.

Project-wide redistribution licensing has not been selected. Preserve all
third-party license notices; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
