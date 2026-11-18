#!/usr/bin/env python3
"""Research-only source-region census; never selects production placement.

Usage: groups_candidates.py EXAMPLES OUTPUT [--check JSON]
Only MOS sources and off-rail resistors generate raw regions. D/S components
are a competing hypothesis, not an input to source-region ownership.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import re
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent.parent / 'figures'))
from channel_bridges import read_cards, rail


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def components(nodes, edges):
    neighbours = {n: set() for n in nodes}
    for a, b in edges:
        neighbours[a].add(b)
        neighbours[b].add(a)
    todo = set(nodes)
    result = []
    while todo:
        pending, found = [min(todo)], set()
        while pending:
            at = pending.pop()
            if at in found:
                continue
            found.add(at)
            pending.extend(neighbours[at] - found)
        todo -= found
        result.append(sorted(found))
    return sorted(result)


def terminals(card):
    kind = card[0][0]
    if kind == 'q':
        # This corpus uses C/B/E[/substrate], model, then key=value options.
        # Optional bare area/OFF syntax is outside this research parser.
        end = next((i for i, token in enumerate(card) if '=' in token), len(card))
        if end not in (5, 6) or any('=' not in token for token in card[end:]):
            return None
        if card[end - 1].lower() in ('off', 'on', 'params:'):
            return None
        if re.fullmatch(r'[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?[a-zA-Z]*', card[end - 1]):
            return None
        return card[1:end - 1]
    count = 4 if kind == 'm' else 2 if kind in 'rcldiv' else None
    return card[1:1 + count] if count is not None else None


def census(cards, rails):
    mos = {n: c for n, c in cards.items() if n[0] == 'm'}
    resistors = {n: c for n, c in cards.items() if n[0] == 'r'}
    source_nets = {c[3] for c in mos.values()} - rails
    redges = [c[1:3] for c in resistors.values() if not set(c[1:3]) & rails]
    rnodes = source_nets | {n for e in redges for n in e}
    raw = []
    for nets in components(rnodes, redges):
        members = sorted(n for n, c in mos.items() if c[3] in nets)
        if len(members) < 2:
            continue
        rs = sorted(n for n, c in resistors.items() if set(c[1:3]) <= set(nets))
        incidence = []
        unknown = []
        for n, c in sorted(cards.items()):
            terms = terminals(c)
            if terms is None:
                unknown.append(n)
                continue
            for i, net in enumerate(terms):
                if net in nets:
                    incidence.append([n, i, net])
        tails = sorted({n for n, i, _ in incidence if n[0] == 'm' and i == 0 and n not in members})
        sources = []
        reasons = []
        if len(members) != 2:
            reasons.append('not_exactly_two_sources')
        if len({tuple(mos[n][5:]) for n in members}) != 1:
            reasons.append('unequal_model_or_parameters')
        if len({mos[n][2] for n in members}) != len(members):
            reasons.append('shared_gate')
        if len({mos[n][1] for n in members}) != len(members):
            reasons.append('shared_drain')
        if unknown:
            reasons.append('unsupported_card_incidence')
        if len(rs) > 2:
            reasons.append('resistor_network_larger_than_two')
        if len(rs) == 1 and (len(nets) != 2 or len({mos[n][3] for n in members}) != 2):
            reasons.append('not_single_resistor_between_two_source_nets')
        if len(rs) == 2:
            counts = {net: sum(net in resistors[n][1:3] for n in rs) for net in nets}
            centers = [net for net, count in counts.items() if count == 2]
            if len(nets) != 3 or len(centers) != 1 or centers[0] in source_nets:
                reasons.append('not_private_two_arm_resistor_path')
            if len({tuple(resistors[n][3:]) for n in rs}) != 1:
                reasons.append('unequal_resistor_values')
        if len(tails) > 1:
            reasons.append('multiple_drain_anchors')
        if tails and len(rs) == 1:
            reasons.append('tail_at_asymmetric_resistor_endpoint')
        if any(mos[n][5] != mos[m][5] for n in tails for m in members):
            reasons.append('different_tail_model')
        for n, i, _ in incidence:
            if n[0] == 'i':
                other = cards[n][2 - i]
                sources.append(dict(card=n, terminal=i, far_net=other, far_is_rail=other in rails))
                if other not in rails:
                    reasons.append('current_source_not_private_rail_attachment')
                continue
            if n in members and i == 2 or n in rs:
                continue
            if n in tails and i == 0 and mos[n][3] in rails:
                continue
            reasons.append('nonprivate_incidence')
        raw.append(dict(members=members, resistors=rs, nets=nets, incidence=incidence,
                        drain_anchors=tails, unsupported_cards=unknown,
                        current_source_interfaces=sources,
                        disposition='decline' if reasons else 'shape_candidate_pending_ownership',
                        reasons=sorted(set(reasons))))
    ds = {}
    for n, c in mos.items():
        for net in (c[1], c[3]):
            if net not in rails:
                ds.setdefault(net, []).append(n)
    edges = [(ms[0], n) for ms in ds.values() for n in ms[1:]]
    plain = components(mos, edges)
    # Competing broad hypothesis: connect every off-rail resistor into D/S.
    graph_nodes = set(mos) | {'net:' + n for n in rnodes | set(ds)}
    broad_edges = [(m, 'net:' + net) for net, ms in ds.items() for m in ms]
    broad_edges += [('net:' + a, 'net:' + b) for a, b in redges]
    broad = [sorted(n for n in g if n in mos) for g in components(graph_nodes, broad_edges)]
    broad = sorted(g for g in broad if g)
    cross_drains = []
    for a, left in enumerate(raw):
        for b, right in enumerate(raw[a + 1:], a + 1):
            common = sorted({mos[n][1] for n in left['members']} &
                            {mos[n][1] for n in right['members']} - rails)
            if common:
                cross_drains.append(dict(regions=[a, b], nets=common))
    return dict(raw_source_regions=raw, ds_components=plain,
                resistor_extended_ds_components=broad, shared_drains_between_regions=cross_drains)


def invariants(cards, rails, expected):
    assert census(dict(reversed(list(cards.items()))), rails) == expected
    names = sorted(cards)
    rename = {n: n[0] + str(10000 + i) for i, n in enumerate(reversed(names))}
    nets = sorted({n for c in cards.values() for n in (terminals(c) or [])} | rails)
    nm = {n: 'opaque_' + str(i) for i, n in enumerate(reversed(nets))}
    # Restrict transformation control to the supported grammar; census still
    # reports unsupported cards explicitly in other circuits.
    if any(terminals(c) is None for c in cards.values()):
        return ['card_order']
    changed = {}
    for n, c in cards.items():
        count = len(terminals(c))
        changed[rename[n]] = [rename[n]] + [nm[x] for x in c[1:1 + count]] + c[1 + count:]
    actual = census(changed, {nm[n] for n in rails})
    invn = {v: k for k, v in rename.items()}
    invnet = {v: k for k, v in nm.items()}
    def normalize(record, ren, netren):
        dev = lambda n: ren.get(n, n)
        net = lambda n: netren.get(n, n)
        regions = []
        for row in record['raw_source_regions']:
            regions.append((tuple(sorted(map(dev, row['members']))),
                            tuple(sorted(map(dev, row['resistors']))),
                            tuple(sorted(map(net, row['nets']))),
                            tuple(sorted((dev(n), i, net(v)) for n, i, v in row['incidence'])),
                            tuple(sorted(map(dev, row['drain_anchors']))),
                            tuple(sorted(map(dev, row['unsupported_cards']))),
                            tuple(sorted((dev(x['card']), x['terminal'], net(x['far_net']), x['far_is_rail']) for x in row['current_source_interfaces'])),
                            row['disposition'], tuple(row['reasons'])))
        cross = sorted((tuple(sorted(tuple(sorted(map(dev, record['raw_source_regions'][i]['members']))) for i in row['regions'])),
                        tuple(sorted(map(net, row['nets'])))) for row in record['shared_drains_between_regions'])
        return sorted(regions), sorted(sorted(map(dev, g)) for g in record['ds_components']), sorted(sorted(map(dev, g)) for g in record['resistor_extended_ds_components']), cross
    assert normalize(actual, invn, invnet) == normalize(expected, {}, {})
    return ['card_order', 'bijective_device_and_net_rename_with_explicit_rail_transport']


def controls():
    cards = read_cards('''.subckt literal vdd vss a b bias o1 o2
M1 o1 a s1 vss n w=1
M2 o2 b s2 vss n w=1
M3 tail bias vss vss n w=1
R1 s1 tail 1k
R2 tail s2 1k
.ends''')
    rails = {'vdd', 'vss'}
    r = census(cards, rails)
    assert r['ds_components'] == [['m1'], ['m2'], ['m3']]
    assert r['resistor_extended_ds_components'] == [['m1', 'm2', 'm3']]
    assert r['raw_source_regions'][0]['members'] == ['m1', 'm2']
    assert r['raw_source_regions'][0]['drain_anchors'] == ['m3']
    assert r['raw_source_regions'][0]['disposition'] == 'shape_candidate_pending_ownership'
    checks = invariants(cards, rails, r)
    for label, name, index, value, reason in [
        ('one_gate_to_source', 'm1', 2, 's1', 'nonprivate_incidence'),
        ('one_model_changed', 'm1', 5, 'other', 'unequal_model_or_parameters'),
        ('unequal_resistor', 'r1', 3, '2k', 'unequal_resistor_values')]:
        changed = copy.deepcopy(cards)
        changed[name][index] = value
        assert reason in census(changed, rails)['raw_source_regions'][0]['reasons'], label
        checks.append(label + '_declined')
    changed = copy.deepcopy(cards)
    changed['r2'][2] = 'cut'
    assert census(changed, rails)['raw_source_regions'] == []
    checks.append('broken_arm_not_enumerated')
    changed = copy.deepcopy(cards)
    changed['r3'] = ['r3', 's1', 's2', '1k']
    assert 'resistor_network_larger_than_two' in census(changed, rails)['raw_source_regions'][0]['reasons']
    checks.append('parallel_extra_path_declined')
    for label, extra, reason in [
        ('current_to_signal', ['ix', 's1', 'unrelated', '1m'], 'current_source_not_private_rail_attachment'),
        ('current_inside_region', ['ix', 's1', 's2', '1m'], 'current_source_not_private_rail_attachment')]:
        changed = copy.deepcopy(cards)
        changed['ix'] = extra
        assert reason in census(changed, rails)['raw_source_regions'][0]['reasons']
        checks.append(label + '_declined')
    changed = copy.deepcopy(cards)
    changed['m4'] = ['m4', 'o3', 'c', 's3', 'vss', 'n', 'w=1']
    changed['m5'] = ['m5', 'o4', 'd', 's3', 'vss', 'n', 'w=1']
    changed['ix'] = ['ix', 's1', 's3', '1m']
    assert len(census(changed, rails)['raw_source_regions']) == 2
    assert all('current_source_not_private_rail_attachment' in row['reasons'] for row in census(changed, rails)['raw_source_regions'])
    checks.append('current_bridge_keeps_two_raw_regions_declines_both')
    changed = copy.deepcopy(cards)
    changed['m1'][4] = 's1'
    assert 'nonprivate_incidence' in census(changed, rails)['raw_source_regions'][0]['reasons']
    checks.append('body_source_tie_declined')
    changed = copy.deepcopy(cards)
    changed['m3'][5] = 'pmos_model'
    assert 'different_tail_model' in census(changed, rails)['raw_source_regions'][0]['reasons']
    checks.append('different_tail_model_declined')
    changed = copy.deepcopy(cards)
    del changed['r2']
    changed['r1'][2] = 's2'
    assert census(changed, rails)['raw_source_regions'][0]['disposition'] == 'shape_candidate_pending_ownership'
    checks.append('literal_single_resistor_source_bridge_collected')
    changed['r2'] = ['r2', 's1', 's2', '1k']
    assert 'not_private_two_arm_resistor_path' in census(changed, rails)['raw_source_regions'][0]['reasons']
    checks.append('two_competing_resistor_paths_declined')
    assert terminals(['qx', 'c', 'base', 'e', 'npnmod', 'm=1']) == ['c', 'base', 'e']
    assert terminals(['qx', 'c', 'base', 'e', 's1', 'npnmod', 'm=1']) == ['c', 'base', 'e', 's1']
    assert terminals(['qx', 'c', 'base', 'e', 'npnmod', '2']) is None
    assert terminals(['qx', 'c', 'base', 'e', 'npnmod', 'off']) is None
    changed = copy.deepcopy(cards)
    changed['qx'] = ['qx', 'c', 'base', 'e', 's1', 'npnmod']
    region = census(changed, rails)['raw_source_regions'][0]
    assert ['qx', 3, 's1'] in region['incidence']
    assert 'nonprivate_incidence' in region['reasons']
    checks.extend(['q_three_terminal_literal', 'q_four_terminal_substrate_incidence_declined',
                   'q_ambiguous_bare_area_explicitly_unsupported', 'q_bare_off_explicitly_unsupported'])
    return checks


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('examples', type=Path)
    ap.add_argument('output', type=Path)
    ap.add_argument('--check', type=Path)
    args = ap.parse_args()
    names = sorted(x['id'] for x in json.loads((args.examples / 'index.json').read_text()))
    assert names == sorted(p.stem for p in args.examples.glob('*.cir'))
    records = {}
    for ident in names:
        path = args.examples / (ident + '.cir')
        cards = read_cards(path.read_text())
        nets = {n for c in cards.values() for n in (terminals(c) or [])}
        rails = {n for n in nets if rail(n)}
        result = census(cards, rails)
        records[ident] = dict(deck_sha256=digest(path), rails=sorted(rails),
                              ordered_raw_cards=[cards[n] for n in sorted(cards)],
                              controls=invariants(cards, rails, result), **result)
    result = dict(scope='All named AnalogGenie final subcircuits; raw MOS source/resistor census only, not visual admission or production grouping.',
                  index_sha256=digest(args.examples / 'index.json'),
                  dependencies={p.name: digest(p) for p in (Path(__file__), HERE.parent.parent / 'figures/channel_bridges.py')},
                  names=names, controls=controls(), cases=records)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    if args.check:
        assert result == json.loads(args.check.read_text())
    print(json.dumps(dict(decks=len(names), candidate_cases=sum(bool(r['raw_source_regions']) for r in records.values()),
                          raw_regions=sum(len(r['raw_source_regions']) for r in records.values()),
                          shape_candidates=sum(x['disposition'] == 'shape_candidate_pending_ownership' for r in records.values() for x in r['raw_source_regions']),
                          cross_drain_cases=sum(bool(r['shared_drains_between_regions']) for r in records.values()))))


if __name__ == '__main__':
    main()
