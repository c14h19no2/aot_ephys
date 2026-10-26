"""Build persistent native-PTB copies; verify every decoded YUV frame and PTS.

Input is a JSON list of original paths. No original file is modified. Successful
entries are atomically published individually, so interrupted jobs can resume.
Only the Python standard library and FFmpeg/ffprobe are needed.
"""
import argparse
import hashlib
import json
import os
import subprocess
from pathlib import Path

VERSION = 1


def digest(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def run(args):
    return subprocess.check_output(args, stderr=subprocess.PIPE)


def inspect(path, probe):
    d = json.loads(run([probe, '-v', 'error', '-select_streams', 'v:0',
                        '-show_frames', '-show_streams', '-of', 'json', str(path)]))
    s = d['streams'][0]
    return s, [float(f['best_effort_timestamp_time']) for f in d['frames']]


def frame_hashes(path, ffmpeg):
    text = run([ffmpeg, '-nostdin', '-v', 'error', '-noautorotate', '-i', str(path),
                '-map', '0:v:0', '-an', '-sn', '-dn', '-fps_mode', 'passthrough',
                '-f', 'framemd5', '-']).decode()
    return [line.split(',')[-1].strip() for line in text.splitlines()
            if line and not line.startswith('#')]


def prepare(source, output, ffmpeg, probe):
    source = Path(source).resolve()
    before = digest(source)
    target = output / source.name
    record = output / f'{source.stem}.json'
    if target.resolve() == source:
        raise ValueError('Native media directory must differ from the original video directory.')
    if record.exists() and target.exists():
        old = json.loads(record.read_text())
        if (old['source_sha256'] == before and old['sha256'] == digest(target)
                and old['lossless_yuv_equal'] and old['pts_equal']):
            return old, True
    stream, pts = inspect(source, probe)
    assert pts and all(b > a for a, b in zip(pts, pts[1:])), 'Nonmonotonic source PTS'
    partial = output / f'{source.stem}.partial{source.suffix}'
    command = [ffmpeg, '-nostdin', '-v', 'error', '-xerror', '-y', '-noautorotate',
               '-i', str(source), '-map', '0:v:0', '-an', '-sn', '-dn',
               '-vf', 'setpts=PTS-STARTPTS', '-fps_mode', 'passthrough',
               '-c:v', 'libx264', '-preset', 'medium', '-qp', '0',
               '-pix_fmt', stream['pix_fmt'], '-g', '48', '-bf', '3',
               '-sc_threshold', '0']
    # Preserve tags, without inventing a color calibration or conversion.
    for key_name, option in [('color_range', '-color_range'),
                             ('color_space', '-colorspace'),
                             ('color_transfer', '-color_trc'),
                             ('color_primaries', '-color_primaries')]:
        if stream.get(key_name) not in (None, 'unknown', 'unspecified'):
            command += [option, stream[key_name]]
    command += ['-movflags', '+faststart', str(partial)]
    try:
        run(command)
        converted, relative = inspect(partial, probe)
        original_hashes = frame_hashes(source, ffmpeg)
        new_hashes = frame_hashes(partial, ffmpeg)
        assert original_hashes == new_hashes and len(new_hashes) == len(pts), 'Frame content/order changed'
        assert len(relative) == len(pts)
        assert all(abs(a - (b - pts[0])) <= 1e-6 for a, b in zip(relative, pts)), 'PTS spacing changed'
        for field in ['width', 'height', 'pix_fmt', 'r_frame_rate', 'sample_aspect_ratio',
                      'color_range', 'color_space', 'color_transfer', 'color_primaries']:
            assert converted.get(field) == stream.get(field), f'Metadata changed: {field}'
        assert digest(source) == before, 'Source changed during encoding'
        os.replace(partial, target)
        value = dict(schema_version=VERSION, source=str(source), source_sha256=before,
                     path=str(target), sha256=digest(target), name=source.name,
                     frame_count=len(pts), width_px=stream['width'], height_px=stream['height'],
                     duration_s=float(converted['duration']), source_pts_s=pts,
                     relative_pts_s=relative, decoded_yuv_md5=original_hashes,
                     lossless_yuv_equal=True, pts_equal=True, command=command,
                     ffmpeg_version=run([ffmpeg, '-version']).decode().splitlines()[0])
        tmp = record.with_suffix('.json.partial')
        tmp.write_text(json.dumps(value, indent=2) + '\n')
        os.replace(tmp, record)
        return value, False
    finally:
        partial.unlink(missing_ok=True)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--sources', required=True, help='JSON list of original absolute paths')
    p.add_argument('--out', required=True)
    p.add_argument('--ffmpeg', required=True)
    p.add_argument('--ffprobe', required=True)
    a = p.parse_args()
    output = Path(a.out).resolve()
    output.mkdir(parents=True, exist_ok=True)
    paths = list(dict.fromkeys(json.loads(Path(a.sources).read_text())))
    result = []
    for i, source in enumerate(paths, 1):
        try:
            value, reused = prepare(source, output, a.ffmpeg, a.ffprobe)
        except subprocess.CalledProcessError as e:
            raise RuntimeError(e.stderr.decode(errors='replace')) from e
        result.append(value)
        print(f'{i}/{len(paths)} {Path(source).name}: {value["frame_count"]} frames verified'
              f'{" (cached)" if reused else ""}', flush=True)
    tmp = output / 'last_preparation.json.partial'
    tmp.write_text(json.dumps(result, indent=2) + '\n')
    os.replace(tmp, output / 'last_preparation.json')


if __name__ == '__main__':
    main()
