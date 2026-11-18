#!/usr/bin/env python3
"""Explicit caller poses exercise arrangement expressiveness, not automatic choice."""
import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
BASE = ROOT / '.objective/human-schematic-equivalence/runs/iteration21-resume1'
RUN = BASE / 'image-rule-round-2/groups/tenth'
FIG = HERE / 'figures/groups/tenth'
NINTH = BASE / 'image-rule-round-2/groups/ninth'
BINARY = BASE / 'resistor-output-integrated-common/zig-out/bin/cktimg-json'
BINARY_SHA = 'bf7b0749bde5822a68aa93fd9df69eb6e007dee0c24d5e9961ff65b187483560'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rel(path):
    return str(path.relative_to(ROOT))


def load_module(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), HERE / (name + '.py'))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def bridge(text, asymmetric=False):
    text = text.lower().replace('m9 vout1 x vdd vdd', 'm9 vout1 x ptail vdd')
    if not asymmetric:
        text = text.replace('m10 vout2 y vdd vdd', 'm10 vout2 y ptail vdd')
    return text.replace('.ends dut', 'm14 ptail vb3 vdd vdd pch l=0.15 w=1 nf=1 m=1\n.ends dut')


def expected_devices(raw, baseline, groups, layout, new_tail):
    poses = copy.deepcopy(baseline)
    if new_tail:
        poses['m14'] = copy.deepcopy(baseline['m7'])
        poses['m14']['name'] = 'm14'
        poses['m14']['pos'] = [400, -100]
        # Frozen default D=(20,0), G=(0,-20), S=(-20,0); MR270 gives
        # (0,20), (-20,0), (0,-20), respectively. No cached tail exists.
        poses['m14']['pins'] = [dict(term='d', net='ptail', xy=[400, -80]),
                               dict(term='g', net='vb3', xy=[380, -100]),
                               dict(term='s', net='vdd', xy=[400, -120])]
        poses['m14']['rot'], poses['m14']['mirror'] = 3, True
    for name, row in raw.items():
        poses[name]['value'] = ' '.join(row[5:])
        for pin, net in zip(poses[name]['pins'], row[1:4]):
            pin['net'] = net
        poses[name]['bulk'] = row[4]
    assert set(poses) == set(raw)
    offset = {'keep': (0, 0), 'right': (1000, 0), 'below': (0, 800)}[layout]
    for name in groups[1]:
        d = poses[name]
        d['pos'] = [a + b for a, b in zip(d['pos'], offset)]
        for pin in d['pins']:
            pin['xy'] = [a + b for a, b in zip(pin['xy'], offset)]
    return poses


