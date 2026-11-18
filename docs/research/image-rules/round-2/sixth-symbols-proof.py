#!/usr/bin/env python3
"""Sixth symbol study: exact corpus, intentional boxes, actual contact and side proofs.

The box-side certificate changes no electrical direction or truth table. Its
literal source text/anchor/lead witnesses are independent of cached terminals.
"""
import argparse
import collections
import copy
import hashlib
import json
import math
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
sys.path.insert(0,str(ROOT/'docs/research/figures'))
import digital_symbols as d

RUN=ROOT/'.objective/human-schematic-equivalence/runs/iteration21-resume1/image-rule-round-2/ports'
EXAMPLES=ROOT/'external/examples/analoggenie'
CONTROL=frozenset(('pfd','dac','cp','cmfb','translinear','gm','lpf','cm_detect','varactor_switched_caps','zcd','stage1'))
SIDE_CASES={
 439:dict(card='xpfd',object='instance-0d0a8862-5bc9-4a62-b797-90a5cfa97a16',
          ports='a b qa qb',nets='a b qa qb',tips=[[80,140],[80,200],[180,140],[180,200]],
          labels=[[94,144],[94,204],[166,144],[166,204]]),
 440:dict(card='xpfd',object='instance-27b7f145-b9d8-432c-a902-8f500c140469',
          ports='a b qa qb',nets='a b qa qb',tips=[[70,140],[70,230],[170,140],[170,230]],
          labels=[[84,144],[84,234],[156,144],[156,234]]),
 515:dict(card='x1',object='xdac',ports='out1 out2',nets='net1 net0',
          tips=[[30,110],[30,170]],labels=[[16,114],[16,174]]),
 516:dict(card='x1',object='xdac',ports='o1 o2',nets='net0 net2',
          tips=[[30,80],[30,130]],labels=[[16,84],[16,134]])}

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def norm(v):return math.hypot(*v)
def sub(a,b):return [a[i]-b[i] for i in range(2)]
def cross(a,b):return a[0]*b[1]-a[1]*b[0]
def close(a,b):return norm(sub(a,b))<1e-7

def ancestors(root,target):
    def visit(node,path):
        if node is target:return path
        for child in node:
            found=visit(child,path+[node])
            if found is not None:return found
        return None
    found=visit(root,[]);assert found is not None;return found

def visible_scope(root,group):
    """Conservative supported-ink scope, not a general SVG/CSS renderer."""
    unsupported={'visibility','display','opacity','fill-opacity','stroke-opacity','clip-path','mask','filter'}
    for node in ancestors(root,group)+list(group.iter()):
        assert not unsupported.intersection(node.attrib),'unsupported visibility or clipping attribute'
        styles={s.split(':',1)[0].strip().lower():s.split(':',1)[1].strip().lower()
                for s in node.get('style','').split(';') if ':' in s}
        assert not (unsupported|{'transform'}).intersection(styles),'unsupported style visibility/transform'
        if d.native.tag(node) in ('g','line','polygon'):
            assert node.get('stroke','').lower()!='none' and styles.get('stroke')!='none','hidden own stroke'
        if d.native.tag(node) in ('text','tspan'):
            assert node.get('fill','').lower()!='none' and styles.get('fill')!='none','hidden text'

def literal_label_scope(root,label):
    # The four reviewed boxes use plain world-coordinate pin names. More
    # elaborate transformed text needs a new evaluated-anchor certificate.
    for node in ancestors(root,label)+list(label.iter()):
        assert node.get('transform') is None,'transformed literal label unsupported'
    for node in label.iter():
        if node is not label:
            assert not {'x','y','dx','dy','rotate'}.intersection(node.attrib),'shifted literal text unsupported'

def first_contact(body,circles,tip,end):
    """First intersection of an extended physical lead ray and actual outline."""
    delta=sub(end,tip);assert norm(delta)>0
    hits=[]
    for a,b in zip(body,body[1:]+body[:1]):
        edge=sub(b,a);den=cross(delta,edge)
        if abs(den)<1e-10:continue
        t=cross(sub(a,tip),edge)/den;u=cross(sub(a,tip),delta)/den
        if t>=-1e-9 and -1e-9<=u<=1+1e-9:hits.append(t)
    for c in circles:
        v=sub(tip,c['center']);a=sum(x*x for x in delta);b=2*sum(v[i]*delta[i] for i in range(2));cc=sum(x*x for x in v)-c['radius']**2
        disc=b*b-4*a*cc
        if disc>=0:
            hits.extend(t for t in [(-b-math.sqrt(disc))/(2*a),(-b+math.sqrt(disc))/(2*a)] if t>=-1e-9)
    assert hits,'ray misses own body and inversion bubble'
    t=min(hits);contact=[tip[i]+t*delta[i] for i in range(2)]
    return dict(first_parameter=round(t,9),first_point=[round(x,9) for x in contact],
                attachment_error_along_lead=round((1-t)*norm(delta),9),
                terminates_at_first_contact=abs(t-1)*norm(delta)<1e-7)

