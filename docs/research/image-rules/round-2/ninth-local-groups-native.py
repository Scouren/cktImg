#!/usr/bin/env python3
"""Frozen CLI artifacts and isolated raster pairs; viewing is recorded separately."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
BASE = ROOT / '.objective/human-schematic-equivalence/runs/iteration21-resume1'
RUN = BASE / 'image-rule-round-2/groups/ninth'
FIG = HERE / 'figures/groups/ninth'
BINARY = BASE / 'resistor-output-integrated-common/zig-out/bin/cktimg-json'
EXPECTED_SHA = 'bf7b0749bde5822a68aa93fd9df69eb6e007dee0c24d5e9961ff65b187483560'
CONTROLS = ['ag-928', 'ag-1037', 'ag-925', 'ag-1053', 'ag-924', 'ag-1057', 'ag-2361', 'ag-459']


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rel(path):
    return str(path.relative_to(ROOT))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--execute', action='store_true')
    ap.add_argument('--output', type=Path, default=HERE / 'ninth-local-groups-native.json')
    ap.add_argument('--check', type=Path)
    args = ap.parse_args()
    assert sha(BINARY) == EXPECTED_SHA
    RUN.mkdir(exist_ok=True)
    FIG.mkdir(parents=True, exist_ok=True)
    census_path = HERE / 'ninth-local-groups-census.json'
    census = json.loads(census_path.read_text())
    names = census['disposition_names']['raw_multigroup_candidate'] + CONTROLS
    records = []
    for ident in names:
        deck = ROOT / 'external/examples/analoggenie' / (ident + '.cir')
        assert sha(deck) == census['cases'][ident]['deck_sha256'], 'actual deck differs from raw census'
        source, prefix = deck.with_suffix('.svg'), RUN / ident
        command = [str(BINARY), '--svg', str(prefix.with_suffix('.svg')), '--report',
                   str(prefix.with_suffix('.report.json')), str(deck), str(prefix.with_suffix('.json'))]
        render_commands = [[
            'magick', '-background', 'white', '-density', '144', str(svg), '-resize', '1400x1100', str(FIG / (ident + '-' + kind + '.png'))]
            for kind, svg in [('source', source), ('native', prefix.with_suffix('.svg'))]]
        render_commands.append(['magick', str(FIG / (ident + '-source.png')), str(FIG / (ident + '-native.png')),
                                '-background', 'white', '-gravity', 'north', '+append', str(FIG / (ident + '-pair.png'))])
        if args.execute:
            p = subprocess.run(command, capture_output=True)
            prefix.with_suffix('.stdout').write_bytes(p.stdout)
            prefix.with_suffix('.stderr').write_bytes(p.stderr)
            assert p.returncode == 0, (ident, p.stderr)
            for render in render_commands:
                p = subprocess.run(render, capture_output=True)
                assert p.returncode == 0, (ident, p.stderr)
        assert prefix.with_suffix('.svg').read_bytes() == (BASE / 'gallery-preview/img' / (ident + '.ours.svg')).read_bytes()
        document = json.loads(prefix.with_suffix('.json').read_text())
        raw = {row[0]: row for row in census['cases'][ident]['ordered_cards']}
        devices = {d['name']: d for d in document['devices'] if d['name'] in raw}
        assert set(devices) == set(raw)
        for name, row in raw.items():
            d = devices[name]
            count = 3 if name.startswith('m') else 2
            assert [pin['net'] for pin in d['pins']] == row[1:count + 1], (ident, name)
            if name.startswith('m'):
                assert d['bulk'] == row[4]
        records.append(dict(id=ident, disposition=census['cases'][ident]['disposition'],
                            command=command, exit_code=0, render_commands=render_commands,
                            deck_sha256=sha(deck), source_sha256=sha(source),
                            native_svg_byte_identical_to_gallery=True, complete_native_devices=devices,
                            output_sha256={rel(p): sha(p) for p in sorted(RUN.glob(ident + '.*'))},
                            raster_sha256={rel(p): sha(p) for p in sorted(FIG.glob(ident + '-*.png'))}))
    result = dict(script_sha256=sha(Path(__file__)), census_sha256=sha(census_path), binary_sha256=sha(BINARY),
                  names=names, records=records, scope='Executed/rasterized artifacts only; actual view notes are separate.')
    if args.check:
        assert result == json.loads(args.check.read_text())
    args.output.write_text(json.dumps(result, sort_keys=True, indent=2) + '\n')
    print(json.dumps(dict(executed_pairs=len(records), native_devices=sum(len(r['complete_native_devices']) for r in records))))


if __name__ == '__main__':
    main()
