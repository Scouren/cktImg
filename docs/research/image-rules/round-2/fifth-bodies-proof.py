#!/usr/bin/env python3
"""Bind six external body formals to actual source port objects and attached text.

Only explicit object IDs, supported literal marker geometry, and actual-ink paths
associate text with contacts. No nearest-label or net-spelling direction inference.
"""
import argparse
import copy
import json
import math
from pathlib import Path
import re
import xml.etree.ElementTree as ET

import bodies_examples as b
from bodies_census import ROOT, BASE, sha

HERE=Path(__file__).resolve().parent
EXPECTED={
1014:{'m1':('m1','vout1 vdd net1 vi1'),'m2':('m2','vout2 vdd net1 vi2')},
1026:{'m1':('m1','net6 vss net5 vin-'),'m2':('m2','net3 vss net5 vin+')},
1057:{'mn5':('n5','out cinn net2 pwell'),'mn6':('n6','out_bar cinp net3 pwell'),
      'mn7':('n7','net2 out_bar net1 pwell'),'mn8':('n8','net3 out net1 pwell')},
1065:{'mp0':('p0','out clkr vcomp nwell'),'mp1':('p1','out_bar clkr vcomp nwell')}}


def object_label(root,ident):
    found=[e for e in root.iter() if e.get('data-object-id')==ident]
    assert len(found)==1,('ambiguous or absent attached marker label',ident)
    label=found[0]
    assert label.get('data-anchor-kind')=='object'
    plain=''.join(label.itertext()).strip()
    supers=[e for e in label.iter() if e.get('data-text-run')=='superscript']
    subs=[e for e in label.iter() if e.get('data-text-run')=='subscript']
    bars=[e for e in label.iter() if e.get('data-text-run')=='overbar']
    token=plain.lower();interpretation='case-folded literal attached text'
    if supers:
        assert len(supers)==len(subs)==1 and not bars,'unsupported signed marker typography'
        sign=''.join(supers[0].itertext());sub=''.join(subs[0].itertext())
        assert sign in ('+','-') and sub.lower()=='in' and plain.lower()=='v'+sign+'in'
        token='vin'+sign;interpretation='explicit v base, sign superscript, in subscript'
    elif bars:
        assert len(bars)==1 and not subs
        token=plain.lower()+'_bar';interpretation='explicit overbar text-run'
    descendants=set(label.iter())
    positions=[dict(xy=b.apply(matrix,[float(e.get('x','0')),float(e.get('y','0'))]),
                    text_anchor=e.get('text-anchor')) for e,matrix in b.transformed_elements(root)
               if e in descendants and e.tag.rsplit('}',1)[-1]=='text']
    return dict(object=ident,plain_text=plain,semantic_token=token,interpretation=interpretation,
                actual_text_positions=positions,
                runs=[dict(role=e.get('data-text-run'),text=''.join(e.itertext())) for e in label.iter()
                      if e.get('data-text-run') in ('superscript','subscript','overbar')])


def primitive_lines(element,matrix):
    result=[]
    for e,local in b.transformed_elements(element,matrix):
        if e.tag.rsplit('}',1)[-1]=='line':
            result.append([b.apply(local,[float(e.get(x)),float(e.get(y))])
                           for x,y in (('x1','y1'),('x2','y2'))])
    return result


