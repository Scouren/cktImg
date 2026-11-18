#!/usr/bin/env python3
"""Bounded raw all-MOS decomposition experiment; no coordinate or engine edits."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
EXAMPLES = ROOT / 'external/examples/analoggenie'
sys.path.insert(0, str(HERE))
from groups_candidates import components
sys.path.insert(0, str(HERE.parent.parent / 'figures'))
from channel_bridges import read_cards

LIMIT_STATES = 100000
LIMIT_MAPS = 256


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def facts(text):
    cards = read_cards(text)
    logical = []
    for line in text.lower().splitlines():
        if line.startswith('+'):
            if not logical:
                raise ValueError('orphan continuation')
            logical[-1] += ' ' + line[1:]
        else:
            logical.append(line)
    lines = [s.split() for s in logical if s.strip()]
    formals = [r[2:] for r in lines if r[0] == '.subckt'][-1]
    models = {r[1]: r[2:] for r in lines if r[0] == '.model'}
    declarations = [r for r in lines if r[0].startswith('.') and r[0] not in ('.model', '.subckt', '.ends')]
    model_names = [r[1] for r in lines if r[0] == '.model']
    if len(model_names) != len(set(model_names)):
        declarations.append(['duplicate_model_definition'])
    rails = {n: ('supply' if n == 'vdd' else 'sink') for c in cards.values()
             for n in c[1:5] if n in ('vdd', 'vss', '0')}
    if set(rails) - {'0'} - set(formals):
        declarations.append(['unowned_conventional_rail'])
    return cards, formals, models, rails, declarations


def validate(cards, formals, models, rails, declarations):
    reasons = []
    if not cards:
        reasons.append('empty_cell')
    if any(not n.startswith('m') for n in cards):
        return ['non_mos_attachment_or_component']
    named_boundaries = ['duplicate_model_definition', 'unowned_conventional_rail']
    reasons.extend(name for name in named_boundaries if [name] in declarations)
    if any(row not in [[name] for name in named_boundaries] for row in declarations):
        reasons.append('unsupported_declaration')
    if len(formals) != len(set(formals)) or any('=' in n or n == 'params:' for n in formals):
        reasons.append('unsupported_formal_contract')
    used = {net for row in cards.values() for net in row[1:5]}
    if set(formals) - used:
        reasons.append('unused_formal_ownership_unresolved')
    for row in cards.values():
        if len(row) < 6 or any('=' in x for x in row[1:6]) or any('=' not in x for x in row[6:]):
            reasons.append('unsupported_raw_mos_grammar')
            continue
        model = models.get(row[5])
        if model not in (['nmos'], ['pmos']):
            reasons.append('unsupported_model_definition')
            continue
        body = row[4]
        if body not in rails:
            reasons.append('nonrail_body_or_source_body_tie')
        elif rails[body] != ('sink' if model[0] == 'nmos' else 'supply'):
            reasons.append('body_rail_polarity_outside_scope')
        if row[1] == row[3]:
            reasons.append('shorted_channel')
    return sorted(set(reasons))


def colors(cards, formals, rails):
    """Ordered terminal incidence refinement, independent of names and card order."""
    nets = {n for row in cards.values() for n in row[1:5]}
    base = {n: ('rail', n, rails[n]) if n in rails else ('formal' if n in formals else 'internal',) for n in nets}
    # Rail identity is a caller-supplied distinguished vertex, fixed individually.
    nc = {n: repr(base[n]) for n in nets}
    dc = {n: repr(tuple(row[5:])) for n, row in cards.items()}
    def encode(values):
        table = {v: str(i) for i, v in enumerate(sorted(set(values.values())))}
        return {k: table[v] for k, v in values.items()}
    for _ in range(len(nets) + len(cards) + 1):
        nd = encode({n: repr((dc[n], tuple(nc[x] for x in row[1:5]))) for n, row in cards.items()})
        nn = encode({n: repr((nc[n], tuple(sorted((k, nd[d]) for d, row in cards.items()
                                                 for k, net in enumerate(row[1:5]) if net == n)))) for n in nets})
        before = (len(set(dc.values())), len(set(nc.values())))
        after = (len(set(nd.values())), len(set(nn.values())))
        dc, nc = nd, nn
        if before == after:
            return dc, nc
    raise AssertionError('monotone color refinement bound')


def involutions(cards, formals, rails):
    dc, nc = colors(cards, formals, rails)
    candidates = {d: sorted(e for e in cards if dc[e] == dc[d]) for d in cards}
    found = []
    states = 0
    exhausted = False

    def extend(dm, nm, left, right):
        dm, nm = dict(dm), dict(nm)
        for a, b in ((left, right), (right, left)):
            if a in dm and dm[a] != b:
                return None
            dm[a] = b
        for a, b in zip(cards[left][1:5], cards[right][1:5]):
            if nc[a] != nc[b] or (a in rails or b in rails) and a != b:
                return None
            for x, y in ((a, b), (b, a)):
                if x in nm and nm[x] != y:
                    return None
                nm[x] = y
        return dm, nm

    def visit(dm, nm):
        nonlocal states, exhausted
        states += 1
        if states > LIMIT_STATES or len(found) > LIMIT_MAPS:
            exhausted = True
            return
        if len(dm) == len(cards):
            assert all(dm[dm[d]] == d for d in cards)
            assert all(nm[nm[n]] == n for n in nc)
            assert all(cards[d][5:] == cards[e][5:] and [nm[n] for n in cards[d][1:5]] == cards[e][1:5]
                       for d, e in dm.items())
            found.append(dict(devices=dict(sorted(dm.items())), nets=dict(sorted(nm.items()))))
            return
        choices = []
        for d in cards.keys() - dm.keys():
            possible = [x for e in candidates[d] if e not in dm or dm[e] == d
                        if (x := extend(dm, nm, d, e)) is not None]
            if not possible:
                return
            choices.append((len(possible), d, possible))
        _, _, possible = min(choices, key=lambda v: (v[0], v[1]))
        for state in possible:
            visit(*state)
            if exhausted:
                return
    visit({}, {})
    return sorted(found, key=lambda x: tuple(x['devices'].items())), states, exhausted


def decompose(cards, formals, models, rails, declarations=()):
    reasons = validate(cards, formals, models, rails, declarations)
    raw = dict(ordered_cards=[cards[n] for n in sorted(cards)], formals=formals,
               model_definitions=models, admitted_rail_facts=rails)
    if reasons:
        return dict(**raw, disposition='decline_input_boundary', reasons=reasons)
    channels = {}
    for d, row in cards.items():
        for n in (row[1], row[3]):
            if n not in rails:
                channels.setdefault(n, []).append(d)
    edges = [(members[0], member) for members in channels.values() for member in members[1:]]
    groups = components(cards, edges)
    owners = {d: k for k, group in enumerate(groups) for d in group}
    net_owners = {net: owners[members[0]] for net, members in channels.items()}
    interfaces = []
    for device, row in sorted(cards.items()):
        gate = row[2]
        if gate in rails:
            kind = 'admitted_rail_control'
        elif gate in net_owners:
            kind = 'channel_to_gate'
        elif gate in formals:
            kind = 'formal_gate_input'
        else:
            reasons.append('internal_gate_without_channel_owner')
            kind = 'unsupported_floating_internal_gate'
        interfaces.append(dict(device=device, gate=gate, kind=kind, consumer=owners[device],
                               producer=net_owners.get(gate)))
    raw.update(channel_components=groups, complete_gate_interfaces=interfaces)
    if reasons:
        return dict(**raw, disposition='decline_control_boundary', reasons=sorted(set(reasons)))
    maps, states, exceeded = involutions(cards, formals, rails)
    real = [m for m in maps if any(a != b for a, b in m['nets'].items())]
    raw.update(enumerated_involutions=maps, nontrivial_net_involution_count=len(real),
               enumeration_complete=not exceeded, search_states=states)
    if exceeded:
        return dict(**raw, disposition='decline_enumeration_bound', reasons=['bounded_search_incomplete'])
    if len(groups) == 1:
        return dict(**raw, disposition='single_channel_core_keep', reasons=[], proposed_groups=groups)
    if len(real) != 1:
        return dict(**raw, disposition='decline_involution', reasons=[
            'no_nontrivial_involution' if not real else 'multiple_full_ordered_involutions'])
    reflection = real[0]
    proposed = components(cards, edges + list(reflection['devices'].items()))
    new_owners = {d: k for k, group in enumerate(proposed) for d in group}
    dag = {k: set() for k in range(len(proposed))}
    for row in interfaces:
        if row['producer'] is not None:
            source = new_owners[groups[row['producer']][0]]
            target = new_owners[row['device']]
            if source != target:
                dag[source].add(target)
    left = set(dag)
    order = []
    while left:
        ready = sorted(n for n in left if not any(n in dag[k] for k in left))
        if not ready:
            return dict(**raw, disposition='decline_control_cycle', reasons=['intergroup_gate_dependency_cycle'],
                        proposed_groups=proposed, group_dependencies={str(k): sorted(v) for k, v in dag.items()})
        order.extend(ready)
        left -= set(ready)
    return dict(**raw, disposition='single_reflection_core_keep' if len(proposed) == 1 else 'raw_multigroup_candidate',
                reasons=[], proposed_groups=proposed, group_dependencies={str(k): sorted(v) for k, v in dag.items()},
                dependency_order=order, unique_reflection=reflection)


def normal(result, names=None, nets=None):
    names, nets = names or {}, nets or {}
    d = lambda s: names.get(s, s)
    n = lambda s: nets.get(s, s)
    partitions = lambda field: sorted(sorted(d(x) for x in g) for g in result.get(field, []))
    maps = sorted((sorted((d(a), d(b)) for a, b in row['devices'].items()),
                   sorted((n(a), n(b)) for a, b in row['nets'].items())) for row in result.get('enumerated_involutions', []))
    return result['disposition'], result['reasons'], partitions('channel_components'), partitions('proposed_groups'), maps


def invariants(values, expected):
    cards, formals, models, rails, declarations = values
    reversed_result = decompose(dict(reversed(list(cards.items()))), formals, models, rails, declarations)
    assert normal(reversed_result) == normal(expected)
    if expected['disposition'] == 'decline_input_boundary':
        return ['card_order']
    dn = {d: 'm' + str(i + 100) for i, d in enumerate(reversed(sorted(cards)))}
    all_nets = sorted({n for row in cards.values() for n in row[1:5]})
    nn = {n: 'opaque_' + str(i) for i, n in enumerate(reversed(all_nets))}
    changed = {dn[d]: [dn[d]] + [nn[n] for n in row[1:5]] + row[5:] for d, row in cards.items()}
    other = decompose(changed, [nn[n] for n in formals], models, {nn[n]: role for n, role in rails.items()})
    assert normal(other, {v: k for k, v in dn.items()}, {v: k for k, v in nn.items()}) == normal(expected)
    return ['card_order', 'bijective_device_net_rename_with_formal_and_distinguished_rail_transport']


def controls():
    source = (EXAMPLES / 'ag-1080.cir').read_text()
    values = facts(source)
    base = decompose(*values)
    assert base['disposition'] == 'raw_multigroup_candidate'
    assert sorted(len(g) for g in base['proposed_groups']) == [4, 4, 5, 5, 14]
    result = dict(ag1080=invariants(values, base), mutants={})
    for name in ('passive', 'body_source_tie', 'unknown_gate', 'one_gate_tie', 'model_change', 'caller_hint'):
        if name == 'caller_hint':
            try:
                facts(source.replace('.ends', '*@ symmetry off\n.ends'))
            except ValueError:
                result['mutants'][name] = 'input reader declines explicit caller request'
                continue
            raise AssertionError('caller request ignored')
        changed = copy.deepcopy(values)
        cards = changed[0]
        if name == 'passive':
            cards['rx'] = ['rx', 'fn', 'fp', '1k']
        elif name == 'body_source_tie':
            cards['m1'][4] = cards['m1'][3]
        elif name == 'unknown_gate':
            cards['m1'][2] = 'new_private_control'
        elif name == 'one_gate_tie':
            cards['m1'][2] = cards['m1'][3]
        else:
            cards['m1'][5] = 'other'
            changed[2]['other'] = ['nmos']
        candidate = decompose(*changed)
        assert candidate['disposition'].startswith('decline'), (name, candidate['disposition'])
        result['mutants'][name] = dict(disposition=candidate['disposition'], reasons=candidate['reasons'])
    return result


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--output', type=Path, default=HERE / 'ninth-local-groups-census.json')
    ap.add_argument('--check', type=Path)
    args = ap.parse_args()
    names = sorted(row['id'] for row in json.loads((EXAMPLES / 'index.json').read_text()))
    assert names == sorted(p.stem for p in EXAMPLES.glob('*.cir')) and len(names) == 2202
    cases = {}
    for name in names:
        path = EXAMPLES / (name + '.cir')
        values = facts(path.read_text())
        result = decompose(*values)
        cases[name] = dict(deck_sha256=sha(path), controls=invariants(values, result), **result)
    sets = {status: [n for n in names if cases[n]['disposition'] == status]
            for status in sorted({r['disposition'] for r in cases.values()})}
    result = dict(scope='Raw collection and strict candidate admission only; no general source-group or aesthetic correctness claim.',
                  script_sha256=sha(Path(__file__)), index_sha256=sha(EXAMPLES / 'index.json'),
                  dependencies={str(p.relative_to(ROOT)): sha(p) for p in [HERE / 'groups_candidates.py', HERE.parent.parent / 'figures/channel_bridges.py']},
                  limits=dict(states=LIMIT_STATES, maps=LIMIT_MAPS), names=names, disposition_names=sets,
                  literal_controls=controls(), cases=cases)
    if args.check:
        assert result == json.loads(args.check.read_text())
    args.output.write_text(json.dumps(result, sort_keys=True, indent=2) + '\n')
    print(json.dumps({k: len(v) for k, v in sets.items()}))
    print(json.dumps({'candidates': sets.get('raw_multigroup_candidate', [])}))


if __name__ == '__main__':
    main()
