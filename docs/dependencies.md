# Dependencies

| Use | Requirements |
| --- | --- |
| Native video/memory experiment | MATLAB with JVM, installed Psychtoolbox and its movie-playback dependencies, configured media/site |
| Unit tests | MATLAB with JVM; YAML library and WAV assets are bundled |
| Offline native-media preparation | MATLAB with JVM, Python 3, FFmpeg/ffprobe; Python tool uses the standard library |
| Generated-media integration and optional real-media regression | MATLAB with JVM, FFmpeg/ffprobe |
| EyeLink acquisition | Optional EyeLink hardware/software integration, enabled by site configuration |

The current local software validation uses MATLAB R2026b and Psychtoolbox
3.0.22 on Apple Silicon. Earlier MATLAB releases and other device combinations
need their own validation. The MATLAB YAML wrapper is v1.6.0 and bundles
SnakeYAML 1.30; versions and original license files are in `third_party/yaml`.

Install/configure Psychtoolbox separately, or add its installation for the
current MATLAB session with `setup_aot('PsychtoolboxPath',ptbRoot)`. The runner
does not guess a developer-specific installation directory. Setup never
downloads software or saves the global MATLAB path.

For offline preparation, executable paths can be supplied in the selected site
via `playback.ffmpeg_path`, `ffprobe_path` and `python_path`. Native acquisition
does not discover or launch these executables. Original and prepared movie
files remain outside the code repository.

Record actual MATLAB/PTB/device versions for timing validation. Dependency
changes that affect decoding, audio scheduling or presentation require the
relevant software/device regression checks. See [testing.md](testing.md).