def actual_markers(root):
    markers=[];used_labels=set();ink=b.conductor_ink(root)
    for element,matrix in b.transformed_elements(root):
        kind=element.get('data-symbol-id')
        if kind not in ('port','ground','vdd-port'):continue
        ident=element.get('data-object-id');lines=primitive_lines(element,matrix)
        label=None;geometry={}
        if kind=='port':
            circles=[]
            for e,local in b.transformed_elements(element,matrix):
                if e.tag.rsplit('}',1)[-1]!='circle':continue
                sx=math.hypot(local[0],local[1]);sy=math.hypot(local[2],local[3])
                assert abs(sx-1)<1e-5 and abs(sy-1)<1e-5,'unsupported scaled port circle'
                circles.append((b.apply(local,[float(e.get('cx')),float(e.get('cy'))]),float(e.get('r'))))
            assert len(lines)==len(circles)==1,('unsupported port glyph',ident)
            centre,radius=circles[0]
            ends=sorted(lines[0],key=lambda p:math.dist(p,centre))
            assert abs(math.dist(ends[0],centre)-radius)<1e-5
            assert math.dist(ends[1],centre)>radius+1
            anchors=[ends[1]];geometry=dict(actual_line=lines[0],circle_center=centre,circle_radius=radius)
            label=object_label(root,'instance-label-'+ident);used_labels.add(label['object'])
        elif kind=='ground':
            # Current sources use the literal four-line ground family; no text
            # alias from 0 to VSS is needed to reject a reachable ground here.
            assert len(lines)==4
            vertical=[line for line in lines if abs(line[0][0]-line[1][0])<1e-5]
            assert len(vertical)==1
            anchors=[min(vertical[0],key=lambda p:p[1])];geometry=dict(actual_lines=lines)
        else:
            assert len(lines)==1
            polygons=[]
            for e,local in b.transformed_elements(element,matrix):
                if e.tag.rsplit('}',1)[-1]!='polygon' or e.get('fill') in (None,'none'):continue
                values=list(map(float,re.findall(b.NUMBER,e.get('points',''))))
                polygons.append([b.apply(local,values[i:i+2]) for i in range(0,len(values),2)])
            assert len(polygons)==1
            attached=[p for p in lines[0] if b.in_polygon(p,polygons[0])]
            outside=[p for p in lines[0] if not b.in_polygon(p,polygons[0])]
            assert len(attached)==len(outside)==1,'power port stem lacks its actual bar'
            anchors=outside;geometry=dict(actual_line=lines[0],actual_bar=polygons[0])
            label=object_label(root,'power-label-'+ident);used_labels.add(label['object'])
        markers.append(dict(object=ident,kind=kind,anchors=anchors,label=label,geometry=geometry))
    # Full-width rails have explicit label/object/net-id association and route
    # metadata. Every route piece must also occur in actual conductor ink.
    for label in root.iter():
        if label.get('data-kind')!='power-label' or label.get('data-object-id') in used_labels:continue
        ident=label.get('data-object-id','')
        assert ident.startswith('label-agent-rail-'),'unsupported power label owner'
        owner=ident[len('label-'):];netid='net-power-'+owner;segments=[]
        for e,matrix in b.transformed_elements(root):
            if e.get('data-net-id')!=netid or e.get('data-route-presentation')!='power-rail':continue
            values=list(map(float,re.findall(b.NUMBER,e.get('points',''))))
            points=[b.apply(matrix,values[i:i+2]) for i in range(0,len(values),2)]
            for a,c in zip(points,points[1:]):
                assert any((b.close(a,x) and b.close(c,y)) or (b.close(a,y) and b.close(c,x)) for x,y in ink),'rail metadata lacks actual ink'
                segments.append([a,c])
        assert segments,'power rail has no actual supported route'
        anchors=[list(p) for p in sorted({tuple(p) for s in segments for p in s})]
        markers.append(dict(object=owner,kind='power-rail',anchors=anchors,label=object_label(root,ident),
                            geometry=dict(actual_supported_route_segments=segments,data_net_id=netid)))
    assert len({m['object'] for m in markers})==len(markers),'duplicate actual marker object'
    return markers


