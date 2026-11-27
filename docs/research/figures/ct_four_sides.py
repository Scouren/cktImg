#!/usr/bin/env python3
"""Complete CT/LCL/four-side stage: actual SVG frames and physical partitions.

Usage: ct_four_sides.py EXAMPLES OUTPUT [--check]

Human Rules: one complete26-device scene in2936 decks has inward CT taps,
outward upper/lower five-MOS banks, and two reciprocal side banks with
horizontal bypasses above. All72 visible leads and148 physical pair facts
are independent source evidence; topology does not imply every same-net
pair has drawn wire. No native parity or population frequency is claimed.
"""
import argparse,ast,copy,itertools,json,pathlib,sys
HERE=pathlib.Path(__file__).resolve().parent
sys.path.insert(0,str(HERE));sys.dont_write_bytecode=True
import ct_series_tanks as lcl
import center_tap_symbols as ct
import channel_bridges as channels
import input_resistors as inputs
import thin_connectivity as ink
import cross_caps
import block_aliases as aliases

def exactly(xs):return xs[0] if len(xs)==1 else None

def five(pins,ends):
    a,b=ends
    forward=[d for d,p in pins.items() if d.startswith('m') and len(p)==4 and p[:2]==[a,b]]
    reverse=[d for d,p in pins.items() if d.startswith('m') and len(p)==4 and p[:2]==[b,a]]
    if len(forward)!=2 or len(reverse)!=2:return
    bodies={pins[d][3] for d in forward+reverse}
    if len(bodies)!=1:return
    ground,=bodies
    srcs=[{pins[d][2] for d in branch} for branch in (forward,reverse)]
    if srcs[0]!=srcs[1] or len(srcs[0])!=2 or ground not in srcs[0]:return
    common,=srcs[0]-{ground}
    pair=[exactly([d for d in branch if pins[d][2]==common]) for branch in (forward,reverse)]
    shunts=[exactly([d for d in branch if pins[d][2]==ground]) for branch in (forward,reverse)]
    tails=[d for d,p in pins.items() if d.startswith('m') and len(p)==4 and p[0]==common and p[2:]==[ground,ground]]
    tail=exactly(tails)
    if None in pair+shunts or tail is None:return
    return dict(cross=pair,shunts=shunts,tail=tail,common=common,ground=ground,control=pins[tail][1])

def four(pins,ends):
    a,b=ends
    pair=[exactly([d for d,p in pins.items() if d.startswith('m') and len(p)==4 and p[:2]==want]) for want in ([a,b],[b,a])]
    if None in pair:return
    p,q=[pins[d] for d in pair]
    if p[2:]!=q[2:]:return
    common,ground=p[2:]
    tail=exactly([d for d,p in pins.items() if d.startswith('m') and len(p)==4 and p[0]==common and p[2:]==[ground,ground]])
    bypass=exactly([d for d,p in pins.items() if d.startswith('m') and len(p)==4 and p[0]==a and p[2:]==[b,ground]])
    if tail is None or bypass is None:return
    return dict(cross=pair,tail=tail,bypass=bypass,common=common,ground=ground,control=pins[tail][1],bridge_control=pins[bypass][1])

def members(stage):
    out=[]
    for g in stage['tanks']:out += [g['coil'],*g['inductors'],g['capacitor']]
    for g in stage['ends']:out += [*g['cross'],*g['shunts'],g['tail']]
    for g in stage['sides']:out += [*g['cross'],g['tail'],g['bypass']]
    return out

