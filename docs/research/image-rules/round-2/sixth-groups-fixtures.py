#!/usr/bin/env python3
"""Frozen CLI caller controls for one pair and one quad; no engine build."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
FROZEN = ROOT / '.objective/human-schematic-equivalence/runs/iteration21-resume1/resistor-output-integrated-common'
BINARY = FROZEN / 'zig-out/bin/cktimg-json'
RUN = ROOT / '.objective/human-schematic-equivalence/runs/iteration21-resume1/image-rule-round-2/groups/sixth'
BINARY_SHA = 'bf7b0749bde5822a68aa93fd9df69eb6e007dee0c24d5e9961ff65b187483560'
PAIR = '''Caller geometry pair
.model nch nmos level=1
.subckt dut VDD VSS INP INN VB OUTP OUTN
R1 VDD OUTN 1k
R2 VDD OUTP 1k
M1 OUTN INP tail VSS nch w=2u l=1u
M2 OUTP INN tail VSS nch w=2u l=1u
M5 tail VB VSS VSS nch w=4u l=1u
.ends dut
'''
QUAD = '''Caller geometry crossed-gate quad
.model nch nmos level=1
.subckt dut VDD VSS INP INN OUTP OUTN
R1 VDD OUTP 1k
R2 VDD OUTN 1k
M1 OUTP INP s1 VSS nch w=2u l=1u
M2 OUTN INN s1 VSS nch w=2u l=1u
M3 OUTP INN s2 VSS nch w=2u l=1u
M4 OUTN INP s2 VSS nch w=2u l=1u
I1 s1 VSS 1m
I2 s2 VSS 1m
.ends dut
'''


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rel(path):
    return str(path.relative_to(ROOT))


def fixtures():
    pair_rel = '*@ symmetric M1 M2\n*@ symmetric R1 R2\n*@ axis M5\n'
    quad_rel = '*@ symmetric M1 M2\n*@ symmetric M3 M4\n*@ symmetric R1 R2\n*@ axis I1\n*@ axis I2\n'
    requests = {
        'pair-base': '',
        'pair-relations': pair_rel,
        'pair-rejected': '*@ symmetric M1 R1\n*@ axis absent\n*@ group pair M1\n',
        'pair-axis-conflict': '*@ symmetric M1 M2\n*@ axis M1\n',
        'pair-symmetric-conflict': '*@ axis M1\n*@ symmetric M1 M2\n',
        'pair-group': '*@ group pair M1 M2\n',
        'pair-stack': '*@ group stack M5 M1\n',
        'pair-stack-compatible': '*@ group stack M1 M5\n',
        'pair-nogroup': '*@ group pair M1 M2\n*@ nogroup M1\n',
        'pair-fixed': pair_rel + '*@ at M1 -20 -20 r0\n',
        'pair-fixed-weak': pair_rel + '*@ weak at M1 -20 -20 r0\n',
        'pair-fixed-weak-compatible': pair_rel + '*@ weak at M1 -20 -20 r270\n',
        'pair-off': pair_rel + '*@ symmetry off\n',
        'quad-base': '',
        'quad-relations': quad_rel,
        'quad-groups': quad_rel + '*@ group pair M1 M2\n*@ group pair M3 M4\n',
        'quad-fixed': quad_rel + '*@ at M3 -20 -20 r0\n',
        'quad-overlap': '*@ group pair M1 M2\n*@ group pair M2 M3\n',
        'quad-axis-alone': '*@ axis I2\n',
        'quad-mate-conflict': '*@ symmetric M1 M2\n*@ symmetric M1 M3\n',
        'quad-mate-conflict-reversed': '*@ symmetric M1 M3\n*@ symmetric M1 M2\n',
    }
    result = {}
    for name, hints in requests.items():
        base = PAIR if name.startswith('pair-') else QUAD
        result[name] = base.replace('.ends dut', hints + '.ends dut')
    # The same admitted relation text is stable under raw electrical card order.
    for base_name in ('pair-relations', 'quad-groups'):
        text = result[base_name]
        lines = text.splitlines()
        a = next(i for i, line in enumerate(lines) if line.startswith('.subckt')) + 1
        b = next(i for i, line in enumerate(lines) if line.startswith('*@'))
        result[base_name + '-reversed'] = '\n'.join(lines[:a] + list(reversed(lines[a:b])) + lines[b:]) + '\n'
    return result


def parse(text):
    rows = {}
    for line in text.lower().splitlines():
        w = line.split()
        if w and w[0][0] in 'mri' and not line.startswith('caller'):
            rows[w[0]] = w
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--execute', action='store_true')
    ap.add_argument('--output', type=Path, default=HERE / 'sixth-groups-fixtures.json')
    ap.add_argument('--check', type=Path)
    args = ap.parse_args()
    assert sha(BINARY) == BINARY_SHA
    RUN.mkdir(parents=True, exist_ok=True)
    runs = []
    for name, text in sorted(fixtures().items()):
        deck = HERE / ('sixth-groups-' + name + '.cir')
        if deck.exists():
            assert deck.read_text() == text
        else:
            deck.write_text(text)
        prefix = RUN / name
        command = [str(BINARY), '--svg', str(prefix.with_suffix('.svg')), '--report',
                   str(prefix.with_suffix('.report.json')), str(deck), str(prefix.with_suffix('.json'))]
        if args.execute:
            p = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
            prefix.with_suffix('.stdout').write_text(p.stdout)
            prefix.with_suffix('.stderr').write_text(p.stderr)
            assert p.returncode == 0, (name, p.returncode, p.stderr)
        data = json.loads(prefix.with_suffix('.json').read_text())
        report = json.loads(prefix.with_suffix('.report.json').read_text())
        cards = parse(text)
        devices = {d['name']: d for d in data['devices'] if d['name'] in cards}
        assert set(devices) == set(cards)
        for n, w in cards.items():
            d = devices[n]
            indices = 3 if n.startswith('m') else 2
            assert [p['net'] for p in d['pins']] == w[1:indices + 1]
            if indices == 3:
                assert d['bulk'] == w[4]
        outputs = {s: dict(path=rel(prefix.with_suffix(s)), sha256=sha(prefix.with_suffix(s)))
                   for s in ('.json', '.svg', '.report.json', '.stdout', '.stderr')}
        runs.append(dict(name=name, deck=rel(deck), deck_sha256=sha(deck),
                         command=[rel(Path(x)) if x.startswith(str(ROOT)) else x for x in command],
                         model_definitions=[s.lower().split() for s in text.splitlines() if s.startswith('.model')],
                         dut_formals=next(s.lower().split()[2:] for s in text.splitlines() if s.startswith('.subckt')),
                         raw_ordered_cards=cards, devices=devices, requests=report['requests'], outputs=outputs))
    dependencies = {rel(Path(__file__)): sha(Path(__file__))}
    for name in ('structure.zig', 'skeleton.zig', 'sketch.zig', 'checks.zig', 'report.zig', 'hints.zig', 'pinned.zig'):
        for root in (ROOT, FROZEN):
            path = root / 'src' / name
            dependencies[rel(path)] = sha(path)
    result = dict(scope='Frozen final output and caller verdict observations; local-group replacement is future-only.',
                  binary=rel(BINARY), binary_sha256=BINARY_SHA, dependencies=dependencies, runs=runs)
    if args.check:
        assert json.loads(args.check.read_text()) == result
    args.output.write_text(json.dumps(result, sort_keys=True, indent=2) + '\n')
    print(json.dumps(dict(runs=len(runs), names=[r['name'] for r in runs])))


if __name__ == '__main__':
    main()
