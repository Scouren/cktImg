#!/usr/bin/env python3
"""Bounded source-ink certificates; no engine edits and no cached wire oracle.

Data questions: source SVG/deck/JSON are cold immutable inputs; the output is
per reviewed instance, then per declared formal port; one function owns each
record; strings retain exact names and indices are ordinary bounded Python
indices; geometry is transformed once; JSON is written once after checks.
Oracle: hand-transcribed raw bindings/tips plus actual SVG marker/lead paths.
"""
import argparse
import collections
import copy
import hashlib
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / 'docs/research/figures'))
import block_aliases as a
import converter_symbol_cases as prior
import digital_symbols as digital
from cross_caps import conductor_ink, actual_glyph
from input_resistors import actual_resistor

CASES = {
 1674: ('x1', 'vdd vss vb1 vb3 inn inp vb2 out vb4', 'vdd vss vb1 vb3 y x vb2 vout vb4',
        {'vdd': [310,70], 'vb1': [260,210], 'vb2': [280,210], 'vb3': [300,210], 'vb4': [320,210], 'inn': [230,120], 'inp': [230,160], 'out': [350,140]}),
 2212: ('x1', 'vdd vss inn inp vb2 out vb1 vb3 vb4', 'vdd vss fb vref vb2 net0 vb1 vb3 vb4',
        {'vdd': [-40,-70], 'vb1': [-60,70], 'vb2': [-30,70], 'vb3': [0,70], 'vb4': [60,70], 'inn': [-90,20], 'inp': [-90,-20], 'out': [50,0]}),
 3492: ('x2', 'vdd vss clk inn inp out', 'vdd vss clk vx vss vout',
        {'vdd': [440,530], 'clk': [490,620], 'inn': [390,580], 'inp': [390,620], 'out': [510,600]}),
 3493: ('x2', 'vdd vss inp inn clk out', 'vdd vss vss vx phic vout',
        {'vdd': [480,510], 'clk': [520,510], 'inn': [450,560], 'inp': [450,600], 'out': [550,580]}),
 3495: ('x2', 'vss vn vp vo phi3', 'vss vx vss vout phi3',
        {'vn': [380,550], 'vp': [380,610], 'vo': [500,580], 'phi3': [420,500]}),
}
KEEP = [1730,1746,1751,1752,1760,1764,1773,1778,2407,2442,2469]
UNKNOWN = [1677,2190,2586,2699,2713,2838,2905,3177,3265,3286]
SPELLINGS = {'φ1': 'phi1', 'φ2': 'phi2', 'φ3': 'phi3', 'φc': 'phic'}
OBJECTS = {1674:'XA',2212:'XOA',3492:'XCMP',3493:'X2',3495:'XCMP'}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def deck(n):
    text = (ROOT / f'external/examples/analoggenie/ag-{n}.cir').read_text()
    return text, a.read_cards(text), digital.declarations(text)


def role(port):
    return {'vdd':'supply','vss':'ground','inn':'negative','vn':'negative',
            'inp':'positive','vp':'positive','out':'output','vo':'output',
            'vb1':'bias1','vb2':'bias2','vb3':'bias3','vb4':'bias4',
            'clk':'clock','phi3':'clock'}.get(port)


def candidate(call):
    """New exact research contracts, independent of title, net or instance name."""
    ps = call['ports']; rs = list(map(role, ps))
    if len(ps)!=len(call['bindings']) or None in rs or len(set(rs)) != len(rs):
        return None
    if call['family'] in prior.KNOWN and set(rs) == {'supply','ground','positive','negative','output','bias1','bias2','bias3','bias4'}:
        return 'four_bias_signed'
    if call['family'] == 'comparator' and set(rs) in ({'supply','ground','positive','negative','output','clock'}, {'ground','positive','negative','output','clock'}):
        return 'clocked_signed'
    return None


def marker_ink(root):
    """Labels identify their own marker object; coordinates come from its ink."""
    labels = {x.get('data-object-id'): ''.join(x.itertext()) for x in root.iter() if x.tag.endswith('text')}
    out = []
    for group, _, parent in a.glyph.walk(root):
        kind = group.get('data-symbol-id')
        if kind not in ('port','vdd-port','ground'):
            continue
        lines = []
        for x, t, _ in a.glyph.walk(group, parent):
            if x.tag.endswith('line'):
                lines.append([a.glyph.point(t,(float(x.get('x1')),float(x.get('y1')))), a.glyph.point(t,(float(x.get('x2')),float(x.get('y2'))))])
        assert lines, 'marker has no actual terminal stroke'
        # These source assets put the attachment at the first line's first end.
        name = labels.get('instance-label-' + group.get('data-object-id'))
        net = 'vdd' if kind == 'vdd-port' else 'vss' if kind == 'ground' else SPELLINGS.get(name, (name or '').lower())
        out.append(dict(object=group.get('data-object-id'), kind=kind, label=name, net=net, point=lines[0][0], stroke=lines[0]))
    return out


