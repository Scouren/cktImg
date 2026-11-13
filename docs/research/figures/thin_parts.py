#!/usr/bin/env python3
"""Replay actual iteration15 thinning decisions and source terminal ink.

The diagnostic tree is prepared separately by thin_trace_prepare.py and
built only by the build owner. This command runs existing binaries, requires
geometry AND report byte identity in every named case, and independently
checks every traced crossing against raw per-round geometry. --check compares
all retained evidence with thin_parts_cases.json, never counts alone.
"""
import argparse
import hashlib
import itertools
import json
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET

from channel_bridges import read_cards
from converter_loops import wire_tree
from cross_caps import conductor_ink
from thin_trace_run import run
from trunk_rungs import source_loss

CASES = ('ag-2309', 'ag-2318', 'ag-2319', 'ag-2452', 'ag-2376', 'ag-2274', 'ag-1411')
TARGETS = (('vx', ('m11', 'm12')), ('vx', ('m11', 'm12')), ('vx', ('m11', 'm12')),
           ('vz', ('m34', 'm40')), ('net0', ('m4', 'm5')), ('vn', ('m5', 'm6')),
           ('vb1', ('m11', 'm14')))


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def touch(a, b):
    """Closed integer segment boxes: the raw engine adds own-net X dots."""
    return all(max(min(a[0][k], a[1][k]), min(b[0][k], b[1][k])) <=
               min(max(a[0][k], a[1][k]), max(b[0][k], b[1][k])) for k in (0, 1))


def piece(segments, point):
    """Independent segment flood fill; no Route or partition group identity."""
    reached = {i for i, s in enumerate(segments) if touch(s, [point, point])}
    for _ in segments:
        added = {i for i, s in enumerate(segments) if i not in reached and
                 any(touch(s, segments[j]) for j in reached)}
        if not added:
            break
        reached.update(added)
    return sorted(reached)


def crossings(row):
    """All strict proper crossings, preserving storage multiplicity."""
    found = []
    for a, b in itertools.combinations(row['segments'], 2):
        if a['net'] == b['net']:
            continue
        if any(row['nets'][n]['role'] in ('supply', 'sink') for n in (a['net'], b['net'])):
            continue
        for h, v in ((a, b), (b, a)):
            if h['a'][1] != h['b'][1] or v['a'][0] != v['b'][0]:
                continue
            x, y = v['a'][0], h['a'][1]
            if min(h['a'][0], h['b'][0]) < x < max(h['a'][0], h['b'][0]) and min(v['a'][1], v['b'][1]) < y < max(v['a'][1], v['b'][1]):
                found.append((tuple(sorted((h['net'], v['net']))), (x, y)))
    return sorted(found)


def round_evidence(row, target, devices):
    net, = [n for n, meta in row['nets'].items() if meta['name'] == target]
    target_pins = [p for p in row['pins'] if p['net'] == net]
    segments = [[s['a'], s['b']] for s in row['segments'] if s['net'] == net]
    targets = [next(p['at'] for p in target_pins if p['device'] == name and p['index'] == 1) for name in devices]
    physical = {}
    for p in target_pins:
        reached = tuple(piece(segments, p['at']))
        # Pins with no ink are distinct, even when labels have the same name.
        key = reached if reached else ('no-ink', p['pin'])
        if key not in physical:
            ink = [segments[i] for i in reached]
            cross = [c for c in row['target_crossings'] if piece(ink, c['at'])]
            physical[key] = dict(pins=[], segments=ink, crossings=cross)
        physical[key]['pins'].append(p)
    return dict(round=row['round'], target_role=row['nets'][net]['role'], target_style=row['target_style'],
                target_rank=row['nets'][net]['rank'], target_mate=row['nets'][net]['mate'],
                target_connection=row['target_connection'], target_points=targets,
                physical_parts=list(physical.values()), partition_requests=[p for p in row['parts'] if p['net'] == target],
                trunk_results=[p for p in row['part_trunk'] if p['net'] == target],
                all_part_label_collapse=target in row['part_all_label'],
                actual_crossings=row['crossings'], greedy_counts=row['counts'],
                greedy_worst=row['worst'], changes=row['changes'])


def local_isomorphism(examples):
    """A literal 24-terminal certificate, not a whole-circuit isomorphism."""
    device_map = {'m4': 'm6', 'm5': 'm5', 'm6': 'm8', 'm7': 'm7', 'm9': 'm9', 'm11': 'm1'}
    net_map = {'net0': 'vn', 'vdd': 'vss', 'vss': 'vdd', 'vm1': 'net3', 'vm2': 'net6',
               'veaout': 'eao', 'vb1': 'vc', 'vc': 'vb1', 'net4': 'net10', 'v2': 'net9'}
    left, right = [read_cards((examples / (n + '.cir')).read_text()) for n in ('ag-2376', 'ag-2274')]
    rows = []
    for a, b in device_map.items():
        x, y = left[a], right[b]
        assert [net_map[n] for n in x[1:5]] == y[1:5]
        assert (x[5], y[5]) in (('nch', 'pch'), ('pch', 'nch'))
        rows.append(dict(left=a, right=b, left_card=x, right_card=y,
                         pin_map=[[n, net_map[n]] for n in x[1:5]]))
    return dict(left='ag-2376', right='ag-2274', device_map=device_map, net_map=net_map, rows=rows,
                scope='Only six selected D/G/S/B bindings with uniform polarity and rail exchange; no full-circuit isomorphism or placement equivalence.')


