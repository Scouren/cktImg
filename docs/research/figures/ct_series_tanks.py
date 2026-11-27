#!/usr/bin/env python3
"""Source certificate for a unique L-C-L path across a center-tapped coil.

Usage: ct_series_tanks.py EXAMPLES OUTPUT [--check]

Human Rules: in the two correlated AG1153 groups, the series inductors stand
perpendicular to the winding, outside its outer leads. The capacitor spans
their far nets on the side opposite the tap. Actual lead order and wire ink
are the oracle; no fixed spacing or native implementation is claimed.
"""
import argparse
import ast
import copy
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import block_aliases as aliases
import block_tanks as blocks
import center_tap_symbols as ct
import channel_bridges as channels
import cross_caps
import input_resistors as inputs
import thin_connectivity as ink

EXPECTED = ['ag-1153:xl1:series_lcl', 'ag-1153:xl2:series_lcl']


def raw(pins, coil, peers):
    nets = dict(zip(coil['ports'], coil['bindings']))
    ends, tap = [nets['n1'], nets['n2']], nets['n3']
    rivals = [c for c in peers if {dict(zip(c['ports'], c['bindings']))[p]
                                  for p in ('n1', 'n2')} == set(ends)]
    if len(rivals) != 1:
        return None
    candidates = [[d for d, ps in pins.items() if d.startswith('l') and n in ps] for n in ends]
    if any(len(branch) != 1 for branch in candidates):
        return None
    branches = []
    for n, (d,) in zip(ends, candidates):
        ps = pins[d]
        if len(ps) != 2 or ps.count(n) != 1:
            return None
        branches.append((d, ps.index(n), ps[1 - ps.index(n)]))
    left, right = branches
    far = [left[2], right[2]]
    if left[0] == right[0] or len(set(ends + far + [tap])) != 5:
        return None
    caps = [d for d, ps in pins.items() if d.startswith('c')
            and len(ps) == 2 and set(ps) == set(far)]
    if len(caps) != 1:
        return None
    cap = caps[0]
    return dict(coil=coil['card'], inductors=[left[0], right[0]],
                near_indices=[left[1], right[1]], capacitor=cap,
                cap_first=pins[cap].index(far[0]), outer=ends, far=far, tap=tap)


def select(pins, coil, peers):
    group = raw(pins, coil, peers)
    if group is None:
        return None
    members = {group['coil'], group['capacitor'], *group['inductors']}
    for other in peers:
        if other['card'] == coil['card']:
            continue
        candidate = raw(pins, other, peers)
        if candidate is not None and members.intersection(
                {candidate['coil'], candidate['capacitor'], *candidate['inductors']}):
            return None
    if channels.rail(group['tap']) != 'supply' or any(
            channels.rail(n) for n in group['outer'] + group['far']):
        return None
    return group


def subtract(a, b):
    return [x - y for x, y in zip(a, b)]


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def cardinal(delta):
    if (delta[0] == 0) == (delta[1] == 0):
        raise ValueError('absent or skewed actual lead axis')
    return [0 if x == 0 else (1 if x > 0 else -1) for x in delta]


def geometry(winding, inductors, cap):
    a, b, tap = (winding[p] for p in ('n1', 'n2', 'n3'))
    axis = cardinal(subtract(b, a))
    midpoint = [(x + y) / 2 for x, y in zip(a, b)]
    toward_tap = cardinal(subtract(tap, midpoint))
    away = [-x for x in toward_tap]
    near, far = ([pair[i] for pair in inductors] for i in (0, 1))
    along = lambda p: dot(subtract(p, midpoint), axis)
    across = lambda p: dot(subtract(p, midpoint), away)
    return dict(
        centered_cardinal_tap=dot(axis, toward_tap) == 0,
        two_inductors_perpendicular_to_winding=all(
            along(n) == along(f) for n, f in inductors),
        paired_near_and_far_rows=across(near[0]) == across(near[1])
        and across(far[0]) == across(far[1]),
        capacitor_parallel_to_winding=across(cap[0]) == across(cap[1]),
        capacitor_midpoint_on_winding_midpoint_axis=along(cap[0]) + along(cap[1]) == 0,
        actual_end_order=along(near[0]) < along(a) < along(cap[0]) < 0
        < along(cap[1]) < along(b) < along(near[1]),
        capacitor_beyond_series_inductors_opposite_tap=0 < across(near[0])
        < across(far[0]) < across(cap[0]))


def valid(winding, inductors, cap):
    try:
        return all(geometry(winding, inductors, cap).values())
    except ValueError:
        return False


