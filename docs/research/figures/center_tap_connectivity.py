#!/usr/bin/env python3
"""All stable native pin-pair changes with source-verified center-tap terminals.

Usage: center_tap_connectivity.py EXAMPLES OUTPUT --source-work DIR
       --baseline-bin BIN --candidate-bin BIN
       --baseline-ag DIR --baseline-ams DIR --candidate-ag DIR --candidate-ams DIR
       [--accept-resolved EXACT_PAIR] ... [--check]

Every changed physical pair needs actual source terminal correspondences.
Center-tap N1/N2/N3 use observed own SVG leads and the declared call, never
positional asset guesses. Existing source-unknown peers remain unknown.
All historical marker names and prior resolved cases remain explicit.
"""
import argparse
import ast
import copy
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import bias_block_connectivity as bias
import center_tap_native as glyph
import paired_amplifier_ports as paired

banks, native, read = bias.banks, bias.native, bias.read
CENTERS = []
PRIMITIVE_TERMINAL = native.terminal


def primitive_terminal(device, index, term):
    """Add only source-proven diode cathodes and visible ideal-switch contacts."""
    if device['card'][0] == 'd' and term == 'k':
        if index != 1 or set(device['nets']) != {'A', 'K'}:
            raise ValueError('diode cathode source/native role mismatch')
        return 'K'
    if device['card'][0] == 's':
        if (device['type'] != 'ideal-switch' or set(device['nets']) != {'1', '2'}
                or index not in (0, 1) or term != ('a', 'b')[index]):
            raise ValueError('ideal-switch control or contact lacks exact source role')
        return ('1', '2')[index]
    return PRIMITIVE_TERMINAL(device, index, term)


def source(context, row):
    # The frozen reader still verifies card binding and each own SVG lead.
    original = native.terminal
    native.terminal = primitive_terminal
    try:
        return banks.source(context, row)
    finally:
        native.terminal = original


def register(row):
    key = row['id'], row['card']
    if sorted(row['ports']) != ['n1', 'n2', 'n3'] or len(row['bindings']) != 3:
        raise ValueError('incomplete center-tap declared binding')
    if set(row['actual_terminals']) != set(row['ports']):
        raise ValueError('actual center-tap lead inventory differs from declaration')
    proof = dict(ports=row['ports'], bindings=row['bindings'], source_object=row['source_object'],
        source_sha256=row['source_sha256'], missing_geometry=[],
        visible_port_mapping={p: dict(endpoint=point, method='declared N1/N2/N3 matches actual center-tap SVG lead')
                              for p, point in row['actual_terminals'].items()})
    if key in banks.reference.REFERENCE_ROWS and banks.reference.REFERENCE_ROWS[key] != proof:
        raise ValueError('conflicting actual center-tap source certificate: '+str(key))
    banks.reference.REFERENCE_ROWS[key] = proof


def replay(examples, work):
    provenance = bias.replay(examples, work)
    rows, _ = glyph.replay_source(examples)
    CENTERS[:] = rows
    for row in rows:
        register(row)
    provenance['center_tap'] = dict(inventory_sha256=native.digest(HERE/'center_tap_symbols_cases.json'),
                                   selected_names=[r['id']+':'+r['card'] for r in rows])
    boxes = paired.replay(examples)
    if json.loads(json.dumps(boxes)) != read(HERE/'paired_amplifier_ports_cases.json'):
        raise ValueError('DA/PA own-lead certificates differ from frozen source inventory')
    for row in boxes['rows']:
        key = row['id'], row['card']
        if key in banks.reference.REFERENCE_ROWS:
            raise ValueError('duplicate source certificate for DA/PA box: '+str(key))
        banks.reference.REFERENCE_ROWS[key] = row
    provenance['paired_amplifier_boxes'] = boxes
    return provenance


