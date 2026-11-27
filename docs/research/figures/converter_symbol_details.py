#!/usr/bin/env python3
"""Bind every enlarged review panel to its complete independently rasterized input.

This checks existing images. It neither generates nor claims a visual review.
The 36-pixel label band is excluded only from the image-resize comparison;
the complete labeled panel is compared against its half of the joined pair.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import subprocess


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def pixels(path, operations=()):
    return subprocess.run(['magick', str(path), *operations, '-alpha', 'off', '-depth', '8', 'RGB:-'],
                          check=True, capture_output=True).stdout


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--audit-run', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--jobs', type=int, default=4)
    args = p.parse_args()
    index_path = args.audit_run / 'shard-2-images/index.json'
    zoom_path = args.audit_run / 'shard-2-zooms/index.json'
    index = json.loads(index_path.read_text())
    zooms = json.loads(zoom_path.read_text())
    images = {row['id']: row for row in index['rendered']}
    assert len(zooms) == len({row['id'] for row in zooms})

    def check(zoom):
        name = zoom['id']
        pair = args.audit_run / 'shard-2-zooms' / (name + '-detail.png')
        assert digest(pair) == zoom['sha256']
        roles = {}
        for column, role in enumerate(('source', 'native')):
            original = images[name]['images'][role]
            full = args.audit_run / 'shard-2-images' / (name + '-' + role + '-full.png')
            panel = args.audit_run / 'shard-2-zooms' / (name + '-' + role + '.png')
            assert digest(full) == original['full_sha256']
            expected = pixels(full, ('-resize', '1160x1000', '-gravity', 'center', '-background', 'white', '-extent', '1200x1040'))
            actual = pixels(panel, ('-crop', '1200x1040+0+36', '+repage'))
            assert len(actual) == 1200 * 1040 * 3
            assert expected == actual, (name, role, 'complete image')
            joined = pixels(pair, ('-crop', f'1200x1076+{column * 1200}+0', '+repage'))
            labeled = pixels(panel)
            assert len(labeled) == 1200 * 1076 * 3
            assert joined == labeled, (name, role, 'joined panel')
            roles[role] = dict(svg_sha256=original['svg_sha256'], full_sha256=digest(full),
                               panel_sha256=digest(panel), image_rgb_sha256=hashlib.sha256(actual).hexdigest(),
                               panel_rgb_sha256=hashlib.sha256(labeled).hexdigest(),
                               image_equals_complete_resized_full=True, joined_equals_labeled_panel=True)
        return dict(id=name, pair_sha256=digest(pair), roles=roles)

    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        rows = list(pool.map(check, zooms))
    result = dict(scope='Exact source/native enlarged-image provenance; visual observations remain in the separate ledger.',
                  index_sha256=digest(index_path), zoom_index_sha256=digest(zoom_path),
                  script_sha256=digest(Path(__file__)), rows=rows)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    print('PASS exact enlarged names:', ','.join(row['id'] for row in rows))


if __name__ == '__main__':
    main()
