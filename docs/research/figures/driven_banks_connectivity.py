#!/usr/bin/env python3
"""Stable native pin-pair transitions, actual source ink, and prior failures.

Usage: driven_banks_connectivity.py EXAMPLES OUTPUT --source-work DIRECTORY
       --baseline-ag DIR --baseline-ams DIR --candidate-ag DIR --candidate-ams DIR
       --baseline-bin BIN --candidate-bin BIN [--accept-resolved EXACT_PAIR] ...

Both complete corpora are discovered, never restricted to selected banks.
Unknown source geometry and new source disagreements fail. Historical17/18
markers stay unchanged; exact reviewed repair names are explicit inputs.
--check compares every recorded evidence field with the frozen companion.
"""
import argparse
import ast
import copy
import json
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
FIG = Path(__file__).resolve().parent
sys.path.insert(0, str(FIG))
import thin_connectivity as native
import reference_amplifiers_connectivity as reference

ROWS = []
REFERENCES = {}
PROVENANCE = {}


def replay(examples, directory):
    """Repeat both actual SVG extractions; hashes alone cannot certify a lead."""
    directory.mkdir(parents=True, exist_ok=True)
    REFERENCES.clear()
    PROVENANCE.clear()
    for stem in ('reference_amplifiers', 'driven_banks'):
        output = directory / (stem + '.json')
        subprocess.run([sys.executable, '-B', str(FIG / (stem + '.py')), str(examples), str(output)],
                       check=True, capture_output=True)
        observed = json.loads(output.read_text())
        frozen = FIG / (stem + '_cases.json')
        if observed != json.loads(frozen.read_text()):
            raise ValueError('every source evidence field changed: ' + stem)
        PROVENANCE[stem] = dict(inventory_sha256=native.digest(frozen), replay_sha256=native.digest(output))
        if stem == 'reference_amplifiers':
            REFERENCES.update({(r['id'], r['card']): r for r in observed['rows']})
        else:
            ROWS[:] = observed['rows']
    reference.REFERENCE_ROWS.clear()
    reference.REFERENCE_ROWS.update(REFERENCES)
    for row in ROWS:
        key = row['id'], row['driver']
        if key in reference.REFERENCE_ROWS:
            existing = reference.REFERENCE_ROWS[key]
            if existing['ports'] != row['ports'] or existing['bindings'] != row['bindings']:
                raise ValueError('independent declared source contracts disagree: ' + str(key))
            term = row['output_port']
            if existing['visible_port_mapping'][term]['endpoint'] != row['source']['output']['endpoint']:
                raise ValueError('independent actual output endpoints disagree: ' + str(key))
            continue
        proof = row['source']['output']
        reference.REFERENCE_ROWS[key] = dict(
            ports=row['ports'], bindings=row['bindings'], source_object=proof['object'],
            source_sha256=row['source']['source_sha256'],
            visible_port_mapping={row['output_port']: proof},
            missing_geometry=[p for p in row['ports'] if p != row['output_port']])
    return dict(PROVENANCE, admitted_names=[r['id'] + ':' + r['driver'] for r in ROWS if r['admitted']],
                certified_output_names=[r['id'] + ':' + r['driver'] + ':' + r['output_port'] for r in ROWS])


def certified_tree(context, row):
    """Only a replayed bound output-to-gate tree may supplement cache gaps."""
    additions, evidence = [], []
    for bank in ROWS:
        if bank['id'] != row['id'] or bank['net'] != row['net']:
            continue
        for suffix, digest in bank['source']['source_sha256'].items():
            if context['source_sha256'].get(row['id'] + suffix) != digest:
                raise ValueError('source tree provenance differs')
        if context['cards'][bank['driver']][bank['output_pin'] + 1] != row['net']:
            raise ValueError('source output binding differs from tree certificate')
        for gate in bank['source']['gates']:
            if context['cards'][gate['card']][2] != row['net']:
                raise ValueError('source gate binding differs from tree certificate')
            tree = gate['output_tree']
            if tree is None:
                continue
            if any(not any(native.on(a, c, d) and native.on(b, c, d)
                           for c, d in context['ink']) for a, b in tree):
                raise ValueError('certified source path contains unsupported actual stroke')
            output = bank['source']['output']['endpoint']
            target = gate['terminals']['G']
            if not native.source_connection(context, tree, [output, target])['continuous']:
                raise ValueError('certified source path is not physically continuous')
            evidence.append(dict(driver=bank['driver'], output_pin=bank['output_pin'],
                                 output_port=bank['output_port'], gate=gate['card'],
                                 targets=[output, target], spanning_ink_segments=tree))
            additions.extend(tree)
    return additions, evidence


