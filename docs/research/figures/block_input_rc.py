#!/usr/bin/env python3
"""Source-backed paired input RC branches, retaining the first-stage boundary.

Usage: block_input_rc.py EXAMPLES OUTPUT [--check]

All 2,936 decks are rescanned. Named ports select a candidate only; actual
own attached leads establish its frame. No DA/PA triangle, hidden VSS lead,
physical join through a text label, or universal block-input habit is inferred.
"""
import argparse
import ast
import collections
import copy
import itertools
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import channel_bridges as channels
import input_resistors as inputs
import digital_symbols as digital
import paired_amplifier_ports as boxes
import center_tap_native as coils
import thin_connectivity as ink

BROAD = ['ag-1103:x1', 'ag-1103:x2', 'ag-1103:x3']
SELECTED = ['ag-1103:x2', 'ag-1103:x3']


def same(a, b, context):
    if json.loads(json.dumps(a)) != json.loads(json.dumps(b)):
        raise ValueError(context + ': exact evidence differs')


def select(cards, pins, definitions):
    """Broad common-bias two-input RC topology, counting every raw incidence."""
    incidence = collections.defaultdict(list)
    for device, nets in pins.items():
        for index, net in enumerate(nets):
            incidence[net].append([device, index])
    result = []
    for block, bound in pins.items():
        if not block.startswith('x'):
            continue
        ports = definitions[cards[block][len(bound)+1]]
        if ports.count('inp') != 1 or ports.count('inn') != 1:
            continue
        indexes = [ports.index(p) for p in ('inp', 'inn')]
        nets = [bound[i] for i in indexes]
        if len(set(nets)) != 2 or any(channels.rail(n) for n in nets):
            continue
        caps, resistors, bias, upstream, input_indices = [], [], [], [], []
        for net in nets:
            members = incidence[net]
            if len(members) != 3 or sum(d == block for d, _ in members) != 1:
                break
            others = [(d, i) for d, i in members if d != block]
            cs = [(d, i) for d, i in others if d.startswith('c') and len(pins[d]) == 2 and pins[d][0] != pins[d][1]]
            rs = [(d, i) for d, i in others if d.startswith('r') and len(pins[d]) == 2 and pins[d][0] != pins[d][1]]
            if len(cs) != 1 or len(rs) != 1:
                break
            cap, cp = cs[0]
            resistor, rp = rs[0]
            caps.append(cap)
            resistors.append(resistor)
            input_indices.append([cp, rp])
            bias.append(pins[resistor][1-rp])
            upstream.append(pins[cap][1-cp])
        if len(caps) != 2 or len(set([block, *caps, *resistors])) != 5:
            continue
        if (len(set(bias)) != 1 or channels.rail(bias[0]) or bias[0] in nets
                or len(set(upstream)) != 2
                or any(n in nets+[bias[0]] or channels.rail(n) for n in upstream)):
            continue
        leftover = [(d, i) for d, i in incidence[bias[0]] if d not in resistors]
        choke = (len(incidence[bias[0]]) == 3 and len(leftover) == 1
                 and leftover[0][0].startswith('l') and len(pins[leftover[0][0]]) == 2
                 and len(set(pins[leftover[0][0]])) == 2)
        result.append(dict(block=block, block_pins=indexes, input_nets=nets, caps=caps,
                           resistors=resistors, cap_resistor_input_indices=input_indices,
                           bias=bias[0], upstream=upstream, bias_incidence=incidence[bias[0]],
                           series_bias_inductor=choke,
                           binding={n: pins[n] for n in [block, *caps, *resistors]}))
    return result


def driver(row, cards, pins, definitions, passives):
    """A common bias choke and unique upstream named-output block bound the case."""
    if not row['series_bias_inductor']:
        return None
    raw = [d for d, nets in pins.items() if d.startswith('x') and d != row['block']
           and d not in passives and all(n in nets for n in row['upstream'])]
    if len(raw) != 1:
        return None
    device = raw[0]
    ports = definitions[cards[device][len(pins[device])+1]]
    if ports.count('outp') != 1 or ports.count('outn') != 1:
        return None
    indexes = [ports.index(p) for p in ('outp', 'outn')]
    if ([pins[device][i] for i in indexes] != row['upstream']
            or any(pins[device].count(n) != 1 for n in row['upstream'])):
        return None
    return dict(block=device, pins=indexes, ports=['outp', 'outn'], binding=pins[device])