def methods(pins, coil, peers):
    selected = select(pins, coil, peers)
    if selected is None:
        raise ValueError('literal complete L-C-L path was not selected')
    names = ['complete_unique_lcl', 'card_permutation']
    blocks.same(select(dict(reversed(list(pins.items()))), coil, peers), selected, names[-1])
    p, c, cs = copy.deepcopy((pins, coil, peers))
    p['c_shared'] = selected['outer'][:]
    other = dict(c, card='x_shared', bindings=c['bindings'][:])
    for port, net in zip(('n1', 'n2'), selected['far']):
        other['bindings'][other['ports'].index(port)] = net
    # Ineligible tap still cannot hide a structurally competing owner.
    other['bindings'][other['ports'].index('n3')] = 'private_unclassified_tap'
    cs.append(other)
    if raw(p, c, cs) is None or raw(p, other, cs) is None or select(p, c, cs) is not None:
        raise ValueError('shared complete owner was not rejected before role eligibility')
    names.append('shared_owner_before_tap_eligibility_rejected')
    for name, mutate in [
        ('second_inductor_at_outer_end', lambda p, c, cs: p.update(l_extra=p[selected['inductors'][0]][:])),
        ('shorted_extra_inductor_at_outer_end', lambda p, c, cs: p.update(l_extra=[selected['outer'][0]] * 2)),
        ('second_capacitor', lambda p, c, cs: p.update(c_extra=p[selected['capacitor']][:])),
        ('second_winding', lambda p, c, cs: cs.append(dict(c, card='x_extra'))),
        ('open_series_path', lambda p, c, cs: p.pop(selected['capacitor'])),
        ('shorted_far_nets', lambda p, c, cs: p[selected['inductors'][1]].__setitem__(1 - selected['near_indices'][1], selected['far'][0])),
        ('tap_is_outer_net', lambda p, c, cs: c['bindings'].__setitem__(c['ports'].index('n3'), selected['outer'][0])),
    ]:
        p, c, cs = copy.deepcopy((pins, coil, peers))
        mutate(p, c, cs)
        if select(p, c, cs) is not None:
            raise ValueError('topology mutation survived: ' + name)
        names.append(name + '_rejected')
    winding = dict(n1=[-50, 0], n2=[50, 0], n3=[0, -20])
    inductors, cap = [[[-70, 10], [-70, 50]], [[70, 10], [70, 50]]], [[-20, 60], [20, 60]]
    assert valid(winding, inductors, cap)
    names.append('literal_actual_lead_order')
    for rotation in range(4):
        for mirror in (False, True):
            def transform(point):
                x, y = point
                if mirror:
                    x = -x
                for _ in range(rotation):
                    x, y = -y, x
                return [x + 37, y - 91]
            assert valid({k: transform(p) for k, p in winding.items()},
                         [[transform(p) for p in pair] for pair in inductors],
                         [transform(p) for p in cap])
    names.append('eight_rigid_poses_and_translation')
    for name, mutate in [
        ('tap_toward_capacitor', lambda w, ls, c: w['n3'].__setitem__(1, 20)),
        ('skewed_inductor', lambda w, ls, c: ls[0][1].__setitem__(0, -60)),
        ('inductor_inside_winding', lambda w, ls, c: [p.__setitem__(0, -40) for p in ls[0]]),
        ('reversed_capacitor_binding', lambda w, ls, c: c.reverse()),
        ('shifted_capacitor_midpoint', lambda w, ls, c: c[0].__setitem__(0, -30)),
        ('cap_before_far_inductor', lambda w, ls, c: [p.__setitem__(1, 40) for p in c]),
        ('inductor_polarity', lambda w, ls, c: ls[0].reverse()),
        ('staggered_inductor_rows', lambda w, ls, c: ls[0][0].__setitem__(1, 20)),
    ]:
        w, ls, c = copy.deepcopy((winding, inductors, cap))
        mutate(w, ls, c)
        if valid(w, ls, c):
            raise ValueError('geometry mutation survived: ' + name)
        names.append(name + '_rejected')
    return names


def endpoint(context, actual, name, index):
    device = context['devices'][name]
    terminal = ink.terminal(device, index, 'a' if index == 0 else 'b')
    if context['cards'][name][index + 1] != device['nets'][terminal].lower():
        raise ValueError('source primitive binding mismatch: ' + name)
    return actual['terminals'][terminal]


