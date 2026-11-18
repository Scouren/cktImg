#!/usr/bin/env python3
"""Raw reflected complementary-stack census and bounded actual-ink evidence."""
import argparse
import copy
import hashlib
import importlib.util
import itertools
import json
from pathlib import Path
import re
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
EXAMPLES = ROOT / 'external/examples/analoggenie'
BASE = ROOT / '.objective/human-schematic-equivalence/runs/iteration21-resume1'
NATIVE = BASE / 'image-rule-round-2/groups/ninth'
sys.path.insert(0, str(HERE))


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


raw = module('eleventh_raw', HERE / 'ninth-local-groups-census.py')
parts = module('eleventh_parts', HERE / 'eighth-partitions-proof.py')
ink = parts.ink


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rel(path):
    return str(path.relative_to(ROOT))


def candidates(row):
    """No coordinate, caller-eligibility, cycle or source-label selection."""
    groups = row.get('proposed_groups', [])
    if not groups or not row.get('enumeration_complete'):
        return []
    maps = [m for m in row['enumerated_involutions'] if any(a != b for a, b in m['nets'].items())]
    if len(maps) != 1:
        return []
    reflection = maps[0]
    cards = {r[0]: r for r in row['ordered_cards']}
    assert sorted(x for g in groups for x in g) == sorted(cards)
    owners = {d: k for k, group in enumerate(groups) for d in group}
    rails = row['admitted_rail_facts']
    incidences = {}
    for device, card in cards.items():
        for index, net in enumerate(card[1:5]):
            incidences.setdefault(net, []).append([device, index])
    interfaces = {r['device']: r for r in row['complete_gate_interfaces']}
    found = []
    for parent, group in enumerate(groups):
        if len(group) != 4 or {reflection['devices'][d] for d in group} != set(group):
            continue
        drains = {}
        for d in group:
            drains.setdefault(cards[d][1], []).append(d)
        if len(drains) != 2 or any(len(v) != 2 for v in drains.values()):
            continue
        stacks = []
        for net, members in sorted(drains.items()):
            if net in rails or net in row['formals']:
                break
            by_type = {row['model_definitions'][cards[d][5]][0]: d for d in members}
            if set(by_type) != {'nmos', 'pmos'}:
                break
            if any(cards[d][3] != cards[d][4] or cards[d][3] not in rails for d in members):
                break
            occur = sorted(incidences[net])
            outside = [d for d, k in occur if k == 1 and owners[d] != parent]
            if len(occur) != 3 or len(outside) != 1:
                break
            if sorted([d, k] for d, k in occur if k != 1) != sorted([d, 0] for d in members):
                break
            stacks.append(dict(net=net, p=by_type['pmos'], n=by_type['nmos'],
                               outside_gate=outside[0], outside_parent=groups[owners[outside[0]]],
                               complete_occurrences=occur, proposed_parts=[sorted([[d, 0] for d in members]), [[outside[0], 1]]]))
        if len(stacks) != 2:
            continue
        a, b = stacks
        if reflection['nets'][a['net']] != b['net']:
            continue
        if any(reflection['devices'][a[role]] != b[role] for role in ('p', 'n', 'outside_gate')):
            continue
        if a['outside_parent'] != b['outside_parent']:
            continue
        controls = {role: [cards[s[role]][2] for s in stacks] for role in ('p', 'n')}
        found.append(dict(parent_members=group, stacks=stacks,
                          shared_control_polarities=[role for role in ('p', 'n') if len(set(controls[role])) == 1],
                          control_nets=controls,
                          gate_interfaces=[interfaces[d] for d in sorted(set(group + [s['outside_gate'] for s in stacks]))],
                          parent_disposition=row['disposition'],
                          acyclic_parent_cohort=row['disposition'] == 'raw_multigroup_candidate',
                          automatic_partition_admission='unresolved'))
    return sorted(found, key=lambda r: r['parent_members'])