def source(context, row):
    observed = reference.source_observation(context, row)
    if observed['status'] != 'unsupported' or 'actual conductor path lacks' not in observed.get('reason', ''):
        return observed
    # A stale cache can omit a real declared-output path (AG2420). Do not
    # reinterpret arbitrary whole-SVG connectivity as a named net assignment.
    additions, evidence = certified_tree(context, row)
    targets = [r['xy'] for r in observed['ordered_terminal_bindings']]
    ink = observed['verified_ink_segments'] + additions
    proof = native.source_connection(context, ink, targets)
    if not evidence or not proof['continuous']:
        return observed
    return dict(status='source_connected', ordinary_reader=observed,
                source_sha256=context['source_sha256'], source_glyphs=observed['source_glyphs'],
                ordered_terminal_bindings=observed['ordered_terminal_bindings'],
                supplemental_declared_output_paths=evidence, source_connection=proof)


def checks():
    methods = reference.checks()
    import xml.etree.ElementTree as ET
    key = ('literal-bank', 'x1')
    reference.REFERENCE_ROWS[key] = dict(ports=['inp', 'out', 'vss'], bindings=['a', 'n', '0'],
        visible_port_mapping={'out': dict(endpoint=[0, 0], method='literal_actual_endpoint')},
        source_object='literal-x', source_sha256={}, missing_geometry=['inp', 'vss'])
    context = dict(root=ET.fromstring('<svg/>'), source_sha256={},
                   cards={'x1': ['x1', 'a', 'n', '0', 'opamp']}, nets={}, glyphs={},
                   ink=[[[0, 0], [20, 0]]], human=dict(wires=[dict(net='n', segments=[[[0, 0], [20, 0]]])]))
    pair = dict(id=key[0], net='n', pins=[['x1', 1], ['x1', 1]], terms=['out', 'out'])
    assert source(context, pair)['status'] == 'source_connected'
    for name, mutate in (
        ('wrong_custom_port_index_rejected', lambda r:r.update(pins=[['x1', 0], ['x1', 1]])),
        ('negative_custom_port_index_rejected', lambda r:r.update(pins=[['x1', -1], ['x1', 1]])),
        ('wrong_custom_port_name_rejected', lambda r:r.update(terms=['inp', 'out'])),
        ('wrong_custom_net_binding_rejected', lambda r:r.update(net='other')),
        ('unproved_custom_control_rejected', lambda r:r.update(net='a', pins=[['x1', 0], ['x1', 0]], terms=['inp', 'inp']))):
        changed=copy.deepcopy(pair);mutate(changed)
        assert source(context, changed)['status']=='unsupported', name
        methods.append(name)
    del reference.REFERENCE_ROWS[key]
    return methods + ['actual_custom_output_endpoint_and_binding', 'unknown_custom_nonoutput_never_guessed']


def read(path):
    return json.loads(path.read_text())


def prior_markers():
    seventeen=read(FIG/'thin_connectivity_cases.json')
    eighteen=read(FIG/'reference_amplifiers_connectivity_cases.json')
    rows=[]
    for corpus, data in seventeen['corpora'].items():
        for kind, names in data['expected_candidate_mismatches'].items():
            rows.extend(dict(name=n,corpus=corpus,source_connected=kind=='missing_joins',introduced='iteration17-bounded') for n in names)
    for run in eighteen['runs']:
        for kind,names in run['expected_candidate_mismatches'].items():
            rows.extend(dict(name=n,corpus=run['corpus'],source_connected=kind=='missing_joins',introduced='iteration18-reference') for n in names)
    if len({r['name'] for r in rows})!=len(rows):raise ValueError('repeated prior marker')
    return sorted(rows,key=lambda r:r['name'])


