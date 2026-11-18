#!/usr/bin/env python3
"""Raw interface census and finite diagnostic arrangement grammar, not selection."""
import argparse
import functools
import hashlib
import importlib.util
import itertools
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
RUN = ROOT / '.objective/human-schematic-equivalence/runs/iteration21-resume1/image-rule-round-2/groups/tenth'
EXAMPLES = ROOT / 'external/examples/analoggenie'
EXPECTED = ['ag-1016', 'ag-1028', 'ag-1046', 'ag-1047', 'ag-1051', 'ag-1071',
            'ag-1075', 'ag-1077', 'ag-1079', 'ag-1080', 'ag-364']
NOTES = {
    'ag-1016': 'Fresh tenth view: all five parents are reflected component pairs. Their source spans nest/interleave, including seven positive-area channel-stub box overlaps; retain the compound incumbent alternative.',
    'ag-1028': 'Fresh tenth view: source producer is left of consumer; complete boundary stars match AG364 under the explicit certificate, but source arrangement differs. Native is a nested alternative.',
    'ag-1046': 'Fresh tenth view: source producer is RIGHT of consumer, despite the same one-edge quotient as AG1028. The interface is mostly named fp/fn, not a mandatory left-to-right route.',
    'ag-1047': 'Fresh tenth view: source producer lies below consumer; diagonals belong to the producer internal core. Dependency direction does not choose above/below.',
    'ag-1051': 'Fresh tenth view: source producer is above consumer, with long outer interfaces. Both parents are single self-mapped channel components.',
    'ag-1071': 'Fresh tenth view: source producer left and paired-component output parent right. A two-component reflected parent does not require nesting.',
    'ag-1075': 'Fresh tenth view: paired-component producer above single-component consumer. The paired-component property permits several source arrangements.',
    'ag-1077': 'Fresh tenth view: producer above consumer; channel-stub bounds touch at the row boundary. Tail orientation remains separate from parent membership.',
    'ag-1079': 'Fresh tenth view: first two parents share an upper row and final parent is below. A mixed H/V composition is needed to reproduce this coarse placement.',
    'ag-1080': 'Fresh tenth view: five parents occupy two upper rows and one lower parent; lower parent includes named detached side pieces. Packing parents must not assert physical continuity.',
    'ag-364': 'Fresh tenth view: the paired output parent surrounds the inner self-mapped parent. Actual source and native both preserve this nested relation.',
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rel(path):
    return str(path.relative_to(ROOT))


def module():
    spec = importlib.util.spec_from_file_location('ninth', HERE / 'ninth-local-groups-census.py')
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


def interfaces(case):
    cards = {row[0]: row for row in case['ordered_cards']}
    parents = case['proposed_groups']
    owner = {name: i for i, names in enumerate(parents) for name in names}
    channels = {net: owner[name] for name, row in cards.items() for net in (row[1], row[3])
                if net not in case['admitted_rail_facts']}
    cross = sorted({row[2] for name, row in cards.items()
                    if row[2] in channels and channels[row[2]] != owner[name]})
    all_incidence = {net: [[name, index, owner[name], row[5:]]
                          for name, row in sorted(cards.items())
                          for index, value in enumerate(row[1:5]) if value == net]
                     for net in sorted({n for row in cards.values() for n in row[1:5]})}
    boundary = {net: dict(producer=channels[net], all_incidences=all_incidence[net],
                         consumers=sorted({owner[n] for n, k, _, _ in all_incidence[net]
                                           if k == 1 and owner[n] != channels[net]})) for net in cross}
    component_orbits = [[i for i, component in enumerate(case['channel_components'])
                         if set(component) <= set(group)] for group in parents]
    assert all(len(orbit) in (1, 2) for orbit in component_orbits)
    return dict(ordered_cards=case['ordered_cards'], formals=case['formals'],
                model_definitions=case['model_definitions'], admitted_rail_facts=case['admitted_rail_facts'],
                parents=parents, component_orbits=component_orbits,
                channel_components=case['channel_components'], all_terminal_incidences=all_incidence,
                all_gate_interfaces=case['complete_gate_interfaces'], boundary_stars=boundary,
                dependencies=case['group_dependencies'], reflection=case['unique_reflection'])


def canonical_star(row):
    return sorted((i, parent, tuple(params)) for _, i, parent, params in row['all_incidences'])


def star_transport(left, right, names, nets):
    assert set(left['boundary_stars']) == set(nets)
    assert set(right['boundary_stars']) == set(nets.values())
    assert set(names) == {d for s in left['boundary_stars'].values() for d, *_ in s['all_incidences']}
    assert set(names.values()) == {d for s in right['boundary_stars'].values() for d, *_ in s['all_incidences']}
    for net, other in nets.items():
        a, b = left['boundary_stars'][net], right['boundary_stars'][other]
        assert a['producer'] == b['producer'] and a['consumers'] == b['consumers']
        assert sorted([names[d], i, parent, params] for d, i, parent, params in a['all_incidences']) == sorted(b['all_incidences'])
        assert net not in left['formals'] and other not in right['formals']
        assert left['reflection']['nets'][net] in nets
        assert nets[left['reflection']['nets'][net]] == right['reflection']['nets'][other]
    return dict(device_map=names, net_map=nets, complete_boundary_star_transport=True,
                whole_DUT_isomorphism_claim=False)


@functools.lru_cache(None)
def slicing(ids):
    """Every ordered binary H/V tree exactly once; no geometric equivalence claim."""
    if len(ids) == 1:
        return (str(ids[0]),)
    out = []
    for size in range(1, len(ids)):
        for selected in itertools.combinations(ids, size):
            other = tuple(i for i in ids if i not in selected)
            for left in slicing(selected):
                for right in slicing(other):
                    out.extend((f'H({left},{right})', f'V({left},{right})'))
    assert len(out) == len(set(out))
    return tuple(sorted(out))


def validate_tree(text, expected):
    """Independent recursive parser checks coverage; repeated/missing leaf fails."""
    at = 0
    def parse():
        nonlocal at
        if text[at].isdigit():
            start = at
            while at < len(text) and text[at].isdigit():
                at += 1
            return [int(text[start:at])]
        assert text[at] in 'HV' and text[at + 1] == '('
        at += 2
        left = parse()
        assert text[at] == ','
        at += 1
        right = parse()
        assert text[at] == ')'
        at += 1
        return left + right
    leaves = parse()
    assert at == len(text) and sorted(leaves) == list(expected)


def source_relation(a, b):
    directions = []
    if a[2] <= b[0]:
        directions.append('producer_left')
    if b[2] <= a[0]:
        directions.append('producer_right')
    if a[3] <= b[1]:
        directions.append('producer_above')
    if b[3] <= a[1]:
        directions.append('producer_below')
    return directions or ['positive_area_box_overlap']


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--check', type=Path)
    ap.add_argument('--output', type=Path, default=HERE / 'tenth-arrangement-graphs.json')
    args = ap.parse_args()
    m = module()
    census_path, proof_path = [HERE / f'ninth-local-groups-{x}.json' for x in ('census', 'proof')]
    census, proof = [json.loads(p.read_text()) for p in (census_path, proof_path)]
    assert census['script_sha256'] == sha(HERE / 'ninth-local-groups-census.py')
    assert census['disposition_names']['raw_multigroup_candidate'] == EXPECTED
    actual_names = sorted(p.stem for p in EXAMPLES.glob('ag-*.cir'))
    assert actual_names == sorted(census['cases']) and len(actual_names) == 2202
    RUN.mkdir(parents=True, exist_ok=True)
    records, unchanged = {}, {}
    for name in actual_names:
        deck = EXAMPLES / (name + '.cir')
        expected = census['cases'][name]
        assert sha(deck) == expected['deck_sha256']
        actual = m.decompose(*m.facts(deck.read_text()))
        assert all(expected[k] == value for k, value in actual.items()), name
        unchanged[name] = actual['disposition']
        if actual['disposition'] != 'raw_multigroup_candidate':
            continue
        record = interfaces(actual)
        cert = proof['source_certificates'][name]
        assert sha(deck.with_suffix('.svg')) == cert['source_svg_sha256']
        assert cert['groups'] == actual['proposed_groups']
        boxes = cert['channel_lead_boxes']
        record['source_edge_directions'] = [[int(a), b, source_relation(boxes[int(a)], boxes[b])]
                                             for a, bs in actual['group_dependencies'].items() for b in bs]
        record['source_channel_stub_boxes'] = boxes
        plans = slicing(tuple(range(len(actual['proposed_groups']))))
        for plan in plans:
            validate_tree(plan, range(len(actual['proposed_groups'])))
        path = RUN / (name + '-slicing.txt')
        data = 'KEEP_INCUMBENT\n' + '\n'.join(plans) + '\n'
        if path.exists():
            assert path.read_text() == data
        else:
            path.write_text(data)
        record['finite_symbolic_candidates'] = dict(path=rel(path), sha256=sha(path), count=1 + len(plans),
                                                    geometry_generated=False, automatically_selected=False)
        pair = HERE / 'figures/groups/ninth' / (name + '-pair.png')
        record['fresh_view'] = dict(path=rel(pair), sha256=sha(pair), observation=NOTES[name])
        records[name] = record
    assert sorted(records) == EXPECTED
    names = dict(m1='m3', m2='m4', m3='m5', m4='m6', m6='m9', m7='m10')
    transport = star_transport(records['ag-1028'], records['ag-364'], names, dict(net3='x', net1='y'))
    single = sorted(n for n, r in records.items() if all(len(o) == 1 for o in r['component_orbits']))
    paired = sorted(set(records) - set(single))
    assert single == ['ag-1028', 'ag-1046', 'ag-1047', 'ag-1051', 'ag-1077']
    rejected = []
    for text in ['H(0,0)', 'V(0,2)', 'H(0,1)garbage']:
        try:
            validate_tree(text, range(2))
        except (AssertionError, IndexError):
            rejected.append(text)
        else:
            raise AssertionError('invalid candidate accepted')
    result = dict(script_sha256=sha(Path(__file__)), dependencies={rel(p): sha(p) for p in
                  (census_path, proof_path, HERE / 'ninth-local-groups-census.py')},
                  all_2202_dispositions_unchanged=unchanged, candidates=records,
                  exact_feature_names=dict(all_parents_self_mapped_components=single,
                                           contains_paired_component_parent=paired),
                  ag1028_to_ag364_boundary_transport=transport, rejected_tree_mutations=rejected,
                  scope='Feature/candidate grammar census; no changed admissions, native placement or automatic arrangement selection.')
    if args.check:
        assert result == json.loads(args.check.read_text())
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    print(json.dumps(dict(corpus=len(unchanged), raw_candidates=len(records),
                         symbolic_candidate_rows=sum(r['finite_symbolic_candidates']['count'] for r in records.values()),
                         all_parents_self_mapped_names=single)))


if __name__ == '__main__':
    main()
