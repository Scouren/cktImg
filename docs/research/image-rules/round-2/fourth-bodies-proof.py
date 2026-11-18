#!/usr/bin/env python3
"""Close the exact 23-case source-body denominator without relaxing source gates."""
import argparse
import copy
import importlib.util
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET

from bodies_census import ROOT, BASE, sha
import bodies_examples as b

HERE=Path(__file__).resolve().parent
THIRD=HERE/'third-bodies-proof.py'
spec=importlib.util.spec_from_file_location('third_body_proof',THIRD)
third=importlib.util.module_from_spec(spec);spec.loader.exec_module(third)

# Manually transcribed ordered raw-card literals, including model, not selected
# from source cache or from the implementation's parsed result.
LITERALS={
1236:'mp2 net2 vref net1 net8 pch;mp3 net7 vfp1 net1 net8 pch',
1294:'mp7 vx2 vref net2 net4 pch;mp8 va vfp1 net2 net4 pch',
1296:'mp4 net9 vfp1 net3 net6 pch;mp5 vx2 vref net3 net6 pch',
1297:'mp7 net2 vfp1 net1 net0 pch;mp8 vx2 vref net1 net0 pch',
1299:'mp7 vx2 vref net1 net6 pch;mp8 net0 vfp1 net1 net6 pch',
1307:'m15 vx2 vref net8 net7 pch;m16 net0 vfp1 net8 net7 pch',
1313:'mp7 vx2 vref net0 net7 pch;mp8 va vfp1 net0 net7 pch',
1319:'mp4 net6 vfp1 net5 net0 pch;mp5 vx2 vref net5 net0 pch',
1329:'m8 vx2 vref net6 net1 pch;m9 net3 vfp1 net6 net1 pch',
1335:'mp7 net2 vfp1 net6 net5 pch;mp8 vx2 vref net6 net5 pch',
1337:'m4 net2 vfp1 net8 net3 pch;m5 vx2 vref net8 net3 pch',
1343:'m13 net1 vfp1 net6 net2 pch;m14 vx2 vref net6 net2 pch',
1399:'m2 net6 vg net7 net5 pch;m3 vy vx net7 net5 pch',
1404:'m10 net0 vx net1 net4 pch;m11 net5 vg net1 net4 pch',
2193:'m2 vy vref net2 net3 pch;m3 vx fb net2 net3 pch',
2285:'m3 vx vref eao net11 pch;m4 vy fb eao net11 pch',
2287:'m3 vx vref eao net4 pch;m4 vy fb eao net4 pch',
2315:'m3 net6 vref net0 net3 pch;m4 net5 fb net0 net3 pch',
2397:'m5 vy vref vc net1 pch;m6 vx veaout vc net1 pch',
2463:'m12 net2 vfb net13 net5 pch;m13 va vref net13 net5 pch',
2464:'m12 net11 vfb net7 net5 pch;m13 vx vref net7 net5 pch',
2490:'m12 net5 vfb net1 net10 pch;m13 net3 vref net1 net10 pch',
2498:'m12 net6 vfb net9 net2 pch;m13 net5 vref net9 net2 pch'}


def literals(number):
    return {tokens[0]:tokens for row in LITERALS[number].split(';') if (tokens:=row.split())}


def upright_pmos_roles(root,device,geometry):
    """Literal source-family frame: arrow branch identifies S independently."""
    lines=[];branches=[];triangles=[]
    for element,matrix in b.transformed_elements(root):
        if element.get('data-object-id')!=geometry['actual_DGS']['object']:continue
        for e,local in b.transformed_elements(element,matrix):
            tag=e.tag.rsplit('}',1)[-1]
            if tag=='line':
                lines.append([b.apply(local,[float(e.get(x)),float(e.get(y))])
                              for x,y in (('x1','y1'),('x2','y2'))])
            elif tag in ('polyline','polygon'):
                values=list(map(float,re.findall(b.NUMBER,e.get('points',''))))
                points=[b.apply(local,values[i:i+2]) for i in range(0,len(values),2)]
                if tag=='polyline':branches.append([points[0],points[-1]])
                elif len(points)==3 and e.get('fill') not in (None,'none'):triangles.append(points)
    assert device['type']=='pmos' and len(lines)==1 and len(branches)==2 and len(triangles)==1
    assert b.close([0,lines[0][0][1]],[0,lines[0][1][1]])
    gate_y=lines[0][0][1];arrow_y=sum(p[1] for p in triangles[0])/3
    assert arrow_y<gate_y,'only the observed upright PMOS source family is admitted'
    ends=[max(branch,key=lambda p:abs(p[1]-gate_y)) for branch in branches]
    assert min(p[1] for p in ends)<arrow_y<gate_y<max(p[1] for p in ends)
    roles=dict(S=min(ends,key=lambda p:p[1]),D=max(ends,key=lambda p:p[1]),
               G=max(lines[0],key=lambda p:abs(p[0]-geometry['cached_B'][0])))
    assert all(b.close(point,device['terminals'][role]) for role,point in roles.items()),'cached D/G/S role contradicts actual arrow/outer-lead frame'
    return dict(actual_roles=roles,source_arrow=triangles[0],frame='upright PMOS, horizontal gate, source branch selected by actual arrow')