def markers(examples,before,after):
    observed=[]
    for marker in prior_markers():
        ident, net, pair=marker['name'].split(':')
        keys=[(n.rsplit('.',1)[0],int(n.rsplit('.',1)[1])) for n in pair.split('--')]
        tag='ag' if marker['corpus']=='analoggenie' else 'ams'
        dirs=[before[tag],after[tag]]
        ds=[read(d/(ident+'.json')) for d in dirs];ps=[native.pins(d) for d in ds]
        if any(k not in p or p[k][0]!=net for p in ps for k in keys):raise ValueError('prior marker pin/net changed: '+marker['name'])
        if any(ps[0][k][::2]!=ps[1][k][::2] for k in keys):raise ValueError('prior marker pin role changed: '+marker['name'])
        parts=[native.components(d,net,sorted(k for k,v in p.items() if v[0]==net),p) for d,p in zip(ds,ps)]
        connected=[c[keys[0]]==c[keys[1]] for c in parts]
        row=dict(id=ident,net=net,pins=keys,terms=[ps[0][k][2] for k in keys])
        proof=source(native.load_source(examples/marker['corpus'],ident),row)
        if proof['status']=='unsupported' or (proof['status']=='source_connected')!=marker['source_connected']:
            raise ValueError('prior actual source marker evidence changed: '+marker['name']+' '+proof.get('reason',''))
        observed.append(dict(marker,baseline=connected[0],candidate=connected[1],resolved=connected[1]==marker['source_connected'],
                             source=proof,native_sha256=[native.digest(d/(ident+'.json')) for d in dirs]))
    return dict(rows=observed,remaining=[r['name'] for r in observed if not r['resolved']],
                resolved=[r['name'] for r in observed if r['resolved']])


def dependency_hashes():
    """Retain the complete local import closure, including replayed readers."""
    pending=[Path(__file__),FIG/'reference_amplifiers.py',FIG/'driven_banks.py']
    found={}
    while pending:
        path=pending.pop()
        if path.name in found:continue
        found[path.name]=native.digest(path)
        for node in ast.walk(ast.parse(path.read_text())):
            names=[n.name for n in node.names] if isinstance(node,ast.Import) else [node.module] if isinstance(node,ast.ImportFrom) else []
            for name in names:
                dependency=FIG/((name or '').split('.')[0]+'.py')
                if dependency.is_file():pending.append(dependency)
    return dict(sorted(found.items()))