def path(segments, start, end):
    """Endpoint/T junction graph; a proper crossing without a vertex is not joined."""
    start, end = tuple(start), tuple(end)
    vertices = {tuple(p) for seg in segments for p in seg} | {start,end}
    graph = collections.defaultdict(set)
    for x,y in segments:
        ps = sorted((p for p in vertices if a.on_segment(p,x,y)), key=lambda p:(p[0]-x[0])**2+(p[1]-x[1])**2)
        for u,v in zip(ps,ps[1:]):
            graph[u].add(v);graph[v].add(u)
    todo = collections.deque([(start,[start])]);seen={start}
    while todo:
        p, steps=todo.popleft()
        if p == end:
            return steps
        for q in sorted(graph[p]):
            if q not in seen:
                seen.add(q);todo.append((q,steps+[q]))
    return None


def own_lead(body, lead):
    points=lead['path']; tip=points[-1]; previous=points[-2]
    direction=a.glyph.direction(previous,tip)
    vector={'right':(1,0),'left':(-1,0),'up':(0,-1),'down':(0,1)}[direction]
    support=[sum((tip[i]-p[i])*vector[i] for i in range(2)) for p in body]
    first=points[0]; second=points[1]
    assert a.location(first,body)=='boundary'
    assert a.location(((first[0]+second[0])/2,(first[1]+second[1])/2),body)=='outside'
    # Split at every body-edge intersection, so an exterior midpoint cannot
    # hide a short interior crossing on a long later segment.
    for start,end in zip(points,points[1:]):
        dx,dy=end[0]-start[0],end[1]-start[1];ts=[0.,1.]
        assert dx or dy
        for u,v in zip(body,body[1:]+body[:1]):
            ex,ey=v[0]-u[0],v[1]-u[1];den=dx*ey-dy*ex
            if abs(den)>1e-8:
                t=((u[0]-start[0])*ey-(u[1]-start[1])*ex)/den
                z=((u[0]-start[0])*dy-(u[1]-start[1])*dx)/den
                if 0<=t<=1 and 0<=z<=1:ts.append(t)
            else:
                for p in (u,v):
                    if a.on_segment(p,start,end):ts.append(((p[0]-start[0])*dx+(p[1]-start[1])*dy)/(dx*dx+dy*dy))
        ts=sorted(set(ts))
        for l,r in zip(ts,ts[1:]):
            if r-l>1e-8:
                mid=(l+r)/2
                outside=a.location((start[0]+dx*mid,start[1]+dy*mid),body)=='outside'
                # Source strokes are rounded to .001; the existing boundary
                # oracle uses .01. Allow only that initial attachment sliver.
                rounded_attachment=start==first and r*(dx*dx+dy*dy)**.5<=.01
                assert outside or rounded_attachment,'lead re-enters or follows body'
    return dict(first_attachment=first, tip=tip, path=points, outward=direction,
                body_behind_tip=min(support)>=-.01, support_min=min(support),
                first_segment_exits_body=True)


