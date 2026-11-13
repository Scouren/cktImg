#!/usr/bin/env python3
"""Complete analog output contracts -> two-MOS banks and actual source leads.

Usage: driven_banks.py <examples-dir> <output.json> [--native DIR] [--check]

Selection reads only outer cards, declared ports and model polarity. Every
selected source output and MOS endpoint is certified against its own SVG.
A broad named-output comparison retains digital and opaque counterexamples.
Native snapshots measure existing geometry separately; no engine is invoked.
"""
import argparse
import ast
import collections
import copy
import hashlib
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import block_aliases as aliases
import digital_symbols as digital
import remaining_amplifiers as remaining
import reference_amplifiers as reference
from cross_caps import actual_glyph, conductor_ink
from thin_connectivity import junctions, source_connection, verified_segments
from mos_forms import read_cards, rail

ANALOG = frozenset('opamp icm_opamp_vdd_vss voltage_amplifier amp amp1 ea cmp comp comparator a1 ea1 aea'.split())
OUTPUTS = frozenset('vout out vo o y vea'.split())
EXPECTED = ('ag-2415:x1 ag-2418:x1 ag-2420:x1 ag-2421:x1 ag-2422:x1 ag-2423:x1 ag-2425:x1 '
            'ag-2427:x1 ag-2428:x1 ag-2434:x1 ag-2435:x1 ag-2436:x1 ag-2440:x2 ag-2441:x1 '
            'ag-2443:x1 ag-2444:x2 ag-2447:x1 ag-735:x1 ag-952:x1 ag-981:x1 ag-994:x1').split()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def dependencies():
    """Hash the complete local Python import closure, including this reader."""
    pending, found = [Path(__file__).name], {}
    while pending:
        name = pending.pop()
        if name in found:
            continue
        path = HERE / name
        found[name] = digest(path)
        for node in ast.walk(ast.parse(path.read_text())):
            modules = [n.name for n in node.names] if isinstance(node, ast.Import) else [node.module] if isinstance(node, ast.ImportFrom) else []
            for module in modules:
                local = (module or "").split(".")[0] + ".py"
                if (HERE / local).is_file() and local not in found:
                    pending.append(local)
    return dict(sorted(found.items()))


def output(family, ports):
    """Independent complete-contract oracle; ordinary VEA remains unknown."""
    if family in reference.FAMILIES and 'vref' in ports:
        roles = reference.roles(family, ports)
        return None if roles is None else roles.index('output')
    if family not in ANALOG:
        return None
    paired_vin = any(p in ports for p in ('vip', 'inp', 'in+', 'vp', 'vin+'))
    roles = aliases.contract(['inn' if p == 'vin' and paired_vin else p for p in ports])
    if roles is None or (family == 'voltage_amplifier' and roles.count('unsigned') != 1):
        return None
    return roles.index('output')


def call(words, definitions):
    index = next((i for i, word in enumerate(words) if '=' in word or word == 'params:'), len(words)) - 1
    family = words[index]
    ports = definitions[family]
    if len(ports) != index - 1:
        raise ValueError('external definition/call arity mismatch')
    return family, ports, words[1:index]


def select(cards, definitions, models):
    rows = []
    for driver, words in sorted(cards.items()):
        if driver[0] != 'x':
            continue
        family, ports, bindings = call(words, definitions)
        analog = output(family, ports)
        for index, (port, net) in enumerate(zip(ports, bindings)):
            if port not in OUTPUTS or rail(net):
                continue
            for polarity in ('nmos', 'pmos'):
                bank = sorted(n for n, w in cards.items() if n[0] == 'm' and w[2] == net and models.get(w[5]) == polarity)
                if len(bank) != 2 or any(len(set(cards[n][1:4])) != 3 or cards[n][4] == net for n in bank):
                    continue
                blockers, capacitors = [], []
                for name, w in sorted(cards.items()):
                    if name in bank:
                        continue
                    count = 4 if name[0] == 'm' else 3 if name[0] in 'qjz' else 2
                    if name[0] == 'x':
                        count = len(call(w, definitions)[2])
                    pins = [i for i, value in enumerate(w[1:count + 1]) if value == net]
                    if not pins:
                        continue
                    if name == driver and pins == [index]:
                        continue
                    if name[0] == 'c':
                        capacitors.append(name)
                    else:
                        blockers.append(dict(card=name, pins=pins))
                rows.append(dict(driver=driver, family=family, ports=ports, bindings=bindings,
                                 output_pin=index, output_port=port, net=net, bank=bank,
                                 bank_cards={n: cards[n] for n in bank},
                                 polarity=polarity, capacitors=capacitors, blockers=blockers,
                                 admitted=analog == index and not blockers))
    return rows


def side(gate, ends):
    center = [sum(p[i] for p in ends) / 2 for i in range(2)]
    delta = [gate[i] - center[i] for i in range(2)]
    if bool(delta[0]) == bool(delta[1]):
        raise ValueError('control is not cardinal to its current path')
    return ('right' if delta[0] > 0 else 'left') if delta[0] else ('down' if delta[1] > 0 else 'up')