def sub(a, b):
    return [x-y for x, y in zip(a, b)]


def dot(a, b):
    return sum(x*y for x, y in zip(a, b))


def geometry(block, cap, res):
    """Actual input tips define longitudinal and INP-to-INN transverse axes."""
    leads = [block['visible_port_mapping'][name] for name in ('inp', 'inn')]
    directions = [sub(p['endpoint'], p['attachment']) for p in leads]
    assert all((v[0] == 0) != (v[1] == 0) for v in directions)
    units = [[0 if v == 0 else 1 if v > 0 else -1 for v in d] for d in directions]
    assert units[0] == units[1]
    u = units[0]
    tips = [p['endpoint'] for p in leads]
    delta = sub(tips[1], tips[0])
    assert (delta[0] == 0) != (delta[1] == 0)
    w = [0 if v == 0 else 1 if v > 0 else -1 for v in delta]
    assert dot(u, w) == 0 and all(dot(sub(p, t), u) < 0 for p in block['body'] for t in tips)
    P = lambda point: dot(point, u)
    T = lambda point: dot(point, w)
    near, far = [c[0] for c in cap], [c[1] for c in cap]
    rn, rb = [r[0] for r in res], [r[1] for r in res]
    low, high = sorted(T(t) for t in tips)
    return dict(
        actual_inputs_share_outward_plane=P(tips[0]) == P(tips[1]),
        capacitors_parallel_to_input_leads=all(T(a) == T(b) for a, b in cap),
        capacitor_near_tips_on_input_rows=all(T(c) == T(t) for c, t in zip(near, tips)),
        capacitors_share_near_and_far_planes=P(near[0]) == P(near[1]) and P(far[0]) == P(far[1]),
        capacitor_farther_from_block=all(P(t) < P(a) < P(b) for t, (a, b) in zip(tips, cap)),
        resistors_transverse=all(P(a) == P(b) and T(a) != T(b) for a, b in res),
        resistors_between_input_and_cap=all(P(t) < P(r) < P(c) for t, r, c in zip(tips, rn, near)),
        resistor_input_rows_equal=T(rn[0]) == T(rn[1]),
        resistor_bias_rows_equal=T(rb[0]) == T(rb[1]),
        resistor_branch_outside_input_span=(high < T(rn[0]) < T(rb[0]) or T(rb[0]) < T(rn[0]) < low),
        first_input_resistor_farther_outward=P(rn[0]) > P(rn[1]))