def check_actual(text, expected_raw, poses, document, report, parser):
    raw_text = '\n'.join(line for line in text.splitlines() if not line.startswith('*@')) + '\n'
    facts = parser.facts(raw_text)
    assert facts[0] == expected_raw
    names = [d['name'] for d in document['devices']]
    assert len(names) == len(set(names)), 'duplicate document device identity'
    raw_nets = {n for row in expected_raw.values() for n in row[1:5]}
    for index, d in enumerate(document['devices']):
        if d['name'] in expected_raw:
            continue
        assert d['class'] in ('vdd', 'gnd', 'ipin', 'opin'), 'unexpected non-generated device'
        assert d['name'] == f"_{d['class']}{index}" and d['value'] == '' and 'bulk' not in d
        assert len(d['pins']) == 1 and d['pins'][0]['term'] == 'p' and d['pins'][0]['net'] in raw_nets
    actual = {d['name']: d for d in document['devices'] if d['name'] in expected_raw}
    assert set(actual) == set(expected_raw)
    for name, row in expected_raw.items():
        d = actual[name]
        assert [p['net'] for p in d['pins']] == row[1:4] and d['bulk'] == row[4]
        assert d['value'].split() == row[5:]
        for key in ('class', 'rot', 'mirror', 'pos', 'pins', 'bulk', 'value'):
            assert d[key] == poses[name][key], (name, key, d[key], poses[name][key])
    requests = [r for r in report['requests'] if r['text'].lower().split()[1] == 'at']
    assert len(requests) == len(expected_raw)
    assert {r['text'].lower().split()[2] for r in requests} == set(expected_raw)
    assert {r['text'].lower() for r in requests} == {s.lower() for s in text.splitlines() if s.startswith('*@')}
    assert all(r['state'] == 'honoured' and r['code'] == 'ok' for r in requests)
    return actual


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--execute', action='store_true')
    ap.add_argument('--check', type=Path)
    ap.add_argument('--output', type=Path, default=HERE / 'tenth-arrangement-literals.json')
    args = ap.parse_args()
    assert sha(BINARY) == BINARY_SHA
    m, graphs = [load_module(n) for n in ('ninth-local-groups-census', 'tenth-arrangement-graphs')]
    census_path = HERE / 'ninth-local-groups-census.json'
    census = json.loads(census_path.read_text())
    RUN.mkdir(parents=True, exist_ok=True)
    FIG.mkdir(parents=True, exist_ok=True)
    records, dependencies = [], {rel(census_path): sha(census_path)}
    definitions = [('ag-1028', False, x) for x in ('keep', 'right', 'below')]
    definitions += [('ag-364', False, x) for x in ('keep', 'right', 'below')]
    definitions += [('ag-364', True, x) for x in ('keep', 'right')]
    for ident, tail, layout in definitions:
        source = ROOT / 'external/examples/analoggenie' / (ident + '.cir')
        assert sha(source) == census['cases'][ident]['deck_sha256']
        baseline_path = NINTH / (ident + '.json')
        dependencies.update({rel(p): sha(p) for p in (source, baseline_path)})
        original = source.read_text().lower()
        text = bridge(original) if tail else original
        values = m.facts(text)
        raw = values[0]
        collected = m.decompose(*values)
        assert collected['disposition'] == 'raw_multigroup_candidate'
        assert len(collected['proposed_groups']) == 2
        baseline_names = {r[0] for r in census['cases'][ident]['ordered_cards']}
        baseline = {d['name']: d for d in json.loads(baseline_path.read_text())['devices'] if d['name'] in baseline_names}
        poses = expected_devices(raw, baseline, collected['proposed_groups'], layout, tail)
        hints = []
        for name, d in sorted(poses.items()):
            word = ('m' if d['mirror'] else '') + 'r' + str(d['rot'] * 90)
            hints.append(f"*@ at {name} {d['pos'][0] / 40:g} {d['pos'][1] / 40:g} {word}")
        text = text.replace('.ends dut', '\n'.join(hints) + '\n.ends dut')
        name = ident + ('-tail' if tail else '') + '-' + layout
        deck = HERE / ('tenth-arrangement-' + name + '.cir')
        if deck.exists():
            assert deck.read_text() == text
        else:
            deck.write_text(text)
        prefix = RUN / name
        command = [str(BINARY), '--svg', str(prefix.with_suffix('.svg')), '--report',
                   str(prefix.with_suffix('.report.json')), str(deck), str(prefix.with_suffix('.json'))]
        render = ['magick', '-background', 'white', '-density', '144', str(prefix.with_suffix('.svg')),
                  '-resize', '1800x1400', '-define', 'png:exclude-chunks=date,time',
                  str(FIG / (name + '.png'))]
        if args.execute:
            p = subprocess.run(command, capture_output=True)
            prefix.with_suffix('.stdout').write_bytes(p.stdout)
            prefix.with_suffix('.stderr').write_bytes(p.stderr)
            prefix.with_suffix('.exit').write_text(str(p.returncode) + '\n')
            assert p.returncode == 0, (name, p.stderr)
            p = subprocess.run(render, capture_output=True)
            assert p.returncode == 0, (name, p.stderr)
        assert prefix.with_suffix('.exit').read_text() == '0\n'
        data = json.loads(prefix.with_suffix('.json').read_text())
        report = json.loads(prefix.with_suffix('.report.json').read_text())
        actual = check_actual(deck.read_text(), raw, poses, data, report, m)
        records.append(dict(name=name, source=ident, tail_bridge_mutation=tail, arrangement=layout,
                            deck=rel(deck), deck_sha256=sha(deck), raw_facts=dict(cards=raw,
                            formals=values[1], models=values[2], rails=values[3], declarations=values[4]),
                            raw_decomposition=collected, actual_devices=actual, command=command,
                            exit_code=0, render_command=render, report_requests=report['requests'],
                            outputs={rel(p): sha(p) for p in sorted(RUN.glob(name + '.*'))},
                            raster=dict(path=rel(FIG / (name + '.png')), sha256=sha(FIG / (name + '.png')))))
    original = (ROOT / 'external/examples/analoggenie/ag-364.cir').read_text()
    asymmetric = m.decompose(*m.facts(bridge(original, asymmetric=True)))
    assert asymmetric['disposition'] == 'decline_involution'
    nested_mutant = next(r for r in records if r['name'] == 'ag-364-tail-keep')
    assert len(nested_mutant['raw_decomposition']['channel_components']) == 2
    left = graphs.interfaces(census['cases']['ag-1028'])
    right = graphs.interfaces(nested_mutant['raw_decomposition'])
    transport = graphs.star_transport(left, right, dict(m1='m3', m2='m4', m3='m5', m4='m6', m6='m9', m7='m10'), dict(net3='x', net1='y'))
    for p in [Path(__file__), HERE / 'ninth-local-groups-census.py', HERE / 'tenth-arrangement-graphs.py',
              BASE / 'resistor-output-integrated-common/tests/symbols.zon']:
        dependencies[rel(p)] = sha(p)
    result = dict(binary_sha256=BINARY_SHA, dependencies=dependencies, records=records,
                  asymmetric_tail_control=asymmetric, tail_bridge_boundary_transport=transport,
                  scope='Eight executed explicit-caller pose witnesses; no automatic local-group implementation or source-human preference for the invented tail circuit.')
    if args.check:
        assert result == json.loads(args.check.read_text())
    args.output.write_text(json.dumps(result, sort_keys=True, indent=2) + '\n')
    print(json.dumps(dict(executed=len(records), complete_native_devices=sum(len(r['actual_devices']) for r in records))))


if __name__ == '__main__':
    main()