def identity(rows, devices=None, nets=None):
    devices, nets = devices or {}, nets or {}
    d = lambda s: devices.get(s, s)
    n = lambda s: nets.get(s, s)
    return sorted((tuple(sorted(d(x) for x in r['parent_members'])),
                   tuple(sorted((n(s['net']), d(s['p']), d(s['n']), d(s['outside_gate']),
                                 tuple(sorted(d(x) for x in s['outside_parent']))) for s in r['stacks']))) for r in rows)


def invariances(values, expected):
    cards, formals, models, rails, declarations = values
    reversed_row = raw.decompose(dict(reversed(list(cards.items()))), formals, models, rails, declarations)
    assert identity(candidates(reversed_row)) == identity(expected)
    dn = {d: 'm' + str(i + 200) for i, d in enumerate(reversed(sorted(cards)))}
    nn = {n: 'n' + str(i) for i, n in enumerate(reversed(sorted({v for c in cards.values() for v in c[1:5]})))}
    changed = {dn[d]: [dn[d]] + [nn[n] for n in c[1:5]] + c[5:] for d, c in cards.items()}
    renamed = raw.decompose(changed, [nn[n] for n in formals], models, {nn[n]: r for n, r in rails.items()})
    assert identity(candidates(renamed), {v: k for k, v in dn.items()}, {v: k for k, v in nn.items()}) == identity(expected)
    return ['card_reversal', 'bijective_rename_with_formal_and_admitted_rail_transport']


def near_misses():
    values = raw.facts((EXAMPLES / 'ag-1080.cir').read_text())
    target = ['m15', 'm16', 'm17', 'm18']
    result = []
    for name in ('extra_gate_consumers', 'extra_body_consumer', 'extra_passive', 'export_outputs',
                 'nonrail_source', 'wrong_model_identity', 'unknown_control'):
        changed = copy.deepcopy(values)
        cards, formals, models, rails, declarations = changed
        if name == 'extra_gate_consumers':
            cards['m1'][2], cards['m2'][2] = 'fn1', 'fp1'
        elif name == 'extra_body_consumer':
            cards['m1'][4] = 'fn1'
        elif name == 'extra_passive':
            cards['rx'] = ['rx', 'fn1', 'fp1', '1k']
        elif name == 'export_outputs':
            formals.extend(['fn1', 'fp1'])
        elif name == 'nonrail_source':
            cards['m15'][3] = cards['m16'][3] = 'net0'
        elif name == 'wrong_model_identity':
            cards['m16'][5] = 'different'
            models['different'] = ['pmos']
        else:
            cards['m16'][2] = 'new_private_control'
        outcome = raw.decompose(*changed)
        found = candidates(outcome)
        assert target not in [r['parent_members'] for r in found], name
        result.append(dict(name=name, changed_ordered_cards=[cards[d] for d in sorted(cards)],
                           changed_formals=formals, disposition=outcome['disposition'], reasons=outcome['reasons'],
                           remaining_parent_tuples=[r['parent_members'] for r in found], rejected_parent=target))
    base = raw.decompose(*values)
    with_intent = copy.deepcopy(base)
    with_intent['original_caller_requests'] = ['*@ wire FN1', '*@ at M29 -20 -20 r0']
    assert candidates(with_intent) == candidates(base)
    result.append(dict(name='caller_intent_does_not_erase_raw_candidates',
                       requests=with_intent['original_caller_requests'], raw_candidates_unchanged=True,
                       scope='literal collector input only; future arrangement/partition admission must honor requests'))
    return result


EXPECTED_SOURCE = {
    'ag-1053': {'net1': [['mn5.0', 'mp0.1', 'mp5.0']], 'net3': [['mn4.0', 'mp1.1', 'mp4.0']]},
    'ag-1079': {'rn': [['m11.1'], ['m7.0', 'm9.0']], 'rp': [['m12.1'], ['m6.0', 'm8.0']]},
    'ag-1080': {'fn1': [['m16.0', 'm18.0'], ['m29.1']], 'fp1': [['m15.0', 'm17.0'], ['m31.1']],
                'rn': [['m27.1'], ['m7.0', 'm9.0']], 'rp': [['m28.1'], ['m6.0', 'm8.0']]},
}

