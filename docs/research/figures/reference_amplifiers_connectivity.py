#!/usr/bin/env python3
"""Reference-glyph checkpoint: native pin-pair changes against actual source ink.

Arguments name the complete paired native corpora and independently generated
reference source report. Source expectations remain unchanged: --check replays
known tradeoffs exactly; --require-preserved rejects source-agreement losses,
including already recorded ones. Unknown geometry is an error, never a skip.
"""

import argparse
import json
from pathlib import Path
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import thin_connectivity as native

PRIMITIVE_SOURCE=native.source
REFERENCE_ROWS={}


def source_observation(context,row):
    if all(card[0]!='x' for card,index in row['pins']):return PRIMITIVE_SOURCE(context,row)
    targets=[]
    evidence=dict(source_sha256=context['source_sha256'],ordered_terminal_bindings=[],source_glyphs={},
                  literal_net_labels=native.label_evidence(context['root'],row['net']))
    try:
        for (card,index),term in zip(row['pins'],row['terms']):
            if card[0]=='x':
                ref=REFERENCE_ROWS.get((row['id'],card))
                if ref is None:raise ValueError('no independent named actual lead certificate for other custom block '+card)
                if not 0 <= index < len(ref['ports']) or ref['ports'][index]!=term or ref['bindings'][index]!=row['net']:
                    raise ValueError('reference ordered source/native port binding disagrees')
                if context['cards'][card][index+1]!=row['net']:
                    raise ValueError('reference SPICE call binding disagrees')
                if term not in ref['visible_port_mapping']:
                    raise ValueError('reference '+term+' has no actual source lead geometry; missing source VSS is unknown')
                proof=ref['visible_port_mapping'][term]
                point=proof['endpoint']
                evidence['source_glyphs'][card]=dict(object=ref['source_object'],source_sha256=ref['source_sha256'],actual_named_port_certificates=ref['visible_port_mapping'],missing_source_geometry=ref['missing_geometry'])
                name=term
            else:
                device=context['devices'][card];name=native.terminal(device,index,term)
                if context['cards'][card][index+1]!=row['net'] or device['nets'][name].lower()!=row['net']:
                    raise ValueError('primitive source/card/native binding mismatch')
                if card not in context['glyphs']:
                    reader=native.actual_resistor if card[0]=='r' else native.actual_inductor if card[0]=='l' else native.actual_glyph
                    context['glyphs'][card]=reader(context['root'],device)
                evidence['source_glyphs'][card]=context['glyphs'][card]
                point=context['glyphs'][card]['terminals'][name]
            evidence['ordered_terminal_bindings'].append(dict(card=card,card_index=index,native_term=term,source_term=name,net=row['net'],xy=point))
            targets.append(point)
        if row['net'] not in context['nets']:
            context['nets'][row['net']]=native.verified_segments(context['human'],row['net'],context['ink'])
        ink,missing=context['nets'][row['net']]
        proof=native.source_connection(context,ink,targets)
        evidence.update(verified_ink_segments=ink,cache_segments_without_ink=missing,source_connection=proof)
        if proof['continuous']:return dict(status='source_connected',**evidence)
        whole=native.source_connection(context,context['ink'],targets)
        evidence['whole_svg_connection']=whole
        if whole['continuous']:return dict(status='unsupported',reason='actual conductor path lacks verified named-net assignment',**evidence)
        return dict(status='source_disconnected',**evidence)
    except (ValueError,KeyError,IndexError,AssertionError) as error:
        return dict(status='unsupported',reason=str(error),**evidence)