def calls(text):
    defs=d.declarations(text);out=[]
    for name,words in d.source.read_cards(text).items():
        if not name.startswith('x'):continue
        end=next((i for i,w in enumerate(words) if '=' in w or w=='params:'),len(words))
        family=words[end-1];ports=defs[family];bindings=words[1:end-1]
        assert len(ports)==len(bindings)
        out.append(dict(card=name,family=family,ports=ports,bindings=bindings))
    return out

def box_sides(call):
    """Research-only exact graphical side choice; no functional role inference."""
    p=call['ports'];f=call['family'].lower()
    if len(p)!=len(call['bindings']) or len(set(p))!=len(p):return None
    if f=='pfd' and set(p)=={'a','b','qa','qb'}:
        return {k:('left' if k in ('a','b') else 'right') for k in p}
    if f=='dac' and set(p) in ({'o1','o2'},{'out1','out2'}):
        return {k:'right' for k in p}
    return None

def side_source(n,root_override=None,human_override=None):
    e=SIDE_CASES[n];base=EXAMPLES/f'ag-{n}'
    call=next(c for c in calls(base.with_suffix('.cir').read_text()) if c['card']==e['card'])
    assert call['ports']==e['ports'].split() and call['bindings']==e['nets'].split()
    root=root_override if root_override is not None else ET.parse(base.with_suffix('.svg')).getroot()
    human=human_override if human_override is not None else json.loads(base.with_suffix('.human.json').read_text())
    _,group,_=d.source.source_group(human,root,e['card'])
    assert group.get('data-object-id')==e['object'],'wrong object'
    visible_scope(root,group)
    ink=d.source_ink(human,root,e['card']);assert ink['body']=='box'
    body=ink['polygons'][0];labels=[x for x in group if x.get('data-pin-name') is not None]
    assert len(labels)==len(call['ports'])==len(ink['lines'])
    expected_sides=box_sides(call);assert expected_sides is not None
    rows=[];used=[]
    for i,(formal,net,tip,anchor) in enumerate(zip(call['ports'],call['bindings'],e['tips'],e['labels'])):
        found=[x for x in labels if x.get('data-pin-name').lower()==formal]
        assert len(found)==1,'pin-name association is not unique'
        label=found[0]
        literal_label_scope(root,label)
        assert ''.join(label.itertext()).lower()==formal,'visible text contradicts pin association'
        assert [float(label.get('x')),float(label.get('y'))]==anchor,'literal label anchor changed'
        matches=[(j,line) for j,line in enumerate(ink['lines']) if any(close(p,tip) for p in line)]
        assert len(matches)==1,'literal contact lacks unique own stroke'
        j,line=matches[0];used.append(j);end=line[1] if close(line[0],tip) else line[0]
        contact=first_contact(body,[],tip,end);assert contact['terminates_at_first_contact']
        side='left' if tip[0]<min(p[0] for p in body) else 'right' if tip[0]>max(p[0] for p in body) else None
        assert side==expected_sides[formal]
        assert all((p[0]-tip[0])*(1 if side=='left' else -1)>0 for p in body),'body is not behind external tip'
        rows.append(dict(index=i,formal=formal,net=net,tip=tip,attachment=end,label_anchor=anchor,
                         actual_text=''.join(label.itertext()),side=side,contact=contact))
    assert len(set(used))==len(ink['lines'])
    return dict(id=f'ag-{n}',call=call,object=e['object'],body=body,ports=rows,
                contract_scope='Graphical side choice on an intentional box; no inferred truth table, timing, polarity or electrical port direction.')

