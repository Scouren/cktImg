#!/usr/bin/env python3
"""Round 3: complete AG808/1242 raw bindings and actual source contacts.

Literal text/anchor/route witnesses certify AG1242's two VFP1 islands. They
are an explicit bounded association, not a nearest-label or prefix heuristic.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET

import ports_contracts as p

HERE=Path(__file__).resolve().parent
CASES={
 808:dict(card='x2',object='X2',formals='vdd vss out inn inp clk',
          nets='vdd vss vout vx vss phic',direction='right',
          tips={'vdd':[450,430],'out':[490,500],'inn':[400,480],'inp':[400,520],'clk':[450,570]}),
 1242:dict(card='x1',object='XEA',formals='vdd vss vb1 vb3 vb2 inp inn out vb4',
           nets='vdd vss vb1 vb3 vb2 vref vfp1 vctrl vb4',direction='left',
           tips={'vdd':[570,-40],'vb1':[530,90],'vb3':[590,90],'vb2':[560,90],
                 'inp':[640,-10],'inn':[640,50],'out':[500,20],'vb4':[620,100]})}
LABELS=[
 dict(object='label-04e85785-86c7-435d-91bd-1b1c012ee5e0',text='VFP1',anchor=[660,40],route=[[640,50],[660,50]]),
 dict(object='label-62d8d1ca-dcf2-497a-9d27-3d856bb1c8a7',text='VFP1',anchor=[418,265],route=[[410,250],[410,280]])]


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def label_islands(root,human,cards,ink):
    out=[]
    for expected in LABELS:
        nodes=[e for e in root.iter() if e.get('data-object-id')==expected['object']]
        assert len(nodes)==1,'label identity ambiguous'
        node=nodes[0];text=''.join(node.itertext());anchor=[float(node.get('x')),float(node.get('y'))]
        assert node.get('data-kind')=='net-label' and node.get('data-anchor-kind')=='route'
        assert text==expected['text'] and anchor==expected['anchor'],'literal VFP1 label changed'
        assert node.get('transform')==f"rotate(0 {expected['anchor'][0]} {expected['anchor'][1]})"
        a,b=expected['route'];route=p.path(ink,a,b);assert route is not None,'label island lacks actual conductor'
        out.append(dict(**expected,actual_path=route,raw_net=text.lower(),
                        association='Literal viewed label object/anchor and route pair; no automatic nearest-label inference.'))
    assert p.path(ink,LABELS[0]['route'][0],LABELS[1]['route'][0]) is None,'islands unexpectedly connected by ink'
    peers=[]
    for card,pin,expected in [('r1','2',[410,250]),('r2','1',[410,280])]:
        dev=next(d for d in human['devices'] if d['card']==card)
        actual=p.actual_resistor(root,dev)['terminals'][pin]
        assert actual==expected and cards[card][int(pin)]=='vfp1'
        peers.append(dict(card=card,pin=pin,net='vfp1',actual_endpoint=actual))
    return dict(net='vfp1',islands=out,raw_neighbours=peers,continuous_conductor_between_islands=False)


def source(n,root_override=None,human_override=None):
    expected=CASES[n];base=p.ROOT/f'external/examples/analoggenie/ag-{n}'
    _,cards,defs=p.deck(n);call=next(c for c in p.prior.calls(cards,defs) if c['card']==expected['card'])
    assert call['ports']==expected['formals'].split() and call['bindings']==expected['nets'].split()
    root=root_override if root_override is not None else ET.parse(base.with_suffix('.svg')).getroot()
    human=human_override if human_override is not None else json.loads(base.with_suffix('.human.json').read_text())
    dev,group,parent=p.a.source_group(human,root,expected['card']);assert group.get('data-object-id')==expected['object']
    body,leads,inside=p.a.primitives(group,parent);marks=p.a.polarity_marks(inside)
    signals,direction=p.a.signal_leads(body,leads,marks,['positive','negative','output'])
    assert direction==expected['direction']
    ink=p.conductor_ink(root);markers=p.marker_ink(root);used=[];rows=[]
    for index,(formal,net) in enumerate(zip(call['ports'],call['bindings'])):
        role=p.role(formal)
        row=dict(index=index,formal=formal,net=net,role=role)
        if formal=='vss':
            row.update(source_geometry='not_drawn',canonical_placement='choice_required');rows.append(row);continue
        if role in signals:
            matches=[(i,l) for i,l in enumerate(leads) if p.a.glyph.close(l['endpoint'],signals[role])]
        else:
            matches=[(i,l) for i,l in enumerate(leads) if any(m['net']==net and p.path(ink,l['endpoint'],m['point']) is not None for m in markers)]
        assert len(matches)==1,(n,formal,'ambiguous own lead')
        i,lead=matches[0];used.append(i)
        assert p.a.glyph.close(lead['endpoint'],expected['tips'][formal]),'literal actual tip changed'
        witnesses=[]
        for marker in markers:
            if route:=p.path(ink,lead['endpoint'],marker['point']):
                assert marker['net']==net,(n,formal,'contradictory reachable marker')
                witnesses.append(dict(marker=marker,actual_path=route))
        if role in ('supply','positive','clock','bias1','bias2','bias3','bias4') or (n==808 and role=='output'):
            assert witnesses,'required actual marker missing'
        cached=dev['terminals'].get(formal.upper())
        row.update(source_geometry='visible',lead=p.own_lead(body,lead),marker_witnesses=witnesses,
                   cached_tip=cached,cache_matches=cached is not None and p.a.glyph.close(cached,lead['endpoint']))
        rows.append(row)
    assert len(used)==len(leads)==len(set(used))
    neighbours=[];named=None
    if n==808:
        other=next(c for c in p.prior.calls(cards,defs) if c['card']=='x1')
        assert other['ports']==['vdd','vss','vb3','vb1','vb2','out','inn','inp','ib']
        assert p.candidate(other) is None,'IB was silently treated as fourth voltage bias'
        _,g,t=p.a.source_group(human,root,'x1');b,l,i=p.a.primitives(g,t)
        s,_=p.a.signal_leads(b,l,p.a.polarity_marks(i),['positive','negative','output'])
        assert other['bindings'][other['ports'].index('out')]=='vx'
        route=p.path(ink,expected['tips']['inn'],s['output']);assert route is not None
        neighbours.append(dict(formal='inn',net='vx',other_call=other,actual_other_output=s['output'],actual_path=route))
    else:
        named=label_islands(root,human,cards,ink)
        assert p.path(ink,expected['tips']['inn'],named['islands'][0]['route'][1]) is not None
        dev=next(d for d in human['devices'] if d['card']=='mp15')
        actual=p.actual_glyph(root,dev)['terminals']['G'];assert cards['mp15'][2]=='vctrl'
        route=p.path(ink,expected['tips']['out'],actual);assert route is not None
        neighbours.append(dict(formal='out',net='vctrl',card='mp15',pin='G',actual_endpoint=actual,actual_path=route))
    return dict(id=f'ag-{n}',call=call,contract=p.candidate(call),body=body,marks=marks,
                output_direction=direction,ports=rows,neighbour_witnesses=neighbours,named_island_witness=named,
                source_hashes={s:sha(base.with_suffix(s)) for s in ('.cir','.svg','.human.json')})


def native_binding(n,override=None):
    manifest=json.loads((HERE/'third-ports-native.json').read_text())
    assert sha(p.ROOT/manifest['binary'])==manifest['binary_sha256']
    row=next(r for r in manifest['runs'] if r['id']==f'ag-{n}')
    source=p.ROOT/row['json'];assert sha(source)==row['json_sha256']
    assert sha(p.ROOT/row['svg'])==sha(p.ROOT/row['frozen_svg'])==row['svg_sha256']
    data=json.loads(source.read_text())
    native=override if override is not None else next(d for d in data['devices'] if d['name']==CASES[n]['card'])
    assert [x['term'] for x in native['pins']]==CASES[n]['formals'].split()
    assert [x['net'] for x in native['pins']]==CASES[n]['nets'].split()
    assert len({tuple(x['xy']) for x in native['pins']})==len(native['pins'])
    return dict(id=f'ag-{n}',device=native,json_sha256=sha(source),frozen_svg_sha256=row['svg_sha256'],binary_sha256=manifest['binary_sha256'])


def controls():
    out=[]
    def reject(name,n,root):
        try:source(n,root_override=root)
        except (AssertionError,ValueError):out.append(name)
        else:raise AssertionError(name)
    root=ET.parse(p.ROOT/'external/examples/analoggenie/ag-1242.svg').getroot()
    for label in LABELS:
        changed=copy.deepcopy(root);node=next(x for x in changed.iter() if x.get('data-object-id')==label['object'])
        for child in list(node):node.remove(child)
        node.text='VREF'
        reject('contradictory_'+label['object'],1242,changed)
    changed=copy.deepcopy(root);node=next(x for x in changed.iter() if x.get('data-object-id')==LABELS[0]['object']);node.set('y','10')
    reject('stale_VFP1_label_anchor_rejected',1242,changed)
    changed=copy.deepcopy(root)
    for node in changed.iter():
        if node.get('data-role')=='conductor-ink':node.set('d',node.get('d').replace('M 640 50 L 660 50','M 640 20 L 660 20'))
    reject('stale_negative_wire_rejected',1242,changed)
    changed=copy.deepcopy(root)
    for node in changed.iter():
        if node.get('data-object-id')=='XEA':node.set('data-object-id','wrong-EA')
    reject('wrong_left_facing_body_identity_rejected',1242,changed)
    changed=copy.deepcopy(root)
    # Correct name on the wrong marker cannot replace the original VB4 route.
    for node in changed.iter():
        if node.get('data-object-id')=='instance-label-nVB4':
            for child in list(node):node.remove(child)
            node.text='VB3'
    reject('fourth_bias_marker_mislabel_rejected',1242,changed)
    for n in CASES:
        h=json.loads((p.ROOT/f'external/examples/analoggenie/ag-{n}.human.json').read_text())
        h['wires']=[];h['labels']=[]
        for dev in h['devices']:
            if dev['card']==CASES[n]['card']:dev['terminals']={key:[9999,9999] for key in dev['terminals']}
        value=source(n,human_override=h)
        assert [r['lead']['tip'] for r in value['ports'] if 'lead' in r]==[r['lead']['tip'] for r in source(n)['ports'] if 'lead' in r]
        out.append(f'ag{n}_corrupt_cached_target_tips_wires_labels_preserves_actual_proof')
    clock=ET.parse(p.ROOT/'external/examples/analoggenie/ag-808.svg').getroot()
    for node in clock.iter():
        if node.get('data-object-id')=='instance-label-pCLK':
            for child in list(node):node.remove(child)
            node.text='IB'
    reject('clock_marker_mislabeled_as_IB_rejected',808,clock)
    value=source(1242);vdd=next(r for r in value['ports'] if r['formal']=='vdd')
    assert not vdd['lead']['body_behind_tip'] and vdd['lead']['support_min']==-10
    out.append('left_facing_VDD_support_failure_retained_as_pose_boundary')
    # A horizontal reflection can change facing without changing vertical
    # signed/rail order. A half-turn does not preserve that order.
    source_tips=CASES[1242]['tips']
    reflect={name:[1140-xy[0],xy[1]] for name,xy in source_tips.items()}
    halfturn={name:[1140-xy[0],40-xy[1]] for name,xy in source_tips.items()}
    assert reflect['inp'][1]==-10 and reflect['inn'][1]==50 and reflect['vdd'][1]==-40
    assert halfturn['inp'][1]==50 and halfturn['inn'][1]==-10 and halfturn['vdd'][1]==80
    out.append('horizontal_reflection_and_half_turn_have_distinct_signed_rail_order')
    native=native_binding(1242)['device']
    for kind in ('drop_declared_vss','swap_signed_roles','swap_signed_nets'):
        changed=copy.deepcopy(native)
        if kind=='drop_declared_vss':changed['pins'].pop(1)
        else:
            key='term' if kind=='swap_signed_roles' else 'net'
            changed['pins'][5][key],changed['pins'][6][key]=changed['pins'][6][key],changed['pins'][5][key]
        try:native_binding(1242,changed)
        except AssertionError:out.append('native_'+kind+'_rejected')
        else:raise AssertionError(kind)
    return out


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--output',type=Path,required=True);ap.add_argument('--check',type=Path);args=ap.parse_args()
    result=dict(scope='Round3 completion of two extra full-corpus contracts; fifteen raw formals, thirteen visible own leads, two undrawn VSS terminals.',
                cases=[source(n) for n in CASES],native_bindings=[native_binding(n) for n in CASES],controls=controls(),
                prior_five_certificate_sha256=sha(HERE/'ports_contracts.json'),native_replay_manifest_sha256=sha(HERE/'third-ports-native.json'),
                dependencies={**p.prior.dependencies(),'ports_contracts.py':sha(Path(p.__file__)),Path(__file__).name:sha(Path(__file__))})
    result=json.loads(json.dumps(result))
    if args.check:assert result==json.loads(args.check.read_text())
    args.output.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps(dict(cases=[r['id'] for r in result['cases']],controls=result['controls'])))


if __name__=='__main__':main()
