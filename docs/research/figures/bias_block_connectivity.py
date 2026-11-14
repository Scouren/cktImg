#!/usr/bin/env python3
"""Complete native pin-pair changes with actual amplifier/bias peer source leads.

Usage: bias_block_connectivity.py EXAMPLES OUTPUT --source-work DIR
       --baseline-bin BIN --candidate-bin BIN
       --baseline-ag DIR --baseline-ams DIR --candidate-ag DIR --candidate-ams DIR
       [--accept-resolved EXACT_PAIR] ... [--check]

Unverified VSS and other custom terminals remain unknown. Any changed physical
pair without an actual source correspondence fails; unchanged connectivity is
measured without fabricating source geometry. Historical markers are retained.
"""
import argparse
import ast
import copy
import json
from pathlib import Path
import subprocess
import sys
import xml.etree.ElementTree as ET

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import driven_banks_connectivity as banks

native = banks.native
read = banks.read
BIAS_ROWS = []
PEERS = {}


def register(row, peer):
    """Keep declared order and only replayed, actual own-body named leads."""
    key = row['id'], peer['card']
    ports = peer['ports']
    visible = peer['visible_named_leads']
    unknown = peer['unknown_geometry']
    if len(set(ports)) != len(ports) or len(ports) != len(peer['bindings']):
        raise ValueError('ambiguous peer declaration')
    if set(visible) & set(unknown) or set(visible) | set(unknown) != set(ports):
        raise ValueError('peer visible/unknown source partition differs from declaration')
    proof = dict(ports=ports, bindings=peer['bindings'], source_object=peer['source_object'],
                 source_sha256=row['source_sha256'], missing_geometry=unknown,
                 visible_port_mapping={p: dict(v, method='declared port matches actual own-body lead')
                                       for p, v in visible.items()})
    if key in banks.reference.REFERENCE_ROWS and banks.reference.REFERENCE_ROWS[key] != proof:
        raise ValueError('conflicting actual source certificate: ' + str(key))
    banks.reference.REFERENCE_ROWS[key] = proof
    PEERS[key] = dict(id=row['id'], card=peer['card'], ports=ports, bindings=peer['bindings'],
                     visible=sorted(visible), unknown=sorted(unknown), selected=row['isolated_block_case'])


def replay(examples, directory):
    provenance = banks.replay(examples, directory)
    PEERS.clear()
    output = directory / 'bias-block-neighbors.json'
    subprocess.run([sys.executable, '-B', str(HERE/'bias_block_neighbors.py'), str(examples), str(output), '--check'],
                   check=True, capture_output=True)
    observed = read(output)
    inventory = HERE/'bias_block_neighbors_cases.json'
    if observed != read(inventory):
        raise ValueError('every actual bias-peer source evidence field changed')
    BIAS_ROWS[:] = observed['rows']
    for row in BIAS_ROWS:
        for peer in row['other_pins']:
            if peer['card'].startswith('x'):
                register(row, peer)
    provenance['bias_block_neighbors'] = dict(inventory_sha256=native.digest(inventory),
                                             replay_sha256=native.digest(output),
                                             selected_names=observed['isolated_names'])
    return provenance


def checks():
    methods = banks.checks()
    key = ('literal-bias-peer', 'x2')
    row = dict(id=key[0], source_sha256={}, isolated_block_case=True)
    peer = dict(card=key[1], ports=['vdd', 'vss', 'vb1', 'nb'], bindings=['p', '0', 'b', 'n'],
                source_object='literal-peer', unknown_geometry=['vss'],
                visible_named_leads={p: dict(endpoint=xy) for p, xy in
                                     [('vdd', [0, -20]), ('vb1', [-20, 0]), ('nb', [0, 20])]})
    register(row, peer)
    context = dict(root=ET.fromstring('<svg/>'), source_sha256={}, glyphs={}, nets={},
                   cards={'x2': ['x2', 'p', '0', 'b', 'n', 'bias']}, ink=[], human=dict(wires=[]))
    for index, term in enumerate(peer['ports']):
        pair = dict(id=key[0], net=peer['bindings'][index], pins=[['x2', index]]*2, terms=[term]*2)
        result = banks.source(context, pair)
        expected = 'unsupported' if term == 'vss' else 'source_connected'
        assert result['status'] == expected
    methods += ['peer_all_visible_declared_ports_use_actual_endpoints', 'peer_missing_vss_remains_unknown']
    pair = dict(id=key[0], net='n', pins=[['x2', 3]]*2, terms=['nb']*2)
    for name, mutate in (
        ('peer_wrong_terminal_index_rejected', lambda r:r.update(pins=[['x2', 2]]*2)),
        ('peer_wrong_terminal_name_rejected', lambda r:r.update(terms=['vb1']*2)),
        ('peer_wrong_net_binding_rejected', lambda r:r.update(net='b'))):
        changed = copy.deepcopy(pair); mutate(changed)
        assert banks.source(context, changed)['status'] == 'unsupported', name
        methods.append(name)
    changed = copy.deepcopy(peer)
    changed['visible_named_leads']['vss'] = dict(endpoint=[0, 40])
    try:
        register(row, changed)
    except ValueError:
        pass
    else:
        raise ValueError('unknown source VSS was silently assigned a coordinate')
    methods.append('peer_visible_unknown_overlap_rejected')
    del banks.reference.REFERENCE_ROWS[key]
    del PEERS[key]
    return methods


