#!/usr/bin/env python3
"""Source census for a CT-linked NPN reciprocal-feedback stage.

Usage: ct_feedback_stage.py <examples-root> <output.json> [--check]

Selection uses complete declared incidence, never source IDs or geometry.
Actual SVG leads and conductor ink certify the selected world frame and
five local trees. The broader three-stage cohort retains its counterexample.
"""
from pathlib import Path
import argparse,ast,collections,copy,json,sys
sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
import center_tap_symbols as ct
import channel_bridges as ch
import thin_connectivity as ink
import input_resistors as ir
import block_aliases as aliases


def same(a,b,context):
    if json.loads(json.dumps(a))!=json.loads(json.dumps(b)):raise ValueError(context)


def dependencies():
    pending,found=[Path(__file__).name],{}
    while pending:
        name=pending.pop()
        if name in found:continue
        path=HERE/name;found[name]=ink.digest(path)
        for node in ast.walk(ast.parse(path.read_text())):
            modules=[n.name for n in node.names] if isinstance(node,ast.Import) else [node.module] if isinstance(node,ast.ImportFrom) else []
            for module in modules:
                local=(module or '').split('.')[0]+'.py'
                if (HERE/local).is_file() and local not in found:pending.append(local)
    found['center_tap_symbols_cases.json']=ink.digest(HERE/'center_tap_symbols_cases.json')
    return dict(sorted(found.items()))


def select(cards,pins,models,coils):
    incidences=collections.defaultdict(list)
    for name,ps in pins.items():
        for i,n in enumerate(ps):incidences[n].append((name,i))
    rows=[]
    for coil in coils:
        named=dict(zip(coil['ports'],coil['bindings']));outer=[named['n1'],named['n2']];tap=named['n3']
        if len(set(outer+[tap]))!=3:continue
        if sum(set(dict(zip(c['ports'],c['bindings']))[n] for n in ('n1','n2'))==set(outer) for c in coils)!=1:continue
        drivers=[]
        for end in outer:
            raw=[n for n,p in pins.items() if n[0] in 'mq' and len(p)>=3 and p[0]==end and p[0]!=p[1]]
            if len(raw)!=1:break
            drivers.append(raw[0])
        if len(drivers)!=2 or drivers[0]==drivers[1] or drivers[0][0]!=drivers[1][0]:continue
        a,b=[pins[d] for d in drivers]; kind=models.get(cards[drivers[0]][len(a)+1])
        if kind not in ('npn','nmos') or models.get(cards[drivers[1]][len(b)+1])!=kind:continue
        if len(a)!=4 or len(b)!=4 or a[3]!=b[3] or ch.rail(a[3])!='sink':continue
        controls=[a[1],b[1]]
        if len(set(outer+controls+[tap]))!=5 or any(ch.rail(n) for n in outer+controls):continue
        caps=[];bias=[]
        for i,end in enumerate(outer):
            cs=[n for n,p in pins.items() if n[0]=='c' and len(p)==2 and set(p)=={end,controls[1-i]}]
            if len(cs)!=1:break
            caps.append(cs[0])
        if len(caps)!=2 or caps[0]==caps[1]:continue
        for i,control in enumerate(controls):
            local=[(n,j) for n,j in incidences[control] if n!=drivers[i] and n!=caps[1-i]]
            if len(incidences[control])!=3 or len(local)!=1:break
            n,j=local[0]
            if n[0] not in 'rl' or len(pins[n])!=2 or pins[n][0]==pins[n][1]:break
            bias.append(n)
        if len(bias)!=2 or bias[0]==bias[1] or bias[0][0]!=bias[1][0]:continue
        common=[next(n for n in pins[q] if n!=controls[i]) for i,q in enumerate(bias)]
        if common[0]!=common[1] or common[0] in outer+controls+[tap] or ch.rail(common[0]):continue
        if sorted(incidences[common[0]])!=sorted((q,pins[q].index(common[0])) for q in bias):continue
        clamps=[n for n,p in pins.items() if n[0] in 'mq' and len(p)>=3 and p[0]==p[1] and set((p[0],p[2]))==set(outer)]
        complete_clamps=len(clamps)==2 and all(n[0]==drivers[0][0] and len(pins[n])==4 and pins[n][3]==a[3] and models.get(cards[n][5])==kind for n in clamps) and pins[clamps[0]][0]!=pins[clamps[1]][0]
        whole=(kind=='npn' and bias[0][0]=='l' and complete_clamps and a[2]!=b[2] and ch.rail(tap)=='supply' and all(len(incidences[n])==6 for n in outer) and len(set(outer+controls+[tap,common[0],a[2],b[2]]))==8 and not any(ch.rail(n) for n in (a[2],b[2])))
        members=[coil['card'],*drivers,*caps,*bias,*clamps]
        if len(set(members))!=len(members):continue
        rows.append(dict(coil=coil['card'],ports=coil['ports'],bindings=coil['bindings'],outer=outer,tap=tap,drivers=drivers,kind=kind,controls=controls,caps=caps,bias=bias,common_bias=common[0],clamps=clamps,whole_npn_l_stage=whole,control_incidence={n:incidences[n] for n in controls},bias_incidence=incidences[common[0]]))
    return rows


