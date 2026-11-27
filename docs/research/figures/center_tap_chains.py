#!/usr/bin/env python3
"""Exact source census for paired CT banks and their C-S-C coupling chains.

Usage: center_tap_chains.py <examples-root> <output.json> [--check]

The source contains one complete two-bank scene. Actual own symbol leads,
declared bindings, four private paths, four eight-terminal outer buses,
and relative geometry are independently verified. The four direct/cross
switches form a separate observed relation and placement owner.
"""
import argparse
import ast
import collections
import copy
import itertools
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import center_tap_symbols as ct
import center_tap_tanks as tanks
import input_resistors as inputs
import channel_bridges as channels
import cross_caps
import thin_connectivity as ink
import block_aliases as aliases

FIG = HERE
EXPECTED = ['ag-1180:coupling-bridges']
# These names are the independent literal source expectation, not selected
# from the implementation's groups. Source control tips are unobserved.
OUTER = {
    'net4': 'c1.2 ct1.1 m1.D m2.G se1.1 so1.1 xle1.n1 xlo1.n1'.split(),
    'net5': 'c3.2 ct1.2 m1.G m2.D se2.1 so2.2 xle1.n2 xlo1.n2'.split(),
    'net2': 'c2.1 ct2.1 m3.D m4.G se1.2 so2.1 xle2.n1 xlo2.n1'.split(),
    'net7': 'c4.1 ct2.2 m3.G m4.D se2.2 so1.2 xle2.n2 xlo2.n2'.split(),
}


def inner_coil(row, actual, bank):
    """Inner means nearest the other bank's winding columns, not LE/LO."""
    first = actual[row['banks'][0]['coils'][0]]['terminals']
    axis = 0 if abs(first['n1'][1]-first['n2'][1]) < 1e-6 else 1
    across = 1-axis
    for b in row['banks']:
        for name in b['coils']:
            tips=actual[name]['terminals']
            assert abs(tips['n1'][across]-tips['n2'][across])<1e-6, 'nonparallel bank winding'
            assert abs(tips['n1'][axis]-first['n1'][axis])<1e-6 and abs(tips['n2'][axis]-first['n2'][axis])<1e-6, 'unequal bank endpoint rows'
    columns = [[actual[n]['terminals']['n1'][across] for n in b['coils']]
               for b in row['banks']]
    assert max(columns[0])<min(columns[1]) or max(columns[1])<min(columns[0]), 'overlapping bank columns'
    other = sum(columns[1-bank])/2
    ranked = sorted((abs(x-other), n) for x,n in zip(columns[bank],row['banks'][bank]['coils']))
    assert ranked[0][0] != ranked[1][0], 'ambiguous inner winding'
    return ranked[0][1]


def outer_buses(row, context, actual):
    proofs=[]
    for net,names in sorted(OUTER.items()):
        targets=[]; bindings=[]
        for name in names:
            device,term=name.split('.')
            index=('DGSB'.index(term) if device.startswith('m') else
                   int(term.removeprefix('n'))-1)
            assert context['pins'][device][index] == net, (name,net)
            targets.append(actual[device]['terminals'][term])
            bindings.append([device,index,net])
        # Exact named membership, not just eight arbitrary points.
        observed=[]
        for device,ps in row['pins'].items():
            for index,bound in enumerate(ps):
                if bound==net: observed.append([device,index,net])
        tanks.same(sorted(observed),sorted(bindings),'outer bus exact membership '+net)
        segments,missing=ink.verified_segments(context['human'],net,context['ink'])
        proof=ink.source_connection(context,segments,targets)
        assert proof['continuous'] and not missing, net
        proofs.append(dict(net=net,named_terminals=names,bindings=bindings,
                           actual_targets=targets,verified_segments=segments,
                           cache_segments_without_ink=missing,actual_connection=proof))
    return proofs