def checks():
    names = bias.checks()
    for kind, symbol, schema, terms in (('d', 'diode', ['A', 'K'], ['a', 'k']),
                                       ('s', 'ideal-switch', ['1', '2'], ['a', 'b'])):
        device = dict(card=kind+'1', type=symbol, nets={p:'n'+str(i) for i,p in enumerate(schema)})
        if [primitive_terminal(device, i, term) for i, term in enumerate(terms)] != schema:
            raise ValueError('literal primitive terminal roles changed')
        names.append('literal_'+symbol+'_actual_contact_roles')
        for index, term in ((0, terms[1]), (1, terms[0]), (2, 'c+'), (-1, terms[1])):
            try:
                primitive_terminal(device, index, term)
            except ValueError:
                pass
            else:
                raise ValueError('unproved primitive contact/control was guessed')
        names.append(symbol+'_swapped_roles_negative_index_and_unseen_control_rejected')
    row = dict(id='literal-center-tap', card='x1', ports=['n3', 'n1', 'n2'], bindings=['mid', 'left', 'right'],
        source_object='literal-own-coil', source_sha256={}, actual_terminals=dict(n1=[-50, 0], n2=[50, 0], n3=[0, 20]))
    register(row)
    context = dict(root=ET.fromstring('<svg/>'), source_sha256={}, glyphs={}, nets={}, ink=[], human=dict(wires=[]),
                   cards={'x1':['x1', 'mid', 'left', 'right', 'ct_inductor']})
    for index, (term, net) in enumerate(zip(row['ports'], row['bindings'])):
        pair = dict(id=row['id'], net=net, pins=[['x1', index]]*2, terms=[term]*2)
        if banks.source(context, pair)['status'] != 'source_connected':
            raise ValueError('actual reordered center-tap terminal was not resolved')
    names.append('center_tap_all_reordered_named_terminals_use_actual_leads')
    base = dict(id=row['id'], net='mid', pins=[['x1', 0]]*2, terms=['n3']*2)
    for name, change in (
        ('center_tap_wrong_terminal_index_rejected', dict(pins=[['x1', 2]]*2)),
        ('center_tap_wrong_terminal_name_rejected', dict(terms=['n2']*2)),
        ('center_tap_wrong_net_binding_rejected', dict(net='right'))):
        pair = dict(base, **change)
        if banks.source(context, pair)['status'] != 'unsupported':
            raise ValueError('source resolver accepted '+name)
        names.append(name)
    missing = copy.deepcopy(row)
    del missing['actual_terminals']['n3']
    try:
        register(missing)
    except ValueError:
        names.append('center_tap_missing_actual_tap_rejected')
    else:
        raise ValueError('missing center-tap source geometry was guessed')
    del banks.reference.REFERENCE_ROWS[(row['id'], row['card'])]
    return names


def terminals(before, after):
    result = []
    for row in CENTERS:
        maps = [native.pins(read(d['ag']/(row['id']+'.json'))) for d in (before, after)]
        for index, (term, net) in enumerate(zip(row['ports'], row['bindings'])):
            key = row['card'], index
            if any(key not in ps or ps[key][0] != net or ps[key][2] != term for ps in maps):
                raise ValueError('ordered center-tap terminal binding changed: '+row['id']+':'+term)
            result.append(dict(name=row['id']+':'+row['card']+':'+term, net=net,
                source=row['actual_terminals'][term], baseline=maps[0][key][1], candidate=maps[1][key][1]))
    return result