def points(ctx,row,pins):
    glyphs={}
    for name in row['drivers']+row['caps']+row['bias']+row['clamps']:
        dev=ctx['devices'][name]
        g=ir.actual_resistor(ctx['root'],dev) if name[0]=='r' else ink.actual_inductor(ctx['root'],dev) if name[0]=='l' else ink.actual_glyph(ctx['root'],dev)
        terms=['D','G','S'] if name[0]=='m' else ['C','B','E'] if name[0]=='q' else ['1','2']
        if terms==['1','2'] and not all(t in g['terminals'] for t in terms):terms=['P1','P2']
        assert [dev['nets'][t].lower() for t in terms]==pins[name][:len(terms)],name
        glyphs[name]=dict(g,ordered_terminals=[g['terminals'][t] for t in terms])
    _,group,parent=aliases.source_group(ctx['human'],ctx['root'],row['coil'])
    terminals=ct.center_tap_ink(ct.primitives(group,parent))
    frozen=next(c for c in json.loads((HERE/'center_tap_symbols_cases.json').read_text())['selected'] if c['id']==ctx['human']['id'] and c['card']==row['coil'])
    assert {k:list(v) for k,v in terminals.items()}==frozen['actual_terminals']
    assert row['ports']==frozen['ports'] and row['bindings']==frozen['bindings']
    for i,name in enumerate(('n1','n2','n3'),1):assert ctx['devices'][row['coil']]['nets'][str(i)].lower()==frozen['bindings_by_port'][name]
    glyphs[row['coil']]=dict(object=group.get('data-object-id'),terminals=terminals,ordered_terminals=[terminals[n] for n in row['ports']])
    return glyphs


