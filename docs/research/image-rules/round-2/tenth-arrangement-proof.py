#!/usr/bin/env python3
"""Actual-file pose/binding proof and a reported-metric diagnostic comparison."""
import argparse
import copy
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import re

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
BASE = ROOT / '.objective/human-schematic-equivalence/runs/iteration21-resume1'
NOTES = {
    'ag-1028-keep': 'Actually viewed: the old global-axis frame places the output parent around the input parent; all caller poses hold. This is the preserved nested incumbent.',
    'ag-1028-right': 'Actually viewed: translating only the complete output parent gives a separated horizontal arrangement, with long two-net interfaces. No compaction or human-quality improvement is claimed.',
    'ag-1028-below': 'Actually viewed: the same complete parent is below the input with two long outer interfaces. Reported crossings decrease to zero; this orientation differs from the source horizontal arrangement.',
    'ag-364-keep': 'Actually viewed: original nested inner/outer relation survives explicit pose replay. Short direct two-net interfaces remain.',
    'ag-364-right': 'Actually viewed: horizontal separation remains drawable but adds long crossing interfaces. Its existence does not make it preferred over the nested source/incumbent.',
    'ag-364-below': 'Actually viewed: vertical separation preserves exact poses internally but lengthens interfaces. The nested source remains the observed preference.',
    'ag-364-tail-keep': 'Actually viewed: added PMOS tail is above the retained inner core, with two output branches still surrounding it. Both parents are now single D/S components. The vb3 label touches its line, so this is a pose witness, not a complete label-clearance pass.',
    'ag-364-tail-right': 'Actually viewed: the same tail-connected output core can be translated right. Long crossed interfaces and vb3 label/line contact remain; no routing-quality or human preference gate is claimed.',
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rel(path):
    return str(path.relative_to(ROOT))


def load(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), HERE / (name + '.py'))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def transformed(xy, turn, mirror, origin):
    x, y = xy
    if mirror:
        x = -x
    x, y = ((x, y), (-y, x), (-x, -y), (y, -x))[turn]
    return [x + origin[0], y + origin[1]]


def check_frames(raw, text, document, models):
    rows = [line.lower().split() for line in text.splitlines() if line.startswith('*@')]
    assert len(rows) == len(raw) and all(row[:2] == ['*@', 'at'] and len(row) == 6 for row in rows)
    assert len({row[2] for row in rows}) == len(rows) and {row[2] for row in rows} == set(raw)
    names = [d['name'] for d in document['devices']]
    assert len(names) == len(set(names))
    by_name = {d['name']: d for d in document['devices']}
    expected = {}
    for row in rows:
        d = by_name[row[2]]
        assert d['class'] == models[raw[row[2]][5]][0]
        origin = [float(row[3]) * 40, float(row[4]) * 40]
        assert all(x == int(x) for x in origin)
        word = re.fullmatch('(m?)r(0|90|180|270)', row[5])
        assert word is not None
        mirror, turn = bool(word[1]), int(word[2]) // 90
        assert d['pos'] == origin and d['rot'] == turn and d['mirror'] == mirror
        pins = [transformed(p, turn, mirror, origin) for p in [(20, 0), (0, -20), (-20, 0)]]
        assert [p['term'] for p in d['pins']] == ['d', 'g', 's']
        assert [p['xy'] for p in d['pins']] == pins
        assert [p['net'] for p in d['pins']] == raw[row[2]][1:4]
        assert d['bulk'] == raw[row[2]][4] and d['value'].split() == raw[row[2]][5:]
        expected[row[2]] = d
    return expected