def opaque(call,cid):
    base=EXAMPLES/cid;human=json.loads(base.with_suffix('.human.json').read_text());root=ET.parse(base.with_suffix('.svg')).getroot()
    ink=d.source_ink(human,root,call['card']);assert ink['body']=='box'
    device,group,_=d.source.source_group(human,root,call['card'])
    labels=[dict(pin=x.get('data-pin-name'),text=''.join(x.itertext()),anchor=[float(x.get('x')),float(x.get('y'))]) for x in group if x.get('data-pin-name')]
    jp=RUN/f'sixth-native/{cid}.json';sp=jp.with_suffix('.svg')
    row=dict(**call,id=cid,source=ink)
    native=d.native_ink(json.loads(jp.read_text()),ET.parse(sp).getroot(),row)
    assert native['body']=='box'
    return dict(**row,actual_pin_labels=labels,native=native,
                scalar_formals_without_same_named_source_label=sorted(set(call['ports'])-{x['pin'].lower() for x in labels}),
                source_label_names_without_same_named_scalar_formal=sorted({x['pin'].lower() for x in labels}-set(call['ports'])),
                cached_nets=device['nets'],native_hashes={'.json':sha(jp),'.svg':sha(sp)})

def controls():
    out=[]
    base=next(c for c in calls((EXAMPLES/'ag-439.cir').read_text()) if c['family']=='pfd')
    for name,change in [('extra_port',lambda c:(c['ports'].append('reset'),c['bindings'].append('rst'))),
                        ('missing_qa',lambda c:(c['ports'].pop(2),c['bindings'].pop(2))),
                        ('duplicate_role',lambda c:c['ports'].__setitem__(3,'qa')),
                        ('short_call',lambda c:c['bindings'].pop()),
                        ('long_call',lambda c:c['bindings'].append('other')),
                        ('prefix_family',lambda c:c.__setitem__('family','pfd_extra')),
                        ('lookalike_ports',lambda c:c.__setitem__('ports',['a','b','q','qb']))]:
        changed=copy.deepcopy(base);change(changed);assert box_sides(changed) is None;out.append(name+'_declines')
    perm=copy.deepcopy(base);order=[3,0,2,1]
    for k in ('ports','bindings'):perm[k]=[perm[k][i] for i in order]
    assert box_sides(perm)==box_sides(base);assert dict(zip(perm['ports'],perm['bindings']))==dict(zip(base['ports'],base['bindings']))
    out.append('formal_and_binding_permutation_keeps_semantic_side_map')
    renamed=copy.deepcopy(base);renamed['card']='xanything';renamed['bindings']=['n4','n2','n8','n9'];assert box_sides(renamed)==box_sides(base)
    out.append('instance_and_net_renaming_keeps_graphical_contract')
    def reject(name,root):
        try:side_source(439,root_override=root)
        except (AssertionError,ValueError):out.append(name)
        else:raise AssertionError(name)
    root=ET.parse(EXAMPLES/'ag-439.svg').getroot()
    for mode in ('wrong_object','swapped_text','swapped_metadata','stale_anchor','missing_lead','duplicate_label',
                 'translated_qa_label','hidden_qa_label','hidden_own_lead','hidden_symbol_group','empty_text_fill','shifted_tspan'):
        changed=copy.deepcopy(root);group=next(x for x in changed.iter() if x.get('data-object-id')==SIDE_CASES[439]['object'])
        labels=[x for x in group if x.get('data-pin-name')]
        if mode=='wrong_object':group.set('data-object-id','wrong')
        elif mode=='swapped_text':
            for x,value in zip(labels[2:],['QB','QA']):
                for child in list(x):x.remove(child)
                x.text=value
        elif mode=='swapped_metadata':labels[2].set('data-pin-name','QB');labels[3].set('data-pin-name','QA')
        elif mode=='stale_anchor':labels[2].set('x','94')
        elif mode=='duplicate_label':group.append(copy.deepcopy(labels[2]))
        elif mode=='translated_qa_label':labels[2].set('transform','translate(-72 0)')
        elif mode=='hidden_qa_label':labels[2].set('visibility','hidden')
        elif mode=='hidden_symbol_group':group.set('visibility','hidden')
        elif mode=='empty_text_fill':labels[2].set('fill','none')
        elif mode=='shifted_tspan':next(iter(labels[2])).set('dx','-72')
        elif mode=='hidden_own_lead':next(x for x in group.iter() if d.native.tag(x)=='line').set('visibility','hidden')
        elif mode=='missing_lead':
            for parent in group.iter():
                child=next((x for x in parent if d.native.tag(x)=='line'),None)
                if child is not None:parent.remove(child);break
        reject(mode+'_rejected',changed)
    human=json.loads((EXAMPLES/'ag-439.human.json').read_text())
    for device in human['devices']:
        if device['card']=='xpfd':device['terminals']={k:[9999,9999] for k in device['terminals']};device['nets']={k:'wrong' for k in device['nets']}
    human['wires']=[];human['labels']=[]
    assert side_source(439,human_override=human)==side_source(439)
    out.append('corrupted_cached_tips_nets_wires_labels_do_not_change_actual_source_certificate')
    square=[[-2,-2],[2,-2],[2,2],[-2,2]]
    assert first_contact(square,[],[-5,0],[-2,0])['terminates_at_first_contact']
    assert not first_contact(square,[],[-5,0],[-1,0])['terminates_at_first_contact']
    assert not first_contact(square,[],[-5,0],[-3,0])['terminates_at_first_contact']
    out.extend(['literal_contact_positive','literal_inside_overshoot_rejected','literal_outside_gap_rejected'])
    return out

