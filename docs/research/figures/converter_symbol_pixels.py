#!/usr/bin/env python3
"""Prove every raster contact-sheet panel contains its complete resized input."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import shutil
import subprocess


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--index', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--jobs', type=int, default=4)
    args = parser.parse_args()
    index = json.loads(args.index.read_text())
    magick = shutil.which('magick')
    assert magick
    rows = {row['id']: row for row in index['rendered']}
    panels = [(sheet, pos, name) for sheet in index['sheets'] for pos, name in enumerate(sheet['ids'])]

    def pixels(path, operations=()):
        return subprocess.run([magick, str(path), *operations, '-alpha', 'off', '-depth', '8', 'RGB:-'],
                              check=True, capture_output=True).stdout

    def verify(entry):
        sheet, pos, name = entry
        row = rows[name]
        assert digest(Path(sheet['path'])) == sheet['sha256']
        assert digest(Path(row['pair'])) == row['pair_sha256']
        result = {'id': name, 'sheet': Path(sheet['path']).name, 'sheet_sha256': sheet['sha256'], 'roles': {}}
        for role_index, role in enumerate(('source', 'native')):
            proof = row['images'][role]
            full = Path(proof['full'])
            tile = full.with_name(name + '-' + role + '.png')
            assert digest(full) == proof['full_sha256']
            assert digest(tile) == proof['tile_sha256']
            expected = pixels(tile)
            x, y = (pos % 2) * 1000 + role_index * 500, (pos // 2) * 300
            actual = pixels(sheet['path'], ('-crop', f'500x300+{x}+{y}', '+repage'))
            pair = pixels(row['pair'], ('-crop', f'500x300+{role_index * 500}+0', '+repage'))
            image = pixels(full, ('-resize', '480x260', '-gravity', 'center', '-background', 'white', '-extent', '500x270'))
            tiled_image = pixels(tile, ('-crop', '500x270+0+30', '+repage'))
            assert len(expected) == 500 * 300 * 3
            assert actual == expected, (name, role, 'sheet pixels')
            assert pair == expected, (name, role, 'pair pixels')
            assert image == tiled_image, (name, role, 'complete resized full image')
            result['roles'][role] = {'panel_rgb_sha256': hashlib.sha256(actual).hexdigest(),
                                     'full_sha256': proof['full_sha256'], 'tile_sha256': proof['tile_sha256'],
                                     'sheet_equals_tile': True, 'pair_equals_tile': True,
                                     'tile_equals_complete_resized_full': True}
        return result

    with ThreadPoolExecutor(max_workers=args.jobs) as executor:
        result = list(executor.map(verify, panels))
    args.output.write_text(json.dumps({'index_sha256': digest(args.index),
                                      'script_sha256': digest(Path(__file__)), 'rows': result,
                                      'scope': 'Exact raster containment, not human visual review.'}, indent=2, sort_keys=True) + '\n')
    print('PASS exact panels', len(result) * 2, 'named pairs', len(result))


if __name__ == '__main__':
    main()