def certify(number,human=None,root=None):
    ident='ag-'+str(number);paths={k:b.EXAMPLES/(ident+s) for k,s in
        [('deck','.cir'),('source_json','.human.json'),('source_svg','.svg')]}
    if human is None:human=json.loads(paths['source_json'].read_text())
    if root is None:root=ET.parse(paths['source_svg']).getroot()
    formals,rows=b.parse(paths['deck'].read_text());raw={r['card']:r for r in rows};inc=b.incidence(rows)
    drawn={d['card']:d for d in human['devices']};ink=b.conductor_ink(root);context=dict(junctions=b.junctions(root))
    markers=actual_markers(root);results=[]
    for card,(literal_label,textpins) in EXPECTED[number].items():
        pins=textpins.split();assert raw[card]['nets']==pins and pins[3] in formals
        device=drawn[card];b.source_binding(device,pins);geometry=b.body_geometry(root,device)
        assert geometry['actual_instance_label']==literal_label,'literal device alias changed'
        assert geometry['B_is_own_lead_endpoint'] or geometry['containing_filled_polygons'],'detached cached B'
        point=geometry['cached_B'];named,missing=b.verified_segments(human,pins[3],ink)
        assert not missing and b.touch(named,point),'body named source ink missing'
        # Enumerate every actual marker before text/net eligibility filtering.
        reachable=[]
        for marker in markers:
            paths_to=[b.source_connection(context,ink,[point,anchor]) for anchor in marker['anchors']]
            if any(path['continuous'] for path in paths_to):
                reachable.append(dict(marker=marker,paths=paths_to))
        assert len(reachable)==1,('ambiguous or absent reachable raw marker set',card,[r['marker']['object'] for r in reachable])
        target=reachable[0]['marker'];assert target['kind']=='port','body formal reaches a rail/ground marker'
        assert target['label']['semantic_token']==pins[3],('actual marker text contradicts raw body formal',card,target['label'])
        anchor=target['anchors'][0]
        cached=[m for m in human['markers'] if m['kind']=='port' and b.close(m['at'],anchor)]
        assert len(cached)==1 and cached[0]['net'].lower()==pins[3] and cached[0]['name'].lower()==pins[3]
        named_path=b.source_connection(context,named,[point,anchor]);assert named_path['continuous']
        results.append(dict(card=card,ordered_DGSB=pins,raw=raw[card]['raw'],raw_formal_index=formals.index(pins[3]),
            complete_body_incidence=inc[pins[3]],device_alias=dict(raw_card=card,actual_label=literal_label,
                policy='literal case-specific alias; no prefix inference'),source_geometry=geometry,
            reachable_raw_markers=reachable,source_cached_marker=cached[0],named_actual_path=named_path))
    unassociated=[dict(object=e.get('data-object-id'),plain_text=''.join(e.itertext()),
                      anchor_kind=e.get('data-anchor-kind'),data_net_id=e.get('data-net-id'),
                      text_xy=b.apply(matrix,[float(e.get('x','0')),float(e.get('y','0'))]))
                  for e,matrix in b.transformed_elements(root) if e.get('data-kind')=='net-label']
    return dict(id=ident,files={k:dict(path=str(p.relative_to(ROOT)),sha256=sha(p)) for k,p in paths.items()},
                raw_formals=formals,all_actual_markers=markers,body_bindings=results,
                unassociated_route_or_free_labels=unassociated)


def change_label(root,object_id,text):
    label=next(e for e in root.iter() if e.get('data-object-id')==object_id)
    attrs=dict(label.attrib);label.clear();label.attrib.update(attrs);label.text=text


def rejection(number,human,root):
    try:certify(number,human,root)
    except (AssertionError,ValueError,KeyError) as error:return dict(reason=str(error),kind=type(error).__name__)
    raise AssertionError('actual source mutation incorrectly accepted')