def relative(row,glyphs):
    terms=glyphs[row['coil']]['terminals'];a,b,t=[terms[n] for n in ('n1','n2','n3')]
    assert (a[0]==b[0])!=(a[1]==b[1])
    axis=[int(b[0]>a[0])-int(b[0]<a[0]),int(b[1]>a[1])-int(b[1]<a[1])]
    normal=[-axis[1],axis[0]]
    midpoint=[(a[i]+b[i])/2 for i in (0,1)]
    if sum((t[i]-midpoint[i])*normal[i] for i in (0,1))>0:normal=[-v for v in normal]
    def local(p):return [sum((p[i]-midpoint[i])*v[i] for i in (0,1)) for v in (axis,normal)]
    p={n:[local(q) for q in g['ordered_terminals']] for n,g in glyphs.items()}
    ds=[p[n] for n in row['drivers']];cs=[p[n] for n in row['caps']];bs=[p[n] for n in row['bias']];cl=[p[n] for n in row['clamps']]
    result=dict(driver_controls_one_row=ds[0][1][1]==ds[1][1][1],driver_paths_perpendicular=all(q[0][0]==q[2][0] and q[0][1]!=q[2][1] for q in ds),caps_parallel=all(q[0][1]==q[1][1] and q[0][0]!=q[1][0] for q in cs),caps_one_row=cs[0][0][1]==cs[1][0][1],caps_before_drivers=max(q[0][1] for q in cs)<min(q[0][1] for q in ds),bias_parallel=all(q[0][1]==q[1][1] and q[0][0]!=q[1][0] for q in bs),bias_after_driver_controls=min(min(x[1] for x in q) for q in bs)>max(q[1][1] for q in ds))

    # Signal endpoints face outward; the complementary feedback/bias ends
    # face the stage centre. Use exact card-net correspondence, not names.
    def bound(name,net):return p[name][row['binding_by_member'][name].index(net)]
    cap_outer=[bound(n,row['outer'][i]) for i,n in enumerate(row['caps'])]
    cap_inner=[bound(n,row['controls'][1-i]) for i,n in enumerate(row['caps'])]
    bias_outer=[bound(n,row['controls'][i]) for i,n in enumerate(row['bias'])]
    bias_inner=[bound(n,row['common_bias']) for n in row['bias']]
    result.update(driver_controls_inward=ds[0][0][0]<ds[0][1][0]<0<ds[1][1][0]<ds[1][0][0],
                  feedback_ends_outward=cap_outer[0][0]<cap_inner[0][0]<0<cap_inner[1][0]<cap_outer[1][0],
                  bias_ends_outward=bias_outer[0][0]<bias_inner[0][0]<0<bias_inner[1][0]<bias_outer[1][0],
                  driver_paths_outside_winding=ds[0][0][0]<local(a)[0] and ds[1][0][0]>local(b)[0],
                  driver_path_rows_equal=ds[0][0][1]==ds[1][0][1] and ds[0][2][1]==ds[1][2][1],
                  base_feedback_bias_column_order=ds[0][1][0]<cap_inner[0][0]<bias_outer[0][0]<bias_inner[0][0]<0<bias_inner[1][0]<bias_outer[1][0]<cap_inner[1][0]<ds[1][1][0])
    if cl:
        result.update(coil_before_all_clamp_leads=min(x[1] for q in cl for x in q)>0,clamps_before_caps=max(x[1] for q in cl for x in q)<min(x[1] for q in cs for x in q),clamps_distinct_path_rows=cl[0][0][1]!=cl[1][0][1])
    return dict(axis=axis,away_from_tap=normal,midpoint=midpoint,local_terminals=p,relations=result)