def raw_stages(pins,peers):
    tanks=[g for c in peers if (g:=lcl.raw(pins,c,peers)) is not None]
    out=[]
    for ta,tb in itertools.permutations(tanks,2):
        if ta['tap']!=tb['tap']:continue
        ea,eb=five(pins,ta['far']),five(pins,tb['far'])
        if ea is None or eb is None:continue
        for swap in (False,True):
            order=[1,0] if swap else [0,1]
            side=[four(pins,[ta['outer'][i],tb['outer'][j]]) for i,j in enumerate(order)]
            if any(g is None for g in side):continue
            allg=[ea,eb,*side]
            if len({g['ground'] for g in allg})!=1:continue
            if ea['control']!=eb['control'] or any(g['bridge_control']!=ea['control'] for g in side):continue
            if side[0]['control']!=side[1]['control']:continue
            nets=[*ta['outer'],*tb['outer'],*ta['far'],*tb['far'],*(g['common'] for g in allg),ta['tap'],ea['ground'],ea['control'],side[0]['control']]
            if len(set(nets))!=16:continue
            stage=dict(tanks=[ta,tb],ends=[ea,eb],sides=side,side_second_order=order,nets=nets)
            names=members(stage)
            if len(names)!=26 or len(set(names))!=26:continue
            # Every raw incidence of all16 named stage nets is counted. This
            # includes substrate/control pins; no invisible pin is discarded.
            incidence={n:sorted([d,i] for d,p in pins.items() for i,v in enumerate(p) if v==n) for n in nets}
            if any(any(d not in names for d,i in ps) for ps in incidence.values()):continue
            expected=[5]*4+[6]*4+[3]*4+[2,26,4,2]
            if [len(incidence[n]) for n in nets]!=expected:continue
            stage['incidences']=incidence;out.append(stage)
    # Count all full candidates before known-polarity/rail eligibility.
    return out

def select(pins,peers,cards,models):
    raw=raw_stages(pins,peers)
    if len(raw)!=1:return None
    s=raw[0]
    if any(models.get(cards[d][5])!='nmos' for d in members(s) if d.startswith('m')):return None
    if channels.rail(s['tanks'][0]['tap'])!='supply' or channels.rail(s['ends'][0]['ground'])!='sink':return None
    if any(channels.rail(n) for n in s['nets'][:12]+s['nets'][14:]):return None
    return s

def methods(pins,peers,cards,models):
    s=select(pins,peers,cards,models);assert s is not None
    names=[]
    def rejected(label,edit):
        p,c,ps,m=copy.deepcopy((pins,cards,peers,models));edit(p,c,ps,m)
        assert select(p,ps,c,m) is None,label
        names.append(label)
    picked=s['sides'][0]['cross'][0]
    rejected('extra_raw_channel_competitor',lambda p,c,ps,m:(p.update(m_extra=p[picked][:]),c.update(m_extra=c[picked][:])))
    rejected('extra_path_incidence',lambda p,c,ps,m:p.update(r_extra=[s['tanks'][0]['far'][0],'external']))
    rejected('extra_control_incidence',lambda p,c,ps,m:p.update(r_extra=[s['ends'][0]['control'],'external']))
    rejected('extra_hidden_bulk_incidence',lambda p,c,ps,m:p.update(m_extra=['external1','external2','external3',s['ends'][0]['ground']]))
    rejected('missing_bypass',lambda p,c,ps,m:p.pop(s['sides'][0]['bypass']))
    rejected('second_complete_winding',lambda p,c,ps,m:ps.append(dict(ps[0],card='x_duplicate')))
    def polarity(p,c,ps,m):
        c[picked][5]='known_pmos';m['known_pmos']='pmos'
    rejected('wrong_known_polarity_after_raw_selection',polarity)
    rejected('unknown_model_after_raw_selection',lambda p,c,ps,m:c[picked].__setitem__(5,'unknown'))
    assert select(dict(reversed(list(pins.items()))),list(reversed(peers)),cards,models)==s
    names.append('card_order_invariance')
    rename={d:d[0]+'renamed_'+str(i) for i,d in enumerate(sorted(pins))}
    netmap={n:'vdd' if n==s['tanks'][0]['tap'] else 'vss' if n==s['ends'][0]['ground'] else 'signal_'+str(i) for i,n in enumerate(s['nets'])}
    p={rename[d]:[netmap.get(n,n) for n in ps] for d,ps in pins.items()}
    c={rename[d]:[rename[d],*[netmap.get(n,n) for n in row[1:]]] for d,row in cards.items()}
    ps=[dict(q,card=rename[q['card']],bindings=[netmap.get(n,n) for n in q['bindings']]) for q in peers]
    renamed=select(p,ps,c,models);assert renamed and set(members(renamed))=={rename[d] for d in members(s)}
    names.append('all_device_and_nonrail_net_renaming')
    for which in range(len(peers)):
        p,c,ps,m=copy.deepcopy((pins,cards,peers,models))
        coil=ps[which];d=coil['card'];i,j=coil['ports'].index('n1'),coil['ports'].index('n2')
        coil['bindings'][i],coil['bindings'][j]=coil['bindings'][j],coil['bindings'][i]
        p[d][i],p[d][j]=p[d][j],p[d][i];c[d][i+1],c[d][j+1]=c[d][j+1],c[d][i+1]
        altered=select(p,ps,c,m);assert altered and set(members(altered))==set(members(s))
    names.append('either_winding_outer_card_reversal')
    p,c,ps,m=copy.deepcopy((pins,cards,peers,models))
    for d in members(s):
        if d[0] in 'lc':p[d].reverse();c[d][1:3]=reversed(c[d][1:3])
    altered=select(p,ps,c,m);assert altered and set(members(altered))==set(members(s))
    names.append('all_two_terminal_cards_reversed')
    return names

