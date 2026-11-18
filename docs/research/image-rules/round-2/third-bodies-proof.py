#!/usr/bin/env python3
"""Twenty-three ordered body contracts; actual source geometry for three examples.

The 23 source-style classifications are manual observations in a separate ledger.
This checker deliberately does not promote them all to physical certificates.
"""
import argparse
import copy
import json
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET

import bodies_examples as b
from bodies_census import ROOT, BASE, parse, incidence, sha
from thin_connectivity import on, label_evidence

HERE=Path(__file__).resolve().parent
RUN=BASE/'image-rule-round-2/bodies/third-bodies'
LITERALS={
 'ag-1236':{'mp2':['net2','vref','net1','net8'],'mp3':['net7','vfp1','net1','net8']},
 'ag-1294':{'mp7':['vx2','vref','net2','net4'],'mp8':['va','vfp1','net2','net4']},
 'ag-2490':{'m12':['net5','vfb','net1','net10'],'m13':['net3','vref','net1','net10']}}


def physical(human, root, cards):
    devices={d['card']:d for d in human['devices']}
    geometries=[b.body_geometry(root,devices[card]) for card in cards]
    points=[g['cached_B'] for g in geometries]
    nets=[devices[card]['nets']['B'].lower() for card in cards]
    assert len(set(nets))==1
    ink=b.conductor_ink(root)
    verified,missing=b.verified_segments(human,nets[0],ink)
    support=[[s for s in ink if on(point,*s)] for point in points]
    named=b.source_connection(dict(junctions=b.junctions(root)),verified,points)
    all_strokes=b.source_connection(dict(junctions=b.junctions(root)),ink,points)
    return dict(geometries=geometries,body_net=nets[0],named_actual_segments=verified,
                cache_segments_without_actual_ink=missing,actual_segments_through_B=support,
                named_body_connection=named,all_actual_ink_connection=all_strokes,
                literal_net_labels=label_evidence(root,nets[0]))