def checks(row,ctx,pins,models,coils):
    methods=[]
    def whole(c,p,m,cs):return [v for v in select(c,p,m,cs) if v['whole_npn_l_stage']]
    changes=[
      ('extra_control_incidence',lambda c,p,m,cs:(c.update(rextra=['rextra']),p.update(rextra=['net7','remote']))),
      ('extra_outer_incidence',lambda c,p,m,cs:(c.update(rextra=['rextra']),p.update(rextra=['net10','remote']))),
      ('third_unknown_driver',lambda c,p,m,cs:(c.update(qextra=['qextra','net10','g','e','vss','unknown']),p.update(qextra=['net10','g','e','vss']))),
      ('third_unknown_clamp',lambda c,p,m,cs:(c.update(qextra=['qextra','net10','net10','net8','vss','unknown']),p.update(qextra=['net10','net10','net8','vss']))),
      ('duplicate_ct_before_tap_filter',lambda c,p,m,cs:cs.append(dict(cs[0],card='xextra',bindings=['net10','net8','net10']))),
      ('unknown_clamp_model',lambda c,p,m,cs:c['q3'].__setitem__(5,'unknown')),
      ('aliased_driver_emitters',lambda c,p,m,cs:p['q2'].__setitem__(2,'net5')),
      ('unshared_driver_body',lambda c,p,m,cs:p['q2'].__setitem__(3,'other')),
      ('feedback_to_own_control',lambda c,p,m,cs:p['c1'].__setitem__(0,'net7')),
      ('parallel_feedback_ambiguity',lambda c,p,m,cs:(c.update(cextra=['cextra']),p.update(cextra=p['c1'][:]))),
      ('nonrail_tap',lambda c,p,m,cs:cs[0]['bindings'].__setitem__(2,'other')),
    ]
    for name,mut in changes:
        c,p,m,cs=copy.deepcopy((ctx['cards'],pins,models,coils));mut(c,p,m,cs);assert not whole(c,p,m,cs),name;methods.append(name)
    assert len(whole(dict(reversed(list(ctx['cards'].items()))),dict(reversed(list(pins.items()))),models,coils))==1;methods.append('card_order')
    reordered=copy.deepcopy(coils);reordered[0]['ports']=['n3','n2','n1'];reordered[0]['bindings']=['vcc','net8','net10'];assert len(whole(ctx['cards'],pins,models,reordered))==1;methods.append('declared_port_order')
    for swap in (False,True):
        for sx in (-1,1):
            for sy in (-1,1):
                g=copy.deepcopy(row['actual'])
                def transform(point):
                    x,y=point if not swap else point[::-1]
                    return [sx*x+137,sy*y-49]
                for item in g.values():
                    item['terminals']={n:transform(p) for n,p in item['terminals'].items()}
                    item['ordered_terminals']=[transform(p) for p in item['ordered_terminals']]
                assert all(relative(row,g)['relations'].values()),(swap,sx,sy)
    methods.append('eight_rigid_poses')
    for name,device,index,point in [
      ('driver_base_row_mismatch','q1',1,[20,200]),
      ('cap_no_longer_parallel','c1',0,[60,140]),
      ('bias_not_outward','lb1a',1,[160,240]),
      ('bias_before_controls','lb1a',0,[120,100]),
      ('clamp_not_between_coil_and_caps','q3',0,[90,150]),
      ('left_bias_control_before_feedback_inner','lb1a',1,[40,240]),
      ('right_bias_control_before_feedback_inner','lb1b',0,[320,240])]:
        g=copy.deepcopy(row['actual']);g[device]['ordered_terminals'][index]=point
        assert not all(relative(row,g)['relations'].values()),name;methods.append(name)
    return methods