def source(n, human_override=None, root_override=None):
    card, ports, bindings, expected=CASES[n]
    prefix=ROOT/f'external/examples/analoggenie/ag-{n}'
    text,cards,defs=deck(n);call=next(c for c in prior.calls(cards,defs) if c['card']==card)
    assert call['ports']==ports.split() and call['bindings']==bindings.split(), f'{n}: literal raw binding changed'
    human=human_override if human_override is not None else json.loads(prefix.with_suffix('.human.json').read_text())
    root=root_override if root_override is not None else ET.parse(prefix.with_suffix('.svg')).getroot()
    dev,g,parent=a.source_group(human,root,card);body,leads,inside=a.primitives(g,parent)
    assert g.get('data-object-id')==OBJECTS[n], (n,'literal source body identity differs')
    assert len(body)==3
    marks=a.polarity_marks(inside)
    signals,_=a.signal_leads(body,leads,marks,['negative','positive','output'])
    ink=conductor_ink(root);markers=marker_ink(root);bound=dict(zip(call['ports'],call['bindings']))
    rows=[];used=[]
    for i,(p,net) in enumerate(zip(call['ports'],call['bindings'])):
        r=role(p)
        if p=='vss':
            rows.append(dict(index=i,formal=p,net=net,role=r,source_geometry='not_drawn',canonical_placement='choice_required'))
            continue
        if r in signals:
            matches=[(j,l) for j,l in enumerate(leads) if a.glyph.close(l['endpoint'],signals[r])]
        else:
            targets=[m for m in markers if m['net']==net]
            matches=[(j,l) for j,l in enumerate(leads) if any(path(ink,l['endpoint'],m['point']) is not None for m in targets)]
        assert len(matches)==1,(n,p,'no unique actual lead')
        j,lead=matches[0];used.append(j)
        assert a.glyph.close(lead['endpoint'],expected[p]),(n,p,'independent literal tip')
        witnesses=[]
        for m in markers:
            route=path(ink,lead['endpoint'],m['point'])
            if route is not None:
                witnesses.append(dict(marker=m,actual_conductor_path=route))
        assert all(w['marker']['net']==net for w in witnesses),(n,p,'reachable marker contradicts raw binding')
        if r not in signals or (r=='output' and n!=2212) or (r=='positive' and n!=1674):
            assert witnesses and {w['marker']['net'] for w in witnesses}=={net},(n,p,'marker binding disagrees')
        cached=dev['terminals'].get(p.upper(),dev['terminals'].get(p))
        rows.append(dict(index=i,formal=p,net=net,role=r,source_geometry='visible',lead=own_lead(body,lead),
                         witnesses=witnesses,cached_tip=cached,cache_matches=cached is not None and a.glyph.close(cached,lead['endpoint'])))
    assert len(used)==len(leads)==len(set(used)), 'unassigned or reused own-symbol lead'
    # Independent raw-neighbour witness for non-marker signal nets.
    neighbours=[]
    if n==1674:
        for formal,device,pin in [('inn','r2','2'),('inp','r1','2')]:
            d=next(d for d in human['devices'] if d['card']==device)
            actual=actual_resistor(root,d)['terminals'][pin]
            assert cards[device][int(pin)]==bound[formal]
            endpoint=next(r['lead']['tip'] for r in rows if r['formal']==formal)
            route=path(ink,endpoint,actual);assert route is not None
            neighbours.append(dict(formal=formal,device=device,pin=pin,raw_net=bound[formal],actual_endpoint=actual,path=route))
    elif n==2212:
        d=next(d for d in human['devices'] if d['card']=='mnp');actual=actual_glyph(root,d)['terminals']['G']
        assert cards['mnp'][2]==bound['out'];route=path(ink,expected['out'],actual);assert route is not None
        neighbours.append(dict(formal='out',device='mnp',pin='G',raw_net=bound['out'],actual_endpoint=actual,path=route))
        d=next(d for d in human['devices'] if d['card']=='r1');actual=actual_resistor(root,d)['terminals']['2']
        assert cards['r1'][2]==bound['inn'];route=path(ink,expected['inn'],actual);assert route is not None
        neighbours.append(dict(formal='inn',device='r1',pin='2',raw_net=bound['inn'],actual_endpoint=actual,path=route))
    else:
        other=next(c for c in prior.calls(cards,defs) if c['card']=='x1')
        _,og,op=a.source_group(human,root,'x1');ob,ol,oi=a.primitives(og,op)
        os,_=a.signal_leads(ob,ol,a.polarity_marks(oi),['negative','positive','output'])
        output=next(net for p,net in zip(other['ports'],other['bindings']) if role(p)=='output')
        negative=next(r for r in rows if r['role']=='negative');assert output==negative['net']
        route=path(ink,negative['lead']['tip'],os['output']);assert route is not None
        neighbours.append(dict(formal=negative['formal'],device='x1',raw_net=output,actual_endpoint=os['output'],path=route))
    return dict(id=f'ag-{n}',call=call,contract=candidate(call),body=body,marks=marks,ports=rows,neighbour_witnesses=neighbours,
                source_vss='Declared and bound, but not drawn: no source VSS coordinate claimed.',
                global_vdd_without_formal=n==3495,hashes={s:sha(prefix.with_suffix(s)) for s in ('.cir','.svg','.human.json')})


