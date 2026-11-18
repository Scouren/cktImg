#!/usr/bin/env python3
"""Read saved forced AG1080 ink; independent segment oracle, no producer run."""
import argparse
import collections
import copy
from fractions import Fraction as F
import hashlib
import itertools
import json
from pathlib import Path
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
BASE = ROOT / '.objective/human-schematic-equivalence/runs/iteration21-resume1'
STEM = BASE / 'image-rule-round-2/groups/twelfth/ag-1080-reconstruct'
SOURCE = ROOT / 'external/examples/analoggenie'
EXPECTED = {
    'rn': [['m7.d', 'm9.d'], ['m27.g']],
    'rp': [['m6.d', 'm8.d'], ['m28.g']],
    'fn1': [['m16.d', 'm18.d'], ['m29.g']],
    'fp1': [['m15.d', 'm17.d'], ['m31.g']],
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canon(blocks):
    return sorted(sorted(block) for block in blocks)


def on(p, a, b):
    return ((b[0]-a[0])*(p[1]-a[1]) == (b[1]-a[1])*(p[0]-a[0])
            and all(min(a[k], b[k]) <= p[k] <= max(a[k], b[k]) for k in (0, 1)))


def segments(d):
    rows = []
    for wi, wire in enumerate(d['wires']):
        for pi, points in enumerate(wire['segments']):
            for si, (a, b) in enumerate(zip(points, points[1:])):
                assert a != b and (a[0] == b[0] or a[1] == b[1])
                rows.append(dict(net=wire['net'], a=a, b=b, index=[wi, pi, si]))
    return rows


def relation(u, v, dots):
    a, b, c, e = u['a'], u['b'], v['a'], v['b']
    if a[0] == b[0] == c[0] == e[0] or a[1] == b[1] == c[1] == e[1]:
        k = 1 if a[0] == b[0] else 0
        lo, hi = max(min(a[k], b[k]), min(c[k], e[k])), min(max(a[k], b[k]), max(c[k], e[k]))
        if lo < hi:
            return dict(kind='collinear_overlap', interval=[lo, hi])
    touching = sorted({tuple(p) for p in (a, b, c, e) if on(p, a, b) and on(p, c, e)})
    if touching:
        return dict(kind='endpoint_or_T', points=touching)
    if a[0] == b[0] and c[1] == e[1]:
        p = (a[0], c[1])
    elif a[1] == b[1] and c[0] == e[0]:
        p = (c[0], a[1])
    else:
        return None
    if on(p, a, b) and on(p, c, e):
        return dict(kind='dotted_crossing' if p in dots else 'undotted_crossing', at=p)
    return None


def scan(d):
    rows, dots = segments(d), set(map(tuple, d['junctions']))
    contacts, crosses, pins = [], [], []
    for u, v in itertools.combinations(rows, 2):
        if u['net'] == v['net']:
            continue
        r = relation(u, v, dots)
        if r:
            (crosses if r['kind'] == 'undotted_crossing' else contacts).append(dict(left=u, right=v, **r))
    for dev in d['devices']:
        for pin in dev['pins']:
            for s in rows:
                if pin['net'] != s['net'] and on(pin['xy'], s['a'], s['b']):
                    pins.append(dict(device=dev['name'], pin=pin, segment=s))
    return dict(foreign_conductor_contacts=contacts, undotted_foreign_crossings=crosses, foreign_pin_contacts=pins)


def parts(d, net, raw):
    """Segments are vertices; no label or pin coordinate becomes a union vertex."""
    rows = [s for s in segments(d) if s['net'] == net]
    parent = list(range(len(rows)))
    def root(i):
        while parent[i] != i:
            i = parent[i]
        return i
    for i, j in itertools.combinations(range(len(rows)), 2):
        r = relation(rows[i], rows[j], set(map(tuple, d['junctions'])))
        if r and r['kind'] != 'undotted_crossing':
            parent[root(i)] = root(j)
    blocks, named = collections.defaultdict(list), collections.defaultdict(list)
    for dev in d['devices']:
        if dev['name'] not in raw:
            continue
        for pin in dev['pins']:
            if pin['net'] == net:
                roots = {root(i) for i, s in enumerate(rows) if on(pin['xy'], s['a'], s['b'])}
                assert len(roots) == 1, ('unattached or ambiguous actual pin', dev['name'], pin, roots)
                blocks[next(iter(roots))].append(dev['name'] + '.' + pin['term'])
    markers = [dict(kind='label', **l) for l in d['labels']]
    markers += [dict(kind=dev['class'], net=dev['pins'][0]['net'], at=dev['pins'][0]['xy'])
                for dev in d['devices'] if dev['name'] not in raw]
    for mark in markers:
        roots = {root(i) for i, s in enumerate(rows) if on(mark['at'], s['a'], s['b'])}
        assert len(roots) <= 1, ('marker at unjoined crossing', mark)
        if roots:
            assert mark['net'] == net, ('foreign marker', mark, net)
            named[next(iter(roots))].append(mark)
        elif mark['net'] == net:
            raise AssertionError(('detached marker', mark))
    if len(blocks) > 1:
        assert all(named[k] for k in blocks)
    return dict(blocks=canon(blocks.values()), components=[dict(pins=sorted(v), markers=named[k]) for k, v in blocks.items()])


def raw_contract(d, deck):
    cards, models, formals = {}, {}, None
    for line in deck.splitlines():
        w = line.lower().split()
        if not w or w[0].startswith('*'):
            continue
        if w[0] == '.model':
            assert w[1] not in models
            models[w[1]] = w[2:]
        elif w[0] == '.subckt':
            assert formals is None and w[1] == 'dut'
            formals = w[2:]
        elif w[0].startswith('m'):
            assert w[0] not in cards and len(w) == 10
            cards[w[0]] = w
        else:
            assert w == ['.ends', 'dut'], w
    assert len(cards) == 32 and len({v['name'] for v in d['devices']}) == len(d['devices'])
    actual = {}
    for dev in d['devices']:
        if dev['name'] not in cards:
            assert dev['class'] in ('ipin', 'opin', 'gnd', 'vdd') and len(dev['pins']) == 1
            assert dev['name'].startswith('_' + dev['class']) and dev['pins'][0]['term'] == 'p' and dev['value'] == ''
            continue
        card = cards[dev['name']]
        assert dev['class'] == models[card[5]][0] and dev['value'].split() == card[5:]
        assert [p['term'] for p in dev['pins']] == ['d', 'g', 's']
        assert [p['net'] for p in dev['pins']] + [dev['bulk']] == card[1:5]
        actual[dev['name']] = dict(card=card, actual=dev)
    assert set(actual) == set(cards)
    return dict(cards=cards, models=models, formals=formals, complete_actual_bindings=actual)


def svg_binding(d, path):
    root = ET.parse(path).getroot()
    group = root[1]
    assert group.attrib == dict(fill='none', stroke='#1d2330', **{'stroke-width': '1.6', 'stroke-linejoin': 'round', 'stroke-linecap': 'round'})
    raw_paths = [p for w in d['wires'] for p in w['segments']]
    def points(e):
        assert e.tag.endswith('}polyline') and set(e.attrib) == {'points'}
        return [[F(v) for v in p.split(',')] for p in e.attrib['points'].split()]
    first = points(group[0])
    scale = (first[0][1]-first[1][1]) / (raw_paths[0][0][1]-raw_paths[0][1][1])
    offset = [first[0][k]-scale*raw_paths[0][0][k] for k in (0, 1)]
    transform = lambda p: [scale*p[k]+offset[k] for k in (0, 1)]
    for e, path in zip(group, raw_paths):
        assert points(e) == [transform(p) for p in path]
    circles = [e for e in root if e.tag.endswith('}circle')]
    assert len(circles) == len(d['junctions'])
    for e, p in zip(circles, d['junctions']):
        assert set(e.attrib) == {'cx', 'cy', 'r', 'fill', 'stroke'} and e.attrib['fill'] == '#1d2330' and e.attrib['stroke'] == 'none'
        assert [F(e.attrib['cx']), F(e.attrib['cy'])] == transform(p) and F(e.attrib['r']) == F('3.8')
    # The nearby painted FP dot does not even touch the FN horizontal stroke.
    crossing, dot = transform([570, 630]), transform([570, 635])
    assert abs(crossing[1]-dot[1]) > F('3.8') + F('1.6')/2
    return dict(route_polylines=len(raw_paths), junction_circles=len(circles), scale=str(scale), offset=list(map(str, offset)),
                fn_fp_svg_crossing=list(map(str, crossing)), nearest_fp_dot=list(map(str, dot)), dot_to_crossing_distance='8',
                dot_radius='3.8', wire_half_width='0.8', painted_clearance='3.4')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--check', type=Path)
    ap.add_argument('--output', type=Path, default=HERE / 'twelfth-ports-route-review.json')
    args = ap.parse_args()
    d = json.loads(STEM.with_suffix('.json').read_text())
    raw = raw_contract(d, STEM.with_suffix('.cir').read_text())
    assert raw_contract(d, (SOURCE/'ag-1080.cir').read_text()) == raw
    svg = svg_binding(d, STEM.with_suffix('.svg'))
    found = scan(d)
    assert not found['foreign_conductor_contacts'] and not found['foreign_pin_contacts']
    expected_crosses = {('fn', 'fp', (570, 630)), ('rn1', 'rp1', (1370, 710)), ('rn1', 'rp1', (1230, 720))}
    assert expected_crosses <= {(r['left']['net'], r['right']['net'], tuple(r['at'])) for r in found['undotted_foreign_crossings']}
    prior_path = HERE/'eleventh-partition-candidates.json'
    prior = json.loads(prior_path.read_text())['physical_evidence']['ag-1080']
    local_path = HERE/'twelfth-organization-proof.json'
    local = next(r for r in json.loads(local_path.read_text())['runs'] if r['kind'] == 'reconstruct')
    assert len(local['local_gates']) == 2 and all(r['pass_local_gate'] for r in local['local_gates'])
    assert local['artifacts'][str(STEM.with_suffix('.json').relative_to(ROOT))] == sha(STEM.with_suffix('.json'))
    for name, digest in prior['source_hashes'].items():
        assert sha(SOURCE/name) == digest
    failures = {}
    for net, expected in EXPECTED.items():
        expected = canon(expected)
        p = parts(d, net, raw['cards'])
        keys = sorted(itertools.chain.from_iterable(expected))
        assert sorted(itertools.chain.from_iterable(p['blocks'])) == keys
        pairs = prior['nets'][net]['pairs']
        assert len(pairs) == 3
        actual_pair_ids = {tuple(sorted(dev + '.' + 'dgsb'[i] for dev, i in pair['pins'])) for pair in pairs}
        assert actual_pair_ids == set(itertools.combinations(keys, 2))
        for pair in pairs:
            names = [dev + '.' + 'dgsb'[i] for dev, i in pair['pins']]
            assert pair['source_connected'] == any(set(names) <= set(b) for b in expected)
        assert p['blocks'] != expected
        failures[net] = dict(expected_source_blocks=expected, actual=p, source_pair_relations=pairs)
    assert failures['fn1']['actual']['blocks'] == [['m16.d'], ['m18.d'], ['m29.g']]
    assert all(len(v['actual']['blocks']) == 1 for k, v in failures.items() if k != 'fn1')
    mutations = []
    m = copy.deepcopy(d); m['junctions'].append([570, 630])
    assert any(r['kind'] == 'dotted_crossing' and tuple(r['at']) == (570, 630) for r in scan(m)['foreign_conductor_contacts'])
    mutations.append('add_actual_crossing_dot_detects_foreign_join')
    assert d['wires'][14]['net'] == 'fp' and d['wires'][14]['segments'][0] == [[570,620],[570,635]]
    m = copy.deepcopy(d); m['wires'][14]['segments'][0][0] = [570, 630]
    assert any(r['kind'] == 'endpoint_or_T' and set((r['left']['net'], r['right']['net'])) == {'fn', 'fp'}
               and (570,630) in r['points'] for r in scan(m)['foreign_conductor_contacts'])
    mutations.append('move_foreign_endpoint_to_crossing_detects_T')
    m = copy.deepcopy(d); m['wires'].append(dict(net='foreign', segments=[[[500,630],[600,630]]]))
    assert any(r['kind'] == 'collinear_overlap' for r in scan(m)['foreign_conductor_contacts'])
    mutations.append('added_foreign_collinear_stroke_detects_overlap')
    m = copy.deepcopy(d); m['wires'].append(dict(net='foreign', segments=[[[430,620],[450,620]]]))
    assert scan(m)['foreign_pin_contacts']; mutations.append('foreign_route_at_raw_pin_detected')
    # A label at the undotted X cannot change conductor connectivity.
    m = copy.deepcopy(d); m['labels'].append(dict(net='fn', at=[570,630]))
    assert scan(m) == found; mutations.append('label_at_crossing_does_not_union_conductors')
    dependencies = [STEM.with_suffix(s) for s in ('.cir','.json','.svg','.report.json')]
    dependencies += [prior_path, local_path, SOURCE/'ag-1080.cir', SOURCE/'ag-1080.svg', SOURCE/'ag-1080.human.json',
                     HERE/'figures/groups/twelfth/ag-1080-reconstruct.png']
    result = dict(script_sha256=sha(Path(__file__)), dependencies={str(p.relative_to(ROOT)):sha(p) for p in dependencies},
                  scope='Saved frozen native only; actual route polylines and junction circles, raw inventory and exported pins. No generic glyph/text clearance, target import or arbitrary SVG paint validation.',
                  actual_view='Forced reconstruction viewed independently; suspicious crossings corrected after JSON/SVG check.',
                  raw=raw, svg_binding=svg, route_segment_count=len(segments(d)), scan=found,
                  peer_local_gates=local['local_gates'], n0_failures=failures, mutation_controls=mutations)
    result = json.loads(json.dumps(result))
    if args.check:
        assert json.loads(args.check.read_text()) == result
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True)+'\n')
    print(json.dumps(dict(raw_devices=32, ordered_raw_terminals=128, route_segments=len(segments(d)),
                         foreign_contacts=0, foreign_pin_contacts=0, n0_failed_names=sorted(failures), controls=len(mutations))))


if __name__ == '__main__':
    main()
