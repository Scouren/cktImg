#!/usr/bin/env python3
"""Independent local relation/footprint gates plus two actual caller-pose controls."""
import argparse
import copy
import json
from pathlib import Path

from importlib.util import spec_from_file_location, module_from_spec

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]


def load(name):
    spec = spec_from_file_location(name, HERE / (name + '.py'))
    m = module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


p = load('twelfth-organization-probe')
parser = load('ninth-local-groups-census')
frames = load('tenth-arrangement-proof')


def assess(devices, candidate):
    leads = {d: [v['pins'][0]['xy'], v['pins'][2]['xy']] for d, v in devices.items()}
    measured = p.geometry(leads, candidate)
    relations = ['branch_columns', 'inputs_same_row', 'loads_same_row', 'tail_between', 'branch_order', 'tail_beyond_inputs']
    directed = {}
    for name in candidate['members']:
        device = devices[name]
        expected_type = candidate['input_type']
        if name in candidate['loads']:
            expected_type = 'pmos' if expected_type == 'nmos' else 'nmos'
        sign = 1 if expected_type == 'nmos' else -1
        drain, source = device['pins'][0], device['pins'][2]
        directed[name] = (device['class'] == expected_type and drain['term'] == 'd' and source['term'] == 's'
                          and sign * (source['xy'][1] - drain['xy'][1]) > 0)
    # Chosen literal default-class reference, measured separately by six frozen runs.
    # This fixed test obligation is independent of the proposal's H/V syntax.
    verdict = all(measured[k] for k in relations) and all(directed.values()) and measured['span'] <= 140 and measured['height'] <= 150
    return dict(measurements=measured, relation_checks={k:measured[k] for k in relations},
                directed_channel_roles=directed,
                within_frozen_local_reference=measured['span'] <= 140 and measured['height'] <= 150, pass_local_gate=verdict)


def shift(device, dx, dy):
    device['pos'] = [device['pos'][0] + dx, device['pos'][1] + dy]
    for pin in device['pins']:
        pin['xy'] = [pin['xy'][0] + dx, pin['xy'][1] + dy]