def census(assignment):
    chosen=[];unknown=[];keeps=[];hashes={}
    for row in json.loads(assignment.read_text())['images']:
        n=int(row['id'].split('-')[1]);text,cards,defs=deck(n);hashes[row['id']]=sha(ROOT/f'external/examples/analoggenie/ag-{n}.cir')
        for call in prior.calls(cards,defs):
            kind=candidate(call)
            if kind: chosen.append(dict(id=row['id'],contract=kind,call=call))
            if n in UNKNOWN: unknown.append(dict(id=row['id'],call=call,unknown_formals=[p for p in call['ports'] if role(p) is None]))
            if n in KEEP:
                prefix=ROOT/f'external/examples/analoggenie/ag-{n}';human=json.loads(prefix.with_suffix('.human.json').read_text());root=ET.parse(prefix.with_suffix('.svg')).getroot()
                _,g,p=a.source_group(human,root,call['card']);body,leads,marks=a.primitives(g,p)
                if len(body)==4: keeps.append(dict(id=row['id'],call=call,body=body,actual_leads=leads))
    assert [(r['id'],r['contract']) for r in chosen]==[('ag-1674','four_bias_signed'),('ag-2212','four_bias_signed'),('ag-3492','clocked_signed'),('ag-3493','clocked_signed'),('ag-3495','clocked_signed')]
    assert sorted(set(int(r['id'].split('-')[1]) for r in keeps))==sorted(KEEP)
    return dict(candidates=chosen,unknown_controls=unknown,genuine_box_controls=keeps,deck_hashes=hashes)


def global_census():
    """Separate raw contract scan, without claiming image review beyond the shard."""
    names=[];hashes={}
    paths=sorted((ROOT/'external/examples/analoggenie').glob('ag-*.cir'),key=lambda p:int(p.stem.split('-')[1]))
    assert len(paths)==2202
    for p in paths:
        n=int(p.stem.split('-')[1]);_,cards,defs=deck(n);hashes[p.stem]=sha(p)
        for call in prior.calls(cards,defs):
            if kind:=candidate(call):names.append(dict(id=p.stem,contract=kind,call=call))
    assert [(r['id'],r['contract']) for r in names]==[('ag-808','clocked_signed'),('ag-1242','four_bias_signed'),('ag-1674','four_bias_signed'),('ag-2212','four_bias_signed'),('ag-3492','clocked_signed'),('ag-3493','clocked_signed'),('ag-3495','clocked_signed')]
    return dict(candidates=names,deck_hashes=hashes)


