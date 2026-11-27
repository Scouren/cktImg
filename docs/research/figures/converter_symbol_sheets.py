#!/usr/bin/env python3
"""Render a frozen source/native image shard into labeled visual review sheets.

Rendering is not a review. The output index deliberately has no reviewed flag;
the separate human/agent ledger records observations only after image viewing.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import shutil
import subprocess


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--jobs', type=int, default=4)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[3])
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    magick = shutil.which('magick')
    if magick is None:
        raise ValueError('ImageMagick required')
    manifest = json.loads(args.manifest.read_text())
    rows = manifest['images']
    assert len({row['id'] for row in rows}) == len(rows)

    def render(row):
        tiles = []
        proofs = {}
        for role in ('source', 'native'):
            source = Path(row[role + '_svg'])
            if not source.is_absolute():
                source = args.root / source
            assert sha(source) == row[role + '_svg_sha256'], source
            tile = output / (row['id'] + '-' + role + '.png')
            full = output / (row['id'] + '-' + role + '-full.png')
            subprocess.run([magick, '-background', 'white', str(source), '-alpha', 'remove',
                            '-alpha', 'off', '-trim', '+repage', '-resize', '1800x1400',
                            str(full)], check=True, capture_output=True)
            subprocess.run([magick, str(full), '-resize', '480x260', '-gravity', 'center',
                            '-background', 'white', '-extent', '500x270',
                            '-gravity', 'northwest', '-splice', '0x30', '-font', 'DejaVu-Sans',
                            '-pointsize', '17', '-fill', 'black', '-annotate', '+8+5',
                            row['id'] + ' ' + role.upper(), str(tile)], check=True, capture_output=True)
            tiles.append(tile)
            proofs[role] = {'svg': str(source), 'svg_sha256': sha(source),
                            'full': str(full), 'full_sha256': sha(full), 'tile_sha256': sha(tile)}
        pair = output / (row['id'] + '-pair.png')
        subprocess.run([magick, *map(str, tiles), '+append', str(pair)], check=True, capture_output=True)
        return {'id': row['id'], 'name': row['name'], 'pair': str(pair),
                'pair_sha256': sha(pair), 'images': proofs}

    with ThreadPoolExecutor(max_workers=args.jobs) as executor:
        rendered = list(executor.map(render, rows))
    sheets = []
    for start in range(0, len(rendered), 12):
        part = rendered[start:start + 12]
        path = output / ('sheet-%03d.png' % (start // 12 + 1))
        subprocess.run([magick, 'montage', *[row['pair'] for row in part], '-tile', '2x',
                        '-geometry', '+0+0', '-background', '#dddddd', str(path)],
                       check=True, capture_output=True)
        sheets.append({'path': str(path), 'sha256': sha(path), 'ids': [row['id'] for row in part]})
        print(path.name, ','.join(row['id'] for row in part), flush=True)
    inventory = {'manifest_sha256': sha(args.manifest), 'script_sha256': sha(Path(__file__)),
                 'magick': str(Path(magick).resolve()), 'magick_sha256': sha(Path(magick)),
                 'rendered': rendered, 'sheets': sheets,
                 'scope': 'Rasterization provenance only. No visual-review claim.'}
    (output / 'index.json').write_text(json.dumps(inventory, indent=2, sort_keys=True) + '\n')


if __name__ == '__main__':
    main()
