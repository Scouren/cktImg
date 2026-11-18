#!/usr/bin/env python3
"""Independent source/raw review and partial-geometry-gate controls; no CLI run."""
import argparse
import collections
from fractions import Fraction
import hashlib
import importlib.util
import json
from pathlib import Path
import re
from types import SimpleNamespace

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
BASE = ROOT / '.objective/human-schematic-equivalence/runs/iteration21-resume1'
RUN = BASE / 'image-rule-round-2/bodies/twelfth-review-organization'
EXAMPLES = ROOT / 'external/examples/analoggenie'
EXPECTED = {
    ('ag-1028', 'm5'): (False, ['m1', 'm2', 'm3', 'm4', 'm5']),
    ('ag-1046', 'mtail1'): (True, ['m1', 'm2', 'm3', 'm4', 'mtail1']),
    ('ag-1071', 'm1'): (True, ['m1', 'm2', 'm3', 'm4', 'm5']),
    ('ag-1079', 'm5'): (True, ['m1', 'm2', 'm3', 'm4', 'm5']),
    ('ag-1080', 'm5'): (True, ['m1', 'm2', 'm3', 'm4', 'm5']),
    ('ag-1080', 'm10'): (True, ['m10', 'm11', 'm12', 'm13', 'm14']),
}
SOURCE_CENTERS = {
    ('ag-1028', 'm5'): {'m1': [80, 140], 'm2': [160, 180], 'm3': [80, 0], 'm4': [160, 0], 'm5': [120, 240]},
    ('ag-1046', 'mtail1'): {'m1': [300, 120], 'm2': [380, 120], 'm3': [300, 40], 'm4': [380, 40], 'mtail1': [340, 180]},
    ('ag-1071', 'm1'): {'m1': [150, 0], 'm2': [100, 60], 'm3': [200, 60], 'm4': [100, 150], 'm5': [200, 150]},
    ('ag-1079', 'm5'): {'m1': [-170, 60], 'm2': [-90, 60], 'm3': [-170, 0], 'm4': [-90, 0], 'm5': [-130, 120]},
    ('ag-1080', 'm5'): {'m1': [-170, 60], 'm2': [-90, 60], 'm3': [-170, 0], 'm4': [-90, 0], 'm5': [-120, 120]},
    ('ag-1080', 'm10'): {'m10': [130, 130], 'm11': [90, 190], 'm12': [170, 190], 'm13': [90, 250], 'm14': [170, 250]},
}


def load(name):
    spec = importlib.util.spec_from_file_location(name, HERE / (name + '.py'))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rel(path):
    return str(path.relative_to(ROOT))


def reference_candidates(row):
    """Start from complete private net incidence, then require the certified owner."""
    if row['disposition'] != 'raw_multigroup_candidate':
        return []
    cards = {r[0]: r for r in row['ordered_cards']}
    owners = {d: group for group in row['proposed_groups'] for d in group}
    types = {d: row['model_definitions'][r[5]][0] for d, r in cards.items()}
    rails, formals = row['admitted_rail_facts'], row['formals']
    mate = row['unique_reflection']['devices']
    incidence = collections.defaultdict(list)
    for name, r in cards.items():
        for role, net in enumerate(r[1:5]):
            incidence[net].append((name, role))
    found = []
    for net, endpoints in incidence.items():
        if net in rails or net in formals or sorted(k for _, k in endpoints) != [0, 2, 2]:
            continue
        tail = next(d for d, k in endpoints if k == 0)
        inputs = sorted(d for d, k in endpoints if k == 2)
        group = owners[tail]
        if len(group) != 5 or any(owners[d] != group for d in inputs):
            continue
        if mate[tail] != tail or mate[inputs[0]] != inputs[1]:
            continue
        tr = cards[tail]
        if tr[3] != tr[4] or tr[3] not in rails or any(types[d] != types[tail] for d in inputs):
            continue
        gates = [cards[d][2] for d in inputs]
        if len(set(gates)) != 2 or not set(gates) <= set(formals):
            continue
        loads = sorted(set(group) - {tail, *inputs})
        if len(loads) != 2 or mate[loads[0]] != loads[1] or any(types[d] == types[tail] for d in loads):
            continue
        if any(cards[d][3] != cards[d][4] or cards[d][3] not in rails or cards[d][3] == tr[3] for d in loads):
            continue
        if cards[loads[0]][2] != cards[loads[1]][2] or cards[loads[0]][2] not in formals or tr[2] not in formals:
            continue
        if set(gates) & {tr[2], cards[loads[0]][2]}:
            continue
        gate_formals = set(gates) | {tr[2], cards[loads[0]][2]}
        if any(role != 1 for name, card in cards.items() for role, net in enumerate(card[1:5]) if net in gate_formals):
            continue
        drains = [cards[d][1] for d in inputs]
        if len(set(drains)) != 2 or set(drains) & (set(formals) | set(rails)):
            continue
        if sorted(cards[d][1] for d in loads) != sorted(drains):
            continue
        found.append((tail, tr[2] == cards[loads[0]][2], sorted(group)))
    return sorted(found)