def select(cards,pins,models,coils):
    grouped=collections.defaultdict(list)
    for c in coils:
        n=dict(zip(c['ports'],c['bindings']))
        grouped[tuple(sorted((n['n1'],n['n2'])))].append(c)
    banks=[]
    for ends,cs in sorted(grouped.items()):
        cs=sorted(cs,key=lambda c:c['card'])
        if len(cs)!=2:continue
        n=dict(zip(cs[0]['ports'],cs[0]['bindings'])); a,b,t=n['n1'],n['n2'],n['n3']
        if a==b or t in (a,b) or channels.rail(a) or channels.rail(b) or channels.rail(t)!='supply':continue
        if any(dict(zip(c['ports'],c['bindings']))['n3']!=t for c in cs):continue
        caps=[k for k,w in cards.items() if k[0]=='c' and set(pins[k])=={a,b}]
        mos=[[k for k,w in cards.items() if k[0]=='m' and pins[k][:2]==pair] for pair in ([a,b],[b,a])]
        if len(caps)!=1 or any(len(v)!=1 for v in mos):continue
        ms=[x[0] for x in mos]
        if any(len(pins[m])!=4 or pins[m][2]!=pins[m][3] or channels.rail(pins[m][2])!='sink' or models.get(cards[m][5])!='nmos' for m in ms):continue
        if pins[ms[0]][2]!=pins[ms[1]][2]:continue
        banks.append(dict(coils=[c['card'] for c in cs],cap=caps[0],mos=ms,ends=[a,b],tap=t))
    result=[]
    for a,b in itertools.combinations(banks,2):
        if len(set(a['ends']+b['ends']))!=4 or a['tap']!=b['tap']:continue
        direct={f'{i}{j}':[k for k,w in cards.items() if k[0]=='s' and len(pins[k])==4 and set(pins[k][:2])=={x,y}] for i,x in enumerate(a['ends']) for j,y in enumerate(b['ends'])}
        if any(len(v)!=1 for v in direct.values()):continue
        chains=[]
        for x,y in zip(a['ends'],b['ends']):
            choices=[]
            for c in (k for k in cards if k[0]=='c' and x in pins[k]):
                u=next((n for n in pins[c] if n!=x),None)
                for d in (k for k in cards if k[0]=='c' and y in pins[k] and k!=c):
                    v=next((n for n in pins[d] if n!=y),None)
                    if u is None or v is None:continue
                    for sw in (k for k in cards if k[0]=='s' and set(pins[k][:2])=={u,v}):
                        incidence=lambda n:sorted((k,i) for k,ps in pins.items() for i,q in enumerate(ps) if q==n)
                        if len(set(a['ends']+b['ends']+[u,v]))!=6 or channels.rail(u) or channels.rail(v):continue
                        if any(len(incidence(n))!=2 or {k for k,i in incidence(n)}!=set(pair) for n,pair in zip((u,v),([c,sw],[sw,d]))):continue
                        choices.append(dict(devices=[c,sw,d],ends=[x,y],private=[u,v]))
            if len(choices)!=1:break
            choice=choices[0];u,v=choice['private']
            if len(set(a['ends']+b['ends']+[u,v]))!=6 or channels.rail(u) or channels.rail(v):break
            incidence=lambda n:sorted((k,i) for k,ps in pins.items() for i,q in enumerate(ps) if q==n)
            if any(len(incidence(n))!=2 or {k for k,i in incidence(n)}!=set(pair) for n,pair in zip((u,v),(choice['devices'][:2],choice['devices'][1:]))):break
            choice['private_incidence']=[incidence(u),incidence(v)];chains.append(choice)
        if len(chains)!=2:continue
        owned=[n for c in chains for n in c['devices']]+[v[0] for v in direct.values()]
        if len(set(owned))!=10:continue
        result.append(dict(banks=[a,b],chains=chains,direct={k:v[0] for k,v in direct.items()},bridge_devices=sorted(owned)))
    return result