def controls():
    ident='ag-1294'
    human=json.loads((b.EXAMPLES/(ident+'.human.json')).read_text())
    root=ET.parse(b.EXAMPLES/(ident+'.svg')).getroot()
    before=physical(human,root,list(LITERALS[ident]))
    assert before['named_body_connection']['continuous']
    changed=copy.deepcopy(root);hits=0
    for e in changed.iter():
        if e.get('data-role')!='conductor-ink':continue
        text=e.get('d','');old='M 606 100 L 714 100'
        if old in text:
            hits+=text.count(old);e.set('d',text.replace(old,'M 606 100'))
    assert hits==1
    after=physical(human,changed,list(LITERALS[ident]))
    assert not after['named_body_connection']['continuous']
    assert not after['all_actual_ink_connection']['continuous']
    assert after['cache_segments_without_actual_ink']==[[[606,100],[714,100]]]
    # Rename semantic nodes in every cache occurrence, preserving actual ink.
    renamed=copy.deepcopy(human)
    for d in renamed['devices']:
        d['nets']={role:('renamed_well' if n.lower()=='net4' else n) for role,n in d['nets'].items()}
    for wire in renamed['wires']:
        if wire['net'].lower()=='net4':wire['net']='renamed_well'
    renamed['devices'].reverse();renamed['wires'].reverse()
    replay=physical(renamed,root,list(reversed(LITERALS[ident])))
    assert replay['named_body_connection']['continuous']
    assert replay['named_actual_segments']==before['named_actual_segments']
    altered=copy.deepcopy(next(d for d in human['devices'] if d['card']=='mp7'))
    altered['nets']['B']=altered['nets']['S']
    try:b.source_binding(altered,LITERALS[ident]['mp7'])
    except AssertionError:pass
    else:raise AssertionError('B rebound to S passed ordered binding')
    return dict(actual_AG1294_bridge_deletion=dict(before=before['named_body_connection'],
                after=after['named_body_connection'],all_actual_after=after['all_actual_ink_connection'],
                missing=after['cache_segments_without_actual_ink']),
                consistent_net_rename_and_record_reorder_preserve_connection=True,
                cached_B_rebound_to_S_rejected=True)


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('output',type=Path)
    ap.add_argument('--replay-native',action='store_true');ap.add_argument('--render-crops',action='store_true')
    ap.add_argument('--check',type=Path);args=ap.parse_args()
    manifest=json.loads((RUN/'manifest.json').read_text())
    binary=BASE/'resistor-output-integrated-common/zig-out/bin/cktimg-json'
    native_dir=RUN/'native';native_dir.mkdir(exist_ok=True)
    cases=[];physical_cases=[]
    for entry in manifest['cases']:
        ident=entry['id'];cards={m['card']:m['pins'] for m in entry['body_cards']}
        paths={key:ROOT/value['path'] for key,value in entry['files'].items()}
        for key,path in paths.items():assert sha(path)==entry['files'][key]['sha256']
        native_json=native_dir/(ident+'.json');native_svg=native_dir/(ident+'.svg')
        if args.replay_native:
            subprocess.run([str(binary),'--svg',str(native_svg),str(paths['deck']),str(native_json)],check=True)
        assert native_svg.read_bytes()==paths['native_svg'].read_bytes()
        native=json.loads(native_json.read_text());nd={d['name']:d for d in native['devices']}
        formals,rows=parse(paths['deck'].read_text());raw={r['card']:r for r in rows};inc=incidence(rows)
        human=json.loads(paths['source_json'].read_text());drawn={d['card']:d for d in human['devices']}
        checked=[]
        for card,pins in cards.items():
            assert raw[card]['nets']==pins
            assert pins[3] not in pins[:3] and pins[3] not in formals
            assert sorted(inc[pins[3]])==sorted([[name,3,'B'] for name in cards])
            b.source_binding(drawn[card],pins);b.native_binding(nd[card],pins)
            assert nd[card]['bulk']==pins[3] and len(nd[card]['pins'])==3
            assert not any(w['net']==pins[3] for w in native['wires'])
            checked.append(dict(card=card,ordered_DGSB=pins,raw=raw[card]['raw'],
                model=raw[card]['nonterminal_tokens'][0],source_type=drawn[card]['type'],
                complete_body_incidence=inc[pins[3]],native=nd[card],source_binding='raw/cache pass'))
        cases.append(dict(id=ident,checked=checked,files=entry['files'],
            native_json=dict(path=str(native_json.relative_to(ROOT)),sha256=sha(native_json)),
            replay_svg_sha256=sha(native_svg),native_body_route_absent=True))
        if ident not in LITERALS:continue
        assert cards==LITERALS[ident]
        root=ET.parse(paths['source_svg']).getroot();proof=physical(human,root,list(cards))
        expected=ident!='ag-1236'
        assert proof['named_body_connection']['continuous']==expected
        assert proof['all_actual_ink_connection']['continuous']==expected
        assert not proof['cache_segments_without_actual_ink']
        assert all(not g['B_is_own_lead_endpoint'] and g['containing_filled_polygons'] for g in proof['geometries'])
        assert not proof['literal_net_labels']
        if not expected:assert proof['actual_segments_through_B']==[[],[]]
        crop_points=[p for g in proof['geometries'] for p in g['actual_DGS']['terminals'].values()]
        x=min(p[0] for p in crop_points)-50;y=min(p[1] for p in crop_points)-55
        width=max(p[0] for p in crop_points)-x+50;height=max(p[1] for p in crop_points)-y+45
        crop=RUN/(ident+'-source-crop.svg');png=RUN/(ident+'-source-crop.png')
        if args.render_crops:
            root.set('viewBox',f'{x} {y} {width} {height}')
            ET.ElementTree(root).write(crop,encoding='utf-8',xml_declaration=True)
            subprocess.run(['magick','-background','white',str(crop),'-resize','1400x1000',str(png)],check=True)
        physical_cases.append(dict(id=ident,literal_expected_DGSB=LITERALS[ident],proof=proof,
            crop_box=[x,y,width,height],crop_files={str(p.relative_to(ROOT)):sha(p) for p in (crop,png)}))
    result=dict(scope='All 23 exact raw/native body contracts; actual source geometry only 1236/1294/2490',
        cases=cases,physical_representatives=physical_cases,controls=controls(),
        source_geometry_unproved_names=[c['id'] for c in cases if c['id'] not in LITERALS],
        limitations=['Actual formal label-to-net binding not certified; raw/cache supplies semantic names.',
                    'No C ABI or Schemify round trip; no circuit-operating claim.',
                    'Dashed versus omitted source class is manually viewed, not inferred by this checker.'],
        binary_sha256=sha(binary),manifest_sha256=sha(RUN/'manifest.json'),
        dependency_sha256={str(p.relative_to(ROOT)):sha(p) for p in (Path(__file__),HERE/'bodies_examples.py',HERE/'bodies_census.py')},
        source_proof_helper_sha256={name:sha(ROOT/name) for name in
            json.loads((HERE/'bodies_evidence.json').read_text())['dependency_sha256']})
    if args.check:assert result==json.loads(args.check.read_text()),'third-body evidence changed'
    args.output.write_text(json.dumps(result,indent=2)+'\n')
    print('PASS 23 exact names, 46 D/G/S/B bindings, 3 literal physical cases and actual bridge deletion')


if __name__=='__main__':main()
