#!/usr/bin/env python3
"""Actual source and native center-tapped winding/lead/disk certificates.

Usage: center_tap_native.py EXAMPLES WORK OUTPUT --curve-proof JSON
       --baseline-bin BIN --candidate-bin BIN
       --baseline-corpus AG --baseline-corpus AMS
       --candidate-corpus AG --candidate-corpus AMS [--require-glyph] [--check]
       [--expected-outside JSON]

All native records come from existing binaries and complete scored corpora.
Named source terminals are independently bound to actual source SVG leads.
Native winding endpoints, center bridge and solid disk are observed in SVG,
not inferred from a class name. Curve distance concerns centerlines only.
Other routing repairs require an explicit exact-name drawing/report manifest;
that manifest does not waive the independent complete source-continuity gate.
"""
import argparse
import ast
import copy
import hashlib
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import center_tap_symbols as source
import center_tap_curve_measure as curves
import center_tap_curves as certificate
import block_aliases_native as glyph
import driven_banks_native as corpus
import remaining_amplifiers_native as renderer

PATHS = ['0e036faf054f5c1384b8e77d6418a8a76efcb855f0cdf10b55f897893b22b6e0',
         'a2613494f578a215cefc1c7f9e3f9b9208b3bfb11f82c86c7306456716e08267']


def same(a, b, name):
    renderer.same(a, b, name)


def outside_scope(changes, scope, expected):
    same(sorted(expected), ['drawings', 'reports'], 'outside-scope manifest fields')
    actual = {}
    for kind in ('drawings', 'reports'):
        same(expected[kind], sorted(set(expected[kind])), 'outside-scope sorted unique names: '+kind)
        actual[kind] = sorted(set(changes[kind])-set(scope))
        same(actual[kind], expected[kind], 'exact outside-scope change names: '+kind)
    return actual


def dependencies():
    pending, found = [Path(__file__).name], {}
    while pending:
        name = pending.pop()
        if name in found:
            continue
        path = HERE/name
        found[name] = corpus.digest(path)
        for node in ast.walk(ast.parse(path.read_text())):
            modules = [n.name for n in node.names] if isinstance(node, ast.Import) else [node.module] if isinstance(node, ast.ImportFrom) else []
            for module in modules:
                local = (module or '').split('.')[0]+'.py'
                if (HERE/local).is_file() and local not in found:
                    pending.append(local)
    return dict(sorted(found.items()))


def compact(parts, paths):
    parts = copy.deepcopy(parts)
    for part in parts:
        if part['tag'] != 'path':
            continue
        data, commands = part.pop('path'), part.pop('commands')
        key = hashlib.sha256(data.encode()).hexdigest()
        same(dict(path=data, commands=commands), paths[key], 'actual source cubic path')
        vertices = part.pop('control_vertices')
        part.update(actual_endpoints=[vertices[0], vertices[-1]], path_sha256=key)
        del part['attributes']['d']
    return parts