def controls():
    checks=[]
    def check(name,value):
        assert value,name;checks.append(name)
    check('literal_disconnected_ink_rejected',path([[(0,0),(1,0)],[(2,0),(3,0)]],(0,0),(3,0)) is None)
    check('literal_proper_crossing_not_joined',path([[(0,1),(2,1)],[(1,0),(1,2)]],(0,1),(1,2)) is None)
    check('literal_T_endpoint_joined',path([[(0,1),(2,1)],[(1,1),(1,2)]],(0,1),(1,2))==[(0,1),(1,1),(1,2)])
    n=1674;_,c,d=deck(n);call=prior.calls(c,d)[0]
    mutation=copy.deepcopy(call);mutation['ports'][-1]='vx'
    check('unknown_replaces_bias4_rejected',candidate(mutation) is None)
    mutation=copy.deepcopy(call);mutation['ports'][-1]='vb3'
    check('duplicate_bias_role_rejected',candidate(mutation) is None)
    mutation=copy.deepcopy(call);mutation['family']='a1_extra'
    check('family_prefix_rejected',candidate(mutation) is None)
    mutation=copy.deepcopy(call);mutation['ports'].reverse();mutation['bindings'].reverse()
    check('paired_formal_permutation_retained',candidate(mutation)=='four_bias_signed' and dict(zip(mutation['ports'],mutation['bindings']))==dict(zip(call['ports'],call['bindings'])))
    mutation=copy.deepcopy(call);mutation['bindings']=['renamed_'+str(i) for i in range(len(call['bindings']))]
    check('net_names_do_not_choose_shape',candidate(mutation)=='four_bias_signed')
    for name in ('missing','extra'):
        mutation=copy.deepcopy(call)
        if name=='missing':mutation['bindings'].pop()
        else:mutation['bindings'].append('extra')
        check(name+'_raw_binding_rejected',candidate(mutation) is None)
    try:
        own_lead([(-6,-6),(-6,6),(6,0)],dict(path=[(-6,0),(-8,0),(0,0),(8,0)]))
    except AssertionError:checks.append('later_segment_body_reentry_rejected')
    else:raise AssertionError('later segment body reentry survived')
    root=ET.parse(ROOT/'external/examples/analoggenie/ag-1674.svg').getroot();ink=conductor_ink(root)
    check('actual_bias2_path_accepts',path(ink,(280,210),(400,300)) is not None)
    check('stale_bias2_coordinate_rejected',path(ink,(290,210),(400,300)) is None)
    check('wrong_bias2_marker_rejected',path(ink,(280,210),(400,270)) is None)
    broken=[s for s in ink if not (a.glyph.close(s[0],(280,210)) and a.glyph.close(s[1],(280,300)))]
    check('deleted_actual_bias2_segment_rejected',path(broken,(280,210),(400,300)) is None)
    check('clock3492_global_body_support_failure_retained',not own_lead([(400,542.265),(400,657.735),(500,600)],dict(path=[(490,605.774),(490,620)]))['body_behind_tip'])
    hp=ROOT/'external/examples/analoggenie/ag-1674.human.json'
    h=json.loads(hp.read_text());h['wires']=[]
    for dev in h['devices']:
        if dev['card']=='x1':
            dev['terminals']={k:[9999,9999] for k in dev['terminals']}
    repaired=source(1674,human_override=h)
    check('corrupted_cached_symbol_tips_and_all_wires_do_not_change_ink_binding',
          [r['lead']['tip'] for r in repaired['ports'] if 'lead' in r]==
          [r['lead']['tip'] for r in source(1674)['ports'] if 'lead' in r])
    def rejects(name, mutated):
        try:
            source(1674,root_override=mutated)
        except (AssertionError,ValueError):
            checks.append(name)
        else:
            raise AssertionError(name)
    changed=copy.deepcopy(root)
    for node in changed.iter():
        if node.get('data-role')=='conductor-ink':
            node.set('d',node.get('d').replace('M 280 210 L 280 300 L 400 300','M 281 210 L 281 300 L 400 300'))
    rejects('actual_conductor_shift_is_rejected',changed)
    changed=copy.deepcopy(root)
    for node in changed.iter():
        if node.get('data-object-id')=='instance-label-tVB2':
            node.clear();node.text='VB3'
    rejects('source_bias_label_deletion_is_rejected',changed)
    changed=copy.deepcopy(root)
    for node in changed.iter():
        oid=node.get('data-object-id')
        if oid in ('instance-label-tVB2','instance-label-tVB3'):
            for child in list(node):node.remove(child)
            node.text='VB3' if oid=='instance-label-tVB2' else 'VB2'
    rejects('swapped_actual_bias_marker_labels_are_rejected',changed)
    changed=copy.deepcopy(root)
    for node in changed.iter():
        if node.get('data-object-id')=='XA':node.set('data-object-id','wrong-body')
    rejects('wrong_actual_symbol_object_identity_is_rejected',changed)
    changed=copy.deepcopy(root)
    # Add a contradictory marker on an otherwise raw-neighbour-certified input.
    original=next(x for x in changed.iter() if x.get('data-object-id')=='tVB2')
    marker=copy.deepcopy(original);marker.set('data-object-id','conflicting-input-marker')
    marker[0].set('transform','translate(230,120)');changed.append(marker)
    label=ET.SubElement(changed,'text',{'data-object-id':'instance-label-conflicting-input-marker'})
    label.text='VB2'
    rejects('conflicting_input_marker_is_rejected_even_with_raw_neighbour',changed)
    return checks


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=Path,required=True);p.add_argument('--check',type=Path);args=p.parse_args()
    assignment=ROOT/'docs/research/image-rules/converters_assignment.json'
    result=dict(scope='Fresh round-2 exact source contracts. Raw all-port proof and visible own-lead proof are separate.',
                certificates=[source(n) for n in CASES],census=census(assignment),full_corpus=global_census(),controls=controls(),
                assignment_sha256=sha(assignment),dependencies=prior.dependencies(),script_sha256=sha(Path(__file__)),
                source_label_spellings=SPELLINGS,spelling_scope='Literal source-label transcription only; not a global role or net normalization rule.')
    result=json.loads(json.dumps(result))
    if args.check: assert result==json.loads(args.check.read_text()),'evidence differs'
    args.output.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps({'certificates':[r['id'] for r in result['certificates']],'controls':result['controls'],'box_controls':[r['id'] for r in result['census']['genuine_box_controls']]}))

if __name__=='__main__':
    main()
