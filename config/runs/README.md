# Saved participant schedules

The experiment resolves its default schedules inside this project:

| Folder | Contents | Files |
| --- | --- | ---: |
| `main/` | Video schedules: 13 subjects, 156 subject/session pairs, 10 runs per pair | 1560 YAML |
| `memory_main_complete/` | Default memory schedules, 360 pictures per schedule | 132 YAML |
| `memory_main/` | Optional older memory schedules, 180 pictures per schedule | 72 YAML |
| `memory_main/answers/` | Answer keys for the optional older memory schedules | 72 TSV |

Participant filenames retain the original format:
`experiment_settings_sub_XX_ses_YY_run_ZZ.yml`.
The optional fourth argument to `run_aot_ephys` labels the recording only;
it does not select another schedule or repeat the run.

The files were copied on 2026-10-16 from
`arrow_of_time_experiment/aot/data/experiment/settings/`.
Every copied file was verified byte-for-byte, preserving stimulus order,
repetitions, blank positions, answer keys and line endings. The original
project is not read by the active experiment or schedule-based preparation.

`source_manifest.json` records the relative path, byte count and SHA-256 of
all 1836 copied files. It documents this import; it is not a runtime dependency.
It is expected to become historical if schedules are intentionally edited later.
Each experiment output separately saves and hashes the selected schedule.

The small `debug_*.yml` schedules in this directory remain explicit debugging
fixtures. A missing video schedule falls back to `debug_blank.yml` only when
`Debug=true`. Acquisition does not search the old project as a fallback.

Movie files, prepared native movie copies and memory images are located through
the selected site YAML. They can remain outside this code repository.