EXPECTED_NATIVE = {
    'ag-1053': {'net1': [['mn5.0', 'mp0.1', 'mp5.0']], 'net3': [['mn4.0', 'mp1.1', 'mp4.0']]},
    'ag-1079': {'rn': [['m11.1', 'm7.0', 'm9.0']], 'rp': [['m12.1', 'm6.0', 'm8.0']]},
    'ag-1080': {'fn1': [['m16.0'], ['m18.0'], ['m29.1']], 'fp1': [['m15.0'], ['m17.0'], ['m31.1']],
                'rn': [['m27.1', 'm7.0', 'm9.0']], 'rp': [['m28.1', 'm6.0', 'm8.0']]},
}


def native_inventory(drawing, cards, models):
    """Complete default-class fixture inventory, including generated terminals."""
    rows = drawing['devices']
    assert len({d['name'] for d in rows}) == len(rows)
    devices = {}
    for d in rows:
        name = d['name']
        if name not in cards:
            assert d['class'] in ('gnd', 'ipin', 'opin')
            assert re.fullmatch('_' + d['class'] + r'\d+', name)
            assert d['value'] == '' and 'bulk' not in d
            assert len(d['pins']) == 1 and d['pins'][0]['term'] == 'p'
            assert d['pins'][0]['net'] in drawing['nets'] and d['pins'][0]['xy'] == d['pos']
            continue
        card = cards[name]
        assert d['class'] == models[card[5]][0]
        assert [p['term'] for p in d['pins']] == ['d', 'g', 's']
        assert [p['net'] for p in d['pins']] + [d['bulk']] == card[1:5]
        assert d['value'].split() == card[5:]
        devices[name] = d
    assert set(devices) == set(cards)
    return devices


def native_inventory_controls():
    cards, _, models, _, _ = raw.facts((EXAMPLES / 'ag-1080.cir').read_text())
    drawing = json.loads((NATIVE / 'ag-1080.json').read_text())
    native_inventory(drawing, cards, models)
    result = []
    for name in ('extra_unrelated_mos', 'duplicate_raw_mos', 'wrong_selected_class', 'swapped_terminal_roles'):
        changed = copy.deepcopy(drawing)
        m = next(d for d in changed['devices'] if d['name'] == 'm1')
        if name == 'extra_unrelated_mos':
            extra = copy.deepcopy(m)
            extra['name'] = 'm_extra'
            changed['devices'].append(extra)
        elif name == 'duplicate_raw_mos':
            changed['devices'].append(copy.deepcopy(m))
        elif name == 'wrong_selected_class':
            m['class'] = 'pmos'
        else:
            m['pins'][0]['term'], m['pins'][1]['term'] = m['pins'][1]['term'], m['pins'][0]['term']
        try:
            native_inventory(changed, cards, models)
        except AssertionError:
            result.append(dict(name=name, rejected=True))
        else:
            raise AssertionError(name)
    return result