def frame_geometry(row,actual):
    # Axial coordinate follows the first winding's N1→N2; transverse runs
    # between the two banks. Every comparison uses actual lead endpoints.
    a,b=row['banks'];ca=actual[inner_coil(row,actual,0)]['terminals'];cb=actual[inner_coil(row,actual,1)]['terminals']
    p,q=ca['n1'],ca['n2'];axis=0 if abs(p[1]-q[1])<1e-6 else 1;cross=1-axis
    sign=1 if q[axis]>p[axis] else -1;side=1 if cb['n1'][cross]>p[cross] else -1
    def at(name,index):return actual[name]['terminals'][str(index+1)]
    def axial(point):return point[axis]*sign
    def transverse(point):return point[cross]*side
    mids=[(transverse(ca['n1'])+transverse(ca['n2']))/2,(transverse(cb['n1'])+transverse(cb['n2']))/2]
    checks={}; details=[]
    for i,chain in enumerate(row['chains']):
        points=[p for n in chain['devices'] for p in [at(n,0),at(n,1)]]
        ordered=[]
        for n,x,y in zip(chain['devices'],[chain['ends'][0],*chain['private']],[*chain['private'],chain['ends'][1]]):
            ps=row['pins'][n];ordered += [at(n,ps.index(x)),at(n,ps.index(y))]
        values=[axial(p) for p in ordered];xs=[transverse(p) for p in ordered]
        top=axial(actual[a['mos'][0]]['terminals']['D']);bottom=axial(actual[a['mos'][1]]['terminals']['D'])
        checks[f'chain{i}_straight']=max(values)-min(values)<1e-6
        checks[f'chain{i}_ordered']=all(x<y for x,y in zip(xs,xs[1:]))
        checks[f'chain{i}_outer_coil_columns']=abs(xs[0]-mids[0])<1e-6 and abs(xs[-1]-mids[1])<1e-6
        checks[f'chain{i}_outside_drain_rows']=values[0]<top if i==0 else values[0]>bottom
        details.append(dict(devices=chain['devices'],ordered_actual_points=ordered))
        sw=row['direct'][str(i)*2];ends=[at(sw,0),at(sw,1)]
        checks[f'direct{i}_on_corresponding_drain_row']=all(abs(axial(t)-(top if i==0 else bottom))<1e-6 for t in ends)
        checks[f'direct{i}_between_inner_coils']=all(mids[0]<transverse(t)<mids[1] for t in ends)
    cross_points=[]
    for k in ['01','10']:
        n=row['direct'][k];ps=row['pins'][n]
        upper_net=a['ends'][0] if k=='01' else b['ends'][0]
        j=ps.index(upper_net);top=at(n,j);low=at(n,1-j);cross_points += [top,low]
        checks[f'cross{k}_axial']=abs(transverse(top)-transverse(low))<1e-6 and axial(top)<axial(low)
        checks[f'cross{k}_upper_drain_row']=abs(axial(top)-axial(actual[a['mos'][0]]['terminals']['D']))<1e-6
        checks[f'cross{k}_inside']=mids[0]<transverse(top)<mids[1] and axial(low)<(axial(p)+axial(q))/2
    checks['cross_pair_distinct_columns']=abs(transverse(cross_points[0])-transverse(cross_points[2]))>1e-6
    checks['cross_pair_equal_row_extent']=all(abs(axial(cross_points[j])-axial(cross_points[j+2]))<1e-6 for j in [0,1])
    return dict(checks=checks,chains=details,source_axis='xy'[axis],source_transverse_sign=side)