def local_reflection(devices, case):
    mapping = case['unique_reflection']['devices']
    axes = []
    for group in case['proposed_groups']:
        sums = set()
        for name in group:
            mate = mapping[name]
            assert mate in group
            a, b = devices[name], devices[mate]
            assert a['pos'][1] == b['pos'][1]
            sums.add(a['pos'][0] + b['pos'][0])
            if name == mate:
                continue  # An on-axis tail origin need not mirror its one-sided gate glyph.
            for p, q in zip(a['pins'], b['pins']):
                assert p['xy'][1] == q['xy'][1]
                sums.add(p['xy'][0] + q['xy'][0])
        assert len(sums) == 1
        axes.append(sums.pop())
    return axes


def boxes(devices, groups):
    out = []
    for group in groups:
        points = [p['xy'] for name in group for p in devices[name]['pins']]
        out.append([min(p[0] for p in points), min(p[1] for p in points),
                    max(p[0] for p in points), max(p[1] for p in points)])
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--check', type=Path)
    ap.add_argument('--output', type=Path, default=HERE / 'tenth-arrangement-proof.json')
    args = ap.parse_args()
    m, runner = load('ninth-local-groups-census'), load('tenth-arrangement-literals')
    literal_path, graph_path = [HERE / f'tenth-arrangement-{k}.json' for k in ('literals', 'graphs')]
    literals, graphs = [json.loads(p.read_text()) for p in (literal_path, graph_path)]
    for path, digest in literals['dependencies'].items():
        assert sha(ROOT / path) == digest
    lib = BASE / 'resistor-output-integrated-common/tests/symbols.zon'
    for cls in ('nmos', 'pmos'):
        line = next(s for s in lib.read_text().splitlines() if f'.name = "{cls}"' in s)
        local = re.findall(r'\.name = "([dgs])", \.at = \.\{ \.x = (-?\d+), \.y = (-?\d+)', line.split('.draw')[0])
        assert local == [('d', '20', '0'), ('g', '0', '-20'), ('s', '-20', '0')]
    rows = literals['records']
    assert sorted(r['name'] for r in rows) == sorted(NOTES) and len(rows) == 8
    certificates = {}
    for r in rows:
        for path, digest in r['outputs'].items():
            assert sha(ROOT / path) == digest
        assert sha(ROOT / r['raster']['path']) == r['raster']['sha256']
        deck = ROOT / r['deck']
        assert sha(deck) == r['deck_sha256'] and r['exit_code'] == 0
        assert next((ROOT / p).read_text() for p in r['outputs'] if p.endswith('.exit')) == '0\n'
        text = deck.read_text()
        raw_text = '\n'.join(s for s in text.splitlines() if not s.startswith('*@')) + '\n'
        values = m.facts(raw_text)
        raw = values[0]
        assert dict(cards=raw, formals=values[1], models=values[2], rails=values[3], declarations=values[4]) == r['raw_facts']
        original = m.facts((ROOT / 'external/examples/analoggenie' / (r['source'] + '.cir')).read_text())
        expected = copy.deepcopy(original[0])
        if r['tail_bridge_mutation']:
            expected['m9'][3] = expected['m10'][3] = 'ptail'
            expected['m14'] = ['m14', 'ptail', 'vb3', 'vdd', 'vdd', 'pch', 'l=0.15', 'w=1', 'nf=1', 'm=1']
        assert raw == expected and values[1:] == original[1:]
        case = m.decompose(*values)
        assert case == r['raw_decomposition']
        doc = json.loads(next((ROOT / p).read_text() for p in r['outputs'] if p.endswith('.json') and not p.endswith('.report.json')))
        report = json.loads(next((ROOT / p).read_text() for p in r['outputs'] if p.endswith('.report.json')))
        assert report['requests'] == r['report_requests']
        poses = check_frames(raw, text, doc, values[2])
        runner.check_actual(text, raw, poses, doc, report, m)  # Includes the entire document inventory guard.
        assert poses == r['actual_devices']
        axes = local_reflection(poses, case)
        bounds = boxes(poses, case['proposed_groups'])
        a, b = bounds
        overlap = max(a[0], b[0]) < min(a[2], b[2]) and max(a[1], b[1]) < min(a[3], b[3])
        assert overlap == (r['arrangement'] == 'keep')
        certificates[r['name']] = dict(local_axes2=axes, actual_terminal_boxes=bounds,
                                      box_interiors_overlap=overlap, reported_metrics=report['metrics'],
                                      reported_gate_findings=report['gates'],
                                      raw_terminal_occurrences=4 * len(raw),
                                      view=dict(**r['raster'], actual_view_note=NOTES[r['name']],
                                                raster_revision='Actually re-viewed all eight normalized PNGs after the final replay metadata repair; old PNG bytes were not retained.'))
    selection = {}
    for family in ('ag-1028', 'ag-364', 'ag-364-tail'):
        keys = [n for n in certificates if n.rsplit('-', 1)[0] == family]
        scores = {n: [certificates[n]['reported_metrics']['crossings'],
                      certificates[n]['reported_metrics']['bends']] for n in keys}
        best = min(scores.values())
        winners = sorted(n for n in keys if scores[n] == best)
        keep = family + '-keep'
        winner = keep if keep in winners else winners[0]
        selection[family] = dict(scores=scores, winner=winner, policy='reported crossings then bends; keep on ties',
                                scope='Executed arithmetic comparison only; not a complete geometry/route/target acceptance gate.')
    assert selection['ag-1028']['winner'] == 'ag-1028-below'
    assert selection['ag-364']['winner'] == 'ag-364-keep'
    assert selection['ag-364-tail']['winner'] == 'ag-364-tail-keep'
    syntax_counts = {}
    for name, case in graphs['candidates'].items():
        k = len(case['parents'])
        catalan = math.comb(2 * (k - 1), k - 1) // k
        expected = 1 + math.factorial(k) * catalan * 2 ** (k - 1)
        path = ROOT / case['finite_symbolic_candidates']['path']
        assert sha(path) == case['finite_symbolic_candidates']['sha256']
        assert len(path.read_text().splitlines()) == expected == case['finite_symbolic_candidates']['count']
        syntax_counts[name] = expected
    first = rows[0]
    doc = json.loads(next((ROOT / p).read_text() for p in first['outputs'] if p.endswith('.json') and not p.endswith('.report.json')))
    text = (ROOT / first['deck']).read_text()
    rejected = []
    for what in ('one_actual_gate_moved', 'duplicate_raw_device', 'missing_raw_device', 'wrong_selected_class'):
        changed = copy.deepcopy(doc)
        if what == 'one_actual_gate_moved':
            changed['devices'][0]['pins'][1]['xy'][0] += 1
        elif what == 'duplicate_raw_device':
            changed['devices'].append(copy.deepcopy(changed['devices'][0]))
        elif what == 'missing_raw_device':
            changed['devices'] = changed['devices'][1:]
        else:
            changed['devices'][0]['class'] = 'pmos'
        try:
            check_frames(first['raw_facts']['cards'], text, changed, first['raw_facts']['models'])
        except (AssertionError, KeyError):
            rejected.append(what)
        else:
            raise AssertionError('changed actual frame accepted')
    result = dict(script_sha256=sha(Path(__file__)), dependencies={rel(p): sha(p) for p in
                  (literal_path, graph_path, lib, HERE / 'tenth-arrangement-literals.py')},
                  certificates=certificates, reported_metric_comparison=selection,
                  exact_symbolic_counts=syntax_counts, rejected_actual_mutations=rejected,
                  scope='97 actual MOS poses and388 ordered raw occurrences; three-contact geometry only. No B landing, wire/label-clearance or target round-trip proof.')
    if args.check:
        assert result == json.loads(args.check.read_text())
    args.output.write_text(json.dumps(result, sort_keys=True, indent=2) + '\n')
    print(json.dumps(dict(actual_views=len(certificates), raw_terminal_occurrences=388,
                         reported_metric_winners={k: v['winner'] for k, v in selection.items()})))


if __name__ == '__main__':
    main()