def canonical(candidates, device_map=None, net_map=None):
    dm, nm = device_map or {}, net_map or {}
    d = lambda name: dm.get(name,name)
    n = lambda name: nm.get(name,name)
    result=[]
    for c in candidates:
        boundaries = sorted((n(net), sorted((d(q),k) for q,k in b['inside']), sorted((d(q),k) for q,k in b['outside']),b['formal'],b['rail']) for net,b in c['complete_boundary'].items())
        result.append((tuple(sorted(d(q) for q in c['members'])),d(c['tail']),sorted((d(a),d(b)) for a,b in zip(c['inputs'],c['loads'])),c['input_type'],c['common_control'],boundaries))
    return sorted(result)


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--execute',action='store_true')
    ap.add_argument('--check',type=Path)
    ap.add_argument('--output',type=Path,default=HERE/'twelfth-organization-proof.json')
    args=ap.parse_args()
    path=HERE/'twelfth-organization-probe.json'
    probe=json.loads(path.read_text())
    assert probe['script_sha256']==p.sha(HERE/'twelfth-organization-probe.py')
    for r in probe['records']:
        for file,digest in r['artifacts'].items():assert p.sha(ROOT/file)==digest
        assert p.sha(ROOT/r['raster']['path'])==r['raster']['sha256']
        if r['candidate']['common_control']:
            assert r['isolated_geometry']['span']==140 and r['isolated_geometry']['height']==150
    source_path=p.EXAMPLES/'ag-1080.cir'
    original=source_path.read_text().lower()
    raw,formals,models,rails,declarations=parser.facts(original)
    baseline_path=p.BASE/'image-rule-round-2/groups/ninth/ag-1080.json'
    original_document=json.loads(baseline_path.read_text())
    baseline=p.native_cards(original_document,raw,models)
    chosen=[r for r in probe['records'] if r['id']=='ag-1080']
    assert len(chosen)==2
    baseline_gates=[assess(baseline,r['candidate']) for r in chosen]
    assert all(not v['pass_local_gate'] for v in baseline_gates)
    runs=[]
    for kind in ('translate','reconstruct'):
        expected=copy.deepcopy(baseline)
        for index,r in enumerate(chosen):
            candidate=r['candidate']; tail=candidate['tail']
            old=baseline if kind=='translate' else r['isolated_devices']
            min_y=min(old[d]['pos'][1] for d in candidate['members'])
            dx=(500+800*index)-old[tail]['pos'][0]
            dy=600-min_y
            for name in candidate['members']:
                expected[name]=copy.deepcopy(old[name]);shift(expected[name],dx,dy)
        hints=[]
        for name,d in sorted(expected.items()):
            hints.append(f"*@ at {name} {d['pos'][0]/40:g} {d['pos'][1]/40:g} {'m' if d['mirror'] else ''}r{d['rot']*90}")
        text=original.replace('.ends dut','\n'.join(hints)+'\n.ends dut')
        name='ag-1080-'+kind
        output=p.run(name,text,args.execute)
        doc=json.loads((p.RUN/(name+'.json')).read_text())
        report=json.loads((p.RUN/(name+'.report.json')).read_text())
        actual=p.native_cards(doc,raw,models)
        checked=frames.check_frames(raw,text,doc,models)
        assert actual==checked
        for d,wanted in expected.items():
            for key in ('pos','rot','mirror','pins','class','bulk','value'):assert actual[d][key]==wanted[key],(d,key)
        ats=[r for r in report['requests'] if r['text'].startswith('*@ at ')]
        assert len(ats)==len(raw) and {r['text'] for r in ats}==set(hints)
        assert all(r['state']=='honoured' and r['code']=='ok' for r in ats)
        gates=[assess(actual,r['candidate']) for r in chosen]
        assert all(v['pass_local_gate']==(kind=='reconstruct') for v in gates)
        runs.append(dict(kind=kind,local_gates=gates,actual_raw_devices=actual,original_ordered_cards=raw,original_formals=formals,
                         report_requests=report['requests'],reported_metrics=report['metrics'],**output))
    variants={}
    compact=copy.deepcopy(runs[1]['actual_raw_devices']); c=chosen[0]['candidate']
    for what in ('scale_local_x','stagger_input','tail_outside','break_column','rotate_input_180','translate_whole'):
        mutant=copy.deepcopy(compact); center=mutant[c['tail']]['pos'][0]
        if what=='scale_local_x':
            for d in c['members']:shift(mutant[d],mutant[d]['pos'][0]-center,0)
        elif what=='stagger_input':shift(mutant[c['inputs'][0]],0,20)
        elif what=='tail_outside':shift(mutant[c['tail']],200,0)
        elif what=='break_column':shift(mutant[c['loads'][0]],20,0)
        elif what=='rotate_input_180':
            d=mutant[c['inputs'][0]]; d['rot']=(d['rot']+2)%4
            for pin,xy in zip(d['pins'],[(20,0),(0,-20),(-20,0)]):
                pin['xy']=frames.transformed(xy,d['rot'],d['mirror'],d['pos'])
        else:
            for d in c['members']:shift(mutant[d],113,-227)
        result=assess(mutant,c);assert result['pass_local_gate']==(what=='translate_whole')
        variants[what]=result
    transports={}
    for ident in probe['raw_five_mos_names']:
        values=parser.facts((p.EXAMPLES/(ident+'.cir')).read_text()); cards,fs,ms,rs,ds=values
        base=p.collect(parser.decompose(*values))
        reversed_cards=dict(reversed(list(cards.items())))
        assert canonical(p.collect(parser.decompose(reversed_cards,fs,ms,rs,ds)))==canonical(base)
        dn={d:'mopaque'+str(i) for i,d in enumerate(reversed(sorted(cards)))}
        ns={n:'netopaque'+str(i) for i,n in enumerate(reversed(sorted({n for r in cards.values() for n in r[1:5]})))}
        renamed={dn[d]:[dn[d]]+[ns[n] for n in r[1:5]]+r[5:] for d,r in cards.items()}
        changed=p.collect(parser.decompose(renamed,[ns[n] for n in fs],ms,{ns[n]:v for n,v in rs.items()}))
        assert canonical(changed,{v:k for k,v in dn.items()},{v:k for k,v in ns.items()})==canonical(base)
        transports[ident]=dict(card_reversal=True,complete_device_net_formal_rail_transport=True)
    result=dict(script_sha256=p.sha(Path(__file__)),dependencies={p.rel(f):p.sha(f) for f in
                (path,HERE/'twelfth-organization-probe.py',HERE/'tenth-arrangement-proof.py',source_path,baseline_path)},
                baseline_local_gates=baseline_gates,runs=runs,geometry_mutations=variants,transports=transports,
                scope='Two executed full-DUT explicit-caller pose witnesses,64 MOS contracts/256 raw occurrences. Local relation/140x150 footprint gate only; no full-page quality, automatic placement, final physical partition or target claim.')
    if args.check:assert result==json.loads(args.check.read_text())
    args.output.write_text(json.dumps(result,sort_keys=True,indent=2)+'\n')
    print(json.dumps({'frozen_full_dut_runs':2,'native_raw_contracts':64,'baseline_local_passes':0,'translate_local_passes':0,'reconstructed_local_passes':2}))


if __name__=='__main__':main()