def replay_source(examples):
    inventory = json.loads((HERE/'center_tap_symbols_cases.json').read_text())
    for name, expected in inventory['audit_sha256'].items():
        same(corpus.digest(HERE/name), expected, 'frozen source extractor '+name)
    unknown, selected, counts, hashes = source.scan(examples)
    same(unknown, inventory['unknown_outer_families'], 'complete source outer-family names')
    same(counts, inventory['corpus_drawings'], 'complete source corpus names')
    same(hashes, inventory['corpus_contract_sha256'], 'source corpus content')
    rows = []
    originals = {r['id']+':'+r['card']: r for r in inventory['selected']}
    for row in selected:
        prefix = examples/row['corpus']/row['id']
        human = json.loads(prefix.with_suffix('.human.json').read_text())
        root = ET.parse(prefix.with_suffix('.svg')).getroot()
        device, group, parent = source.aliases.source_group(human, root, row['card'])
        parts = source.primitives(group, parent)
        actual = source.center_tap_ink(parts)
        cached = {'n'+p: xy for p, xy in device['terminals'].items()}
        bound = {'n'+p: n.lower() for p, n in device['nets'].items()}
        same(bound, dict(zip(row['ports'], row['bindings'])), 'actual source named bindings')
        if any(not source.glyph.close(cached[p], actual[p]) for p in row['ports']):
            raise ValueError('actual source lead differs from declared source pin')
        header, remainder = prefix.with_suffix('.cir').read_text().lower().split('.subckt ct_inductor ', 1)[1].split('\n', 1)
        body = [line.split() for line in remainder.split('.ends', 1)[0].splitlines() if line.strip()]
        same(body, source.BODY, 'actual winding-to-midpoint electrical body')
        value = dict(row, source_object=group.get('data-object-id'), actual_terminals=actual,
            cached_terminals=cached, bindings_by_port=bound, pin_mapping_verified=True,
            horizontal=actual['n1'][1] == actual['n2'][1],
            tap_direction=source.glyph.direction(source.glyph.point(parts[0]['transform'], (0, 0)), actual['n3']),
            primitives=compact(parts, inventory['source_paths']), subcircuit_header=header, subcircuit_body=body,
            source_sha256={s: corpus.digest(prefix.with_suffix(s)) for s in ('.cir', '.human.json', '.svg')})
        expected = {k: v for k, v in originals[row['id']+':'+row['card']].items() if k not in ('native', 'native_sha256')}
        same(value, expected, 'every source evidence field '+row['id']+':'+row['card'])
        rows.append(value)
    same(sorted(r['id']+':'+r['card'] for r in rows), source.EXPECTED, 'exact source instance names')
    same(source.checks(parts), source.EXPECTED_CHECKS, 'named source mutation checks')
    return rows, inventory


def bound_device(drawing, row):
    devices = [d for d in drawing['devices'] if d['name'] == row['card']]
    if len(devices) != 1:
        raise ValueError('no unique named native device')
    device = devices[0]
    same([(p['term'], p['net']) for p in device['pins']], list(zip(row['ports'], row['bindings'])), 'every ordered native binding')
    return device


