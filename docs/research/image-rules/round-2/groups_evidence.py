#!/usr/bin/env python3
"""Replay ten source-region counterexamples, including exact source ink.

Usage: groups_evidence.py EXAMPLES NATIVE OUTPUT [--check JSON]
Literal fixture ownership is a manual oracle, not inferred from native layout.
"""
import argparse
import ast
import collections
import copy
import itertools
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
FIGURES = HERE.parent.parent / 'figures'
sys.path.insert(0, str(FIGURES))
import thin_connectivity as ink
from groups_candidates import census, digest, terminals, invariants, rail


def dependencies():
    result, pending = {}, [Path(__file__), HERE / 'groups_candidates.py', FIGURES / 'thin_connectivity.py']
    while pending:
        path = pending.pop()
        key = str(path.relative_to(HERE.parent.parent))
        if key in result:
            continue
        result[key] = digest(path)
        for node in ast.walk(ast.parse(path.read_text())):
            names = [x.name for x in node.names] if isinstance(node, ast.Import) else [node.module] if isinstance(node, ast.ImportFrom) else []
            for name in names:
                for base in (HERE, FIGURES):
                    other = base / ((name or '').split('.')[0] + '.py')
                    if other.is_file():
                        pending.append(other)
    result['image-rules/round-2/groups_expected.json'] = digest(HERE / 'groups_expected.json')
    return dict(sorted(result.items()))


def bindings(context, drawing):
    cards = context['cards']
    ps = ink.pins(drawing)
    native = {d['name']: d for d in drawing['devices'] if not d['name'].startswith('_')}
    assert cards.keys() == context['devices'].keys() == native.keys()
    rows, leads, nets = [], {}, collections.defaultdict(list)
    for name, card in sorted(cards.items()):
        source = context['devices'][name]
        assert terminals(card) is not None
        reader = {'r': ink.actual_resistor, 'l': ink.actual_inductor}.get(name[0], ink.actual_glyph)
        leads[name] = reader(context['root'], source)
        count = len(terminals(card))
        if name[0] == 'm':
            assert native[name]['value'].lower().split() == card[5:]
        else:
            assert native[name]['value'].lower().split() == card[3:]
        for i, net in enumerate(terminals(card)):
            hidden = name[0] == 'm' and i == 3
            term = 'B' if hidden else ink.terminal(source, i, ps[name, i][2])
            assert source['nets'][term].lower() == net, (name, i)
            if hidden:
                assert native[name]['bulk'] == net
            else:
                assert ps[name, i][0] == net
                assert term in leads[name]['terminals']
                nets[net].append((name, i))
            rows.append(dict(card=name, index=i, role=term, net=net, hidden_bulk=hidden,
                             source_xy=None if hidden else leads[name]['terminals'][term],
                             native_xy=None if hidden else ps[name, i][1]))
    return rows, leads, nets, ps


def bounds(points):
    return [[min(p[i] for p in points) for i in range(2)],
            [max(p[i] for p in points) for i in range(2)]]


def ownership(topology, cards, expected):
    """Check each literal owner against complete ordered region incidences."""
    assert len(expected['cores']) == len(expected['owned'])
    owners = [n for group in expected['owned'] for n in group] + expected['boundary']
    assert len(owners) == len(set(owners))
    assert set(owners) == set(cards)
    all_cores = {n for core in expected['cores'] for n in core}
    rows = []
    for core, owned in zip(expected['cores'], expected['owned']):
        candidates = [r for r in topology['raw_source_regions'] if r['members'] == sorted(core)]
        assert len(candidates) == 1
        region = candidates[0]
        assert set(core) <= set(owned)
        currents = {r['card'] for r in region['current_source_interfaces'] if r['far_is_rail']}
        tails = set(region['drain_anchors']) - all_cores
        required = set(core) | set(region['resistors']) | currents | tails
        assert set(owned) == required, (core, owned, required)
        rows.append(dict(core=core, resistor_attachments=region['resistors'],
                         rail_current_attachments=sorted(currents), tail_attachments=sorted(tails),
                         other_core_drain_interfaces=sorted(set(region['drain_anchors']) & all_cores),
                         ordered_incidence=region['incidence']))
    return rows