def topology_checks(row, cards, pins, definitions, passives):
    """Raw incidence mutations must fail before any actual-frame filtering."""
    methods = []
    for name in ('extra_capacitor', 'extra_resistor', 'unknown_input_load',
                 'split_bias', 'aliased_remote_ends', 'rail_remote_end', 'hidden_block_incidence',
                 'missing_input_role', 'duplicate_input_role'):
        c, p, d = copy.deepcopy((cards, pins, definitions))
        cap, resistor = row['caps'][0], row['resistors'][0]
        cp, rp = row['cap_resistor_input_indices'][0]
        if name.startswith('extra_'):
            source = cap if name == 'extra_capacitor' else resistor
            new = source[0] + 'extra'
            p[new] = p[source][:]
            c[new] = [new, *p[new], '1']
        elif name == 'unknown_input_load':
            p['xunknown'] = [row['input_nets'][0], 'other']
            c['xunknown'] = ['xunknown', *p['xunknown'], 'unknown']
            d['unknown'] = ['a', 'b']
        elif name == 'hidden_block_incidence':
            ports = d[c[row['block']][len(p[row['block']])+1]]
            p[row['block']][ports.index('vss')] = row['input_nets'][0]
        elif name == 'split_bias':
            p[resistor][1-rp] = 'other_bias'
        elif name in ('aliased_remote_ends', 'rail_remote_end'):
            p[cap][1-cp] = row['upstream'][1] if name == 'aliased_remote_ends' else 'vss'
        else:
            family = c[row['block']][len(p[row['block']])+1]
            d[family][row['block_pins'][0]] = 'other' if name == 'missing_input_role' else 'inn'
        assert row['block'] not in [r['block'] for r in select(c, p, d)], name
        methods.append(row['name'] + ':' + name + '_rejected')
    # Card direction is not topology; follow the input-net identity after reversal.
    c, p = copy.deepcopy((cards, pins))
    for name in row['caps'] + row['resistors']:
        p[name].reverse()
        c[name][1:3] = p[name]
    reversed_row = next(r for r in select(c, p, definitions) if r['block'] == row['block'])
    same([reversed_row[k] for k in ('caps', 'resistors', 'input_nets', 'bias', 'upstream')],
         [row[k] for k in ('caps', 'resistors', 'input_nets', 'bias', 'upstream')], 'reversed passive cards')
    same(reversed_row['cap_resistor_input_indices'],
         [[1-i for i in pair] for pair in row['cap_resistor_input_indices']], 'reversed card terminal indexes')
    methods.append(row['name'] + ':passive_card_reversal_preserves_semantic_binding')
    parent = driver(row, cards, pins, definitions, passives)
    if parent is None:
        return methods
    for mode in ('extra_bias_incidence', 'missing_bias_inductor'):
        c, p = copy.deepcopy((cards, pins))
        if mode == 'extra_bias_incidence':
            p['xextra'] = [row['bias'], 'other']
            c['xextra'] = ['xextra', *p['xextra'], 'opaque']
            d = dict(definitions, opaque=['a', 'b'])
        else:
            choke = next(n for n, _ in row['bias_incidence'] if n not in row['resistors'])
            del c[choke]
            del p[choke]
            d = definitions
        changed = next(r for r in select(c, p, d) if r['block'] == row['block'])
        assert driver(changed, c, p, d, passives) is None
        methods.append(row['name'] + ':' + mode + '_rejected')
    assert driver(row, cards, pins, definitions, []) is None
    methods.append(row['name'] + ':uncertified_passive_competitor_rejected')
    for mode in ('second_driver', 'wrong_binding', 'unknown_output_role'):
        c, p, d = copy.deepcopy((cards, pins, definitions))
        if mode == 'second_driver':
            p['xunknown'] = row['upstream'][:]
            c['xunknown'] = ['xunknown', *p['xunknown'], 'opaque']
            d['opaque'] = ['a', 'b']
        elif mode == 'wrong_binding':
            p[parent['block']][parent['pins'][0]] = 'wrong'
        else:
            family = c[parent['block']][len(p[parent['block']])+1]
            d[family][parent['pins'][0]] = 'unknown'
        assert driver(row, c, p, d, passives) is None, mode
        methods.append(row['name'] + ':' + mode + '_rejected')
    return methods


def geometry_checks(row):
    block, cap, res = row['actual_block'], row['cap_tips_near_far'], row['resistor_tips_input_bias']
    names = []
    for field in ('cap_row', 'cap_backwards', 'resistor_outside', 'resistor_inside_span'):
        ca, re = copy.deepcopy((cap, res))
        if field == 'cap_row':
            ca[0][0][1] += 1
        elif field == 'cap_backwards':
            ca[0].reverse()
        elif field == 'resistor_outside':
            re[0][0][0] = ca[0][1][0]
        else:
            re[0][0][1] = block['visible_port_mapping']['inp']['endpoint'][1]
        assert not all(geometry(block, ca, re).values()), field
        names.append(row['name'] + ':' + field + '_rejected')
    for rotation, mirror in itertools.product(range(4), (False, True)):
        def transform(point):
            x, y = point
            if mirror:
                x = -x
            for _ in range(rotation):
                x, y = -y, x
            return [x+137, y-49]
        b = copy.deepcopy(block)
        b['body'] = [transform(p) for p in b['body']]
        for lead in b['visible_port_mapping'].values():
            for key in ('attachment', 'endpoint'):
                lead[key] = transform(lead[key])
        assert all(geometry(b, [[transform(p) for p in c] for c in cap],
                            [[transform(p) for p in r] for r in res]).values())
        names.append(row['name'] + ':actual_frame_rotation_' + str(rotation) + '_mirror_' + str(mirror))
    for kind in ('inward_input', 'opposed_inputs', 'coincident_inputs'):
        b = copy.deepcopy(block)
        first, second = [b['visible_port_mapping'][k] for k in ('inp', 'inn')]
        if kind == 'inward_input':
            first['attachment'], first['endpoint'] = first['endpoint'], first['attachment']
            second['attachment'], second['endpoint'] = second['endpoint'], second['attachment']
        elif kind == 'opposed_inputs':
            first['attachment'], first['endpoint'] = first['endpoint'], first['attachment']
        else:
            second.update(copy.deepcopy(first))
        try:
            geometry(b, cap, res)
        except AssertionError:
            names.append(row['name'] + ':' + kind + '_rejected')
        else:
            raise ValueError('actual block frame mutation survived: ' + kind)
    return names