def native(drawing, root, row):
    device = bound_device(drawing, row)
    scale, offset, ink = glyph.frame(drawing, root)
    tolerance = glyph.PIXEL_TOLERANCE/scale
    world = lambda p: [(p[i]-offset[i])/scale for i in range(2)]
    def integer(p):
        local = glyph.inverse(device, world(p))
        result = [round(v) for v in local]
        if not glyph.near(local, result, tolerance):
            raise ValueError('native SVG point disagrees with integer public coordinates')
        return result
    pins = {p['term']: list(glyph.inverse(device, p['xy'])) for p in device['pins']}
    a, b, tap = [pins[p] for p in ('n1', 'n2', 'n3')]
    if not (a[1] == b[1] and a[0] < tap[0] < b[0] and tap[1] > a[1] and 2*tap[0] == a[0]+b[0]):
        raise ValueError('native named midpoint/outer terminal geometry differs')
    joint = [tap[0], a[1]]
    polys = [(i, [integer(p) for p in glyph.points(node)]) for i, node in enumerate(ink) if glyph.tag(node) == 'polyline']
    leads = {}
    for name, endpoint in pins.items():
        matches = []
        for index, ps in polys:
            if len(ps) != 2 or endpoint not in ps:
                continue
            end = ps[1] if ps[0] == endpoint else ps[0]
            valid = end == joint if name == 'n3' else end[1] == joint[1] and min(endpoint[0], joint[0]) < end[0] < max(endpoint[0], joint[0])
            if valid:
                matches.append(dict(index=index, endpoint=endpoint, attachment=end, net=row['bindings'][row['ports'].index(name)]))
        if len(matches) != 1:
            raise ValueError('no unique own actual lead '+name)
        leads[name] = matches[0]
    bridges = [(i, ps) for i, ps in polys if len(ps) == 2 and ps[0][1] == ps[1][1] == joint[1]
               and min(ps[0][0], ps[1][0]) < joint[0] < max(ps[0][0], ps[1][0])]
    bridges = [(i, ps) for i, ps in bridges if all(a[0] < p[0] < b[0] for p in ps)]
    if len(bridges) != 1:
        raise ValueError('no unique actual midpoint bridge')
    bridge_index, bridge = bridges[0]
    coils = []
    for name, sign in (('n1', -1), ('n2', 1)):
        outer = leads[name]['attachment']
        matches = []
        for index, ps in polys:
            if not 4 <= len(ps) < 64 or ps[0] == ps[-1]:
                continue
            sequence = ps if ps[0] == outer else ps[::-1] if ps[-1] == outer else None
            if sequence is None or not glyph.edge_point(sequence[-1], *bridge, .001):
                continue
            if not all(sign*(p[0]-joint[0]) > 0 for p in ps):
                continue
            canonical = ps if ps[0][0] < ps[-1][0] else ps[::-1]
            deltas = [v[1]-u[1] for u, v in zip(canonical, canonical[1:]) if v[1] != u[1]]
            reversals = sum(x*y < 0 for x, y in zip(deltas, deltas[1:]))
            backward = sum(v[0] < u[0] for u, v in zip(canonical, canonical[1:]))
            if reversals >= 3 and backward:
                matches.append(dict(index=index, points=canonical, reversals=reversals, backward_segments=backward))
        if len(matches) != 1:
            raise ValueError('no unique connected looped winding '+name)
        coils.append(matches[0])
    disks = []
    for index, node in enumerate(ink):
        if glyph.tag(node) != 'circle':
            continue
        center = integer([float(node.get('cx')), float(node.get('cy'))])
        if center != joint:
            continue
        fill = node.get('fill', 'none').lower()
        if fill in ('none', 'transparent', 'white', '#fff', '#ffffff') or float(node.get('r')) <= 0:
            raise ValueError('native midpoint disk is hollow or missing')
        disks.append(dict(index=index, center=center, radius=float(node.get('r'))/scale,
                          fill=fill, stroke=node.get('stroke', 'inherited')))
    if len(disks) != 1:
        raise ValueError('no unique actual filled midpoint disk')
    indexes = [v['index'] for v in leads.values()]+[bridge_index]+[v['index'] for v in coils]+[disks[0]['index']]
    if len(set(indexes)) != len(indexes):
        raise ValueError('one stroke was borrowed for two independent symbol parts')
    world_pins = {p['term']:p['xy'] for p in device['pins']}
    return dict(shape='center_tap', terminals=pins, leads=leads, bridge=dict(index=bridge_index, points=bridge),
                coils=coils, disk=disks[0], scale=scale, offset=offset, integer_svg_tolerance=tolerance,
                horizontal=world_pins['n1'][1] == world_pins['n2'][1],
                tap_direction=source.glyph.direction(device['pos'], world_pins['n3']))


def curve_certificate(observed, inventory, proof):
    same(observed['terminals'], dict(n1=[-50, 0], n2=[50, 0], n3=[0, 20]), 'default canonical named terminal locations')
    if abs(observed['disk']['radius']-proof['radius']['integer']) > observed['integer_svg_tolerance']:
        raise ValueError('actual midpoint disk radius differs from the source-certified approximation')
    results = []
    for i, coil in enumerate(observed['coils']):
        expected = [[x+50*i, y] for x, y in proof['coils']['table']]
        same(coil['points'], expected, 'actual full winding versus source-certified table')
        path = inventory['source_paths'][PATHS[i]]['path']
        result = curves.measure(path, tuple(map(tuple, coil['points'])))
        bound = proof['coils']['hausdorff_upper_decimal']
        if result['upper'] > bound:
            raise ValueError('independent actual curve distance exceeds source certificate')
        results.append(dict(source_path_sha256=PATHS[i], observed_numerical_interval=result, certified_upper=bound))
    return results