def toward(gate, ends, driven):
    center = [sum(p[i] for p in ends) / 2 for i in range(2)]
    axis = 0 if gate[0] != center[0] else 1
    return (gate[axis] - center[axis]) * (driven[axis] - center[axis]) > 0


def source_output(human, root, row):
    device, group, parent = aliases.source_group(human, root, row['driver'])
    pins = [p for p, n in device['nets'].items() if n.lower() == row['net'] and p.lower() in OUTPUTS]
    if len(pins) != 1:
        raise ValueError('source output is not uniquely bound by its declared net and role')
    pin = pins[0]
    try:
        proof = actual_glyph(root, dict(device, terminals={pin: device['terminals'][pin]}))
        return dict(object=proof['object'], pin=pin, endpoint=proof['terminals'][pin],
                    method='declared_cached_pin_matches_actual_lead')
    except ValueError:
        body, leads, interior = aliases.primitives(group, parent)
        triangle = remaining.structure(body, leads, aliases.polarity_marks(interior))
        if triangle is not None:
            point = leads[triangle['apex_lead']]['endpoint']
            method = 'unique_actual_triangle_apex'
        else:
            found = [lead['endpoint'] for lead in leads if aliases.glyph.close(lead['endpoint'], device['terminals'][pin])]
            if len(found) != 1:
                raise ValueError('source box has no unique declared output lead')
            point, method = found[0], 'declared_cached_pin_matches_actual_box_lead'
        return dict(object=group.get('data-object-id'), pin=pin, endpoint=point, method=method)


def inspect(row, prefix):
    human = json.loads(prefix.with_suffix('.human.json').read_text())
    root = ET.parse(prefix.with_suffix('.svg')).getroot()
    devices = {d['card'].lower(): d for d in human['devices']}
    output_pin = source_output(human, root, row)
    ink, gates = conductor_ink(root), []
    context = dict(junctions=junctions(root))
    assigned, missing = verified_segments(human, row["net"], ink)
    for name in row['bank']:
        device = devices[name]
        for index, terminal in enumerate(('D', 'G', 'S'), 1):
            if device['nets'][terminal].lower() != row['bank_cards'][name][index]:
                raise ValueError('source terminal binding differs from outer card')
        proof = actual_glyph(root, device)
        p = proof['terminals']
        targets = [output_pin['endpoint'], p['G']]
        connection = source_connection(context, ink, targets)
        gates.append(dict(card=name, **proof, side=side(p['G'], [p['D'], p['S']]),
                          toward_output=toward(p['G'], [p['D'], p['S']], output_pin['endpoint']),
                          output_tree=connection['spanning_ink_segments'],
                          whole_svg_connection=connection,
                          verified_cache_connection=source_connection(context, assigned, targets)))
    return dict(output=output_pin, gates=gates, verified_named_ink=assigned,
                cached_segments_without_ink=missing,
                path_assignment='A continuous actual output-to-gate tree is bound by both verified declared endpoints; unverified cache strokes never participate. Whole-SVG absence proves negatives.',
                gate_rows_equal=gates[0]['terminals']['G'][1] == gates[1]['terminals']['G'][1],
                source_sha256={suffix: digest(prefix.with_suffix(suffix)) for suffix in ('.cir', '.svg', '.human.json')})


def native(row, directory):
    path = directory / (row['id'] + '.json')
    drawing = json.loads(path.read_text())
    devices = {d['name']: d for d in drawing['devices']}
    driver = devices[row['driver']]
    pin = driver['pins'][row['output_pin']]
    if pin['term'] != row['output_port'] or pin['net'] != row['net']:
        raise ValueError('native output order/binding differs')
    gates = []
    for name in row['bank']:
        p = {p['term']: p['xy'] for p in devices[name]['pins']}
        gates.append(dict(card=name, terminals=p, side=side(p['g'], [p['d'], p['s']]),
                          toward_output=toward(p['g'], [p['d'], p['s']], pin['xy'])))
    return dict(geometry_sha256=digest(path), output=pin['xy'], gates=gates)


