#!/usr/bin/env python3
"""Independent literal replay of a label-induced physical partition error."""

import argparse
import copy
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
ARCHIVE = ROOT / '.objective/human-schematic-equivalence/runs/iteration21-resume1/image-rule-round-2/root-partition-review'
LIVE = HERE / 'eighth-partitions-proof.py'
OLD = ARCHIVE / 'eighth-partitions-proof-before-label-crossing.py'
OLD_SHA = '8a445e54b8e3ffbb86a7acd98cf536dd12eec189528dec902a38376b5427e5fc'
PARTS = [['a.0', 'b.0'], ['c.0', 'd.0']]
JOINED = [['a.0', 'b.0', 'c.0', 'd.0']]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def reader(path):
    # Preserve the old source bytes while resolving its sibling imports from
    # their original location. Imported dependency hashes are recorded below.
    scope = dict(__file__=str(LIVE), __name__='partition_literal_review')
    exec(compile(path.read_text(), str(path), 'exec'), scope)
    return scope['native_contract']


def literal():
    pins = {('a', 0): ('n', (-10, 0), 'p'), ('b', 0): ('n', (10, 0), 'p'),
            ('c', 0): ('n', (0, -10), 'p'), ('d', 0): ('n', (0, 10), 'p')}
    drawing = dict(devices=[], wires=[dict(net='n', segments=[
        [[-10, 0], [10, 0]], [[0, -10], [0, 10]]])], junctions=[],
        labels=[dict(net='n', at=[10, 0]), dict(net='n', at=[0, 10])])
    return drawing, pins


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--check', type=Path)
    args = parser.parse_args()
    assert sha(OLD) == OLD_SHA
    old, current = reader(OLD), reader(LIVE)
    base, pins = literal()
    assert old(base, 'n', pins)['blocks'] == PARTS
    assert current(base, 'n', pins)['blocks'] == PARTS
    at_cross = copy.deepcopy(base)
    at_cross['labels'].append(dict(net='n', at=[0, 0]))
    assert old(at_cross, 'n', pins)['blocks'] == JOINED
    try:
        current(at_cross, 'n', pins)
    except AssertionError as error:
        assert 'marker touches unjoined components' in str(error)
        decline = str(error)
    else:
        raise AssertionError('label silently joined physical components')
    ordinary = copy.deepcopy(base)
    ordinary['labels'].append(dict(net='n', at=[-5, 0]))
    assert current(ordinary, 'n', pins)['blocks'] == PARTS
    dotted = copy.deepcopy(at_cross)
    dotted['junctions'] = [[0, 0]]
    assert current(dotted, 'n', pins)['blocks'] == JOINED
    tee = copy.deepcopy(base)
    tee['wires'][0]['segments'] = [[[-10, 0], [10, 0]], [[0, 0], [0, 10]]]
    tee_pins = {k: v for k, v in pins.items() if k != ('c', 0)}
    assert current(tee, 'n', tee_pins)['blocks'] == [['a.0', 'b.0', 'd.0']]
    overlap = copy.deepcopy(base)
    overlap['wires'][0]['segments'] = [[[-10, 0], [5, 0]], [[0, 0], [10, 0]]]
    overlap['labels'] = [dict(net='n', at=[10, 0])]
    overlap_pins = {k: v for k, v in pins.items() if k in [('a', 0), ('b', 0)]}
    assert current(overlap, 'n', overlap_pins)['blocks'] == [['a.0', 'b.0']]
    foreign = copy.deepcopy(ordinary)
    foreign['labels'][-1]['net'] = 'wrong'
    try:
        current(foreign, 'n', pins)
    except AssertionError as error:
        assert 'conflicting reachable marker' in str(error)
    else:
        raise AssertionError('foreign reachable name accepted')
    dependencies = [Path(__file__), OLD, LIVE, HERE / 'eighth-partitions-fixtures.py',
                    HERE.parent / 'grouping_evidence.py',
                    HERE.parents[1] / 'figures/thin_connectivity.py']
    result = dict(scope='Independent literal research-verifier review; no production or corpus layout changed.',
        inputs={str(p.relative_to(ROOT)): sha(p) for p in dependencies},
        literal=base, raw_pins=[dict(device=k[0], index=k[1], net=v[0], xy=list(v[1])) for k, v in pins.items()],
        before=dict(no_center_label=PARTS, with_center_label=JOINED),
        after=dict(no_center_label=PARTS, center_label_decline=decline,
                   ordinary_lead_label=PARTS, actual_dot=JOINED),
        controls=['old_no_label_keeps_two_parts', 'old_added_label_invents_join',
                  'current_no_label_keeps_two_parts', 'current_ambiguous_label_declines',
                  'ordinary_marker_keeps_two_parts', 'actual_dot_joins',
                  'endpoint_T_joins', 'collinear_overlap_joins', 'foreign_reachable_marker_rejects'])
    if args.check:
        assert result == json.loads(args.check.read_text())
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    print(json.dumps(dict(controls=len(result['controls']), old_failure_reproduced=True,
                         repaired_ambiguity_decline=True)))


if __name__ == '__main__':
    main()
