#!/usr/bin/env python3
"""Source-only census: complementary mirror chain feeding a CT oscillator.

Usage: ct_mirror_controls.py <examples-root> <output.json> [--check]

Selection uses complete declared incidences, never source layout or
circuit/device names. Actual SVG leads and conductor ink independently
certify the two source intervals; only the output pair nominates a native
full-cost tie. This is one figure, not a universal mirror routing rule.
"""
from pathlib import Path
import argparse
import ast
import collections
import copy
import json
import sys

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import center_tap_symbols as ct
import channel_bridges as channels
import input_resistors as reader
import thin_connectivity as ink
import block_aliases as aliases


def same(a, b, context):
    if json.loads(json.dumps(a)) != json.loads(json.dumps(b)):
        raise ValueError(context)


def dependencies():
    pending, found = [Path(__file__).name], {}
    while pending:
        name = pending.pop()
        if name in found:
            continue
        path = HERE / name
        found[name] = ink.digest(path)
        for node in ast.walk(ast.parse(path.read_text())):
            modules = [n.name for n in node.names] if isinstance(node, ast.Import) else [node.module] if isinstance(node, ast.ImportFrom) else []
            for module in modules:
                local = (module or "").split(".")[0] + ".py"
                if (HERE / local).is_file() and local not in found:
                    pending.append(local)
    found["center_tap_symbols_cases.json"] = ink.digest(HERE / "center_tap_symbols_cases.json")
    return dict(sorted(found.items()))


def select(cards, pins, models, coils):
    # Count every declared pin, including controls and hidden bodies, first.
    incidence = collections.defaultdict(list)
    for name, ps in pins.items():
        for index, net in enumerate(ps):
            incidence[net].append((name, index))
    mirrors = []
    gates = collections.defaultdict(list)
    for name, ps in pins.items():
        if name[0] == 'm' and len(ps) >= 3:
            gates[ps[1]].append(name)
    for gate, names in gates.items():
        if len(names) != 2:
            continue
        refs = [name for name in names if pins[name][0] == gate]
        if len(refs) != 1:
            continue
        reference = refs[0]
        output = next(name for name in names if name != reference)
        a, b = pins[reference], pins[output]
        if len(a) != 4 or len(b) != 4 or a[2:] != b[2:] or a[2] != a[3]:
            continue
        kind = models.get(cards[reference][5])
        if kind not in ('nmos', 'pmos') or models.get(cards[output][5]) != kind:
            continue
        if channels.rail(a[2]) != ('sink' if kind == 'nmos' else 'supply'):
            continue
        if len({gate, b[0], a[2]}) != 3 or channels.rail(gate) or channels.rail(b[0]):
            continue
        mirrors.append(dict(reference=reference, output=output, gate=gate,
                            drain=b[0], rail=a[2], kind=kind))
    result = []
    for output in mirrors:
        previous = [m for m in mirrors if m['drain'] == output['gate']]
        if len(previous) != 1:
            continue
        reference = previous[0]
        if reference['kind'] == output['kind']:
            continue
        bridge = sorted([(output['reference'], 0), (output['reference'], 1),
                         (output['output'], 1), (reference['output'], 0)])
        if sorted(incidence[output['gate']]) != bridge:
            continue
        load_ends = [(name, index) for name, index in incidence[output['drain']]
                     if name != output['output']]
        if len(load_ends) != 2 or any(name[0] != 'm' or index != 2 for name, index in load_ends):
            continue
        x, y = sorted(name for name, index in load_ends)
        a, b = pins[x], pins[y]
        if x == y or len(a) != 4 or len(b) != 4 or a[3] != output['rail'] or b[3] != output['rail']:
            continue
        if any(models.get(cards[name][5]) != output['kind'] for name in (x, y)):
            continue
        if a[0] != b[1] or b[0] != a[1] or a[0] == b[0]:
            continue
        outer = [a[0], b[0]]
        matched = [c for c in coils if {dict(zip(c['ports'], c['bindings']))[p]
                   for p in ('n1', 'n2')} == set(outer)]
        if len(matched) != 1:
            continue
        coil = matched[0]
        tap = dict(zip(coil['ports'], coil['bindings']))['n3']
        nonrails = [reference['gate'], output['gate'], output['drain'], *outer, tap]
        if len(set(nonrails)) != 6 or any(channels.rail(net) for net in nonrails):
            continue
        members = [reference['reference'], reference['output'], output['reference'],
                   output['output'], x, y, coil['card']]
        if len(set(members)) != 7:
            continue
        result.append(dict(reference=reference, output=output, load=[x, y],
                           coil=coil['card'], outer=outer, tap=tap, members=members,
                           bridge_incidence=bridge, load_incidence=sorted(incidence[output['drain']])))
    return result