def method_checks():
    checks = []
    base = [[[0, 0], [40, 0]], [[0, 100], [40, 100]]]
    assert piece(base, [0, 0]) == [0]
    checks.append('separate_same_net_segments_not_joined')
    for name, bridge in (
        ('endpoint', [[[40, 0], [40, 100]]]),
        ('T', [[[30, 0], [30, 100]]]),
        ('overlap', [[[30, 0], [50, 0]], [[50, 0], [50, 100]], [[50, 100], [30, 100]]]),
        ('proper_X', [[[30, -10], [30, 110]]]),
        ('transitive_X', [[[30, -10], [30, 40]], [[25, 30], [40, 30]], [[35, 20], [35, 110]]])):
        segs = base + bridge
        assert piece(segs, [0, 0]) == list(range(len(segs)))
        rev = [list(reversed(s)) for s in reversed(segs)]
        assert piece(rev, [0, 0]) == list(range(len(rev)))
        checks.append(name + '_and_reversed_permuted_connected')
    assert piece(base + [[[30, 1], [30, 99]]], [0, 0]) == [0]
    checks.append('one_unit_gaps_not_joined')
    return checks


def audit(root, diagnostic, baseline):
    trace = run(root, diagnostic, baseline)
    assert trace['source_manifest']['cases'] == list(CASES)
    revision = subprocess.check_output(['git', 'rev-parse', '10def3a7'], cwd=root, text=True).strip()
    for rel, wanted in trace['source_manifest']['source_sha256'].items():
        blob = subprocess.check_output(['git', 'show', revision + ':' + rel], cwd=root)
        assert hashlib.sha256(blob).hexdigest() == wanted, ('not committed15', rel)
    for rel, wanted in trace['source_manifest']['instrumented_sha256'].items():
        assert digest(diagnostic / rel) == wanted, ('instrumented copy changed', rel)
    examples = root / 'external/examples/analoggenie'
    source = []
    for name, (net, devices) in zip(CASES, TARGETS):
        native = json.loads((diagnostic / 'results' / (name + '-compact-1') / 'trace.json').read_text())
        proof = source_loss(examples, dict(id=name, net=net, pins=[[d, 1] for d in devices]), native, native)
        # Even a disconnected target cannot be rescued by unassigned SVG ink.
        if not proof['source_connection']['continuous']:
            ink = conductor_ink(ET.parse(examples / (name + '.svg')).getroot())
            assert wire_tree(ink, proof['source_targets']) is None, (name, 'complete ink unexpectedly connects')
        proof.pop('native')
        source.append(proof)
    names, crossing_checks, rows = [], [], []
    for case in trace['cases']:
        name = case['name'] + ':compact=' + str(case['compact']).lower()
        names.append(name)
        for r in case['rounds']:
            actual = sorted((tuple(sorted(c['nets'])), tuple(c['at'])) for c in r['crossings'])
            assert crossings(r) == actual, (name, r['round'], 'actual crossing multiset mismatch')
            crossing_checks.append(name + ':round=' + str(r['round']) + ':actual_crossings')
        rows.append(dict(name=name, target=case['target'], target_devices=case['target_devices'],
                         deck_sha256=case['deck_sha256'], final_geometry_sha256=case['final_geometry_sha256'],
                         final_report_sha256=case['final_report_sha256'],
                         trace_log_sha256=digest(diagnostic / 'results' / (case['name'] + '-compact-' + str(int(case['compact']))) / 'trace.log'),
                         rounds=[round_evidence(r, case['target'], case['target_devices']) for r in case['rounds']]))
    assert names == trace['named_byte_identical_cases']
    # Explicit named baseline markers: a pass here requires inventory review.
    continuous = [r['name'] for r in rows if r['rounds'][-1]['target_connection']['continuous']]
    assert continuous == ['ag-2452:compact=false', 'ag-2376:compact=false']
    return dict(provenance=dict(matching_committed_revision=revision,
                               capture_note='Original capture had HEAD04ed02e6 with uncommitted15 edits; every retained source hash matches committed15 10def3a7.',
                               source_sha256=trace['source_manifest']['source_sha256'],
                               instrumented_sha256=trace['source_manifest']['instrumented_sha256'],
                               baseline_binary_sha256=trace['baseline_binary_sha256'], trace_binary_sha256=trace['trace_binary_sha256']),
                named_byte_identical_cases=names, named_actual_crossing_checks=crossing_checks,
                method_checks=method_checks(), source=source, cases=rows,
                local_polarity_counterexample=local_isomorphism(examples),
                baseline_final_continuous=continuous,
                unresolved_noncompact_partition_gaps=[n + ':compact=false' for n in CASES[:3]],
                separate_whole_part_collapse=[n + ':compact=true' for n in ('ag-2452', 'ag-2376')],
                intentionally_disconnected_sources=['ag-2274', 'ag-1411'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('diagnostic', type=Path)
    parser.add_argument('baseline', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    result = audit(Path(__file__).resolve().parents[3], args.diagnostic, args.baseline)
    if args.check:
        assert result == json.loads(Path(__file__).with_name('thin_parts_cases.json').read_text()), 'exact thinning evidence differs'
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    print('Named byte-identical runs:', result['named_byte_identical_cases'])
    print('Named literal checks:', result['method_checks'])


if __name__ == '__main__':
    main()