def audit(examples):
    unknown,coils,counts,contracts=ct.scan(examples)
    inv=json.loads((HERE/'center_tap_symbols_cases.json').read_text())
    assert unknown==inv['unknown_outer_families'] and counts==inv['corpus_drawings'] and contracts==inv['corpus_contract_sha256']
    by=collections.defaultdict(list)
    for c in coils:by[c['corpus'],c['id']].append(c)
    rows=[];scope={};primitive_count=0
    for corpus in ('analoggenie','amsnet'):
        hashes={}
        for path in sorted((examples/corpus).glob('*.human.json')):
            ident=path.name.removesuffix('.human.json');text=path.with_name(ident+'.cir').read_text();cards=ink.read_cards(text);pins,models=ir.nodes(cards,text)
            for device in json.loads(path.read_text())['devices']:
                if device['card'][0] not in 'mq':continue
                name=device['card'];terms=('D','G','S') if name[0]=='m' else ('C','B','E')
                assert [device['nets'][term].lower() for term in terms]==pins[name][:3]
                assert models[cards[name][len(pins[name])+1]]==device['type']
                primitive_count+=1
            hashes[ident]={s:ink.digest(path.with_name(ident+s)) for s in ('.cir','.human.json','.svg')}
            for row in select(cards,pins,models,by[corpus,ident]):
                ctx=ink.load_source(examples/corpus,ident);ctx['human']['wires']=[w for w in ctx['human']['wires'] if w['net'] is not None]
                actual=points(ctx,row,pins);row['binding_by_member']={n:pins[n] for n in actual};row.update(id=ident,corpus=corpus,actual=actual,geometry=relative(row,actual),connections=[])
                for net in row['outer']+row['controls']+[row['common_bias']]:
                    named=[(n,i,g['ordered_terminals'][i]) for n,g in actual.items() for i,v in enumerate(pins[n][:len(g['ordered_terminals'])]) if v==net]
                    segments,missing=ink.verified_segments(ctx['human'],net,ctx['ink']);proof=ink.source_connection(ctx,segments,[p for n,i,p in named])
                    if row['whole_npn_l_stage']:assert proof['continuous'],(ident,net,proof)
                    whole=None if proof['continuous'] else ink.source_connection(ctx,ctx['ink'],[p for n,i,p in named])
                    if whole is not None:assert not whole['continuous'],(ident,net,'unassigned actual connection')
                    row['connections'].append(dict(net=net,terminals=named,proof=proof,whole_ink=whole,status='source_connected' if proof['continuous'] else 'source_disconnected',cache_only=missing))
                rows.append(row)
        scope[corpus]=dict(names=sorted(hashes),source_sha256=hashes,index_sha256=ink.digest(examples/corpus/'index.json'))
    assert [(r['id'],r['coil']) for r in rows]==[('ag-1114','x1'),('ag-1131','x1'),('ag-1149','xlp')]
    selected=[r for r in rows if r['whole_npn_l_stage']];assert [r['id'] for r in selected]==['ag-1149']
    r=selected[0];assert all(r['geometry']['relations'].values())
    ctx=ink.load_source(examples/r['corpus'],r['id']);pins,models=ir.nodes(ctx['cards'],(examples/r['corpus']/(r['id']+'.cir')).read_text());methods=checks(r,ctx,pins,models,by[r['corpus'],r['id']])
    out=dict(methods=methods,scope=scope,ct_inventory_sha256=ink.digest(HERE/'center_tap_symbols_cases.json'),rows=rows,selected_names=[r['corpus']+':'+r['id']+':'+r['coil'] for r in selected],script_sha256=ink.digest(Path(__file__)),limits=['One whole NPN/L/clamp source figure, three broader reciprocal-cap stages.','The selected figure is world-horizontal with tap up and NPN drivers emitter down; no universal orientation or absolute-gap rule is inferred.','Bias resistors are below in1114 but above in1131; broad bias-row generalization fails.'])
    assert primitive_count==25103
    expected_methods=['extra_control_incidence','extra_outer_incidence','third_unknown_driver','third_unknown_clamp','duplicate_ct_before_tap_filter','unknown_clamp_model','aliased_driver_emitters','unshared_driver_body','feedback_to_own_control','parallel_feedback_ambiguity','nonrail_tap','card_order','declared_port_order','eight_rigid_poses','driver_base_row_mismatch','cap_no_longer_parallel','bias_not_outward','bias_before_controls','clamp_not_between_coil_and_caps','left_bias_control_before_feedback_inner','right_bias_control_before_feedback_inner']
    same(methods,expected_methods,'named methods changed')
    same(out['selected_names'],['analoggenie:ag-1149:xlp'],'selected names changed')
    g=r['actual'];a,b,t=[g[r['coil']]['terminals'][p] for p in ('n1','n2','n3')]
    world=dict(coil_horizontal=a[1]==b[1] and a[0]<b[0],tap_up=t[1]<a[1] and 2*t[0]==a[0]+b[0],drivers_upright_emitter_down=all(q[0][0]==q[2][0] and q[0][1]<q[1][1]<q[2][1] for q in [g[n]['ordered_terminals'] for n in r['drivers']]))
    assert all(world.values())
    out.update(dependency_sha256=dependencies(),primitive_bindings=primitive_count,world_frame=world)
    out['summary']=dict(corpus_drawings=sum(counts.values()),broader_stages=len(rows),selected_stages=len(selected),actual_selected_endpoints=sum(len(q['ordered_terminals']) for q in g.values()),selected_trees=len(r['connections']),methods=len(methods))
    assert out['summary']==dict(corpus_drawings=2936,broader_stages=3,selected_stages=1,actual_selected_endpoints=23,selected_trees=5,methods=21)
    return out


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('examples',type=Path)
    parser.add_argument('output',type=Path)
    parser.add_argument('--check',action='store_true')
    args=parser.parse_args();result=audit(args.examples)
    args.output.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    if args.check:same(result,json.loads((HERE/'ct_feedback_stage_cases.json').read_text()),'frozen feedback-stage evidence changed')
    print(json.dumps(result['summary'],sort_keys=True))

if __name__=='__main__':main()