def strict_source(human,root,cards,pins):
    devices={d['card']:d for d in human['devices']}
    for card in cards:b.source_binding(devices[card],pins[card])
    proof=third.physical(human,root,cards)
    for card,g in zip(cards,proof['geometries']):
        assert g['literal_label_matches_card'],'actual instance-label contradiction or alias'
        assert g['containing_filled_polygons'],'cached B lacks actual own channel support'
        assert not g['B_is_own_lead_endpoint'],'source family has an unexpected fourth lead'
        g['independent_role_frame']=upright_pmos_roles(root,devices[card],g)
    assert not proof['cache_segments_without_actual_ink'],'cache claims absent source conductor'
    assert not proof['literal_net_labels'],'literal body-net label needs separate representation classification'
    return proof


def segment_text(points):
    a,c=points
    return f'M {a[0]:g} {a[1]:g} L {c[0]:g} {c[1]:g}'


def certify(entry):
    number=int(entry['id'][3:]);expected=literals(number);cards=list(expected)
    paths={key:ROOT/value['path'] for key,value in entry['source_and_native_files'].items()}
    for key,path in paths.items():assert sha(path)==entry['source_and_native_files'][key]['sha256']
    deck=paths['deck'].read_text()
    declarations=[line.lower().split() for line in deck.splitlines() if line.strip().lower().startswith('.model pch ')]
    assert declarations==[['.model','pch','pmos']],'unsupported or contradictory pch model declaration'
    formals,rows=b.parse(deck);raw={r['card']:r for r in rows};inc=b.incidence(rows)
    pins={card:tokens[1:5] for card,tokens in expected.items()}
    for card,tokens in expected.items():
        assert raw[card]['raw'].lower().split()[:6]==tokens
        assert raw[card]['nets']==pins[card]
        assert pins[card][3] not in pins[card][:3] and pins[card][3] not in formals
        assert sorted(inc[pins[card][3]])==sorted([[name,3,'B'] for name in cards])
    assert len({pins[card][2] for card in cards})==1,'separate common source expected'
    human=json.loads(paths['source_json'].read_text());root=ET.parse(paths['source_svg']).getroot()
    proof=strict_source(human,root,cards,pins)
    visible=number!=1236
    assert proof['named_body_connection']['continuous']==visible
    assert proof['all_actual_ink_connection']['continuous']==visible
    witness=None;deletion=None
    if visible:
        points=[g['cached_B'] for g in proof['geometries']]
        assert points[0][1]==points[1][1]
        texts=[segment_text(points),segment_text(list(reversed(points)))]
        matches=[(e,t) for e in root.iter() if e.get('data-role')=='conductor-ink'
                 for t in texts if t in e.get('d','')]
        assert len(matches)==1,'ambiguous or nonliteral direct body bridge'
        element,text=matches[0]
        assert element.get('stroke-dasharray')=='3 3'
        assert len(proof['named_actual_segments'])==1
        witness=dict(segment=text,stroke_dasharray=element.get('stroke-dasharray'),
                     stroke_width=element.get('stroke-width'))
        changed=copy.deepcopy(root);removed=0
        for e in changed.iter():
            if e.get('data-role')=='conductor-ink' and text in e.get('d',''):
                removed+=1;e.set('d',e.get('d').replace(text,text.split(' L ')[0]))
        assert removed==1
        after=third.physical(human,changed,cards)
        assert not after['named_body_connection']['continuous']
        assert not after['all_actual_ink_connection']['continuous']
        assert after['cache_segments_without_actual_ink']==proof['named_actual_segments']
        deletion=dict(deleted_only=text,named_connection=after['named_body_connection'],
            all_actual_connection=after['all_actual_ink_connection'],cache_disagreement=after['cache_segments_without_actual_ink'])
    else:
        assert not proof['named_actual_segments']
        assert proof['actual_segments_through_B']==[[],[]]
    return dict(id=entry['id'],literal_ordered_cards=expected,complete_body_incidence=inc[next(iter(pins.values()))[3]],
                raw_source_files=entry['source_and_native_files'],actual_source=proof,
                presentation='shared_dashed_bridge' if visible else 'omitted',
                literal_dashed_witness=witness,actual_segment_deletion_control=deletion)