def dependencies():
    pending, found = [Path(__file__).name], bias.dependency_hashes()
    seen = set()
    while pending:
        name = pending.pop()
        if name in seen:
            continue
        seen.add(name)
        path = HERE/name
        found[name] = native.digest(path)
        for node in ast.walk(ast.parse(path.read_text())):
            modules = [n.name for n in node.names] if isinstance(node, ast.Import) else [node.module] if isinstance(node, ast.ImportFrom) else []
            for module in modules:
                local = (module or '').split('.')[0]+'.py'
                if (HERE/local).is_file() and local not in seen:
                    pending.append(local)
    return dict(sorted(found.items()))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('examples', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--source-work', type=Path, required=True)
    for stage in ('baseline', 'candidate'):
        parser.add_argument('--'+stage+'-label', default='iteration20-bias-final' if stage == 'baseline' else 'iteration21-center-tap')
        parser.add_argument('--'+stage+'-bin', type=Path, required=True)
        for tag in ('ag', 'ams'):
            parser.add_argument('--'+stage+'-'+tag, type=Path, required=True)
    parser.add_argument('--accept-resolved', action='append', default=[])
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    provenance = replay(args.examples, args.source_work)
    methods = checks()
    before = {tag:getattr(args, 'baseline_'+tag) for tag in ('ag', 'ams')}
    after = {tag:getattr(args, 'candidate_'+tag) for tag in ('ag', 'ams')}
    for dirs, binary in ((before, args.baseline_bin), (after, args.candidate_bin)):
        if any(native.digest(d/'cktimg-json') != native.digest(binary) for d in dirs.values()):
            raise ValueError('frozen executable differs from scored corpus')
    observed = terminals(before, after)
    original = native.source
    native.source = source
    try:
        runs = [native.audit(args.examples/c, before[tag], after[tag]) for tag, c in (('ag', 'analoggenie'), ('ams', 'amsnet'))]
    finally:
        native.source = original
    prior = banks.markers(args.examples, before, after)
    prior['previously_resolved'] = [r['name'] for r in prior['rows'] if r['baseline'] == r['source_connected']]
    prior['newly_resolved'] = [r['name'] for r in prior['rows'] if r['baseline'] != r['source_connected'] and r['resolved']]
    prior['resolved_then_regressed'] = [r['name'] for r in prior['rows'] if r['baseline'] == r['source_connected'] and not r['resolved']]
    failures = []
    for run in runs:
        failures += ['unstable:'+r['id']+':'+str(r['pin']) for r in run['unstable']]
        failures += ['unsupported:'+r['name']+':'+r['source']['reason'] for direction in ('gains', 'losses') for r in run[direction] if r['source']['status'] == 'unsupported']
        failures += ['source_agreement_regressed:'+n for group in run['expected_candidate_mismatches'].values() for n in group]
    if sorted(args.accept_resolved) != prior['resolved']:
        failures.append('resolved_marker_names_require_review:'+str(dict(accepted=sorted(args.accept_resolved), observed=prior['resolved'])))
    data = banks.data_hashes()
    for name in ('bias_block_neighbors_cases.json', 'center_tap_symbols_cases.json', 'paired_amplifier_ports_cases.json'):
        data[name] = native.digest(HERE/name)
    result = dict(baseline=args.baseline_label, candidate=args.candidate_label, source_provenance=provenance,
        method_checks=methods, center_tap_terminals=observed, bias_source_pairs=bias.source_pairs(args.examples, before, after),
        peer_terminals=bias.peer_terminals(before, after), runs=runs, prior_markers=prior,
        accepted_resolved_markers=sorted(args.accept_resolved), failures=failures,
        dependency_sha256=dependencies(), data_sha256=data,
        limits='All changed stable native pin pairs across complete AG/AMS corpora. Changed unsupported correspondences and new source disagreements fail. Unchanged connectivity does not infer unknown source geometry. Exact historical markers and previous resolutions remain named.')
    result = json.loads(json.dumps(result))
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True)+'\n')
    if args.check:
        glyph.same(result, read(HERE/'center_tap_connectivity_cases.json'), 'every source/native connectivity field')
    print(json.dumps(dict(failures=failures, prior={k:prior[k] for k in ('remaining', 'previously_resolved', 'newly_resolved', 'resolved_then_regressed')},
        corpora={r['corpus']:dict(r['summary'], changed_drawings=r['changed_drawings'], source_inventory=r['source_inventory']) for r in runs}), indent=2))
    if failures:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