def source_pairs(examples, before, after):
    """Exercise all seven positive peers and the actual AG2440 negative."""
    observations = []
    for row in BIAS_ROWS:
        for peer in row['other_pins']:
            if not peer['card'].startswith('x') or row['amp_bias_proof'] is None:
                continue
            amplifier = banks.reference.REFERENCE_ROWS[(row['id'], row['card'])]
            keys = [(row['card'], amplifier['ports'].index(row['port'])),
                    (peer['card'], peer['ports'].index(peer['port']))]
            pair = dict(id=row['id'], net=row['net'], pins=keys, terms=[row['port'], peer['port']])
            proof = banks.source(native.load_source(examples/'analoggenie', row['id']), pair)
            expected = peer['verified_wire']['continuous']
            if proof['status'] == 'unsupported' or (proof['status'] == 'source_connected') != expected:
                raise ValueError('source bias path differs from independent actual source certificate: ' + row['name'])
            states = []
            for directory in (before['ag'], after['ag']):
                path = directory/(row['id']+'.json'); drawing = read(path); pins = native.pins(drawing)
                if any(pins[k][0] != row['net'] or pins[k][2] != term for k, term in zip(keys, pair['terms'])):
                    raise ValueError('ordered native bias-pair binding changed: ' + row['name'])
                parts = native.components(drawing, row['net'], sorted(k for k,v in pins.items() if v[0] == row['net']), pins)
                connected = parts[keys[0]] == parts[keys[1]]
                states.append(dict(continuous=connected, source_agreement=connected == expected,
                                   targets=[pins[k][1] for k in keys], geometry_sha256=native.digest(path)))
            observations.append(dict(name=row['name'], selected=row['isolated_block_case'], source=proof,
                                     baseline=states[0], candidate=states[1]))
    return observations


def peer_terminals(before, after):
    """Name all unresolved terminals even when native connectivity is unchanged."""
    observations = []
    for key, peer in sorted(PEERS.items()):
        maps = [native.pins(read(d['ag']/(peer['id']+'.json'))) for d in (before, after)]
        for index, (term, net) in enumerate(zip(peer['ports'], peer['bindings'])):
            pin = peer['card'], index
            if any(pin not in ps or ps[pin][0] != net or ps[pin][2] != term for ps in maps):
                raise ValueError('peer ordered terminal contract changed: ' + str(key))
            positions = [ps[pin][1] for ps in maps]
            observations.append(dict(name=peer['id']+':'+peer['card']+':'+term, net=net,
                                     source_geometry='verified' if term in peer['visible'] else 'unknown',
                                     baseline=positions[0], candidate=positions[1], moved=positions[0] != positions[1]))
    return observations