def physical(ident, row, found):
    path = NATIVE / (ident + '.json')
    provenance = json.loads((HERE / 'ninth-local-groups-native.json').read_text())
    previous = next(r for r in provenance['records'] if r['id'] == ident)
    assert sha(path) == previous['output_sha256'][rel(path)]
    assert sha(path.with_suffix('.svg')) == previous['output_sha256'][rel(path.with_suffix('.svg'))]
    drawing = json.loads(path.read_text())
    context = ink.load_source(EXAMPLES, ident)
    ps = ink.pins(drawing)
    cards = {r[0]: r for r in row['ordered_cards']}
    devices = native_inventory(drawing, cards, row['model_definitions'])
    assert set(devices) == set(cards) == {k[0] for k in ps}
    bindings, glyphs = [], {}
    for name, card in sorted(cards.items()):
        dev, source = devices[name], context['devices'][name]
        glyph = ink.actual_glyph(context['root'], source)
        glyphs[name] = glyph
        for i, term in enumerate(('D', 'G', 'S', 'B')):
            assert source['nets'][term].lower() == card[i + 1]
            bindings.append(dict(device=name, index=i, role=term, net=card[i + 1],
                                 source_actual_contact=glyph['terminals'].get(term),
                                 native_contact=dev['pins'][i]['xy'] if i < 3 else None))
    result = {}
    wanted = sorted(s['net'] for r in found for s in r['stacks'])
    assert wanted == sorted(EXPECTED_SOURCE[ident])
    for net in wanted:
        keys = sorted(k for k, v in ps.items() if v[0] == net)
        assert len(keys) == 3
        pairs = []
        for a, b in itertools.combinations(keys, 2):
            observed = ink.source(context, dict(net=net, pins=[a, b], terms=[ps[a][2], ps[b][2]]))
            assert observed['status'] != 'unsupported', (ident, net, a, b, observed.get('reason'))
            pairs.append(dict(pins=[a, b], source_connected=observed['status'] == 'source_connected', source=observed))
        source_parts = parts.partition(keys, pairs, 'source_connected')
        assert source_parts == parts.canonical(EXPECTED_SOURCE[ident][net])
        native = parts.native_contract(drawing, net, ps, EXPECTED_NATIVE[ident][net])
        for pair in pairs:
            names = {f'{d}.{i}' for d, i in pair['pins']}
            pair['native_connected'] = any(names <= set(block) for block in native['blocks'])
        result[net] = dict(pairs=pairs, source_parts=source_parts, native=native,
                           exact_partition_keep=source_parts == native['blocks'])
    png = HERE / 'figures/groups/ninth' / (ident + '-pair.png')
    return dict(source_hashes=context['source_sha256'], native_sha256=sha(path),
                native_svg_sha256=sha(path.with_suffix('.svg')), complete_bindings=bindings,
                actual_source_glyphs=glyphs, nets=result, viewed_png=rel(png), viewed_sha256=sha(png))