def controls():
    ident='ag-1294';expected=literals(1294);cards=list(expected);pins={k:v[1:5] for k,v in expected.items()}
    human=json.loads((b.EXAMPLES/(ident+'.human.json')).read_text());root=ET.parse(b.EXAMPLES/(ident+'.svg')).getroot()
    result=[]
    changed=copy.deepcopy(root)
    label=next(e for e in changed.iter() if e.get('data-object-id')=='instance-label-MM6')
    label.clear();label.set('data-object-id','instance-label-MM6');label.text='MP8'
    try:strict_source(human,changed,cards,pins)
    except AssertionError:result.append('actual_instance_label_changed_rejected')
    else:raise AssertionError('actual wrong instance label accepted')
    changed=copy.deepcopy(root)
    own=next(e for e in changed.iter() if e.get('data-object-id')=='MM6')
    parent=next(e for e in changed.iter() if own in list(e));parent.append(copy.deepcopy(own))
    try:strict_source(human,changed,cards,pins)
    except ValueError:result.append('duplicate_actual_glyph_rejected')
    else:raise AssertionError('ambiguous actual glyph accepted')
    changed_human=copy.deepcopy(human)
    device=next(d for d in changed_human['devices'] if d['card']=='mp7')
    device['terminals']['D'],device['terminals']['S']=device['terminals']['S'],device['terminals']['D']
    try:strict_source(changed_human,root,cards,pins)
    except AssertionError:result.append('cached_D_S_swap_rejected_by_actual_arrow_frame')
    else:raise AssertionError('cached D/S role swap survived actual frame')
    # The stricter label gate still leaves external marker binding out of scope.
    return result


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('output',type=Path)
    ap.add_argument('--check',type=Path);args=ap.parse_args()
    views_path=HERE/'third-bodies-views.json';views=json.loads(views_path.read_text())
    assert {c['id'] for c in views['cases']}=={'ag-'+str(n) for n in LITERALS}
    cases=[];unsupported=[]
    for entry in views['cases']:
        try:cases.append(certify(entry))
        except (AssertionError,ValueError,KeyError) as error:
            unsupported.append(dict(id=entry['id'],kind=type(error).__name__,reason=str(error)))
    dependencies={name:sha(ROOT/name) for name in
                  json.loads((HERE/'third-bodies-evidence.json').read_text())['source_proof_helper_sha256']}
    dependencies.update({str(p.relative_to(ROOT)):sha(p) for p in (Path(__file__),THIRD,views_path,HERE/'third-bodies-evidence.json')})
    result=dict(scope='Fourth round extends physical source proof to the exact 23 previously viewed body-only circuits.',
        cases=cases,unsupported=unsupported,controls=controls(),
        certified_names=[c['id'] for c in cases],dependency_sha256=dependencies,
        remaining_limits=['Raw/cache supplies semantic net names; external label-to-formal binding remains unproved.',
                          'Body support is actual channel polygon support, not an own fourth lead.',
                          'Literal net-label absence does not prove absence of every possible textual annotation.',
                          'No operating-circuit, C ABI, or host roundtrip claim.'])
    if args.check:assert result==json.loads(args.check.read_text()),'fourth-body proof changed'
    args.output.write_text(json.dumps(result,indent=2)+'\n')
    assert not unsupported,unsupported
    print('PASS all 23 source physical cases; 138 D/G/S endpoints, 46 literal instance bindings; 22 actual bridge deletions')


if __name__=='__main__':main()