def dependencies():
    found, pending = {}, [Path(__file__).name]
    while pending:
        name = pending.pop()
        if name in found:
            continue
        path = HERE / name
        found[name] = ink.digest(path)
        for node in ast.walk(ast.parse(path.read_text())):
            modules = [n.name for n in node.names] if isinstance(node, ast.Import) else [node.module] if isinstance(node, ast.ImportFrom) else []
            for module in modules:
                local = (module or '').split('.')[0] + '.py'
                if (HERE / local).is_file():
                    pending.append(local)
    return dict(sorted(found.items()))


def audit(examples):
    _, coils, counts, hashes = ct.scan(examples)
    rows, observations = [], []
    for coil in coils:
        prefix = examples / coil['corpus'] / coil['id']
        text = prefix.with_suffix('.cir').read_text()
        cards = channels.read_cards(text)
        pins, _ = inputs.nodes(cards, text)
        peers = [c for c in coils if (c['corpus'], c['id']) == (coil['corpus'], coil['id'])]
        group = select(pins, coil, peers)
        observations.append(dict(name=coil['id'] + ':' + coil['card'], selected=group is not None))
        if group is None:
            continue
        name = coil['id'] + ':' + coil['card'] + ':series_lcl'
        context = ink.load_source(examples / coil['corpus'], coil['id'])
        device, svg_group, parent = aliases.source_group(context['human'], context['root'], coil['card'])
        actual_bindings = {'n' + p: n.lower() for p, n in device['nets'].items()}
        blocks.same(actual_bindings, dict(zip(coil['ports'], coil['bindings'])), name + ' source winding bindings')
        winding = ct.center_tap_ink(ct.primitives(svg_group, parent))
        actuals = {d: ink.actual_inductor(context['root'], context['devices'][d]) for d in group['inductors']}
        cap_name = group['capacitor']
        actuals[cap_name] = cross_caps.actual_glyph(context['root'], context['devices'][cap_name])
        inductors = [[endpoint(context, actuals[d], d, i), endpoint(context, actuals[d], d, 1 - i)]
                     for d, i in zip(group['inductors'], group['near_indices'])]
        cap = [endpoint(context, actuals[cap_name], cap_name, i)
               for i in (group['cap_first'], 1 - group['cap_first'])]
        observed = geometry(winding, inductors, cap)
        if not all(observed.values()):
            raise ValueError('actual source frame differs: ' + name)
        paths = []
        for i, (inductor, near_index) in enumerate(zip(group['inductors'], group['near_indices'])):
            cap_index = group['cap_first'] if i == 0 else 1 - group['cap_first']
            coil_index = coil['ports'].index('n' + str(i + 1))
            for net, targets, bindings in [
                (group['outer'][i], [winding['n' + str(i + 1)], inductors[i][0]],
                 [[coil['card'], coil_index], [inductor, near_index]]),
                (group['far'][i], [inductors[i][1], cap[i]],
                 [[inductor, 1 - near_index], [cap_name, cap_index]]),
            ]:
                segments, missing = ink.verified_segments(context['human'], net, context['ink'])
                connection = ink.source_connection(context, segments, targets)
                if not connection['continuous']:
                    raise ValueError('source actual leads lack physical path: ' + name + ':' + net)
                paths.append(dict(net=net, bindings=bindings, actual_targets=targets,
                                  verified_segments=segments, missing_cache_segments=missing, connection=connection))
        rows.append(dict(name=name, topology=group, actual_winding=winding,
                         actual_inductors=inductors, actual_capacitor=cap, source_glyphs=actuals,
                         geometry=observed, paths=paths, method_checks=methods(pins, coil, peers),
                         source_sha256={ext: ink.digest(prefix.with_suffix(ext)) for ext in ('.cir', '.svg', '.human.json')}))
    blocks.same([r['name'] for r in rows], EXPECTED, 'exact unique L-C-L source names')
    return dict(names=EXPECTED, observations=observations, rows=rows, corpus_counts=counts,
                corpus_sha256=hashes, dependencies=dependencies(),
                limits=['Two correlated groups in one figure; no population frequency claim.',
                        'Relations use actual SVG leads and ink; distances are not prescribed.',
                        'Global relative order of the two groups is outside this certificate.',
                        'No native placement improvement or connectivity preservation is claimed.'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('examples', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    result = audit(args.examples)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    if args.check:
        blocks.same(result, json.loads((HERE / 'ct_series_tanks_cases.json').read_text()), 'frozen L-C-L source certificate')
    print(json.dumps(dict(names=result['names'], methods={r['name']: r['method_checks'] for r in result['rows']})))


if __name__ == '__main__':
    main()