def reflection(stage,pins):
    # Electrical involution. CT outer-role exchange and unordered L/C ends
    # are explicit; MOS D/G/S/B roles never exchange. This does not assert
    # that all source control leads are geometric mirror images.
    dev={d:d for d in members(stage)};net={n:n for n in stage['nets']}
    def pair(table,a,b):table[a]=b;table[b]=a
    for t,e in zip(stage['tanks'],stage['ends']):
        pair(dev,*t['inductors']);pair(net,*t['outer']);pair(net,*t['far'])
        pair(dev,*e['cross']);pair(dev,*e['shunts'])
    a,b=stage['sides']
    for u,v in zip(a['cross']+[a['tail'],a['bypass']],b['cross']+[b['tail'],b['bypass']]):pair(dev,u,v)
    pair(net,a['common'],b['common'])
    checked=[]
    for d in sorted(dev):
        mapped=[net[n] for n in pins[d]];target=pins[dev[d]]
        if d.startswith('m'):assert mapped==target
        else:assert sorted(mapped)==sorted(target)
        checked.append(dict(card=d,image=dev[d],mapped_bindings=mapped,image_bindings=target))
    assert all(dev[dev[d]]==d for d in dev) and all(net[net[n]]==n for n in net)
    return dict(device_map=dev,net_map=net,bindings=checked,scope='Electrical involution with CT outer exchange and unordered two-terminal passives, not the engine exact-mate table or full source-lead reflection.')