def dependency_hashes():
    pending = [Path(__file__), HERE/'bias_block_neighbors.py']
    found = {}
    while pending:
        path = pending.pop()
        if path.name in found:continue
        found[path.name] = native.digest(path)
        for node in ast.walk(ast.parse(path.read_text())):
            modules = [n.name for n in node.names] if isinstance(node, ast.Import) else [node.module] if isinstance(node, ast.ImportFrom) else []
            for module in modules:
                p = HERE/((module or '').split('.')[0]+'.py')
                if p.is_file():pending.append(p)
    # banks.replay launches these readers as child processes rather than imports.
    found.update(banks.dependency_hashes())
    return dict(sorted(found.items()))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('examples', type=Path); parser.add_argument('output', type=Path)
    parser.add_argument('--source-work', type=Path, required=True)
    for stage in ('baseline', 'candidate'):
        parser.add_argument('--'+stage+'-label', default='iteration19-banks-inline' if stage=='baseline' else 'iteration20-bias')
        parser.add_argument('--'+stage+'-bin', type=Path, required=True)
        for tag in ('ag', 'ams'):parser.add_argument('--'+stage+'-'+tag, type=Path, required=True)
    parser.add_argument('--accept-resolved', action='append', default=[])
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    provenance = replay(args.examples, args.source_work)
    methods = checks()
    before = {tag:getattr(args, 'baseline_'+tag) for tag in ('ag','ams')}
    after = {tag:getattr(args, 'candidate_'+tag) for tag in ('ag','ams')}
    for directories, binary in ((before, args.baseline_bin), (after, args.candidate_bin)):
        if any(native.digest(d/'cktimg-json') != native.digest(binary) for d in directories.values()):
            raise ValueError('frozen native executable differs from corpus executable')
    pairs = source_pairs(args.examples, before, after)
    terminals = peer_terminals(before, after)
    original = native.source; native.source = banks.source
    try:
        runs = [native.audit(args.examples/corpus, before[tag], after[tag]) for tag,corpus in (('ag','analoggenie'),('ams','amsnet'))]
    finally:
        native.source = original
    prior = banks.markers(args.examples, before, after)
    prior['previously_resolved'] = [r['name'] for r in prior['rows'] if r['baseline'] == r['source_connected']]
    prior['newly_resolved'] = [r['name'] for r in prior['rows'] if r['baseline'] != r['source_connected'] and r['resolved']]
    prior['resolved_then_regressed'] = [r['name'] for r in prior['rows'] if r['baseline'] == r['source_connected'] and not r['resolved']]
    failures = []
    for run in runs:
        failures += ['unstable:'+r['id']+':'+str(r['pin']) for r in run['unstable']]
        failures += ['unsupported:'+r['name']+':'+r['source']['reason'] for direction in ('gains','losses') for r in run[direction] if r['source']['status']=='unsupported']
        failures += ['source_agreement_regressed:'+n for group in run['expected_candidate_mismatches'].values() for n in group]
    if sorted(args.accept_resolved) != prior['resolved']:
        failures.append('resolved_marker_names_require_review:'+str(dict(accepted=sorted(args.accept_resolved), observed=prior['resolved'])))
    data = banks.data_hashes()
    data['bias_block_neighbors_cases.json'] = native.digest(HERE/'bias_block_neighbors_cases.json')
    result = dict(baseline=args.baseline_label, candidate=args.candidate_label, source_provenance=provenance,
                  method_checks=methods, bias_source_pairs=pairs, peer_terminals=terminals,
                  unknown_source_peer_terminals=[r['name'] for r in terminals if r['source_geometry']=='unknown'],
                  runs=runs, prior_markers=prior, accepted_resolved_markers=sorted(args.accept_resolved),
                  failures=failures, dependency_sha256=dependency_hashes(), data_sha256=data,
                  limits='All changed stable native pin pairs across complete AG/AMS corpora. Unknown affected source correspondences and new disagreements fail. Unchanged native connectivity does not establish unknown source VSS geometry. Historical129 markers remain explicit, with previous and newly resolved names separate. Physical ink is not electrical netlist equivalence.')
    result = json.loads(json.dumps(result))
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True)+'\n')
    if args.check and result != read(HERE/'bias_block_connectivity_cases.json'):
        raise ValueError('every frozen source/native evidence field must match')
    print(json.dumps(dict(failures=failures, unknown= result['unknown_source_peer_terminals'],
                         prior={k:prior[k] for k in ('remaining','previously_resolved','newly_resolved','resolved_then_regressed')},
                         corpora={r['corpus']:dict(r['summary'], changed_drawings=r['changed_drawings'], source_inventory=r['source_inventory']) for r in runs}), indent=2))
    if failures:raise SystemExit(1)


if __name__ == '__main__':main()
