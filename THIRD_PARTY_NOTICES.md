# Third-party components and assets

| Component | Bundled material | Source/notice |
| --- | --- | --- |
| MATLAB YAML wrapper | `third_party/yaml`, v1.6.0 / upstream commit 6d36b63 | MartinKoch123/yaml; MIT license in `third_party/yaml/LICENSE.md` |
| SnakeYAML | `third_party/yaml/+yaml/snakeyaml/snakeyaml-1.30.jar` | Apache 2.0 license in the adjacent `LICENSE-2.0.txt` |
| Trigger waveforms | Four original WAV files in `assets/triggers` | Imported from the local trigger example; samples are preserved and pinned by regression tests |

The bundled dependency version/source record is
[`third_party/yaml/VERSION.txt`](third_party/yaml/VERSION.txt). Retain these
licenses and notices when redistributing their components.

Psychtoolbox, MATLAB, FFmpeg and EyeLink are external dependencies, not bundled
toolboxes in this repository. Their respective installation/distribution terms
apply. No project-wide license for newly authored code or the imported stimulus
design/waveform assets is declared here; the owner should select the applicable
licensing before public distribution.