def source(examples,ident,peers,stage,pins):
    ctx=ink.load_source(examples,ident);glyphs={};visible=[]
    bycoil={c['card']:c for c in peers}
    for d in sorted(members(stage)):
        dev=ctx['devices'][d]
        if d.startswith('x'):
            coil=bycoil[d];_,g,parent=aliases.source_group(ctx['human'],ctx['root'],d)
            actual=ct.center_tap_ink(ct.primitives(g,parent));glyphs[d]=dict(terminals=actual)
            for i,port in enumerate(coil['ports']):
                assert dev['nets'][port[1:]].lower()==pins[d][i]
                visible.append(dict(card=d,index=i,role=port,net=pins[d][i],xy=actual[port]))
        else:
            glyphs[d]=(ink.actual_inductor if d.startswith('l') else cross_caps.actual_glyph)(ctx['root'],dev)
            if d.startswith('m'):
                assert dev['nets']['B'].lower()==pins[d][3]
            terms=['d','g','s'] if d.startswith('m') else ['a','b']
            for i,role in enumerate(terms):
                name=ink.terminal(dev,i,role);assert dev['nets'][name].lower()==pins[d][i]
                visible.append(dict(card=d,index=i,role=role,net=pins[d][i],xy=glyphs[d]['terminals'][name]))
    assert len(visible)==72
    partitions=[];pairs=[]
    for net in stage['nets']:
        ps=[p for p in visible if p['net']==net];segments,missing=ink.verified_segments(ctx['human'],net,ctx['ink'])
        parent=list(range(len(ps)))
        def find(i):
            while parent[i]!=i:i=parent[i]
            return i
        for i,j in itertools.combinations(range(len(ps)),2):
            targets=[ps[i]['xy'],ps[j]['xy']];proof=ink.source_connection(ctx,segments,targets)
            whole=None
            if proof['continuous']:parent[find(j)]=find(i)
            else:
                whole=ink.source_connection(ctx,ctx['ink'],targets)
                assert not whole['continuous'],(ident,net,ps[i],ps[j],'unassigned actual ink')
            pairs.append(dict(net=net,pins=[[ps[k]['card'],ps[k]['index']] for k in (i,j)],connected=proof['continuous'],proof=proof,whole_ink_negative=whole))
        groups={}
        for i,p in enumerate(ps):groups.setdefault(find(i),[]).append([p['card'],p['index']])
        partitions.append(dict(net=net,components=list(groups.values()),verified_segments=segments,cache_segments_without_ink=missing,labels=ink.label_evidence(ctx['root'],net)))
    p={(v['card'],v['role']):v['xy'] for v in visible}
    ta,tb=stage['tanks'];ea,eb=stage['ends'];sa,sb=stage['sides']
    ca=[p[(t['coil'],'n'+str(i))] for t in (ta,tb) for i in (1,2,3)]
    axis=(ca[0][0]+ca[1][0])/2
    observed=dict(two_horizontal_coils=ca[0][1]==ca[1][1] and ca[3][1]==ca[4][1],common_midpoint=2*axis==ca[3][0]+ca[4][0],inward_taps=ca[0][1]<ca[2][1]<ca[5][1]<ca[3][1])
    for n,(t,e,up) in enumerate(((ta,ea,True),(tb,eb,False))):
        ms=e['cross']+e['shunts'];d=[p[(x,'d')] for x in ms];s=[p[(x,'s')] for x in ms]
        observed[f'five{n}_common_D_and_S_rows']=len({v[1] for v in d})==1 and len({v[1] for v in s})==1
        observed[f'five{n}_sources_outward']=all((b[1]<a[1])==up for a,b in zip(d,s))
        observed[f'five{n}_tail_on_common_source_row']=p[(e['tail'],'d')][1]==s[0][1]
        observed[f'five{n}_tail_midpoint']=p[(e['tail'],'d')][0]==axis
        observed[f'five{n}_shunts_outside_crosspair']=p[(e['shunts'][0],'d')][0]<p[(e['cross'][0],'d')][0]<axis<p[(e['cross'][1],'d')][0]<p[(e['shunts'][1],'d')][0]
        c=glyphs[t['capacitor']]['terminals'];cy=next(iter(c.values()))[1]
        observed[f'five{n}_beyond_capacitor']=all((v[1]<cy)==up for v in d)
    for n,g in enumerate(stage['sides']):
        ds=[p[(x,'d')] for x in g['cross']];gs=[p[(x,'g')] for x in g['cross']];ss=[p[(x,'s')] for x in g['cross']]
        observed[f'side{n}_common_rows_between_coils']=ds[0][1]==ds[1][1] and gs[0][1]==gs[1][1] and ss[0][1]==ss[1][1] and ca[0][1]<ds[0][1]<gs[0][1]<ss[0][1]<ca[3][1]
        observed[f'side{n}_outside_coils']=all(v[0]<ca[0][0] for v in ds) if n==0 else all(v[0]>ca[1][0] for v in ds)
        observed[f'side{n}_bypass_above']=p[(g['bypass'],'d')][1]==p[(g['bypass'],'s')][1]<ca[0][1]
        observed[f'side{n}_tail_common_source_row']=p[(g['tail'],'d')][1]==ss[0][1]
    assert all(observed.values()),observed
    ref=reflection(stage,pins);mismatches=[]
    for d,image in ref['device_map'].items():
        if not d.startswith('m'):continue
        for role in ('d','g','s'):
            want=[2*axis-p[(d,role)][0],p[(d,role)][1]]
            if want!=p[(image,role)]:mismatches.append(dict(card=d,role=role,image=image,expected=want,actual=p[(image,role)]))
    return dict(glyphs=glyphs,visible_bindings=visible,hidden_bulk_bindings=[dict(card=d,index=3,net=pins[d][3],source_geometry='not assigned') for d in members(stage) if d.startswith('m')],source_sha256=ctx['source_sha256'],partitions=partitions,pairs=pairs,geometry=observed,electrical_reflection=ref,actual_mirror_exceptions=mismatches)