def raw_and_source(probe, census, svg):
    assert probe['all_names'] == census['names'] == sorted(p.stem for p in EXAMPLES.glob('*.cir'))
    assert probe['original_disposition_names'] == census['disposition_names']
    assert probe['trial_domain_names'] == census['disposition_names']['raw_multigroup_candidate']
    assert probe['not_shape_searched_names'] == [n for n in census['names'] if n not in probe['trial_domain_names']]
    actual_names, results, glyph_count = [], {}, 0
    for ident in census['names']:
        row = census['cases'][ident]
        assert sha(EXAMPLES / (ident + '.cir')) == row['deck_sha256']
        expected = reference_candidates(row)
        observed = sorted((c['tail'], c['common_control'], sorted(c['members'])) for c in probe['complete_census'][ident])
        assert expected == observed
        actual_names.extend((ident, t) for t, _, _ in expected)
    assert sorted(actual_names) == sorted(EXPECTED)
    for ident in probe['raw_five_mos_names']:
        row = census['cases'][ident]
        formals, parsed = svg.parse((EXAMPLES / (ident + '.cir')).read_text())
        cards = {r['card']: r['raw'].lower().split() for r in parsed}
        assert formals == row['formals'] and [cards[n] for n in sorted(cards)] == row['ordered_cards']
        human = json.loads((EXAMPLES / (ident + '.human.json')).read_text())
        _, _, glyphs = svg.svg_geometry(EXAMPLES / (ident + '.svg'), human, row['model_definitions'], cards)
        glyph_count += len(glyphs)
        for r in (r for r in probe['records'] if r['id'] == ident):
            c = r['candidate']; key = (ident, c['tail'])
            assert (c['common_control'], sorted(c['members'])) == EXPECTED[key]
            centers = {d: [int((glyphs[d]['D'][i] + glyphs[d]['S'][i]) / 2) for i in (0, 1)] for d in c['members']}
            assert centers == SOURCE_CENTERS[key] == r['source_geometry']['centers']
            boundary = {}
            for net in sorted({n for d in c['members'] for n in cards[d][1:5]}):
                incident = [[d, role] for d, card in sorted(cards.items()) for role, n in enumerate(card[1:5]) if n == net]
                boundary[net] = dict(inside=[v for v in incident if v[0] in c['members']],
                                     outside=[v for v in incident if v[0] not in c['members']],
                                     formal=net in formals, rail=row['admitted_rail_facts'].get(net))
            assert boundary == c['complete_boundary']
            projected = {n for n, b in boundary.items() if b['formal'] or b['outside']}
            assert set(r['projected_formals']) == projected
            assert r['raw_cards'] == {d: cards[d] for d in c['members']}
            # Actual role directions, not only an unoriented channel midpoint.
            for d in c['members']:
                sign = 1 if row['model_definitions'][cards[d][5]][0] == 'nmos' else -1
                assert sign * (glyphs[d]['S'][1] - glyphs[d]['D'][1]) > 0
            results[r['name']] = dict(centers=centers, complete_boundary=boundary,
                                      independent_full_projection=sorted(projected), source_roles_upright=True)
    assert glyph_count == 86
    return dict(exact_parent_names=[list(k) for k in sorted(actual_names)], source_glyphs=glyph_count, records=results,
                trial_domain_names=probe['trial_domain_names'], not_shape_searched_names=probe['not_shape_searched_names'])