def data_hashes():
    names={'reference_amplifiers_cases.json','driven_banks_cases.json',
           'thin_connectivity_cases.json','reference_amplifiers_connectivity_cases.json'}
    source=read(FIG/'reference_amplifiers_cases.json')
    names.update(n for n in source['audit_sha256'] if n.endswith('.json'))
    return {n:native.digest(FIG/n) for n in sorted(names)}


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('examples',type=Path);p.add_argument('output',type=Path)
    p.add_argument('--source-work',type=Path,required=True)
    for stage in ('baseline','candidate'):
        p.add_argument('--'+stage+'-label',default='iteration18-reference' if stage=='baseline' else 'iteration19-banks-inline')
        p.add_argument('--'+stage+'-bin',type=Path,required=True)
        for corpus in ('ag','ams'):p.add_argument('--'+stage+'-'+corpus,type=Path,required=True)
    p.add_argument('--accept-resolved',action='append',default=[])
    p.add_argument('--check',action='store_true')
    args=p.parse_args();examples=args.examples
    provenance=replay(examples,args.source_work)
    methods=checks()
    # Exercise every admitted custom output and both actual source gate paths
    # even when a baseline-self-comparison has no native transitions.
    before={tag:getattr(args,'baseline_'+tag) for tag in ('ag','ams')}
    after={tag:getattr(args,'candidate_'+tag) for tag in ('ag','ams')}
    for directories,binary in ((before,args.baseline_bin),(after,args.candidate_bin)):
        if any(native.digest(d/'cktimg-json')!=native.digest(binary) for d in directories.values()):
            raise ValueError('frozen native executable differs from corpus executable')
    source_checks=[]
    for bank in ROWS:
        if not bank['admitted']:continue
        context=native.load_source(examples/bank['corpus'],bank['id'])
        for card in bank['bank']:
            row=dict(id=bank['id'],net=bank['net'],pins=[[card,1],[bank['driver'],bank['output_pin']]],terms=['g',bank['output_port']])
            observed=source(context,row)
            expected=next(g['output_tree'] is not None for g in bank['source']['gates'] if g['card']==card)
            if observed['status']=='unsupported' or (observed['status']=='source_connected')!=expected:
                raise ValueError('admitted actual output path differs from independent source tree: '+bank['id']+':'+card+' '+str(observed))
            native_states=[]
            tag='ag' if bank['corpus']=='analoggenie' else 'ams'
            pair=[(card,1),(bank['driver'],bank['output_pin'])]
            for directory in (before[tag],after[tag]):
                drawing=read(directory/(bank['id']+'.json'));ps=native.pins(drawing)
                if any(ps[k][0]!=bank['net'] or ps[k][2]!=term for k,term in zip(pair,row['terms'])):
                    raise ValueError('bank output/gate native binding changed: '+bank['id'])
                parts=native.components(drawing,bank['net'],sorted(k for k,v in ps.items() if v[0]==bank['net']),ps)
                connected=parts[pair[0]]==parts[pair[1]]
                native_states.append(dict(continuous=connected,source_agreement=connected==expected,targets=[ps[k][1] for k in pair],geometry_sha256=native.digest(directory/(bank['id']+'.json'))))
            source_checks.append(dict(name=bank['id']+':'+card+'.1--'+bank['driver']+'.'+str(bank['output_pin']),source=observed,baseline=native_states[0],candidate=native_states[1]))
    original=native.source;native.source=source
    try:runs=[native.audit(examples/corpus,before[tag],after[tag]) for tag,corpus in (('ag','analoggenie'),('ams','amsnet'))]
    finally:native.source=original
    prior=markers(examples,before,after)
    failures=[]
    for run in runs:
        failures += ['unstable:'+r['id']+':'+str(r['pin']) for r in run['unstable']]
        failures += ['unsupported:'+r['name']+':'+r['source']['reason'] for direction in ('gains','losses') for r in run[direction] if r['source']['status']=='unsupported']
        failures += ['source_agreement_regressed:'+n for names in run['expected_candidate_mismatches'].values() for n in names]
    if sorted(args.accept_resolved)!=prior['resolved']:
        failures.append('resolved_marker_names_require_review:'+str(dict(accepted=sorted(args.accept_resolved),observed=prior['resolved'])))
    result=dict(baseline=args.baseline_label,candidate=args.candidate_label,source_provenance=provenance,
                method_checks=methods,admitted_source_paths=source_checks,runs=runs,prior_markers=prior,
                accepted_resolved_markers=sorted(args.accept_resolved),failures=failures,
                dependency_sha256=dependency_hashes(),data_sha256=data_hashes(),limits='All changed stable device-pin pairs across complete paired corpora. Uncertified source geometry and unstable identities fail. Historical17/18 mismatch markers are observed separately without modifying their frozen files. Native connectivity does not prove electrical netlist equivalence; round trips remain separate.')
    result=json.loads(json.dumps(result))
    args.output.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    if args.check and result!=read(FIG/'driven_banks_connectivity_cases.json'):
        raise ValueError('every frozen source/native field and named mismatch must match')
    print(json.dumps(dict(failures=failures,prior_remaining=prior['remaining'],prior_resolved=prior['resolved'],
                         corpora={r['corpus']:dict(r['summary'],changed_drawings=r['changed_drawings'],source_inventory=r['source_inventory']) for r in runs}),indent=2))
    if failures:raise SystemExit(1)

if __name__=='__main__':main()