def audit(examples):
    unknown, coils, counts, contracts = ct.scan(examples)
    inventory = json.loads((HERE / 'center_tap_symbols_cases.json').read_text())
    same(unknown, inventory['unknown_outer_families'], 'CT excluded contracts changed')
    same(counts, inventory['corpus_drawings'], 'CT corpus counts changed')
    same(contracts, inventory['corpus_contract_sha256'], 'CT corpus hashes changed')
    by = collections.defaultdict(list)
    for c in coils:
        by[c['corpus'], c['id']].append(c)
    selected, scope, primitive_count = [], {}, 0
    for corpus in ('analoggenie', 'amsnet'):
        hashes = {}
        for path in sorted((examples / corpus).glob('*.human.json')):
            ident = path.name.removesuffix('.human.json')
            text = path.with_name(ident + '.cir').read_text()
            cards = ink.read_cards(text)
            pins, models = reader.nodes(cards, text)
            for d in json.loads(path.read_text())['devices']:
                if d['card'][0] not in 'mq':
                    continue
                name = d['card']
                names = ('D', 'G', 'S') if name[0] == 'm' else ('C', 'B', 'E')
                assert [d['nets'][n].lower() for n in names] == pins[name][:3]
                assert models[cards[name][len(pins[name]) + 1]] == d['type']
                primitive_count += 1
            hashes[ident] = {suffix: ink.digest(path.with_name(ident + suffix))
                            for suffix in ('.cir', '.human.json', '.svg')}
            selected.extend(dict(row, id=ident, corpus=corpus)
                            for row in select(cards, pins, models, by[corpus, ident]))
        scope[corpus] = dict(names=sorted(hashes), sha256=hashes,
                             index_sha256=ink.digest(examples / corpus / 'index.json'))
    assert primitive_count == 25103
    assert [(r['id'], r['members']) for r in selected] == [
        ('ag-1146', ['m1', 'm2', 'm3', 'm4', 'm5', 'm6', 'x1'])]
    row = selected[0]
    ctx = ink.load_source(examples / row['corpus'], row['id'])
    ctx['human']['wires'] = [w for w in ctx['human']['wires'] if w['net'] is not None]
    text = (examples / row['corpus'] / (row['id'] + '.cir')).read_text()
    pins, models = reader.nodes(ctx['cards'], text)
    glyphs = {name: ink.actual_glyph(ctx['root'], ctx['devices'][name])
              for name in row['members'][:-1]}
    _, group, parent = aliases.source_group(ctx['human'], ctx['root'], row['coil'])
    glyphs[row['coil']] = dict(terminals=ct.center_tap_ink(ct.primitives(group, parent)))
    inventory_path = HERE / 'center_tap_symbols_cases.json'
    frozen = [c for c in json.loads(inventory_path.read_text())['selected']
              if (c['corpus'], c['id'], c['card']) == (row['corpus'], row['id'], row['coil'])]
    assert len(frozen) == 1
    frozen = frozen[0]
    fresh = next(c for c in by[row['corpus'], row['id']] if c['card'] == row['coil'])
    for field in ('ports', 'bindings', 'family'):
        assert fresh[field] == frozen[field], field
    assert dict(zip(fresh['ports'], fresh['bindings'])) == frozen['bindings_by_port']
    assert {name: list(point) for name, point in glyphs[row['coil']]['terminals'].items()} == frozen['actual_terminals']
    assert pins[row['coil']] == frozen['bindings']
    assert {suffix: ctx['source_sha256'][row['id'] + suffix]
            for suffix in frozen['source_sha256']} == frozen['source_sha256']
    paths = []
    for mirror in (row['reference'], row['output']):
        targets = [glyphs[mirror[k]]['terminals']['G'] for k in ('reference', 'output')]
        assert targets[0][1] == targets[1][1] and targets[0][0] != targets[1][0]
        segments, missing = ink.verified_segments(ctx['human'], mirror['gate'], ctx['ink'])
        straight = [s for s in segments if s[0][1] == s[1][1] == targets[0][1]]
        proof = ink.source_connection(ctx, straight, targets)
        assert proof['continuous']
        paths.append(dict(net=mirror['gate'], targets=targets, straight=proof, cache_only=missing))
    methods = []
    changes = [
        ('third_unknown_gate', lambda c, p, m, cs: (c.update(mextra=['mextra']), p.update(mextra=['unused', 'net1', 'other', 'vdd']))),
        ('hidden_gate_incidence', lambda c, p, m, cs: p['m7'].__setitem__(3, 'net1')),
        ('third_load_source', lambda c, p, m, cs: (c.update(mextra=['mextra']), p.update(mextra=['unused', 'g', 'net2', 'vdd']))),
        ('foreign_load_control', lambda c, p, m, cs: p['m7'].__setitem__(1, 'net2')),
        ('duplicate_winding', lambda c, p, m, cs: cs.append(dict(cs[0], card='xextra'))),
        ('unknown_mirror_model', lambda c, p, m, cs: c['m4'].__setitem__(5, 'unknown')),
        ('unknown_load_model', lambda c, p, m, cs: c['m5'].__setitem__(5, 'unknown')),
        ('load_not_reciprocal', lambda c, p, m, cs: p['m5'].__setitem__(1, 'elsewhere')),
        ('body_not_shared_rail', lambda c, p, m, cs: p['m3'].__setitem__(3, 'elsewhere')),
        ('tap_alias', lambda c, p, m, cs: cs[0]['bindings'].__setitem__(2, 'net1')),
    ]
    for name, mutation in changes:
        c, p, m, cs = copy.deepcopy((ctx['cards'], pins, models, by[row['corpus'], row['id']]))
        mutation(c, p, m, cs)
        assert not select(c, p, m, cs), name
        methods.append(name)
    assert select(dict(reversed(list(ctx['cards'].items()))), dict(reversed(list(pins.items()))),
                  models, by[row['corpus'], row['id']]) == [dict((k, v) for k, v in row.items() if k not in ('id', 'corpus'))]
    methods.append('card_order')
    out = dict(scope=scope, primitive_bindings=primitive_count, selected=selected,
               actual_glyphs=glyphs, paths=paths, methods=methods,
               coil_certificate=dict(ports=fresh['ports'], bindings=fresh['bindings'],
                                     bindings_by_port=frozen['bindings_by_port'],
                                     actual_terminals=frozen['actual_terminals'],
                                     inventory_sha256=ink.digest(inventory_path)),
               script_sha256=ink.digest(Path(__file__)),
               limits=['One correlated seven-device stage in one source figure.',
                       'Only the two selected actual gate intervals are certified straight here.',
                       'No global preference, cost credit, exact spacing or world orientation is inferred.'])
    out['dependency_sha256'] = dependencies()
    out['selected_names'] = [r['corpus'] + ':' + r['id'] + ':' + '/'.join(r['members']) for r in selected]
    same(out['selected_names'], ['analoggenie:ag-1146:m1/m2/m3/m4/m5/m6/x1'], 'selected names')
    out['summary'] = dict(selected_figures=len(selected), source_straight_intervals=len(paths), primitive_bindings=primitive_count, methods=len(methods))
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('examples', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    result = audit(args.examples)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    if args.check:
        same(result, json.loads((HERE / 'ct_mirror_controls_cases.json').read_text()), 'frozen mirror-control evidence changed')
    print(json.dumps(result['summary'], sort_keys=True))


if __name__ == '__main__':
    main()