def native_records(probe, proof, points, parse):
    records = {}
    for r in probe['records'] + proof['runs']:
        for path, digest in r['artifacts'].items():
            assert sha(ROOT / path) == digest
        assert sha(ROOT / r['raster']['path']) == r['raster']['sha256']
        path = next(ROOT / p for p in r['artifacts'] if p.endswith('.json') and not p.endswith('.report.json'))
        doc = json.loads(path.read_text())
        if 'raw_cards' in r:
            raw, models = r['raw_cards'], r['models']
        else:
            raw = r['original_ordered_cards']
            models = {'nch': ['nmos'], 'pch': ['pmos']}
        deck = next(ROOT / p for p in r['artifacts'] if p.endswith('.cir'))
        text = deck.read_text().lower()
        formals, rows = parse(text)
        assert {v['card']: v['raw'].split() for v in rows} == raw
        assert {w[1]: w[2:] for line in text.splitlines() if (w := line.split()) and w[0] == '.model'} == models
        assert formals == r.get('projected_formals', r.get('original_formals'))
        hints = [line.split()[2:] for line in text.splitlines() if line.startswith('*@ at ')]
        assert len(hints) == (0 if 'raw_cards' in r else len(raw))
        assert len({h[0] for h in hints}) == len(hints)
        by_hint = {h[0]: h[1:] for h in hints}
        assert len({d['name'] for d in doc['devices']}) == len(doc['devices'])
        actual = {}
        for i, d in enumerate(doc['devices']):
            if d['name'] not in raw:
                assert d['class'] in ('vdd', 'gnd', 'ipin', 'opin') and d['name'] == '_' + d['class'] + str(i)
                assert d['value'] == '' and 'bulk' not in d and len(d['pins']) == 1 and d['pins'][0]['term'] == 'p'
                continue
            row = raw[d['name']]
            assert d['class'] == models[row[5]][0] and d['value'].split() == row[5:]
            assert [p['term'] for p in d['pins']] == ['d', 'g', 's']
            assert [p['net'] for p in d['pins']] + [d['bulk']] == row[1:5]
            assert [p['xy'] for p in d['pins']] == points(d)
            if by_hint:
                x, y, orient = by_hint[d['name']]
                assert d['pos'] == [Fraction(x)*40, Fraction(y)*40]
                assert d['rot'] == int(orient.lstrip('m')[1:])//90 and d['mirror'] == orient.startswith('m')
            actual[d['name']] = d
        assert set(actual) == set(raw)
        assert actual == r.get('isolated_devices', r.get('actual_raw_devices'))
        records[path.stem] = dict(devices=len(raw), raw_terminal_bindings=4*len(raw), visible_role_contacts=3*len(raw))
    assert sum(v['devices'] for v in records.values()) == 94
    return records


def partial_gate_controls(proof_module, points):
    provenance = json.loads((RUN / 'before-oriented-gate-provenance.json').read_text())
    archived = []
    for name in ('twelfth-organization-probe', 'twelfth-organization-proof'):
        path = RUN / (name + '-before-oriented-gate.py')
        assert sha(path) == provenance[rel(path)]
        namespace = dict(__name__='archived_' + name, __file__=str(HERE / (name + '.py')))
        exec(compile(path.read_text(), str(path), 'exec'), namespace)
        archived.append(namespace)
    archived[1]['p'] = SimpleNamespace(**archived[0])  # Exact archived geometry dependency.
    result = {}
    for name in ('rotate_input_180', 'compress_rows'):
        path = RUN / (name + '.json')
        value = json.loads(path.read_text())
        for d in value['devices'].values():
            assert [p['xy'] for p in d['pins']] == points(d)
        old = archived[1]['assess'](value['devices'], value['candidate'])
        actual = proof_module.assess(value['devices'], value['candidate'])
        assert old == value['local_gate'] and old['pass_local_gate']
        assert actual['pass_local_gate'] == (name == 'compress_rows')
        result[name] = dict(path=rel(path), sha256=sha(path), old_pass_local_gate=True,
                            current_pass_local_gate=actual['pass_local_gate'], directed_channel_roles=actual['directed_channel_roles'],
                            archived_gate_dependencies=provenance, valid_default_role_frames=True)
        if name == 'rotate_input_180':
            d = value['devices']['m1']
            assert d['pins'][0]['xy'][1] > d['pins'][2]['xy'][1]
            result[name]['source_role_direction_reversed'] = True
        else:
            a, b = value['devices']['m1'], value['devices']['m3']
            assert a['pos'] == [0, 1] and a['rot'] == 3 and not a['mirror']
            assert b['pos'] == [0, 0] and b['rot'] == 1 and not b['mirror']
            assert a['pins'][0]['net'] != b['pins'][2]['net']
            result[name]['overlapping_own_leads'] = dict(left='m1.D', right='m3.S', x=0, y_interval=[-19, -8],
                                                       nets=[a['pins'][0]['net'], b['pins'][2]['net']])
    return result