def dependencies():
    pending, result = [Path(__file__).name], {}
    while pending:
        name = pending.pop()
        if name in result:
            continue
        path = HERE / name
        result[name] = ink.digest(path)
        for node in ast.walk(ast.parse(path.read_text())):
            modules = [n.name for n in node.names] if isinstance(node, ast.Import) else [node.module] if isinstance(node, ast.ImportFrom) else []
            for module in modules:
                local = (module or '').split('.')[0] + '.py'
                if (HERE / local).is_file():
                    pending.append(local)
    for name in ('paired_amplifier_ports_cases.json', 'center_tap_symbols_cases.json'):
        result[name] = ink.digest(HERE / name)
    return dict(sorted(result.items()))


def audit(examples):
    broad, scope, contracts = [], {}, {}
    for corpus in ('analoggenie', 'amsnet'):
        paths = sorted((examples / corpus).glob('*.cir'))
        if not paths:
            raise ValueError('missing complete corpus: ' + corpus)
        scope[corpus] = [p.stem for p in paths]
        for path in paths:
            contracts[corpus + '/' + path.name] = ink.digest(path)
            text = path.read_text()
            cards = channels.read_cards(text)
            pins, _ = inputs.nodes(cards, text)
            for row in select(cards, pins, digital.declarations(text)):
                broad.append(dict(corpus=corpus, id=path.stem, name=path.stem+':'+row['block'], **row))
    same([r['name'] for r in broad], BROAD, 'complete broad topology names')
    proof = boxes.replay(examples)
    same(proof, json.loads((HERE / 'paired_amplifier_ports_cases.json').read_text()), 'fresh own block leads')
    boxmap = {(r['id'], r['card']): r for r in proof['rows']}
    coil_rows, _ = coils.replay_source(examples)
    rows, methods = [], []
    for row in broad:
        directory = examples / row['corpus']
        context = ink.load_source(directory, row['id'])
        text = (directory / (row['id']+'.cir')).read_text()
        pins, _ = inputs.nodes(context['cards'], text)
        definitions = digital.declarations(text)
        passives = [r['card'] for r in coil_rows if (r['id'], r['corpus']) == (row['id'], row['corpus'])]
        parent = driver(row, context['cards'], pins, definitions, passives)
        actual, cap, res, trees = {}, [], [], []
        for k, names in enumerate((row['caps'], row['resistors'])):
            for i, name in enumerate(names):
                device = context['devices'][name]
                glyph = inputs.actual(context['root'], device)
                actual[name] = glyph
                pin = row['cap_resistor_input_indices'][i][k]
                terms = [ink.terminal(device, j, ('a', 'b')[j]) for j in range(2)]
                same([device['nets'][t].lower() for t in terms], pins[name], 'declared actual passive binding')
                (cap if k == 0 else res).append([glyph['terminals'][terms[pin]], glyph['terminals'][terms[1-pin]]])
        block = boxmap[row['id'], row['block']]
        observed = geometry(block, cap, res)
        literal = {
            'x1': [[340,30],[340,70],[250,-10],[210,-10],[250,120],[210,120],
                   [270,-20],[270,-60],[300,-20],[300,-60]],
            'x2': [[90,270],[90,310],[40,270],[0,270],[40,310],[0,310],
                   [50,330],[50,370],[70,330],[70,370]],
            'x3': [[580,270],[580,310],[630,270],[670,270],[630,310],[670,310],
                   [620,330],[620,370],[600,330],[600,370]],
        }
        points = [block['visible_port_mapping'][port]['endpoint'] for port in ('inp', 'inn')]
        points += [point for pair in cap+res for point in pair]
        same(points, literal[row['block']], 'literal actual ten-terminal source frame')
        methods.append(row['name'] + ':ten_literal_actual_source_terminals')
        for i, net in enumerate(row['input_nets'] + [row['bias']]):
            targets = ([block['visible_port_mapping'][('inp', 'inn')[i]]['endpoint'], cap[i][0], res[i][0]]
                       if i < 2 else [r[1] for r in res])
            segments, missing = ink.verified_segments(context['human'], net, context['ink'])
            connection = ink.source_connection(context, segments, targets)
            assert connection['continuous'], row['name'] + ':' + net
            trees.append(dict(name=row['name']+':'+net, net=net, actual_targets=targets,
                              verified_segments=segments, actual_source_path=connection,
                              cache_segments_without_ink=missing))
            # Removing every actual interval through one target must sever it;
            # equal labels and all unrelated conductor strokes are not substitutes.
            cut = [s for s in segments if not ink.on(targets[0], *s)]
            assert not ink.source_connection(context, cut, targets)['continuous']
            methods.append(row['name'] + ':' + net + ':missing_own_target_ink_rejected')
        result = dict(**row, driver=parent, actual_block=block,
                      actual_driver=None if parent is None else boxmap[row['id'], parent['block']],
                      actual_passives=actual, cap_tips_near_far=cap, resistor_tips_input_bias=res,
                      relations=observed, local_trees=trees, source_sha256=context['source_sha256'])
        methods += topology_checks(row, context['cards'], pins, definitions, passives)
        if parent:
            assert all(observed.values()), row['name']
            methods += geometry_checks(result)
        rows.append(result)
    same([r['name'] for r in rows if r['driver']], SELECTED, 'complete selected topology names')
    excluded = [r for r in rows if not r['driver']]
    same([r['name'] for r in excluded], ['ag-1103:x1'], 'named observed boundary')
    same([k for k, v in excluded[0]['relations'].items() if not v],
         ['capacitor_near_tips_on_input_rows'], 'actual X1 counterexample')
    methods.append('ag-1103:x1:upstream_without_named_output_block_retains_row_counterexample')
    methods += ['physical_ink:' + name for name in ink.method_checks()]
    # The public fixture retains every source declaration/card and the same CLI weak roles.
    source = (examples / 'analoggenie/ag-1103.cir').read_text().splitlines()
    expected = '\n'.join(s for s in source if not s.lower().startswith(('.subckt dut', '.ends dut'))) + '\n'
    expected += '*@ weak role rfin output\n*@ weak role rfout output\n*@ weak role v_bias output\n'
    fixture = HERE.parents[2] / 'tests/block_input_rc_fixture.sp'
    same(fixture.read_text(), expected, 'literal full-source public fixture')
    return dict(scope=scope, corpus_contract_sha256=contracts, rows=rows, method_checks=methods,
                selected_names=SELECTED, broad_names=BROAD, excluded_names=['ag-1103:x1'],
                certified_passive_exclusions=[r for r in coil_rows if r['id'] == 'ag-1103'],
                fixture_sha256=ink.digest(fixture), dependencies=dependencies(),
                limits=['Two correlated downstream groups in one source; X1 is a named upstream boundary.',
                        'Actual block input frame is read-only; no hidden VSS coordinate or amplifier triangle is invented.',
                        'Only two input triples and paired resistor bias tips are required local trees.',
                        'The source places bias branches beyond INN in the semantic input axis; no world-down rule follows.',
                        'No whole remote output/bias tree, native placement, or performance claim follows from this source certificate.'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('examples', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    result = audit(args.examples)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    if args.check:
        same(result, json.loads((HERE / 'block_input_rc_cases.json').read_text()), 'frozen paired RC evidence')
    print(json.dumps(dict(selected=result['selected_names'], excluded=result['excluded_names'],
                          methods=result['method_checks'])))


if __name__ == '__main__':
    main()
