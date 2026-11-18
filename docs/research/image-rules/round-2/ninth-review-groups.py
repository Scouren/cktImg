#!/usr/bin/env python3
"""Independent raw-interface and small exhaustive-involution review; no engine run."""
import argparse
import copy
import importlib.util
import itertools
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from bodies_census import ROOT, BASE, parse, sha

RUN = BASE / 'image-rule-round-2/bodies/ninth-review-groups'
SOURCE = ROOT / 'external/examples/analoggenie'
PEER = HERE / 'ninth-local-groups-census.py'
OLD = BASE / 'image-rule-round-2/groups/ninth/ninth-local-groups-before-parser.py'


def module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def map_key(row):
    return (tuple(sorted(row['devices'].items())), tuple(sorted(row['nets'].items())))


def brute_maps(cards, formals, rails):
    """All device permutations, then literal role equations; no color/search reuse."""
    names = sorted(cards)
    result = []
    for perm in itertools.permutations(names):
        dm = dict(zip(names, perm))
        if any(dm[dm[n]] != n or cards[n][5:] != cards[dm[n]][5:] for n in names):
            continue
        nm = {}
        conflict = False
        for d, e in dm.items():
            for a, b in zip(cards[d][1:5], cards[e][1:5]):
                if a in nm and nm[a] != b:
                    conflict = True
                nm[a] = b
        if conflict or set(nm) != set(nm.values()):
            continue
        if any(nm[nm[a]] != a or (a in formals) != (b in formals)
               or (a in rails and a != b) for a, b in nm.items()):
            continue
        result.append(dict(devices=dm, nets=nm))
    return sorted(map_key(row) for row in result)


def partition(names, links):
    """Independent equivalence closure by disjoint-set roots."""
    parent = {n: n for n in names}
    def root(n):
        while parent[n] != n:
            n = parent[n]
        return n
    for a, b in links:
        parent[root(a)] = root(b)
    groups = {}
    for n in names:
        groups.setdefault(root(n), []).append(n)
    return sorted(sorted(g) for g in groups.values())


def verify_case(name, row, exhaustive=False):
    formals, original = parse((SOURCE / (name + '.cir')).read_text())
    ordered = sorted(c['raw'].lower().split() for c in original)
    assert row['formals'] == formals, (name, 'complete formal contract')
    assert row['ordered_cards'] == ordered, (name, 'complete raw ordered cards')
    cards = {c[0]: c for c in ordered}
    if 'channel_components' not in row:
        return 0
    rails = row['admitted_rail_facts']
    channel_owners = {}
    for d, c in cards.items():
        for net in (c[1], c[3]):
            if net not in rails:
                channel_owners.setdefault(net, []).append(d)
    links = [(ds[0], d) for ds in channel_owners.values() for d in ds[1:]]
    groups = partition(cards, links)
    assert groups == row['channel_components'], (name, 'channel partition')
    owner = {d: k for k, group in enumerate(groups) for d in group}
    interfaces = []
    for d, c in sorted(cards.items()):
        g = c[2]
        p = owner[channel_owners[g][0]] if g in channel_owners else None
        kind = ('admitted_rail_control' if g in rails else 'channel_to_gate' if p is not None
                else 'formal_gate_input' if g in formals else 'unsupported_floating_internal_gate')
        interfaces.append(dict(device=d, gate=g, kind=kind, consumer=owner[d], producer=p))
    assert row['complete_gate_interfaces'] == interfaces, (name, 'all raw gate incidences')
    all_nets = {n for c in cards.values() for n in c[1:5]}
    maps = row.get('enumerated_involutions', [])
    assert len({map_key(m) for m in maps}) == len(maps), (name, 'duplicate maps')
    for m in maps:
        dm, nm = m['devices'], m['nets']
        assert set(dm) == set(dm.values()) == set(cards)
        assert set(nm) == set(nm.values()) == all_nets
        for d, e in dm.items():
            assert dm[e] == d and cards[d][5:] == cards[e][5:]
            assert [nm[n] for n in cards[d][1:5]] == cards[e][1:5]
        for a, b in nm.items():
            assert nm[b] == a and (a in formals) == (b in formals)
            assert a not in rails or a == b
    if exhaustive:
        assert row['enumeration_complete']
        assert sorted(map_key(m) for m in maps) == brute_maps(cards, formals, rails), (name, 'exhaustive permutation oracle')
    if 'proposed_groups' in row:
        real = [m for m in maps if any(a != b for a, b in m['nets'].items())]
        merged = links if len(groups) == 1 else links + list(real[0]['devices'].items())
        proposed = partition(cards, merged)
        assert row['proposed_groups'] == proposed
        if 'group_dependencies' in row:
            final_owner = {d: k for k, group in enumerate(proposed) for d in group}
            deps = {str(k): set() for k in range(len(proposed))}
            for d, c in cards.items():
                if c[2] in channel_owners:
                    p, q = final_owner[channel_owners[c[2]][0]], final_owner[d]
                    if p != q:
                        deps[str(p)].add(q)
            assert row['group_dependencies'] == {k: sorted(v) for k, v in deps.items()}
            if 'dependency_order' in row:
                order = row['dependency_order']
                assert sorted(order) == list(range(len(proposed)))
                assert all(order.index(int(a)) < order.index(b) for a, bs in deps.items() for b in bs)
    return len(maps)