def source(row,examples):
    ctx=ink.load_source(examples/row['corpus'],row['id']);actual={}
    ctx['pins'],_=inputs.nodes(ctx['cards'],(examples/row['corpus']/(row['id']+'.cir')).read_text())
    selected=json.loads((FIG/'center_tap_symbols_cases.json').read_text())['selected']
    names=sorted(set(row['bridge_devices']+[n for b in row['banks'] for n in b['coils']+b['mos']+[b['cap']]]))
    for name in names:
        d=ctx['devices'][name]
        if name.startswith('x'):
            r=next(v for v in selected if v['id']==row['id'] and v['card']==name)
            _,group,parent=aliases.source_group(ctx['human'],ctx['root'],name)
            points=ct.center_tap_ink(ct.primitives(group,parent));tanks.same(points,r['actual_terminals'],name)
            actual[name]=dict(object=group.get('id'),terminals=points)
        else:actual[name]=cross_caps.actual_glyph(ctx['root'],d)
        for term,point in actual[name]['terminals'].items():
            key=term[1:] if name.startswith('x') else term
            index=(r['ports'].index(term) if name.startswith('x') else
                   'DGSB'.index(term) if name.startswith('m') else int(key)-1)
            assert ctx['pins'][name][index]==d['nets'][key].lower()
    proofs=[]
    for chain in row['chains']:
        for net in chain['private']:
            targets=[];binding=[]
            for n in chain['devices']:
                if net not in ctx['pins'][n]:continue
                i=ctx['pins'][n].index(net);targets.append(actual[n]['terminals'][str(i+1)]);binding.append([n,i,net])
            segs,missing=ink.verified_segments(ctx['human'],net,ctx['ink']);proof=ink.source_connection(ctx,segs,targets)
            assert proof['continuous'] and not missing
            proofs.append(dict(net=net,bindings=binding,actual_connection=proof))
    row['pins']={n:ctx['pins'][n] for n in names}
    row['actual_glyphs']=actual
    row['geometry']=frame_geometry(row,actual)
    row['private_wire_proofs']=proofs
    row['outer_bus_proofs']=outer_buses(row,ctx,actual)
    row['unobserved_switch_controls']=[dict(device=n,pin=i,net=ctx['pins'][n][i])
        for n in names if n.startswith('s') for i in (2,3)]
    row['inner_coils']=[inner_coil(row,actual,i) for i in range(2)]
    row['source_sha256']={s:ink.digest(examples/row['corpus']/(row['id']+s)) for s in ['.cir','.human.json','.svg']}
    assert all(row['geometry']['checks'].values()),row['geometry']
    return row

def methods(row,cards,pins,models,coils):
    names=['complete_literal_topology']
    assert len(select(cards,pins,models,coils))==1
    for name,mutate in [('extra_direct_switch',lambda c,p: (c.update(sx=c['se1']),p.update(sx=p['se1']))),('extra_chain_capacitor',lambda c,p:(c.update(cx=c['c1']),p.update(cx=p['c1']))),('private_junction_extra_load',lambda c,p:(c.update(rx=['rx','net6','vss','1k']),p.update(rx=['net6','vss']))),('control_aliases_private_junction',lambda c,p:p['se1'].__setitem__(2,'net6'))]:
        c,p=copy.deepcopy(cards),copy.deepcopy(pins);mutate(c,p);assert not select(c,p,models,coils),name;names.append(name)
    base=row['actual_glyphs']
    for turn in range(4):
        for mirror in [False,True]:
            actual=copy.deepcopy(base)
            for g in actual.values():
                for term,(x,y) in g['terminals'].items():
                    if mirror:x=-x
                    for _ in range(turn):x,y=-y,x
                    g['terminals'][term]=[x+137,y-49]
            assert all(frame_geometry(row,actual)['checks'].values())
    names.append('all_eight_rigid_poses')
    swapped=copy.deepcopy(row)
    for bank in swapped['banks']: bank['coils'].reverse()
    assert frame_geometry(swapped,base)==frame_geometry(row,base)
    names.append('winding_card_order_does_not_choose_inner_column')
    actual=copy.deepcopy(base)
    for term,(x,y) in actual['xlo2']['terminals'].items():
        actual['xlo2']['terminals'][term]=[x-100,y]
    assert not all(frame_geometry(row,actual)['checks'].values())
    names.append('other_winding_moved_inward_rejects_old_chain_column')
    for name,device,delta in [('bent_private_chain','c1',[0,10]),('chain_between_drains','s1',[0,100]),('direct_off_drain_row','se1',[0,10]),('cross_wrong_axis','so1',[10,0])]:
        actual=copy.deepcopy(base)
        if name=='cross_wrong_axis':actual[device]['terminals']['2'][0]+=10
        else:
            for p in actual[device]['terminals'].values():p[0]+=delta[0];p[1]+=delta[1]
        assert not all(frame_geometry(row,actual)['checks'].values()),name;names.append(name)
    return names