def certify(ident, example, native_path, expected):
    context = ink.load_source(example, ident)
    drawing_path = native_path / (ident + '.json')
    drawing = json.loads(drawing_path.read_text())
    cards = context['cards']
    rails = {n for c in cards.values() for n in terminals(c) if rail(n)}
    topology = census(cards, rails)
    assert topology['ds_components'] == expected['ds']
    assert topology['resistor_extended_ds_components'] == expected['broad']
    assert sorted(g['members'] for g in topology['raw_source_regions']) == sorted(expected['cores'])
    owner_proof = ownership(topology, cards, expected)
    rows, leads, nets, ps = bindings(context, drawing)
    regions = []
    for core, owned in zip(expected['cores'], expected['owned']):
        src_points = [p for n in core for p in leads[n]['terminals'].values()]
        native_points = [ps[n, i][1] for n in core for i in range(3)]
        src_order = sorted(core, key=lambda n: leads[n]['terminals']['D'][0])
        dst_order = sorted(core, key=lambda n: ps[n, 0][1][0])
        regions.append(dict(core=core, owned_cards=owned, source_lead_bounds=bounds(src_points),
                            native_lead_bounds=bounds(native_points), source_order=src_order,
                            native_order=dst_order,
                            source_gate_sign={n: (leads[n]['terminals']['G'][0] > leads[n]['terminals']['D'][0]) for n in core},
                            native_gate_sign={n: (ps[n, 1][1][0] > ps[n, 0][1][0]) for n in core}))
    def relation(a, b):
        if a[1][0] < b[0][0]:
            return 'left'
        if b[1][0] < a[0][0]:
            return 'right'
        return 'overlap'
    relations = []
    for ai, bi in itertools.combinations(range(len(regions)), 2):
        a, b = regions[ai], regions[bi]
        relations.append(dict(regions=[ai, bi],
                              source=relation(a['source_lead_bounds'], b['source_lead_bounds']),
                              native=relation(a['native_lead_bounds'], b['native_lead_bounds'])))
    expected_relations = expected.get('relations', [dict(regions=[a, b], source='left', native='left')
                                      for a, b in itertools.combinations(range(len(regions)), 2)])
    assert relations == expected_relations, (ident, relations)
    physical = []
    for net, keys in sorted(nets.items()):
        cmp = ink.components(drawing, net, keys, ps)
        for a, b in itertools.combinations(keys, 2):
            request = dict(id=ident, net=net, pins=[a, b], terms=[ps[a][2], ps[b][2]])
            result = ink.source(context, request)
            assert result['status'] != 'unsupported', (ident, request, result.get('reason'))
            physical.append(dict(net=net, pins=[a, b], source_connected=result['status'] == 'source_connected',
                                 native_connected=cmp[a] == cmp[b], source=result))
    mutations = []
    if ident == 'ag-459':
        for label in ('owners_reversed', 'current_sources_swapped'):
            wrong = copy.deepcopy(expected)
            if label == 'owners_reversed':
                wrong['owned'].reverse()
            else:
                wrong['owned'][0][wrong['owned'][0].index('i1')] = 'i3'
                wrong['owned'][1][wrong['owned'][1].index('i3')] = 'i1'
            try:
                ownership(topology, cards, wrong)
            except AssertionError:
                mutations.append(label + '_rejected')
            else:
                raise AssertionError(label + ' accepted')
    # The source/card/native seam must fail when only one side is corrupted.
    for label, changed_context, changed_drawing in [
        ('wrong_ordered_gate', copy.deepcopy(context), copy.deepcopy(drawing)),
        ('detached_actual_source_lead', copy.deepcopy(context), copy.deepcopy(drawing)),
        ('wrong_hidden_bulk', copy.deepcopy(context), copy.deepcopy(drawing)),
        ('wrong_native_model_parameters', copy.deepcopy(context), copy.deepcopy(drawing))]:
        if label == 'wrong_ordered_gate':
            changed_context['cards']['m1'][2] = changed_context['cards']['m1'][3]
        elif label == 'detached_actual_source_lead':
            changed_context['devices']['m1']['terminals']['S'][0] += 1
        elif label == 'wrong_hidden_bulk':
            next(d for d in changed_drawing['devices'] if d['name'] == 'm1')['bulk'] = 'wrong'
        else:
            next(d for d in changed_drawing['devices'] if d['name'] == 'm1')['value'] += ' w=999'
        try:
            bindings(changed_context, changed_drawing)
        except (AssertionError, ValueError):
            mutations.append(label + '_rejected')
        else:
            raise AssertionError(label + ' accepted')
    return dict(source_sha256=context['source_sha256'],
                native_sha256={ext: digest(native_path / (ident + ext)) for ext in ('.json', '.report.json', '.svg')},
                models=[line.strip() for line in (example / (ident + '.cir')).read_text().splitlines() if line.lower().startswith('.model')],
                ordered_raw_cards=[cards[n] for n in sorted(cards)], ordered_bindings=rows,
                native_synthetic_devices=[d for d in drawing['devices'] if d['name'].startswith('_')],
                actual_source_leads=leads, topology=topology, literal_ownership=expected, ownership_incidence=owner_proof,
                regions=regions, region_relations=relations, physical_pairs=physical,
                controls=mutations + invariants(cards, rails, topology))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('examples', type=Path)
    ap.add_argument('native', type=Path)
    ap.add_argument('output', type=Path)
    ap.add_argument('--check', type=Path)
    args = ap.parse_args()
    expected = json.loads((HERE / 'groups_expected.json').read_text())
    result = dict(scope='Ten literal source-region ownership controls. All cards and ordered terminals bound. Visible leads require actual SVG primitives. Full same-net visible pin pairs checked, but no general placement selector is certified.',
                  dependencies=dependencies(), source_ink_controls=ink.checks(),
                  cases={n: certify(n, args.examples, args.native, e) for n, e in expected.items()})
    result = json.loads(json.dumps(result))
    args.output.write_text(json.dumps(result, sort_keys=True, indent=2) + '\n')
    if args.check:
        assert result == json.loads(args.check.read_text())
    print(json.dumps({n: dict(bindings=len(c['ordered_bindings']), physical_pairs=len(c['physical_pairs']),
                             source_regions=len(c['regions'])) for n, c in result['cases'].items()}))


if __name__ == '__main__':
    main()
