#!/usr/bin/env python3
"""Actual bias-choke extension of the frozen paired-input RC certificate.

Usage: block_input_chokes.py EXAMPLES OUTPUT [--check]

Human Rules: the two downstream AG1103 groups put their unique bias choke
parallel to the input leads, outward of INP's resistor and beyond the common
resistor-bias row. A short stepped tree joins the three actual bias tips.
X1 is retained as a counterexample; no whole V_bias wire is required.
"""
import argparse
import copy
import itertools
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import block_input_rc as rc


def choke(row, pins):
    """Recover the unique raw bias incidence already proved by the RC predicate."""
    other = [(d, i) for d, i in row['bias_incidence'] if d not in row['resistors']]
    if not row['series_bias_inductor'] or len(other) != 1:
        return None
    name, index = other[0]
    if pins[name][index] != row['bias']:
        raise ValueError('choke card index disagrees with the raw bias incidence')
    if pins[name][1-index] in row['input_nets'] + row['upstream'] + [row['bias']]:
        return None
    return dict(card=name, bias_index=index, far_index=1-index, binding=pins[name])


def geometry(row, tips):
    """Compare actual terminal order on the untouched block's semantic axes."""
    ports = row['actual_block']['visible_port_mapping']
    start, end = ports['inp']['endpoint'], ports['inn']['endpoint']
    delta = rc.sub(start, ports['inp']['attachment'])
    u = [0 if v == 0 else 1 if v > 0 else -1 for v in delta]
    delta = rc.sub(end, start)
    w = [0 if v == 0 else 1 if v > 0 else -1 for v in delta]
    assert sum(v != 0 for v in u) == sum(v != 0 for v in w) == 1
    assert rc.dot(u, w) == 0
    P, T = lambda p: rc.dot(p, u), lambda p: rc.dot(p, w)
    rb = [pair[1] for pair in row['resistor_tips_input_bias']]
    near, far = tips
    return dict(
        choke_parallel_to_actual_input_leads=T(near) == T(far),
        choke_bias_tip_outward_of_first_resistor=P(rb[0]) < P(near),
        choke_far_tip_outward_of_bias_tip=P(near) < P(far),
        choke_beyond_paired_resistor_bias_row=T(rb[0]) == T(rb[1]) < T(near))


def geometry_checks(row, tips):
    methods = []
    for rotation, mirror in itertools.product(range(4), (False, True)):
        def transform(point):
            x, y = point
            if mirror:
                x = -x
            for _ in range(rotation):
                x, y = -y, x
            return [x+137, y-49]
        changed = copy.deepcopy(row)
        for lead in changed['actual_block']['visible_port_mapping'].values():
            for key in ('attachment', 'endpoint'):
                lead[key] = transform(lead[key])
        changed['resistor_tips_input_bias'] = [
            [transform(p) for p in pair] for pair in row['resistor_tips_input_bias']]
        assert all(geometry(changed, [transform(p) for p in tips]).values())
        methods.append(row['name'] + ':choke_eight_pose_' + str(rotation) + '_' + str(mirror))
    for name in ('reversed_choke', 'skewed_choke', 'on_bias_row', 'inside_resistors'):
        changed = copy.deepcopy(tips)
        if name == 'reversed_choke':
            changed.reverse()
        elif name == 'skewed_choke':
            changed[1][1] += 1
        elif name == 'on_bias_row':
            for point in changed:
                point[1] = row['resistor_tips_input_bias'][0][1][1]
        else:
            changed[0] = row['resistor_tips_input_bias'][0][1][:]
        assert not all(geometry(row, changed).values()), name
        methods.append(row['name'] + ':' + name + '_rejected')
    return methods


