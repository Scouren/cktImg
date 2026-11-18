#!/usr/bin/env python3
"""Prove deterministic metadata-free rerenders and unchanged decoded replay pixels."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import zlib

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
RUN = ROOT / '.objective/human-schematic-equivalence/runs/iteration21-resume1/image-rule-round-2/groups/tenth-raster-repair'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rel(path):
    return str(path.relative_to(ROOT))


def chunks(path):
    data = path.read_bytes()
    assert data[:8] == b'\x89PNG\r\n\x1a\n'
    i, rows = 8, []
    while i < len(data):
        n = struct.unpack('>I', data[i:i + 4])[0]
        typ, payload = data[i + 4:i + 8].decode(), data[i + 8:i + 8 + n]
        assert i + n + 12 <= len(data)
        rows.append((typ, payload))
        i += n + 12
    assert i == len(data) and rows[-1][0] == 'IEND'
    return rows


def rgba(path):
    rows = chunks(path)
    width, height, depth, color, compression, filtering, interlace = struct.unpack('>IIBBBBB', rows[0][1])
    assert depth == 16 and color == 6 and (compression, filtering, interlace) == (0, 0, 0)
    # Independent PNG scanline decoder, preserving all sixteen bits per RGBA sample.
    compressed = b''.join(p for t, p in rows if t == 'IDAT')
    data = zlib.decompress(compressed)
    stride, bpp = width * 8, 8
    assert len(data) == height * (stride + 1)
    decoded, previous = bytearray(), bytearray(stride)
    for y in range(height):
        start = y * (stride + 1)
        filter_type = data[start]
        assert filter_type in range(5)
        row = bytearray(data[start + 1:start + 1 + stride])
        for x in range(stride):
            left = row[x - bpp] if x >= bpp else 0
            up = previous[x]
            upper_left = previous[x - bpp] if x >= bpp else 0
            if filter_type == 0:
                predictor = 0
            elif filter_type == 1:
                predictor = left
            elif filter_type == 2:
                predictor = up
            elif filter_type == 3:
                predictor = (left + up) // 2
            else:
                p = left + up - upper_left
                distances = [abs(p - left), abs(p - up), abs(p - upper_left)]
                predictor = (left, up, upper_left)[distances.index(min(distances))]
            row[x] = (row[x] + predictor) & 255
        decoded.extend(row)
        previous = row
    return (width, height), bytes(decoded)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--execute', action='store_true')
    ap.add_argument('--check', type=Path)
    ap.add_argument('--output', type=Path, default=HERE / 'tenth-arrangement-raster-proof.json')
    args = ap.parse_args()
    prior_path = RUN / 'before-tenth-arrangement-literals.json'
    observed_path = RUN / 'before-tenth-arrangement-literals-observed.json'
    current_path = HERE / 'tenth-arrangement-literals.json'
    prior, observed, current = [json.loads(p.read_text()) for p in (prior_path, observed_path, current_path)]
    a, b = copy.deepcopy(prior), copy.deepcopy(observed)
    for x in (a, b):
        for row in x['records']:
            row.pop('raster')
    assert a == b, 'root failure must differ only in raster metadata/hash'
    assert len(prior['records']) == len(observed['records']) == len(current['records']) == 8
    evidence = []
    for old, replay, now in zip(prior['records'], observed['records'], current['records']):
        assert old['name'] == replay['name'] == now['name']
        assert old['outputs'] == now['outputs'], 'native outputs changed'
        for path, digest in now['outputs'].items():
            assert sha(ROOT / path) == digest
        archived = RUN / ('root-replay-' + Path(replay['raster']['path']).name)
        normalized = ROOT / now['raster']['path']
        assert sha(archived) == replay['raster']['sha256']
        assert sha(normalized) == now['raster']['sha256']
        old_chunks = chunks(archived)
        assert any(t == 'tIME' for t, _ in old_chunks)
        assert any(t == 'tEXt' and p.startswith(b'date:') for t, p in old_chunks)
        repeated, commands = [], []
        for suffix in ('a', 'b'):
            path = RUN / (now['name'] + '-normalized-' + suffix + '.png')
            command = now['render_command'][:-1] + [str(path)]
            commands.append(command)
            if args.execute:
                subprocess.run(command, capture_output=True, check=True)
            repeated.append(path)
        assert normalized.read_bytes() == repeated[0].read_bytes() == repeated[1].read_bytes()
        new_chunks = chunks(normalized)
        assert all(t != 'tIME' and not (t in ('tEXt', 'iTXt', 'zTXt') and p.startswith(b'date:')) for t, p in new_chunks)
        assert new_chunks == [(t, p) for t, p in old_chunks if t != 'tIME' and not (t == 'tEXt' and p.startswith(b'date:'))]
        original_pixels, normalized_pixels = rgba(archived), rgba(normalized)
        assert original_pixels == normalized_pixels
        evidence.append(dict(name=now['name'], original_prior_png_sha256=old['raster']['sha256'],
                             archived_root_replay_png=dict(path=rel(archived), sha256=sha(archived)),
                             normalized_png=dict(path=rel(normalized), sha256=sha(normalized)),
                             repeated_renders=[dict(path=rel(p), sha256=sha(p)) for p in repeated],
                             commands=commands, chunk_types=[t for t, _ in new_chunks],
                             dimensions=list(normalized_pixels[0]), rgba_sha256=hashlib.sha256(normalized_pixels[1]).hexdigest(),
                             changed_rgba_bytes=0))
    dependencies = {rel(p): sha(p) for p in (Path(__file__), prior_path, observed_path, current_path,
                                            RUN / 'before.json', HERE / 'tenth-arrangement-literals.py')}
    result = dict(dependencies=dependencies, records=evidence,
                  scope='Root failed exact replay retained. Two fresh normalized rerenders per SVG are byte-identical and exactly RGBA-equal to archived root replay PNGs. Prior original PNG bytes are unavailable; only their old manifest hashes remain. Native outputs are unchanged from those original manifests.')
    if args.check:
        assert result == json.loads(args.check.read_text())
    args.output.write_text(json.dumps(result, sort_keys=True, indent=2) + '\n')
    print(json.dumps(dict(rasters=8, independent_decoded_pixel_differences=0, repeated_render_byte_differences=0)))


if __name__ == '__main__':
    main()