def caller_controls():
    fixture = json.loads((HERE / 'eighth-partitions-fixtures.json').read_text())
    result = []
    for name, expected in [('1080-wire-fn1', [['m16.0', 'm18.0', 'm29.1']]),
                           ('1080-label-fn1', [['m16.0'], ['m18.0'], ['m29.1']])]:
        record = next(r for r in fixture['runs'] if r['name'] == name)
        # Read the saved actual files, not a cached partition summary.
        path = BASE / 'image-rule-round-2/ports/eighth-partitions' / (name + '.json')
        assert sha(path) == record['outputs']['.json']['sha256']
        deck = ROOT / record['deck']
        assert sha(deck) == record['deck_sha256']
        text = '\n'.join(line for line in deck.read_text().splitlines() if not line.lstrip().startswith('*@')) + '\n'
        cards, _, models, _, _ = raw.facts(text)
        assert cards == raw.facts((EXAMPLES / 'ag-1080.cir').read_text())[0]
        drawing = json.loads(path.read_text())
        native_inventory(drawing, cards, models)
        actual = parts.native_contract(drawing, 'fn1', ink.pins(drawing), expected)
        result.append(dict(name=name, native_path=rel(path), native_sha256=sha(path),
                           source_manifest=record, actual_contract=actual,
                           scope='saved executed caller control; no new CLI execution in this round'))
    return result


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--output', type=Path, default=HERE / 'eleventh-partition-candidates.json')
    ap.add_argument('--check', type=Path)
    args = ap.parse_args()
    saved = json.loads((HERE / 'ninth-local-groups-census.json').read_text())
    names = sorted(r['id'] for r in json.loads((EXAMPLES / 'index.json').read_text()))
    assert names == saved['names'] == sorted(p.stem for p in EXAMPLES.glob('*.cir'))
    cases, found_rows, physical_rows = {}, {}, {}
    for ident in names:
        path = EXAMPLES / (ident + '.cir')
        values = raw.facts(path.read_text())
        row = raw.decompose(*values)
        expected = {k: v for k, v in saved['cases'][ident].items() if k not in ('deck_sha256', 'controls')}
        assert row == expected and sha(path) == saved['cases'][ident]['deck_sha256'], ident
        found = candidates(row)
        cases[ident] = dict(deck_sha256=sha(path), parent_disposition=row['disposition'],
                            parent_reasons=row['reasons'], candidate_parent_members=[r['parent_members'] for r in found])
        if found:
            found_rows[ident] = dict(complete_parent_context=row, candidates=found,
                                    invariances=invariances(values, found), original_caller_requests=[])
            physical_rows[ident] = physical(ident, row, found)
    assert sorted(found_rows) == ['ag-1053', 'ag-1079', 'ag-1080']
    assert sum(len(r['candidates']) for r in found_rows.values()) == 4
    controls = near_misses()
    changed_pairs = [dict(id=ident, net=net, pins=pair['pins'], source_connected=pair['source_connected'],
                          native_connected=pair['native_connected'])
                     for ident, r in physical_rows.items() for net, n in r['nets'].items() for pair in n['pairs']
                     if pair['source_connected'] != pair['native_connected']]
    assert sum(p['native_connected'] for p in changed_pairs) == 8
    assert sum(p['source_connected'] for p in changed_pairs) == 2
    result = dict(script_sha256=sha(Path(__file__)), exact_names=names,
                  exact_parent_dispositions=saved['disposition_names'], cases=cases, matching_cases=found_rows,
                  physical_evidence=physical_rows, exact_physical_pair_mismatches=changed_pairs,
                  near_misses=controls, caller_controls=caller_controls(), native_inventory_controls=native_inventory_controls(),
                  named_sets=dict(raw_cases=sorted(found_rows), acyclic_cases=['ag-1079', 'ag-1080'], cyclic_contrary=['ag-1053'],
                                  source_three_single_cases=[], automatic_partition_admitted=[]),
                  summary=dict(raw_parent_tuples=4, acyclic_tuples=3, cyclic_tuples=1, affected_nets=8,
                               source_pair_relations=24, source_two_plus_one_nets=6, source_continuous_three_nets=2,
                               native_extra_physical_joins=8, native_missing_physical_joins=2,
                               complete_raw_terminal_occurrences=sum(len(r['complete_bindings']) for r in physical_rows.values())),
                  dependencies={rel(p): sha(p) for p in [HERE / 'ninth-local-groups-census.py', HERE / 'ninth-local-groups-census.json',
                                HERE / 'ninth-local-groups-native.json',
                                HERE / 'eighth-partitions-proof.py', HERE / 'eighth-partitions-fixtures.json',
                                HERE / 'groups_candidates.py', EXAMPLES / 'index.json']},
                  ink_dependencies=parts.previous.dependencies(),
                  scope='Raw candidate census and actual bounded source/native ink; cycle eligibility does not erase raw tuples. No generic 2+1 selector, engine change, build, new CLI or target run.')
    result['views'] = [dict(id=n, path=r['viewed_png'], sha256=r['viewed_sha256'],
                           observation={'ag-1053':'Both feedback-side complementary stacks are continuously wired to the outer PMOS gates in source and native; keep despite raw cycle admission decline.',
                                        'ag-1079':'Source isolates the upper-right complementary stage with RN/RP names and lower gate names; native continuously wires all three endpoints on each net.',
                                        'ag-1080':'Source FN1/FP1 and RN/RP each retain a local drain tree with remote named gate. Native splits the first pair into singles and joins the latter pair to their remote gates.'}[n])
                       for n, r in physical_rows.items()]
    encoded = json.loads(json.dumps(result))
    if args.check:
        assert encoded == json.loads(args.check.read_text())
    args.output.write_text(json.dumps(encoded, indent=2, sort_keys=True) + '\n')
    print(json.dumps(result['summary']))


if __name__ == '__main__':
    main()