def audit(examples):
    # Re-run the entire 2,936-deck selector and all actual original frame/ink
    # checks. The old certificate stays frozen and is never regenerated here.
    original = rc.audit(examples)
    rc.same(original, json.loads((HERE / 'block_input_rc_cases.json').read_text()),
            'unchanged original complete RC certificate')
    rows, methods, far_ends = [], [], []
    literal = {'x1': [[310, -70], [350, -70]],
               'x2': [[30, 380], [-10, 380]], 'x3': [[640, 380], [680, 380]]}
    for row in original['rows']:
        directory = examples / row['corpus']
        context = rc.ink.load_source(directory, row['id'])
        text = (directory / (row['id'] + '.cir')).read_text()
        pins, _ = rc.inputs.nodes(context['cards'], text)
        item = choke(row, pins)
        assert item is not None
        device = context['devices'][item['card']]
        actual = rc.ink.actual_inductor(context['root'], device)
        terms = [rc.ink.terminal(device, i, ('a', 'b')[i]) for i in range(2)]
        rc.same([device['nets'][t].lower() for t in terms], item['binding'], 'actual choke binding')
        tips = [actual['terminals'][terms[i]] for i in (item['bias_index'], item['far_index'])]
        rc.same(tips, literal[row['block']], 'literal own inductor path endpoints')
        methods.append(row['name'] + ':literal_actual_choke_endpoints_and_ordered_binding')
        # Pin-number reversal must recover the same semantic bias endpoint.
        reversed_pins, changed = copy.deepcopy((pins, row))
        reversed_pins[item['card']].reverse()
        changed['bias_incidence'] = [[d, 1-i if d == item['card'] else i] for d, i in changed['bias_incidence']]
        reversed_item = choke(changed, reversed_pins)
        assert reversed_item['bias_index'] == 1-item['bias_index']
        assert reversed_item['binding'][reversed_item['bias_index']] == row['bias']
        methods.append(row['name'] + ':reversed_choke_card_preserves_bias_identity')
        targets = [p[1] for p in row['resistor_tips_input_bias']] + [tips[0]]
        segments, missing = rc.ink.verified_segments(context['human'], row['bias'], context['ink'])
        connection = rc.ink.source_connection(context, segments, targets)
        assert connection['continuous'] and not missing
        for index, point in enumerate(targets):
            cut = [s for s in segments if not rc.ink.on(point, *s)]
            assert not rc.ink.source_connection(context, cut, targets)['continuous']
            methods.append(row['name'] + ':missing_bias_terminal_ink_' + str(index) + '_rejected')
        observed = geometry(row, tips)
        if row['driver']:
            for net in row['input_nets'] + row['upstream'] + [row['bias']]:
                aliased = copy.deepcopy(pins)
                aliased[item['card']][item['far_index']] = net
                assert choke(row, aliased) is None, net
                methods.append(row['name'] + ':choke_far_alias_' + net + '_rejected')
            assert all(observed.values()), row['name']
            methods += geometry_checks(row, tips)
        far_ends.append(dict(card=item['card'], index=item['far_index'],
                             net=item['binding'][item['far_index']], xy=tips[1]))
        rows.append(dict(name=row['name'], selected=row['driver'] is not None,
                         block=row['block'], resistors=row['resistors'], bias=row['bias'],
                         choke=item, actual_choke=actual, choke_tips_bias_far=tips,
                         resistor_tips_input_bias=row['resistor_tips_input_bias'],
                         actual_block=row['actual_block'], relations=observed,
                         source_sha256=context['source_sha256'],
                         local_bias_tree=dict(targets=targets, verified_segments=segments,
                                              cache_segments_without_ink=missing, connection=connection)))
    rc.same([r['name'] for r in rows if r['selected']], rc.SELECTED, 'exact selected choke groups')
    first = rows[0]
    rc.same([k for k, v in first['relations'].items() if not v],
            ['choke_bias_tip_outward_of_first_resistor', 'choke_far_tip_outward_of_bias_tip',
             'choke_beyond_paired_resistor_bias_row'], 'named X1 choke counterexample')
    methods.append('ag-1103:x1:actual_opposite_side_choke_excludes_universal_RC_choke_rule')
    remote = []
    for a, b in itertools.combinations(far_ends, 2):
        assert a['net'] == b['net']
        segments, missing = rc.ink.verified_segments(context['human'], a['net'], context['ink'])
        targets = [a['xy'], b['xy']]
        named = rc.ink.source_connection(context, segments, targets)
        whole = rc.ink.source_connection(context, context['ink'], targets)
        assert not named['continuous'] and not whole['continuous'] and not missing
        name = 'ag-1103:' + a['card'] + '.' + str(a['index']) + '--' + b['card'] + '.' + str(b['index'])
        remote.append(dict(name=name, net=a['net'], targets=targets,
                           named_ink=named, whole_svg_ink=whole, verified_segments=segments))
        methods.append(name + ':same_bias_label_does_not_join_source_parts')
    dependencies = dict(original['dependencies'])
    dependencies[Path(__file__).name] = rc.ink.digest(Path(__file__))
    dependencies['block_input_rc_cases.json'] = rc.ink.digest(HERE / 'block_input_rc_cases.json')
    return dict(scope=original['scope'], corpus_contract_sha256=original['corpus_contract_sha256'],
                original_certificate_sha256=dependencies['block_input_rc_cases.json'],
                dependencies=dict(sorted(dependencies.items())), rows=rows,
                selected_names=rc.SELECTED, excluded_names=['ag-1103:x1'],
                remote_source_separations=remote, method_checks=methods,
                limits=['Two correlated downstream groups in one source; no universal bias-choke habit.',
                        'Choke tips are on y380 and resistor bias tips on y370, not one row.',
                        'Only the three-terminal local bias trees are required; all three remote V_bias pairs are source-separated.',
                        'No hidden VSS coordinate, native placement, routing exception, or performance claim.'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('examples', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    result = audit(args.examples)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    if args.check:
        rc.same(result, json.loads((HERE / 'block_input_chokes_cases.json').read_text()), 'frozen choke certificate')
    print(json.dumps(dict(selected=result['selected_names'], excluded=result['excluded_names'],
                          checks=result['method_checks'])))


if __name__ == '__main__':
    main()
