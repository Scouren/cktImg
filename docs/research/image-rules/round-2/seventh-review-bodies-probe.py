#!/usr/bin/env python3
"""Independent raw-incidence, actual NC ink and repaired hidden-lead review."""
import argparse
from collections import Counter
from decimal import Decimal as D
import importlib.util
import json
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET
import hashlib

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
RUN = ROOT / '.objective/human-schematic-equivalence/runs/iteration21-resume1/image-rule-round-2/bodies/sixth-bodies'
OWN = ROOT / '.objective/human-schematic-equivalence/runs/iteration21-resume1/image-rule-round-2/groups/seventh'
MODES = ['missing_body_geometry', 'visible_body', 'hidden_body']
EXPECTED = {
    'lone_resistor': ([['r1', 0]], [[[120, 20]], [[150, 20]], [[120, 20]]]),
    'one_body_peer': ([['m1', 3], ['r1', 0]], [[[90, 100]], [], [[90, 100]]]),
    'two_body_peers': ([['m1', 3], ['m2', 3]], [[], [], []]),
    'two_bodies_and_resistor': ([['m1', 3], ['m2', 3], ['r1', 0]], [[[130, 100]], [], [[240, 120]]]),
    'formal_body_and_resistor': ([['m1', 3], ['r1', 0]], [[], [], []]),
    'source_tie_and_resistor': ([['m1', 2], ['m1', 3], ['r1', 0]], [[], [], []]),
}
NOTES = {
    'lone_resistor': 'All three modes show a lone-resistor cross. Hidden mode still has a short B glyph stroke; visible B=S mode routes the body to the visible source.',
    'one_body_peer': 'Missing and hidden modes show the resistor cross. Visible mode joins its body lead to the resistor. Hidden body lead remains visible but separated from resistor.',
    'two_body_peers': 'Missing mode has no interbody line; visible and hidden modes both visibly join the bodies, for different route/glyph reasons.',
    'two_bodies_and_resistor': 'Hidden bodies visibly meet each other while the resistor remains separately crossed. Visible mode connects all three; missing mode shows no body link.',
    'formal_body_and_resistor': 'All modes connect formal b to resistor and omit the cross. Missing/hidden modes still do not show a body-to-b physical path; hidden glyph retains its short lead.',
    'source_tie_and_resistor': 'All modes route source to resistor; hidden mode also retains a short B stroke, while visible mode explicitly loops B to source.',
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def points(value):
    values = [D(x) for x in re.findall(r'-?\d+(?:\.\d+)?', value)]
    assert len(values) % 2 == 0
    return list(zip(values[::2], values[1::2]))


def actual_nc(svg, document):
    """Independently bind cross ink using all external port-circle positions."""
    root = ET.fromstring(svg)
    unsupported = ('transform', 'visibility', 'style', 'opacity', 'display', 'class', 'clip-path', 'mask', 'filter', 'stroke-opacity')
    assert not any(k in e.attrib for e in root.iter() for k in unsupported)
    groups = [e for e in root if e.tag.endswith('}g')]
    assert len(groups) == 1 and groups[0].attrib == dict(fill='none', stroke='#1d2330',
        **{'stroke-width': '1.6', 'stroke-linejoin': 'round', 'stroke-linecap': 'round'})
    polylines = [e for e in root.iter() if e.tag.endswith('}polyline')]
    assert all(e in list(groups[0]) and set(e.attrib) == {'points'} for e in polylines)
    circles = [(D(e.attrib['cx']), D(e.attrib['cy'])) for e in root.iter() if e.tag.endswith('}circle') and D(e.attrib['r']) == D('4.8')]
    native = [p['xy'] for d in document['devices'] if d['class'] in ('ipin', 'opin') for p in d['pins']]
    assert len(native) == len(circles) and native
    scale = D('1.6')
    candidates = set()
    for x, y in circles:
        dx, dy = x - scale * native[0][0], y - scale * native[0][1]
        if Counter((scale * a + dx, scale * b + dy) for a, b in native) == Counter(circles):
            candidates.add((dx, dy))
    assert len(candidates) == 1
    dx, dy = next(iter(candidates))
    ink = []
    for e in polylines:
        p = points(e.attrib['points'])
        if len(p) == 2 and abs(p[0][0] - p[1][0]) == abs(p[0][1] - p[1][1]) == D('9.6'):
            ink.append(tuple(sorted(p)))
    expected = []
    centers = []
    radius = D('4.8')
    for a, b in document['no_connects']:
        x, y = scale * a + dx, scale * b + dy
        centers.append([str(x), str(y)])
        expected += [tuple(sorted([(x-radius, y-radius), (x+radius, y+radius)])),
                     tuple(sorted([(x-radius, y+radius), (x+radius, y-radius)]))]
    assert Counter(ink) == Counter(expected), (ink, expected)
    return dict(svg_translation=[str(dx), str(dy)], scale=str(scale), cross_centers=centers,
                diagonal_cross_primitive_count=len(ink), external_marker_anchors=len(native))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--output', type=Path, default=HERE / 'seventh-review-bodies-probe.json')
    ap.add_argument('--check', type=Path)
    args = ap.parse_args()
    sys.path.insert(0, str(HERE))
    before_path = OWN / 'sixth-bodies-proof-before.py'
    current_path = HERE / 'sixth-bodies-proof.py'
    old = load_module(before_path, 'seventh_old_bodies')
    current = load_module(current_path, 'seventh_current_bodies')
    evidence_path = HERE / 'sixth-bodies-evidence.json'
    evidence = json.loads(evidence_path.read_text())
    assert evidence['script_sha256'] == sha(current_path)
    rows = {(r['case'], r['mode']): r for r in evidence['cases']}
    assert set(rows) == {(c, m) for c in EXPECTED for m in MODES} and len(evidence['cases']) == 18
    checked = []
    for case, (owners, nc_by_mode) in EXPECTED.items():
        deck = (RUN / (case + '.cir')).read_text().lower()
        cards = [line.split() for line in deck.splitlines() if line and line[0] in 'mr']
        assert all(w[0][0] in 'mr' for w in cards)
        occurrence = [[w[0], i] for w in cards for i, n in enumerate(w[1:5] if w[0][0] == 'm' else w[1:3]) if n == 'b']
        assert occurrence == owners
        formals = next(s.split()[2:] for s in deck.splitlines() if s.startswith('.subckt'))
        for mode, want in zip(MODES, nc_by_mode):
            row = rows[(case, mode)]
            for name, digest in row['files'].items():
                assert sha(ROOT / name) == digest
            assert [x[:2] for x in row['net_b_raw_occurrences']] == owners
            path = RUN / (case + '--' + mode + '.json')
            doc = json.loads(path.read_text())
            actual = {d['name']: d for d in doc['devices']}
            for w in cards:
                d = actual[w[0]]
                nets = [p['net'] for p in d['pins']]
                if 'bulk' in d:
                    nets.append(d['bulk'])
                assert nets == (w[1:5] if w[0][0] == 'm' else w[1:3])
            assert doc['no_connects'] == want == row['native_no_connects']
            if want:
                assert actual['r1']['pins'][0]['xy'] == want[0]
            svg_path = path.with_suffix('.svg')
            nc_ink = actual_nc(svg_path.read_text(), doc)
            checked.append(dict(case=case, mode=mode, exact_raw_owners=owners, b_is_formal='b' in formals,
                                native_no_connects=want, actual_nc_ink=nc_ink,
                                body_routes=[w for w in doc['wires'] if w['net'] == 'b'],
                                document_sha256=sha(path), svg_sha256=sha(svg_path)))
    original = (RUN / 'two_body_peers--hidden_body.svg').read_text()
    old.actual_hidden_bridge(original)
    current.actual_hidden_bridge(original)
    attacks = []
    for mode in ['translated_one_own_lead', 'subprecision_one_tip', 'invisible_one_own_lead']:
        root = ET.fromstring(original)
        p = next(p for p in root.iter() if p.attrib.get('points') == '225.6,128.0 188.8,128.0 ')
        if mode == 'translated_one_own_lead':
            p.set('transform', 'translate(0 10)')
        elif mode == 'subprecision_one_tip':
            p.set('points', '225.6,128.0 188.89,128.0 ')
        else:
            p.set('visibility', 'hidden')
        mutant = ET.tostring(root, encoding='unicode')
        path = OWN / (mode + '.svg')
        path.write_text(mutant)
        old.actual_hidden_bridge(mutant)
        try:
            current.actual_hidden_bridge(mutant)
        except AssertionError:
            pass
        else:
            raise AssertionError('repaired checker accepted ' + mode)
        attacks.append(dict(name=mode, old_accepts=True, repaired_rejects=True, path=str(path.relative_to(ROOT)), sha256=sha(path)))
    views = []
    for case, note in NOTES.items():
        path = RUN / 'figures' / (case + '.png')
        views.append(dict(case=case, actual_view=True, panels=MODES, path=str(path.relative_to(ROOT)), sha256=sha(path), observation=note))
    path = RUN / 'figures/two_body_peers--hidden_body.png'
    views.append(dict(case='two_body_peers', actual_view=True, panels=['hidden_body'], path=str(path.relative_to(ROOT)),
                      sha256=sha(path), observation='Standalone enlarged view confirms an uninterrupted horizontal B bridge between the two actual channel strokes, despite zero B route records.'))
    result = dict(scope='Independent saved native artifact/ink review; no plugin, ABI or host execution.',
                  script_sha256=sha(Path(__file__)), reviewed_evidence_sha256=sha(evidence_path),
                  old_checker=dict(path=str(before_path.relative_to(ROOT)), sha256=sha(before_path)),
                  current_checker=dict(path=str(current_path.relative_to(ROOT)), sha256=sha(current_path)),
                  exact_cases=checked, repaired_attacks=attacks, fresh_actual_views=views,
                  conclusion='Electrical peer count, native route count, actual glyph ink and target named connectivity are separate facts. No electrical-failure claim without target round trip.')
    if args.check:
        assert json.loads(args.check.read_text()) == result
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    print(json.dumps(dict(cases=len(checked), actual_nc_ink_certificates=len(checked), old_attacks_rejected_after_repair=len(attacks), actual_views=len(views))))


if __name__ == '__main__':
    main()