def checks():
    methods=native.checks()
    # Explicit missing VSS must remain unknown even when other source ink is empty.
    ident=('literal-ref','x1')
    REFERENCE_ROWS[ident]=dict(ports=['vref','vss','out'],bindings=['a','0','b'],visible_port_mapping={})
    row=dict(id=ident[0],net='0',pins=[['x1',1],['x1',1]],terms=['vss','vss'])
    import xml.etree.ElementTree as ET
    context=dict(source_sha256={},root=ET.fromstring('<svg/>'),cards={'x1':['x1','a','0','b','aea']})
    observed=source_observation(context,row)
    assert observed['status']=='unsupported' and 'no actual source lead geometry' in observed['reason']
    row['terms']=['out','out']
    assert 'binding disagrees' in source_observation(context,row)['reason']
    del REFERENCE_ROWS[ident]
    return methods+['missing_source_reference_vss_is_unknown','wrong_reference_port_binding_rejected']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('examples', type=Path)
    parser.add_argument('source_report', type=Path)
    parser.add_argument('output', type=Path)
    for side in ('baseline', 'candidate'):
        for corpus in ('ag', 'ams'):
            parser.add_argument('--'+side+'-'+corpus, type=Path, required=True)
    parser.add_argument('--baseline-label', default='iteration17-bounded')
    parser.add_argument('--candidate-label', default='iteration18-reference')
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--require-preserved', action='store_true')
    args = parser.parse_args()

    source = json.loads(args.source_report.read_text())
    inventory = HERE/'reference_amplifiers_cases.json'
    if source != json.loads(inventory.read_text()):
        raise ValueError('source report differs from exact named reference inventory')
    # Repeat actual source SVG inspection; a hash or matching count alone is
    # insufficient to establish that these reference ports own the ink.
    with tempfile.TemporaryDirectory(prefix='reference-connectivity-') as work:
        replay = Path(work)/'source.json'
        subprocess.run([sys.executable, '-B', str(HERE/'reference_amplifiers.py'),
                        str(args.examples), str(replay)], check=True, capture_output=True)
        if json.loads(replay.read_text()) != source:
            raise ValueError('source report no longer matches actual source lead evidence')
    REFERENCE_ROWS.update({(r['id'], r['card']): r for r in source['rows']})
    methods = checks()
    native.source = source_observation
    try:
        runs = [native.audit(args.examples/corpus,
                             getattr(args, 'baseline_'+tag), getattr(args, 'candidate_'+tag))
                for corpus, tag in (('analoggenie', 'ag'), ('amsnet', 'ams'))]
    finally:
        native.source = PRIMITIVE_SOURCE
    selected = sorted({r['id'] for r in source['rows']})
    if (runs[0]['changed_drawings'] != selected or runs[0]['changed_reports'] != selected
            or runs[1]['changed_drawings'] or runs[1]['changed_reports']):
        raise ValueError('exact reference-only geometry/report change inventory differs')
    dependencies = set(source['audit_sha256']) | {
        Path(__file__).name, 'thin_connectivity.py', 'trunk_rungs.py', 'cross_caps.py',
        'input_resistors.py', 'input_resistor_legs.py', 'converter_loops.py',
        'converter_terminals.py', 'channel_bridges.py', inventory.name}
    result = dict(baseline=args.baseline_label, candidate=args.candidate_label,
                  runs=runs, method_checks=methods, selected_names=source['selected'],
                  source_reference_inventory_sha256=native.digest(inventory),
                  source_report_sha256=native.digest(args.source_report),
                  dependency_sha256={name: native.digest(HERE/name) for name in sorted(dependencies)},
                  limits='All stable named native pin-pair transitions on the exact fifteen changed drawings. Pair counts are correlated. Reference source leads require independently replayed actual SVG certificates; absent source VSS coordinates and uncertified blocks remain unknown. Matching labels never connect physical ink. Exact known mismatches are not physical parity or electrical failures.')
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True)+'\n')
    unsupported = [dict(name=r['name'], reason=r['source']['reason'])
                   for run in runs for direction in ('gains', 'losses') for r in run[direction]
                   if r['source']['status']=='unsupported']
    if unsupported or any(run['unstable'] for run in runs):
        raise ValueError('unsupported source or unstable native pin identities: '+str(unsupported))
    if args.check:
        expected = json.loads((HERE/'reference_amplifiers_connectivity_cases.json').read_text())
        if json.loads(json.dumps(result)) != expected:
            raise ValueError('exact evidence or tradeoff inventory changed; review new AND resolved mismatches')
    summary = {run['corpus']: dict(run['summary'], source={direction: {k: len(v) for k, v in inv.items()}
               for direction, inv in run['source_inventory'].items()}) for run in runs}
    print(json.dumps(summary, indent=2, sort_keys=True))
    regressions = sorted(name for run in runs for names in run['expected_candidate_mismatches'].values() for name in names)
    if args.require_preserved and regressions:
        raise ValueError('source-agreement preservation failed: '+str(regressions))


if __name__ == '__main__':
    main()
