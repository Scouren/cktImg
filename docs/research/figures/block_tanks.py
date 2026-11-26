#!/usr/bin/env python3
"""Actual same-side block output leads and their unique CT/capacitor tank.

Usage: block_tanks.py EXAMPLES OUTPUT [--check]

No block family chooses the match and no glyph is inferred. Declared OUTP/OUTN
bindings select a candidate; actual attached outward leads certify its frame.
This one observed group does not prove arbitrary block-load placement.
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
import center_tap_tanks as tanks
import center_tap_symbols as ct
import input_resistors as inputs
import digital_symbols as digital
import paired_amplifier_ports as boxes
import thin_connectivity as ink
import channel_bridges as channels

EXPECTED = ['ag-1103:x1:xl1--c1']


def same(a, b, context):
    tanks.same(a, b, context)


def select(cards, pins, definitions, coil, coils):
    n = dict(zip(coil['ports'], coil['bindings']))
    ends = [n['n1'], n['n2']]
    if len(set(ends + [n['n3']])) != 3 or any(channels.rail(n) for n in ends):
        return None
    rivals = [c for c in coils if {dict(zip(c['ports'], c['bindings']))[p]
                                  for p in ('n1', 'n2')} == set(ends)]
    caps = [d for d, ps in pins.items() if d.startswith('c') and len(ps) == 2 and set(ps) == set(ends)]
    # Count all other blocks touching both ends before named-role filtering.
    blocks = [d for d, ps in pins.items() if d.startswith('x') and d != coil['card']
              and all(n in ps for n in ends)]
    if len(rivals) != 1 or len(caps) != 1 or len(blocks) != 1:
        return None
    block = blocks[0]
    ports = definitions[cards[block][1 + len(pins[block])]]
    if ports.count('outp') != 1 or ports.count('outn') != 1:
        return None
    indexes = []
    for net in ends:
        positions = [i for i, n in enumerate(pins[block]) if n == net]
        if len(positions) != 1:
            return None
        indexes.append(positions[0])
    if {ports[i] for i in indexes} != {'outp', 'outn'}:
        return None
    incident = [sorted((d, i) for d, ps in pins.items() for i, net in enumerate(ps) if net == end)
                for end in ends]
    # The observed external branches are capacitors. No hidden active load
    # or other pin of the anchor becomes an accidentally ignored incidence.
    if any(d not in (coil['card'], block) and not d.startswith('c')
           for members in incident for d, _ in members):
        return None
    return dict(coil=coil['card'], capacitor=caps[0], block=block,
                block_ports=[ports[i] for i in indexes], block_indices=indexes,
                outer_nets=ends, tap=n['n3'], outer_incidences=incident)


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def sub(a, b):
    return [x - y for x, y in zip(a, b)]


def mean(a, b):
    return [(x + y) / 2 for x, y in zip(a, b)]


def geometry(block, coil, cap, ports):
    leads = [block['visible_port_mapping'][p] for p in ports]
    directions = [sub(p['endpoint'], p['attachment']) for p in leads]
    for v in directions:
        if (v[0] == 0) == (v[1] == 0):
            raise ValueError('noncardinal or absent actual output lead')
    unit = [0 if v == 0 else (1 if v > 0 else -1) for v in directions[0]]
    if any([0 if v == 0 else (1 if v > 0 else -1) for v in d] != unit for d in directions):
        raise ValueError('outputs do not face the same actual side')
    tips = [p['endpoint'] for p in leads]
    if any(dot(sub(p, tip), unit) >= 0 for p in block['body'] for tip in tips):
        raise ValueError('output lead is not outward of its own body')
    transverse = [-unit[1], unit[0]]
    outer = [coil[p] for p in ('n1', 'n2')]
    cm, pm, om = mean(*outer), mean(*cap), mean(*tips)
    pairs = [tips, outer, cap]
    signs = [dot(sub(b, a), transverse) for a, b in pairs]
    if any(s == 0 for s in signs):
        raise ValueError('coincident output/tank ends')
    return dict(
        outputs_share_facing_plane=dot(tips[0], unit) == dot(tips[1], unit),
        coil_parallel_to_output_span=dot(outer[0], unit) == dot(outer[1], unit),
        cap_parallel_to_output_span=dot(cap[0], unit) == dot(cap[1], unit),
        three_actual_midpoints_share_transverse_coordinate=dot(cm, transverse) == dot(pm, transverse) == dot(om, transverse),
        matching_named_net_order=signs[0] * signs[1] > 0 and signs[0] * signs[2] > 0,
        capacitor_between_output_and_coil=dot(om, unit) < dot(pm, unit) < dot(cm, unit),
        tap_faces_away_from_block=dot(coil['n3'], unit) > dot(cm, unit) and dot(coil['n3'], transverse) == dot(cm, transverse))


def complete(value):
    return all(value.values())


def methods(cards, pins, definitions, coil, coils):
    selected = select(cards, pins, definitions, coil, coils)
    if selected is None:
        raise ValueError('literal source topology not selected')
    names = ['literal_complete_block_tank']
    mutations = [
        ('duplicate_capacitor', lambda c, p, d, x, xs: (c.update(cx=c['c1']), p.update(cx=p['c1']))),
        ('duplicate_coil', lambda c, p, d, x, xs: xs.append(dict(x, card='xx'))),
        ('duplicate_block', lambda c, p, d, x, xs: (c.update(xx=c['x1']), p.update(xx=p['x1']))),
        ('second_block_with_unknown_roles', lambda c, p, d, x, xs: (c.update(xx=['xx', 'net9', 'net8', 'opaque']), p.update(xx=['net9', 'net8']), d.update(opaque=['a', 'b']))),
        ('output_bound_twice', lambda c, p, d, x, xs: p['x1'].__setitem__(1, 'net9')),
        ('input_ports_are_not_outputs', lambda c, p, d, x, xs: d.__setitem__('da', ['vss', 'vb', 'outp', 'outn', 'inp', 'inn', 'src'])),
        ('unknown_extra_active_incidence', lambda c, p, d, x, xs: (c.update(mextra=['mextra']), p.update(mextra=['net9', 'g', 's', 'b']))),
        ('tap_alias', lambda c, p, d, x, xs: x['bindings'].__setitem__(x['ports'].index('n3'), 'net9')),
    ]
    for name, mutate in mutations:
        c, p, d, x, xs = copy.deepcopy((cards, pins, definitions, coil, coils))
        mutate(c, p, d, x, xs)
        if select(c, p, d, x, xs) is not None:
            raise ValueError('selector mutation survived: ' + name)
        names.append(name + '_rejected')
    c = dict(reversed(list(cards.items())))
    p = dict(reversed(list(pins.items())))
    same(select(c, p, definitions, coil, coils), selected, 'card permutation')
    names.append('card_permutation_keeps_named_binding')
    literal = dict(body=[[0, -40], [20, -40], [20, 40], [0, 40]],
                   visible_port_mapping={
                       'outp': dict(attachment=[20, -20], endpoint=[30, -20]),
                       'outn': dict(attachment=[20, 20], endpoint=[30, 20])})
    winding = dict(n1=[90, -50], n2=[90, 50], n3=[110, 0])
    capacitor = [[60, -20], [60, 20]]
    assert complete(geometry(literal, winding, capacitor, ['outp', 'outn']))
    names.append('literal_actual_three_midpoints_and_outward_order')
    for rotation in range(4):
        for mirror in (False, True):
            def transform(point):
                x, y = point
                if mirror:
                    x = -x
                for _ in range(rotation):
                    x, y = -y, x
                return [x + 137, y - 49]
            b = copy.deepcopy(literal)
            b['body'] = [transform(p) for p in b['body']]
            for lead in b['visible_port_mapping'].values():
                for field in ('endpoint', 'attachment'):
                    lead[field] = transform(lead[field])
            w = {k: transform(p) for k, p in winding.items()}
            c = [transform(p) for p in capacitor]
            assert complete(geometry(b, w, c, ['outp', 'outn']))
    names.append('eight_actual_frame_poses_and_translation')
    for name, change in [
        ('wrong_named_end_order', lambda b, w, c: c.reverse()),
        ('shifted_coil_midpoint', lambda b, w, c: w['n1'].__setitem__(1, -40)),
        ('skew_coil_axis', lambda b, w, c: w['n1'].__setitem__(0, 95)),
        ('cap_beyond_coil', lambda b, w, c: [p.__setitem__(0, 120) for p in c]),
        ('tap_toward_block', lambda b, w, c: w['n3'].__setitem__(0, 80)),
        ('opposite_actual_output_sides', lambda b, w, c: b['visible_port_mapping']['outn'].__setitem__('attachment', [40, 20])),
        ('body_beyond_named_output', lambda b, w, c: b['body'].append([40, 0])),
    ]:
        b, w, c = copy.deepcopy((literal, winding, capacitor))
        change(b, w, c)
        try:
            valid = complete(geometry(b, w, c, ['outp', 'outn']))
        except ValueError:
            valid = False
        if valid:
            raise ValueError('geometry mutation survived: ' + name)
        names.append(name + '_rejected')
    return names


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
    for name in ['center_tap_symbols_cases.json', 'center_tap_tanks_cases.json', 'paired_amplifier_ports_cases.json']:
        found[name] = ink.digest(HERE / name)
    return dict(sorted(found.items()))


def audit(examples):
    tank_proof = tanks.audit(examples)
    same(tank_proof, json.loads((HERE / 'center_tap_tanks_cases.json').read_text()), 'fresh complete tank source evidence')
    block_proof = boxes.replay(examples)
    same(block_proof, json.loads((HERE / 'paired_amplifier_ports_cases.json').read_text()), 'fresh DA/PA actual own-lead evidence')
    _, coils, counts, hashes = ct.scan(examples)
    observations, rows, method_names = [], [], []
    for coil in coils:
        prefix = examples / coil['corpus'] / coil['id']
        text = prefix.with_suffix('.cir').read_text()
        cards = channels.read_cards(text)
        pins, _ = inputs.nodes(cards, text)
        definitions = digital.declarations(text)
        peers = [c for c in coils if c['id'] == coil['id'] and c['corpus'] == coil['corpus']]
        group = select(cards, pins, definitions, coil, peers)
        observations.append(dict(name=coil['id'] + ':' + coil['card'], selected=group is not None))
        if group is None:
            continue
        name = coil['id'] + ':' + group['block'] + ':' + group['coil'] + '--' + group['capacitor']
        tank = next(r for r in tank_proof['rows'] if r['name'] == coil['id'] + ':' + group['coil'] + '--' + group['capacitor'])
        block = next(r for r in block_proof['rows'] if (r['id'], r['card']) == (coil['id'], group['block']))
        cap = [next(r['actual_targets'][1] for r in tank['connections'] if r['port'] == port)
               for port in ('n1', 'n2')]
        observed = geometry(block, tank['actual_coil'], cap, group['block_ports'])
        if not complete(observed):
            raise ValueError('actual block/tank relation failed: ' + name)
        context = ink.load_source(examples / coil['corpus'], coil['id'])
        paths = []
        for port, net, output in zip(('n1', 'n2'), group['outer_nets'], group['block_ports']):
            targets = [block['visible_port_mapping'][output]['endpoint'], tank['actual_coil'][port]]
            segments, missing = ink.verified_segments(context['human'], net, context['ink'])
            connection = ink.source_connection(context, segments, targets)
            if not connection['continuous']:
                raise ValueError('block/tank source leg has no actual ink: ' + name + ':' + net)
            paths.append(dict(name=name + ':' + net, net=net, actual_targets=targets,
                              verified_segments=segments, missing_cache_segments=missing, connection=connection))
        rows.append(dict(name=name, group=group, source_block=block, source_tank=tank,
                         geometry=observed, block_coil_paths=paths, source_sha256=block['source_sha256']))
        method_names += methods(cards, pins, definitions, coil, peers)
    same([r['name'] for r in rows], EXPECTED, 'exact block/tank source names')
    return dict(names=EXPECTED, observations=observations, rows=rows, method_checks=method_names,
                corpus_counts=counts, corpus_sha256=hashes, dependencies=dependencies(),
                limits=['One correlated source group, not a universal output-load habit.',
                        'DA/PA remain rectangles; VSS has no source terminal geometry and is not inferred.',
                        'Capacitor/coil order and alignment are measured; no absolute distance is prescribed.',
                        'World pose must follow actual outward output leads, never declared names alone.',
                        'No native behavior or physical preservation is claimed by this source-only certificate.'])


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('examples', type=Path)
    p.add_argument('output', type=Path)
    p.add_argument('--check', action='store_true')
    args = p.parse_args()
    result = audit(args.examples)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    if args.check:
        same(result, json.loads((HERE / 'block_tanks_cases.json').read_text()), 'frozen source block/tank certificate')
    print(json.dumps(dict(names=result['names'], method_checks=result['method_checks'])))


if __name__ == '__main__':
    main()