def controls():
    results={}
    for number in EXPECTED:
        human=json.loads((b.EXAMPLES/f'ag-{number}.human.json').read_text());root=ET.parse(b.EXAMPLES/f'ag-{number}.svg').getroot()
        original=certify(number,human,root);first=original['body_bindings'][0]['reachable_raw_markers'][0]['marker']
        changed=copy.deepcopy(root);change_label(changed,first['label']['object'],'CONTRADICTORY_BODY')
        results[f'ag-{number}:changed_attached_text']=rejection(number,human,changed)
        # A second actual object is counted even though the cache has no marker.
        changed=copy.deepcopy(root)
        symbol=copy.deepcopy(next(e for e in changed.iter() if e.get('data-object-id')==first['object']))
        symbol.set('data-object-id','injected-body-port');changed.append(symbol)
        label=ET.SubElement(changed,'text',{'data-object-id':'instance-label-injected-body-port',
            'data-kind':'instance-label','data-anchor-kind':'object'});label.text='CONTRADICTORY_BODY'
        results[f'ag-{number}:extra_reachable_uncached_port']=rejection(number,human,changed)
        changed=copy.deepcopy(root)
        duplicate=copy.deepcopy(next(e for e in changed.iter() if e.get('data-object-id')==first['label']['object']))
        duplicate.text='CONTRADICTORY_BODY';changed.append(duplicate)
        results[f'ag-{number}:extra_attached_label']=rejection(number,human,changed)
        reordered=copy.deepcopy(human);reordered['markers'].reverse();reordered['devices'].reverse();reordered['wires'].reverse()
        same=certify(number,reordered,root)
        assert [x['ordered_DGSB'] for x in same['body_bindings']]==[x['ordered_DGSB'] for x in original['body_bindings']]
        renamed=copy.deepcopy(root)
        symbol=next(e for e in renamed.iter() if e.get('data-object-id')==first['object'])
        symbol.set('data-object-id','renamed-body-port')
        label=next(e for e in renamed.iter() if e.get('data-object-id')==first['label']['object'])
        label.set('data-object-id','instance-label-renamed-body-port')
        same=certify(number,human,renamed)
        assert [x['ordered_DGSB'] for x in same['body_bindings']]==[x['ordered_DGSB'] for x in original['body_bindings']]
    for number in (1014,1026):
        human=json.loads((b.EXAMPLES/f'ag-{number}.human.json').read_text());root=ET.parse(b.EXAMPLES/f'ag-{number}.svg').getroot()
        original=certify(number,human,root)
        left,right=[x['reachable_raw_markers'][0]['marker']['label'] for x in original['body_bindings']]
        change_label(root,left['object'],right['semantic_token']);change_label(root,right['object'],left['semantic_token'])
        results[f'ag-{number}:swapped_input_labels']=rejection(number,human,root)
    # The exact previously surviving contradiction now fails the full certificate.
    human=json.loads((b.EXAMPLES/'ag-1014.human.json').read_text());root=ET.parse(b.EXAMPLES/'ag-1014.svg').getroot()
    original=certify(1014,human,root);left=original['body_bindings'][0]['reachable_raw_markers'][0]['marker']
    change_label(root,left['label']['object'],'VI2')
    results['ag-1014:VI1_actual_text_changed_to_VI2']=rejection(1014,human,root)
    root=ET.parse(b.EXAMPLES/'ag-1014.svg').getroot()
    target=next(e for e in root.iter() if e.get('data-object-id')==left['object'])
    for parent in target.iter():
        for child in list(parent):
            if child.tag.rsplit('}',1)[-1]=='line':parent.remove(child)
    results['ag-1014:actual_port_stem_deleted']=rejection(1014,human,root)
    root=ET.parse(b.EXAMPLES/'ag-1014.svg').getroot()
    ground_root=ET.parse(b.EXAMPLES/'ag-1026.svg').getroot()
    ground=copy.deepcopy(next(e for e in ground_root.iter() if e.get('data-symbol-id')=='ground'))
    ground.set('data-object-id','injected-body-ground');list(ground)[0].set('transform','translate(60 120)')
    root.append(ground)
    results['ag-1014:extra_actual_ground_at_body_port']=rejection(1014,human,root)
    return dict(rejections=results,record_reorder_preserves_bindings=True,consistent_actual_port_object_rename_preserves_bindings=True)


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('output',type=Path);ap.add_argument('--check',type=Path)
    args=ap.parse_args();cases=[];unsupported=[]
    for number in EXPECTED:
        try:cases.append(certify(number))
        except (AssertionError,ValueError,KeyError) as error:unsupported.append(dict(id='ag-'+str(number),reason=str(error)))
    deps=json.loads((HERE/'bodies_evidence.json').read_text())['dependency_sha256']
    result=dict(scope='Four actually re-viewed pairs, ten body-to-formal bindings, six distinct body input markers; object-bound text only.',
        cases=cases,unsupported=unsupported,controls=controls() if not unsupported else None,
        dependency_sha256={str(p.relative_to(ROOT)):sha(p) for p in [Path(__file__)]+[ROOT/name for name in deps]},
        limitations=['Not a general visual netlist extractor; free/route net labels do not create graph edges.',
                    'Ground semantics are not normalized to VSS; any reachable ground/rail contradicts this narrow input-port case.',
                    'Explicit N/P device aliases are case-specific. No nearest-label association or prefix inference.',
                    'No production policy, C ABI, host roundtrip, or operating-circuit claim.'])
    if args.check:assert result==json.loads(args.check.read_text()),'fifth-body proof changed'
    args.output.write_text(json.dumps(result,indent=2)+'\n');assert not unsupported,unsupported
    print('PASS four sources, ten body-formal bindings, six exact actual port objects; changed/swapped/extra marker contradictions rejected')


if __name__=='__main__':main()