def checks():
    names = []
    for name, family, ports, expected in (
        ('signed_contract', 'opamp', ['vdd', 'vss', 'inp', 'inn', 'out'], 4),
        ('paired_vin', 'icm_opamp_vdd_vss', ['vdd', 'vss', 'vip', 'vin', 'vout'], 4),
        ('contextual_vea', 'error_amplifier', ['vss', 'vref', 'vea'], 2),
        ('ordinary_vea_unknown', 'opamp', ['inp', 'inn', 'vea'], None),
        ('digital_excluded', 'inverter', ['a', 'y'], None),
        ('opaque_excluded', 'opamp', ['inp', 'inn', 'out', 'vx'], None),
        ('duplicate_output_excluded', 'aea', ['vref', 'out', 'vea'], None)):
        if output(family, ports) != expected:
            raise ValueError(name)
        names.append(name)
    definitions = {'opamp': ['inp', 'inn', 'out']}
    models = {'pch': 'pmos'}
    cards = {n: line.split() for n, line in (
        ('m1', 'm1 a gate vdd vdd pch'), ('m2', 'm2 b gate vdd vdd pch'),
        ('x1', 'x1 ref feedback gate opamp'))}
    baseline = select(cards, definitions, models)
    assert len(baseline) == 1 and baseline[0]['admitted']
    assert select(dict(reversed(list(cards.items()))), definitions, models) == baseline
    names.extend(('two_distinct_gate_channels', 'card_permutation'))
    for name, additions, admitted in (
        ('capacitor_load_allowed', {'c1': 'c1 gate feedback 1p'}, True),
        ('second_output_rejected', {'x2': 'x2 ref other gate opamp'}, False),
        ('channel_driver_rejected', {'m3': 'm3 gate other vdd vdd pch'}, False),
        ('third_gate_rejected', {'m3': 'm3 c gate vdd vdd pch'}, False),
        ('gate_body_alias_rejected', {'m1': 'm1 a gate vdd gate pch'}, False)):
        changed = copy.deepcopy(cards)
        changed.update({n: line.split() for n, line in additions.items()})
        if any(r['admitted'] for r in select(changed, definitions, models)) != admitted:
            raise ValueError(name)
        names.append(name)
    assert toward([0, 10], [[20, 0], [20, 20]], [-40, 10])
    assert not toward([40, 10], [[20, 0], [20, 20]], [-40, 10])
    names.append('actual_gate_reflection_changes_facing')
    crossing = [[[0, 0], [20, 0]], [[10, -10], [10, 10]]]
    targets = [[0, 0], [10, 10]]
    for name, svg, expected in (
        ('proper_crossing_without_dot_is_separate', '<svg/>', False),
        ('actual_contact_dot_joins_crossing', '<svg><circle data-node-kind="contact" cx="10" cy="0" r="2"/></svg>', True),
        ('off_crossing_dot_does_not_join', '<svg><circle data-node-kind="contact" cx="10" cy="1" r="2"/></svg>', False)):
        result = source_connection(dict(junctions=junctions(ET.fromstring(svg))), crossing, targets)
        if result['continuous'] != expected:
            raise ValueError(name)
        names.append(name)
    return names


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('examples', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--native', type=Path)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    rows, hashes, counts = [], {}, {}
    for corpus in ('analoggenie', 'amsnet'):
        directory = args.examples / corpus
        paths = sorted(directory.glob('*.human.json'))
        if not paths:
            raise ValueError('missing corpus ' + corpus)
        counts[corpus] = len(paths)
        hashed = hashlib.sha256()
        for hp in paths:
            cid = hp.name.removesuffix('.human.json')
            prefix = directory / cid
            text = prefix.with_suffix('.cir').read_text()
            for suffix in ('.cir', '.human.json', '.svg'):
                hashed.update((cid + suffix).encode() + bytes.fromhex(digest(prefix.with_suffix(suffix))))
            models = {w[1]: w[2] for line in text.lower().splitlines() if (w := line.split()) and w[0] == '.model'}
            selected = select(read_cards(text), digital.declarations(text), models)
            for row in selected:
                row.update(id=cid, corpus=corpus)
                row['source'] = inspect(row, prefix)
                rows.append(row)
        hashes[corpus] = hashed.hexdigest()
    chosen = [r for r in rows if r['admitted']]
    names = [r['id'] + ':' + r['driver'] for r in chosen]
    if names != EXPECTED:
        raise ValueError('exact source inventory changed')
    if any(g['side'] != 'left' or not g['toward_output'] for r in chosen for g in r['source']['gates']):
        raise ValueError('selected actual source facing changed')
    result = dict(method_checks=checks(), corpus_counts=counts, corpus_sha256=hashes, selected_names=names,
                  summary=dict(selected_banks=len(chosen), selected_gates=2 * len(chosen), broad_candidates=len(rows),
                               equal_source_gate_rows=sum(r['source']['gate_rows_equal'] for r in chosen)),
                  rows=rows, limits='Observed gate facing only. Seventeen selected banks occupy unequal source rows; no row or universal physical-connectivity policy is inferred. Digital and opaque comparison rows are retained but excluded.')
    result['dependency_sha256'] = dependencies()
    result = json.loads(json.dumps(result))
    if args.check:
        if result != json.loads((HERE / 'driven_banks_cases.json').read_text()):
            raise ValueError('every frozen source evidence field must match')
    if args.native:
        result['native'] = [dict(name=r['id'] + ':' + r['driver'], **native(r, args.native)) for r in chosen]
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    print(json.dumps(result['summary'], sort_keys=True))


if __name__ == '__main__':
    main()