def parser_attacks():
    old, current = module(OLD, 'old_ninth'), module(PEER, 'current_ninth')
    source = (SOURCE / 'ag-1080.cir').read_text()
    inputs = {
        'unused_continued_formal': source.replace('OUTP OUTN\n', 'OUTP OUTN\n+ unused_formal\n'),
        'continued_original_formals': source.replace('CLKB OUTP OUTN\n', 'CLKB\n+ OUTP OUTN\n'),
        'duplicate_conflicting_model': source.replace('.model nch nmos', '.model nch pmos\n.model nch nmos'),
        'unowned_conventional_rails': source.replace('.subckt dut VDD VSS ', '.subckt dut '),
    }
    out = {}
    for name, text in inputs.items():
        path = RUN / (name + '.cir')
        path.write_text(text)
        before, after = (m.decompose(*m.facts(text)) for m in (old, current))
        assert before['disposition'] == 'raw_multigroup_candidate'
        if name == 'continued_original_formals':
            assert before['formals'] == ['vdd', 'vss', 'clk', 'vip', 'vin', 'clkb']
            assert after['formals'] == ['vdd', 'vss', 'clk', 'vip', 'vin', 'clkb', 'outp', 'outn']
            assert after['disposition'] == 'raw_multigroup_candidate'
        else:
            expected = {'unused_continued_formal': 'unused_formal_ownership_unresolved',
                        'duplicate_conflicting_model': 'duplicate_model_definition',
                        'unowned_conventional_rails': 'unowned_conventional_rail'}[name]
            assert expected in after['reasons'] and after['disposition'] == 'decline_input_boundary'
        out[name] = dict(path=str(path.relative_to(ROOT)), sha256=sha(path),
                         before=dict(disposition=before['disposition'], formals=before['formals'], reasons=before['reasons']),
                         after=dict(disposition=after['disposition'], formals=after['formals'], reasons=after['reasons']))
    return out


def output_mutations(cases):
    out = {}
    for kind in ('drop_formal', 'change_raw_body', 'wrong_gate_producer', 'drop_small_identity_map'):
        name = 'ag-1112' if kind == 'drop_small_identity_map' else 'ag-1080'
        row = copy.deepcopy(cases[name])
        if kind == 'drop_formal':
            row['formals'].pop()
        elif kind == 'change_raw_body':
            row['ordered_cards'][0][4] = 'wrong_body'
        elif kind == 'wrong_gate_producer':
            edge = next(e for e in row['complete_gate_interfaces'] if e['producer'] is not None)
            edge['producer'] = None
        else:
            row['enumerated_involutions'] = [m for m in row['enumerated_involutions'] if any(a != b for a, b in m['devices'].items())]
        try:
            verify_case(name, row, kind == 'drop_small_identity_map')
        except AssertionError:
            out[kind] = dict(case=name, result='rejected by same independent checker')
        else:
            raise AssertionError(('survived independent checker', kind))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--output', type=Path, default=HERE / 'ninth-review-groups.json')
    ap.add_argument('--check', type=Path)
    args = ap.parse_args()
    RUN.mkdir(parents=True, exist_ok=True)
    census_path = HERE / 'ninth-local-groups-census.json'
    census = json.loads(census_path.read_text())
    assert census['names'] == sorted(p.stem for p in SOURCE.glob('*.cir'))
    small, map_count = [], 0
    for name in census['names']:
        row = census['cases'][name]
        exhaustive = 'enumerated_involutions' in row and len(row['ordered_cards']) <= 8
        if exhaustive:
            small.append(name)
        map_count += verify_case(name, row, exhaustive)
    result = dict(scope='Independent raw correspondence and all returned-map validity for full corpus; complete permutation oracle only for named <=8-card cases; no source geometry or placement admission proof.',
                  names=census['names'], exact_disposition_names=census['disposition_names'],
                  returned_maps_verified=map_count, independently_exhaustive_names=small,
                  parser_attacks=parser_attacks(), output_mutations=output_mutations(census['cases']),
                  predecessor_scope='Peer reconstructed pre-fix bytes by reversing only published facts/validate repair; not an originally archived pre-edit file.',
                  provenance={str(p.relative_to(ROOT)): sha(p) for p in [Path(__file__), PEER, OLD, census_path, HERE / 'bodies_census.py']})
    if args.check:
        assert result == json.loads(args.check.read_text())
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    print(json.dumps(dict(raw_cases=len(census['names']), valid_returned_maps=map_count,
                          independently_exhaustive_cases=len(small), parser_controls=len(result['parser_attacks']),
                          output_mutations=len(result['output_mutations']))))


if __name__ == '__main__':
    main()