def dependencies():
    found,pending={},[pathlib.Path(__file__).name]
    while pending:
        name=pending.pop()
        if name in found:continue
        path=HERE/name;found[name]=ink.digest(path)
        for node in ast.walk(ast.parse(path.read_text())):
            modules=[n.name for n in node.names] if isinstance(node,ast.Import) else [node.module] if isinstance(node,ast.ImportFrom) else []
            for module in modules:
                local=(module or '').split('.')[0]+'.py'
                if (HERE/local).is_file():pending.append(local)
    return dict(sorted(found.items()))

def audit(examples):
    _,coils,counts,hashes=ct.scan(examples);rows=[];observations=[]
    for corpus,ident in sorted({(c['corpus'],c['id']) for c in coils}):
        peers=[c for c in coils if (c['corpus'],c['id'])==(corpus,ident)]
        text=(examples/corpus/(ident+'.cir')).read_text();cards=channels.read_cards(text);pins,models=inputs.nodes(cards,text)
        raw=raw_stages(pins,peers);stage=select(pins,peers,cards,models)
        observations.append(dict(corpus=corpus,id=ident,complete_coils=len(peers),raw_whole_stages=len(raw),selected=stage is not None))
        if stage:
            rows.append(dict(name=ident+':paired_lcl_four_sides',topology=stage,members=sorted(members(stage)),method_checks=methods(pins,peers,cards,models),source=source(examples/corpus,ident,peers,stage,pins)))
    assert [r['name'] for r in rows]==['ag-1153:paired_lcl_four_sides']
    result=dict(corpus_counts=counts,corpus_sha256=hashes,complete_ct_instances=len(coils),observations=observations,rows=rows,script_sha256=ink.digest(pathlib.Path(__file__)),dependencies=dependencies(),limits=['One complete26-device scene; no population frequency claim.','Full90 card incidences validated; only72 actual visible lead endpoints assigned. Eighteen substrate geometries are unknown.','Exact external incidences on all16 stage nets reject extra rail/control/device attachments in this first certificate.','Electrical outer-terminal exchange is explicit and does not modify the engine exact mate table.','This source certificate does not assert native geometry or partition preservation.'])
    # Existing actual-SVG helpers return coordinate tuples; the persisted
    # certificate is JSON. Normalize once so --check compares that schema.
    return json.loads(json.dumps(result))

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('examples',type=pathlib.Path);ap.add_argument('output',type=pathlib.Path)
    ap.add_argument('--check',action='store_true');a=ap.parse_args()
    result=audit(a.examples)
    a.output.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    if a.check:
        expected=json.loads((HERE/'ct_four_sides_cases.json').read_text())
        if result!=expected:raise ValueError('frozen whole26 source certificate differs')
    print(json.dumps(dict(names=[r['name'] for r in result['rows']],methods=[len(r['method_checks']) for r in result['rows']],visible=[len(r['source']['visible_bindings']) for r in result['rows']],pairs=[len(r['source']['pairs']) for r in result['rows']]),indent=2))
if __name__=='__main__':main()