def alias_control(probe_module):
    parser = load('ninth-local-groups-census')
    values = parser.facts((EXAMPLES / 'ag-1028.cir').read_text())
    rename = {'net3': 'vin+', 'net1': 'vin-'}
    for row in values[0].values():
        row[1:5] = [rename.get(n, n) for n in row[1:5]]
    case = parser.decompose(*values)
    assert case['disposition'] == 'raw_multigroup_candidate'
    assert reference_candidates(case) == probe_module.collect(case) == []
    source = Path(__file__).read_text().split('def reference_candidates(row):', 1)[1].split('\ndef raw_and_source', 1)[0]
    guard = "        gate_formals = set(gates) | {tr[2], cards[loads[0]][2]}\n        if any(role != 1 for name, card in cards.items() for role, net in enumerate(card[1:5]) if net in gate_formals):\n            continue\n"
    assert source.count(guard) == 1
    namespace = dict(collections=collections)
    exec('def reference_candidates(row):' + source.replace(guard, ''), namespace)
    omitted = namespace['reference_candidates'](case)
    assert omitted == []  # The private-drain guard also rejects this exact alias.
    return dict(name='ag1028_input_output_alias', raw_disposition=case['disposition'],
                original_ordered_cards=case['ordered_cards'], expected_candidates=[],
                omitted_guard_control=dict(scope='Reconstructed function with only explicit formal-role guard removed; private-drain guard also rejects this literal, so it does not isolate the G-only guard.', candidates=omitted),
                reason='Formal input nets also occur at D; checking formal-name membership alone is insufficient.')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--check', type=Path)
    ap.add_argument('--output', type=Path, default=HERE / 'twelfth-review-organization.json')
    args = ap.parse_args()
    probe = json.loads((HERE / 'twelfth-organization-probe.json').read_text())
    proof = json.loads((HERE / 'twelfth-organization-proof.json').read_text())
    census = json.loads((HERE / 'ninth-local-groups-census.json').read_text())
    svg, frame, gate = [load(n) for n in ('eleventh-review-partitions', 'tenth-review-arrangement', 'twelfth-organization-proof')]
    for record, script in ((probe, 'twelfth-organization-probe.py'), (proof, 'twelfth-organization-proof.py')):
        assert record['script_sha256'] == sha(HERE / script)
        for p, h in record['dependencies'].items():
            assert sha(ROOT / p) == h
    symbol = BASE / 'resistor-output-integrated-common/tests/symbols.zon'
    for kind in ('nmos', 'pmos'):
        line = next(s for s in symbol.read_text().splitlines() if '.name = "' + kind + '"' in s)
        assert re.findall(r'\.name = "([dgs])", \.at = \.\{ \.x = (-?\d+), \.y = (-?\d+)', line.split('.draw')[0]) == [('d', '20', '0'), ('g', '0', '-20'), ('s', '-20', '0')]
        assert '.x = 20, .y = 0 }, .{ .x = 8, .y = 0' in line and '.x = -20, .y = 0 }, .{ .x = -8, .y = 0' in line
    paths = [Path(__file__), symbol] + [HERE / (name + ext) for name, ext in
            [('eleventh-review-partitions', '.py'), ('tenth-review-arrangement', '.py'), ('ninth-local-groups-census', '.json'),
             ('twelfth-organization-probe', '.py'), ('twelfth-organization-probe', '.json'),
             ('twelfth-organization-proof', '.py'), ('twelfth-organization-proof', '.json'),
             ('twelfth-organization-gate', '.md')]]
    views = [HERE / 'figures/groups/ninth' / (ident + '-pair.png') for ident in probe['raw_five_mos_names']]
    views += [ROOT / r['raster']['path'] for r in probe['records'] + proof['runs']]
    result = dict(raw_source=raw_and_source(probe, census, svg), native=native_records(probe, proof, frame.physical_pins, svg.parse),
                  partial_gate_controls=partial_gate_controls(gate, frame.physical_pins),
                  alias_control=alias_control(gate.p),
                  dependencies={rel(p): sha(p) for p in paths},
                  actual_views=[dict(path=rel(p), sha256=sha(p)) for p in views],
                  scope='Independent original-source/raw reference and saved-artifact binding checks; offline partial-gate controls, no new native or host execution, no full-page or N0 route acceptance.')
    result = json.loads(json.dumps(result))
    if args.check:
        assert result == json.loads(args.check.read_text())
    args.output.write_text(json.dumps(result, sort_keys=True, indent=2) + '\n')
    print(json.dumps(dict(parents=6, source_glyphs=86, saved_native_contracts=94, actual_views=len(views), partial_gate_controls=2)))


if __name__ == '__main__':
    main()