def dependencies():
    pending, found = [Path(__file__).name], {}
    while pending:
        name=pending.pop()
        if name in found: continue
        path=HERE/name
        found[name]=ink.digest(path)
        for node in ast.walk(ast.parse(path.read_text())):
            modules=([n.name for n in node.names] if isinstance(node,ast.Import) else
                     [node.module] if isinstance(node,ast.ImportFrom) else [])
            for module in modules:
                local=(module or '').split('.')[0]+'.py'
                if (HERE/local).is_file() and local not in found: pending.append(local)
    found['center_tap_symbols_cases.json']=ink.digest(HERE/'center_tap_symbols_cases.json')
    return dict(sorted(found.items()))


def audit(examples):
    unknown,coils,counts,hashes=ct.scan(examples)
    # The complete source census and every CT glyph/tank leg are freshly
    # replayed; an absent source deck or changed family cannot be skipped.
    tanks.audit(examples)
    by_id=collections.defaultdict(list)
    for c in coils: by_id[c['corpus'],c['id']].append(c)
    rows=[]; considered=[]
    for (corpus,cid),cs in sorted(by_id.items()):
        text=(examples/corpus/(cid+'.cir')).read_text()
        cards=channels.read_cards(text); pins,models=inputs.nodes(cards,text)
        found=select(cards,pins,models,cs)
        considered.append(dict(name=corpus+':'+cid,complete_ct_count=len(cs),coupled_bank_pairs=len(found)))
        for row in found:
            row.update(id=cid,corpus=corpus)
            row=source(row,examples)
            row['method_checks']=methods(row,cards,pins,models,cs)
            rows.append(row)
    names=[r['id']+':coupling-bridges' for r in rows]
    tanks.same(names,EXPECTED,'exact coupled-bank source census')
    # Dot-aware connectivity oracle has its own wrong-net, gap, label,
    # cache-only and actual-junction positive/negative controls.
    wire_methods=ink.method_checks()+ink.source_checks()
    return dict(corpus_counts=counts,corpus_contract_sha256=hashes,
                corpus_exact_names={c:sorted(p.stem.removesuffix('.human')
                    for p in (examples/c).glob('*.human.json')) for c in counts},
                considered_ct_decks=considered,selected_names=names,rows=rows,
                wire_method_checks=wire_methods,dependency_sha256=dependencies(),
                summary=dict(scenes=len(rows),banks=2*len(rows),private_chains=2*len(rows),
                    private_paths=sum(len(r['private_wire_proofs']) for r in rows),
                    outer_buses=sum(len(r['outer_bus_proofs']) for r in rows),
                    named_outer_terminals=sum(len(p['bindings']) for r in rows for p in r['outer_bus_proofs'])),
                limits=['One source figure with two correlated banks, not independent examples.',
                    'Source switches expose two actual path terminals; two electrical control terminals per switch have no asserted source coordinates.',
                    'This evidence authorizes no wiring or crossing-budget exemption.',
                    'The six-device private-chain and four-switch bridge relations have separate placement ownership.'])


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('examples',type=Path)
    parser.add_argument('output',type=Path)
    parser.add_argument('--check',action='store_true')
    args=parser.parse_args()
    result=audit(args.examples)
    args.output.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    if args.check:
        tanks.same(result,json.loads((HERE/'center_tap_chains_cases.json').read_text()),'frozen coupled-bank source evidence')
    print(json.dumps(result['summary'],sort_keys=True))


if __name__=='__main__':
    main()