def methods(inventory, proof):
    row = dict(card='x1', ports=['n1', 'n2', 'n3'], bindings=['a', 'b', 'tap'])
    drawing = dict(devices=[dict(name='x1', pos=[0, 0], rot=0, mirror=False, pins=[
        dict(term=t, net=n, xy=p) for t, n, p in zip(row['ports'], row['bindings'], ([-50, 0], [50, 0], [0, 20]))])],
        wires=[dict(segments=[[[-100, -100], [-100, 100], [100, 100]]])])
    root = ET.fromstring('<svg><g><polyline points="-100,-100 -100,100 100,100"/></g></svg>')
    for ps in ([[-50, 0], [-45, 0]], [[45, 0], [50, 0]], [[-5, 0], [5, 0]], [[0, 0], [0, 20]],
               proof['coils']['table'], [[x+50, y] for x, y in proof['coils']['table']]):
        ET.SubElement(root[0], 'polyline', points=' '.join(f'{x},{y}' for x, y in ps))
    ET.SubElement(root[0], 'circle', cx='0', cy='0', r='4', fill='#1d2330', stroke='none')
    value = native(drawing, root, row)
    curve_certificate(value, inventory, proof)
    names = curves.methods()+['literal_complete_named_windings_leads_and_solid_disk']
    order = [2, 0, 1]
    reordered = dict(row, ports=[row['ports'][i] for i in order], bindings=[row['bindings'][i] for i in order])
    permuted = copy.deepcopy(drawing)
    permuted['devices'][0]['pins'] = [drawing['devices'][0]['pins'][i] for i in order]
    same(native(permuted, root, reordered), value, 'actual geometric identity after declaration permutation')
    names.append('declaration_permutation_retains_named_geometry')
    transforms = [(1, 0, 0, 1), (0, -1, 1, 0), (-1, 0, 0, -1), (0, 1, -1, 0),
                  (-1, 0, 0, 1), (0, -1, -1, 0), (1, 0, 0, -1), (0, 1, 1, 0)]
    for index, (xx, xy, yx, yy) in enumerate(transforms):
        transform = lambda p: [xx*p[0]+xy*p[1], yx*p[0]+yy*p[1]]
        d, r = copy.deepcopy(drawing), copy.deepcopy(root)
        d['devices'][0].update(rot=index%4, mirror=index >= 4)
        for pin in d['devices'][0]['pins']:
            pin['xy'] = transform(pin['xy'])
        d['wires'][0]['segments'][0] = [transform(p) for p in d['wires'][0]['segments'][0]]
        for node in r[0]:
            if glyph.tag(node) == 'polyline':
                node.set('points', ' '.join(f'{x},{y}' for x, y in map(transform, glyph.points(node))))
        observed = native(d, r, row)
        for key in ('terminals', 'leads', 'bridge', 'coils', 'disk'):
            same(observed[key], value[key], 'actual ink under transform '+str(index))
    names.append('all_eight_literal_transforms_preserve_actual_ink')
    changed = copy.deepcopy(proof['coils']['table'])
    changed[6][1] -= 4
    measured = curves.measure(inventory['source_paths'][PATHS[0]]['path'], tuple(map(tuple, changed)))
    if measured['lower'] <= proof['coils']['hausdorff_upper_decimal']:
        raise ValueError('independent curve measurement missed interior displacement')
    names.append('curve_interior_distance_exceeds_independent_bound')
    def swap_outer_tap(d, _):
        pins = d['devices'][0]['pins']
        pins[1]['xy'], pins[2]['xy'] = pins[2]['xy'], pins[1]['xy']
    for name, mutate in (
        ('wrong_declared_net_rejected', lambda d, r: d['devices'][0]['pins'][2].update(net='wrong')),
        ('n2_n3_swap_rejected', swap_outer_tap),
        ('detached_winding_rejected', lambda d, r: r[0][5].set('points', r[0][5].get('points').replace('-45,0', '-45,1', 1))),
        ('missing_winding_rejected', lambda d, r: r[0].remove(r[0][5])),
        ('hollow_dot_rejected', lambda d, r: r[0][-1].set('fill', '#ffffff')),
        ('too_small_dot_rejected', lambda d, r: r[0][-1].set('r', '1')),
        ('too_large_dot_rejected', lambda d, r: r[0][-1].set('r', '9')),
        ('displaced_dot_rejected', lambda d, r: r[0][-1].set('cx', '1')),
        ('curve_interior_mutation_rejected', lambda d, r: r[0][5].set('points', r[0][5].get('points').replace('-34,-7', '-34,-11', 1)))):
        d, r = copy.deepcopy(drawing), copy.deepcopy(root)
        mutate(d, r)
        try:
            curve_certificate(native(d, r, row), inventory, proof)
        except ValueError:
            names.append(name)
        else:
            raise ValueError('native certificate accepted '+name)
    changed = dict(drawings=['ag-selected', 'ag-routing'], reports=['ag-selected'])
    expected = dict(drawings=['ag-routing'], reports=[])
    same(outside_scope(changed, ['ag-selected'], expected), expected, 'literal outside-scope identities')
    names.append('exact_outside_scope_drawing_and_report_names')
    for name, bad in (
        ('unexpected_outside_change_rejected', dict(drawings=[], reports=[])),
        ('unexpected_outside_repair_rejected', dict(drawings=['ag-routing', 'ag-stale'], reports=[])),
        ('outside_drawing_report_swap_rejected', dict(drawings=[], reports=['ag-routing']))):
        try:
            outside_scope(changed, ['ag-selected'], bad)
        except ValueError:
            names.append(name)
        else:
            raise ValueError('outside-scope certificate accepted '+name)
    return names


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('examples', 'work', 'output'):
        parser.add_argument(name, type=Path)
    for stage in ('baseline', 'candidate'):
        parser.add_argument('--'+stage+'-bin', type=Path, required=True)
        parser.add_argument('--'+stage+'-corpus', type=Path, action='append', required=True)
    parser.add_argument('--curve-proof', type=Path, required=True)
    parser.add_argument('--require-glyph', action='store_true')
    parser.add_argument('--expected-outside', type=Path,
                        help='exact sorted drawings/reports outside the selected source family; default is empty')
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    rows, inventory = replay_source(args.examples)
    proof = json.loads(args.curve_proof.read_text())
    same(proof['source_inventory_sha256'], corpus.digest(HERE/'center_tap_symbols_cases.json'), 'curve proof source inventory')
    same(proof['selected_names'], source.EXPECTED, 'curve proof exact instance names')
    same(proof['source_path_sha256'], PATHS, 'curve proof exact cubic paths')
    same(proof['audit_sha256'], corpus.digest(Path(certificate.__file__)), 'curve certificate reader')
    original = certificate.source_path(inventory, PATHS[0])
    generated = certificate.certify(original)
    certificate.verify(original, generated)
    same(certificate.encode(generated), proof['coils'], 'complete rational source-curve certificate')
    same(certificate.runtime_table(certificate.IMPLEMENTATION.read_text()), generated['table'], 'actual runtime winding table')
    same(certificate.checks(original, generated), proof['method_checks'], 'exact curve-certificate mutation names')
    method_checks = methods(inventory, proof)
    args.work.mkdir(parents=True, exist_ok=True)
    corpora, directories = {}, {}
    for stage in ('baseline', 'candidate'):
        ds = getattr(args, stage+'_corpus')
        if len(ds) != 2:
            raise ValueError('both complete AG/AMS corpora are required')
        values, by_name = [], {}
        for directory in ds:
            ids = json.loads((directory/'scorecard.json').read_text())['ids']
            name = 'analoggenie' if all(i.startswith('ag-') for i in ids) else 'amsnet'
            if name in by_name:
                raise ValueError('duplicate corpus')
            by_name[name] = directory
            values.append(corpus.corpus(args.examples/name, directory, getattr(args, stage+'_bin')))
        same(sorted(by_name), ['amsnet', 'analoggenie'], 'complete corpora')
        corpora[stage], directories[stage] = sorted(values, key=lambda v:v['corpus']), by_name
    changes = dict(drawings=[], reports=[])
    for old, new in zip(corpora['baseline'], corpora['candidate']):
        same(old['corpus'], new['corpus'], 'paired corpus')
        same(old['inputs'], new['inputs'], 'paired scored inputs')
        for a, b in zip(old['rows'], new['rows']):
            same(a['id'], b['id'], 'paired source identity')
            for field in ('deck_sha256', 'source_sha256', 'preview_sha256'):
                same(a[field], b[field], 'paired source '+field)
            for kind, field in (('drawings', 'geometry_sha256'), ('reports', 'report_sha256')):
                if a[field] != b[field]:
                    changes[kind].append(a['id'])
    scope = {r['id'] for r in rows}
    for kind in changes:
        changes[kind].sort()
    expected_outside = json.loads(args.expected_outside.read_text()) if args.expected_outside else dict(drawings=[], reports=[])
    actual_outside = outside_scope(changes, scope, expected_outside)
    observations, rendered = [], set()
    for row in rows:
        result = dict(name=row['id']+':'+row['card'], source=row)
        for stage in ('baseline', 'candidate'):
            directory = args.work/stage
            directory.mkdir(exist_ok=True)
            prefix = directory/row['id']
            if (stage, row['id']) not in rendered:
                renderer.render(getattr(args, stage+'_bin'), args.examples/row['corpus']/(row['id']+'.cir'), prefix)
                rendered.add((stage, row['id']))
            drawing = json.loads(prefix.with_suffix('.json').read_text())
            same(drawing, json.loads((directories[stage][row['corpus']]/(row['id']+'.json')).read_text()), 'fresh render versus scored JSON')
            root = ET.parse(prefix.with_suffix('.svg')).getroot()
            bound_device(drawing, row)
            try:
                value = native(drawing, root, row)
                value['curve_certificate'] = curve_certificate(value, inventory, proof)
            except ValueError as error:
                adapter = dict(row, shape='box', expected_marks=[], missing_source_ports=[], signal_frame_mismatches=[])
                value = glyph.inspect(drawing, root, adapter)
                same(value['shape'], 'box', 'failed coil is independently a complete box')
                value['missing_glyph_reason'] = str(error)
            result[stage] = dict(observed=value, native_sha256={s:corpus.digest(prefix.with_suffix(s)) for s in ('.json', '.svg')})
        lines = [p['local'] for p in row['primitives'] if p['tag'] == 'line']
        canonical = dict(n1=next(p[0] for p in lines if p[0][0] < -45),
                         n2=next(p[1] for p in lines if p[1][0] > 45), n3=[0, 20])
        if result['candidate']['observed']['shape'] == 'center_tap':
            result['canonical_terminal_differences'] = [p for p in row['ports']
                if canonical[p] != result['candidate']['observed']['terminals'][p]]
            result['observed_dot_radius_difference'] = round(result['candidate']['observed']['disk']['radius']-float(proof['radius']['source']), 12)
        result['source_canonical_terminals'] = canonical
        observations.append(result)
    summaries = {stage: {kind: [r['name'] for r in observations if r[stage]['observed']['shape'] == kind]
                        for kind in ('box', 'center_tap')} for stage in ('baseline', 'candidate')}
    result = dict(source_inventory_sha256=corpus.digest(HERE/'center_tap_symbols_cases.json'),
        curve_proof_sha256=corpus.digest(args.curve_proof), dependencies=dependencies(),
        runtime_table_source_sha256=corpus.digest(certificate.IMPLEMENTATION),
        selected_names=source.EXPECTED, method_checks=method_checks, corpora=corpora, rows=observations, summaries=summaries, changes=changes,
        outside_selected=actual_outside,
        expected_outside_manifest_sha256=corpus.digest(args.expected_outside) if args.expected_outside else None,
        limits='Canonical default symbol, actual named lead/coil/disk ink and declared bindings only. Source orientations, external routing and pixel-identical strokes are separate. AG1190 outer lead length and the rounded disk radius differ from canonical source coordinates.')
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True)+'\n')
    if args.require_glyph:
        same(summaries['candidate']['center_tap'], source.EXPECTED, 'required exact native coil names')
    if args.check:
        same(result, json.loads((HERE/'center_tap_native_cases.json').read_text()), 'every native center-tap evidence field')
    print(json.dumps(dict(summaries=summaries, method_checks=method_checks), indent=2, sort_keys=True))


if __name__ == '__main__':
    main()