def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--output',type=Path,required=True);ap.add_argument('--check',type=Path);args=ap.parse_args()
    census_path=HERE/'sixth-symbols-census.json';census=json.loads(census_path.read_text())
    assert census['drawings']==2202
    for name,digest in census['source_sha256'].items():assert sha(EXAMPLES/name)==digest
    all_calls=[];opaque_rows=[]
    for path in sorted(EXAMPLES.glob('*.cir')):
        for call in calls(path.read_text()):
            all_calls.append(dict(id=path.stem,**call))
            if call['family'] in CONTROL:opaque_rows.append(opaque(call,path.stem))
    families=dict(sorted(collections.Counter(c['family'] for c in all_calls).items()))
    assert families==census['all_outer_family_counts'] and len(all_calls)==941
    assert len(opaque_rows)==15
    digital=[r for r in census['instances'] if r['family'] in d.GATES]
    assert len(digital)==56 and all(r['complete_contract'] for r in digital)
    contacts=[]
    for row in digital:
        for suffix,digest in row['native_sha256'].items():assert sha(RUN/f"sixth-native/{row['id']}{suffix}")==digest
        for lead in row['native']['leads']:
            check=first_contact(row['native']['body_vertices'],row['native']['circles'],*lead['vertices'])
            contacts.append(dict(id=row['id'],card=row['card'],formal=lead['term'],tip=lead['vertices'][0],attachment=lead['vertices'][1],**check))
    red=sorted(f"{r['id']}:{r['card']}:{r['formal']}" for r in contacts if not r['terminates_at_first_contact'])
    assert red==['ag-1076:x5:vdd','ag-1076:x5:vss','ag-438:x1:vdd','ag-438:x1:vss','ag-545:x1:vdd','ag-545:x1:vss']
    assert len(contacts)==232
    result=dict(scope='All 2202 decks/941 outer X calls; exact 56 conventional digital instances; bounded 15 opaque/control instances across eleven families. No claim all arbitrary families are functionally classified.',
                all_outer_calls=all_calls,all_outer_family_counts=families,conventional_inventory={f:census['inventories'][f] for f in sorted(d.GATES)},
                opaque=opaque_rows,box_side_certificates=[side_source(n) for n in SIDE_CASES],
                box_side_full_corpus_names=sorted(c['id']+':'+c['card'] for c in all_calls if box_sides(c) is not None),
                native_digital_contacts=contacts,expected_contact_failures=red,controls=controls(),
                census_sha256=sha(census_path),dependencies={str(p.relative_to(ROOT)):sha(p) for p in [Path(__file__),Path(d.__file__),ROOT/'src/block_symbols.zig',ROOT/'src/library.zig',ROOT/'tools/schemify/recognize.zig',ROOT/'tools/schemify/layout.zig',ROOT/'tools/schemify/emit.zig',HERE/'worktree-rule-delta.md',HERE.parent/'current-human-rules.md']})
    result=json.loads(json.dumps(result))
    if args.check:assert result==json.loads(args.check.read_text())
    args.output.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps(dict(outer_calls=len(all_calls),digital=len(digital),opaque=len(opaque_rows),contacts=len(contacts),red=red,controls=len(result['controls']))))

if __name__=='__main__':main()
