#!/usr/bin/env python3
"""Actual-source certificate for one CT-linked common-base bias stage.

Usage: ct_common_controls.py <examples-root> <output.json> [--check]

Reselects all complete CT contracts and validates every drawn transistor's
ordered path/control bindings and model. The selected five-member stage is
one figure; a separate exact common-collector/drain census retains both
connected and separated source ink, not an assumed desired connection.
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
import thin_connectivity as t
import input_resistors as ir
import center_tap_symbols as ct
import block_aliases as aliases
import channel_bridges as ch

EXPECTED = ["analoggenie:ag-1114:q3/q4:x1:rb1/rb2"]
NEGATIVES = [("ag-764", "vin", ["q1", "q2"]),
             ("ag-781", "vi+", ["q1", "q3"]),
             ("ag-781", "vi-", ["q2", "q4"]),
             ("ag-2376", "veaout", ["m1", "msen"]),
             ("ag-2381", "veaout", ["m1", "msen"])]


def same(a, b, context):
    if json.loads(json.dumps(a)) != json.loads(json.dumps(b)):
        raise ValueError(context)


def dependencies():
    pending, found = [Path(__file__).name], {}
    while pending:
        name = pending.pop()
        if name in found:
            continue
        path = HERE / name
        found[name] = t.digest(path)
        for node in ast.walk(ast.parse(path.read_text())):
            modules = [n.name for n in node.names] if isinstance(node, ast.Import) else [node.module] if isinstance(node, ast.ImportFrom) else []
            for module in modules:
                local = (module or "").split(".")[0] + ".py"
                if (HERE / local).is_file() and local not in found:
                    pending.append(local)
    found["center_tap_symbols_cases.json"] = t.digest(HERE / "center_tap_symbols_cases.json")
    return dict(sorted(found.items()))


def select(cards,pins,models,coils):
 out=[]
 for coil in coils:
  n=dict(zip(coil['ports'],coil['bindings'])); ends=[n['n1'],n['n2']];tap=n['n3']
  if len(set(ends+[tap]))!=3:continue
  rivals=[c for c in coils if set(dict(zip(c['ports'],c['bindings']))[p] for p in ('n1','n2'))==set(ends)]
  if len(rivals)!=1:continue
  branches=[[k for k in cards if k[0]=='q' and len(pins[k])>=3 and pins[k][2]==end] for end in ends]
  raw=[(a,b) for a in branches[0] for b in branches[1] if a!=b and pins[a][:2]==pins[b][:2]]
  if len(raw)!=1:continue
  a,b=raw[0];pa,pb=pins[a],pins[b];collector,base=pa[:2]
  if len(set(ends+[tap,collector,base]))!=5:continue
  incident=sorted((k,i) for k,ps in pins.items() for i,q in enumerate(ps) if q==base)
  if len(incident)!=4:continue
  if sorted((k,i) for k,i in incident if k[0]!='r')!=sorted([(a,1),(b,1)]):continue
  rs=[k for k,i in incident if k[0]=='r']
  if len(rs)!=2 or len(set(rs))!=2 or any(len(pins[r])!=2 or pins[r][0]==pins[r][1] for r in rs):continue
  other={r:next(q for q in pins[r] if q!=base) for r in rs}
  taps=[r for r in rs if other[r]==tap];supplies=[r for r in rs if ch.rail(other[r])=='supply']
  if len(taps)!=1 or len(supplies)!=1 or taps==supplies:continue
  if len(pa)!=4 or len(pb)!=4 or pa[3]!=pb[3] or ch.rail(pa[3])!='sink':continue
  if any(models.get(cards[q][len(pins[q])+1])!='npn' for q in (a,b)):continue
  if any(ch.rail(n) for n in ends+[tap,collector,base]):continue
  out.append(dict(coil=coil['card'],transistors=[a,b],resistors=rs,collector=collector,base=base,emitters=ends,tap=tap,supply=other[supplies[0]],substrate=pa[3],base_incidence=incident))
 return out


def audit(examples):
    unknown,coils,counts,contracts=ct.scan(examples)
    ct_inventory=json.loads((HERE/'center_tap_symbols_cases.json').read_text())
    same(unknown,ct_inventory['unknown_outer_families'],'CT excluded contracts changed')
    same(counts,ct_inventory['corpus_drawings'],'CT corpus counts changed')
    same(contracts,ct_inventory['corpus_contract_sha256'],'CT corpus hashes changed')
    by=collections.defaultdict(list)
    for c in coils:by[(c['corpus'],c['id'])].append(c)
    selected=[];scope={};primitive_count=0; common=[]
    for corpus in ('analoggenie','amsnet'):
     deck_names=[];hashes={}
     for hp in sorted((examples/corpus).glob('*.human.json')):
      ident=hp.name.removesuffix('.human.json');deck_names.append(ident); cp=hp.with_name(ident+'.cir');text=cp.read_text();cards=t.read_cards(text);pins,models=ir.nodes(cards,text);human=json.loads(hp.read_text())
      for d in human['devices']:
       if d['card'][0] not in 'mq':continue
       card=d['card'];ps=pins[card];roles=('D','G','S') if card[0]=='m' else ('C','B','E')
       assert [d['nets'][k].lower() for k in roles]==ps[:3],(ident,card)
       assert models[cards[card][len(ps)+1]]==d['type'],(ident,card)
       primitive_count+=1
      hashes[ident]={s:t.digest(hp.with_name(ident+s)) for s in ('.cir','.human.json','.svg')}
      # The weaker same-control/common-first-end cohort is derived from the
      # independently validated ordered cards, then challenged by actual ink.
      by_control=collections.defaultdict(list)
      for d in human['devices']:
       card=d['card']
       if card[0] in 'mq': by_control[(d['type'],pins[card][1])].append(card)
      candidates=[]
      for (kind,net),names in sorted(by_control.items()):
       for a,b in itertools.combinations(sorted(names),2):
        pa,pb=pins[a],pins[b]
        matches=[(i,j) for i,k in enumerate((0,2)) for j,l in enumerate((0,2)) if pa[k]==pb[l]]
        if matches==[(0,0)]: candidates.append((kind,net,a,b))
      if candidates:
       context=t.load_source(examples/corpus,ident)
       context['human']['wires']=[w for w in context['human']['wires'] if w['net'] is not None]
       for kind,net,a,b in candidates:
        pair=dict(id=ident,net=net,pins=[[a,1],[b,1]],terms=['g','g'] if a[0]=='m' else ['b','b'])
        proof=t.source(context,pair)
        assert proof['status'] in ('source_connected','source_disconnected'),(ident,a,b,proof)
        common.append(dict(pair,name=corpus+':'+t.key(pair),kind=kind,source=proof))
      for row in select(cards,pins,models,by[(corpus,ident)]):selected.append(dict(row,id=ident,corpus=corpus))
     scope[corpus]=dict(names=deck_names,source_sha256=hashes,index_sha256=t.digest(examples/corpus/'index.json'))
    assert primitive_count==25103
    assert [(r['id'],r['transistors'],r['coil']) for r in selected]==[('ag-1114',['q3','q4'],'x1')]
    r=selected[0];ctx=t.load_source(examples/r['corpus'],r['id']);ctx['human']['wires']=[w for w in ctx['human']['wires'] if w['net'] is not None];text=(examples/r['corpus']/(r['id']+'.cir')).read_text();pins,models=ir.nodes(ctx['cards'],text)
    actual={q:t.actual_glyph(ctx['root'],ctx['devices'][q]) for q in r['transistors']}
    actual.update({q:ir.actual_resistor(ctx['root'],ctx['devices'][q]) for q in r['resistors']})
    _,g,parent=aliases.source_group(ctx['human'],ctx['root'],r['coil']);actual[r['coil']]=dict(terminals=ct.center_tap_ink(ct.primitives(g,parent)),object=g.get('data-object-id'))
    literal=next(v for v in json.loads((HERE/'center_tap_symbols_cases.json').read_text())['selected'] if v['id']==r['id'] and v['card']==r['coil'])
    current=next(v for v in by[(r['corpus'],r['id'])] if v['card']==r['coil'])
    assert current['ports']==literal['ports'] and current['bindings']==literal['bindings']
    assert {k:list(v) for k,v in actual[r['coil']]['terminals'].items()}==literal['actual_terminals']
    for name,index in [('n1','1'),('n2','2'),('n3','3')]:
     assert ctx['devices'][r['coil']]['nets'][index].lower()==literal['bindings_by_port'][name]
    connections=[]
    for net,targets in [(r['base'],[actual[q]['terminals']['B'] for q in r['transistors']]+[actual[q]['terminals'][str(pins[q].index(r['base'])+1)] for q in r['resistors']]),(r['collector'],[actual[q]['terminals']['C'] for q in r['transistors']])]+[(net,[actual[q]['terminals']['E'],actual[r['coil']]['terminals']['n'+str(i+1)]]) for i,(q,net) in enumerate(zip(r['transistors'],r['emitters']))]:
     ink,missing=t.verified_segments(ctx['human'],net,ctx['ink']);proof=t.source_connection(ctx,ink,targets);assert proof['continuous'];connections.append(dict(net=net,targets=targets,proof=proof,cache_only_segments=missing))
    checks=[]
    for name,mut in [('extra_base_load',lambda c,p,m,cs:(c.update(rx=['rx']),p.update(rx=[r['base'],'extra']))),('base_aliases_collector',lambda c,p,m,cs:p['q3'].__setitem__(0,r['base'])),('third_same_stage_transistor',lambda c,p,m,cs:(c.update(qextra=c['q3']),p.update(qextra=p['q3'][:]))),('duplicate_ct',lambda c,p,m,cs:cs.append(dict(cs[0],card='xextra'))),('mixed_polarity',lambda c,p,m,cs:(m.update(qpnp='pnp'),c['q4'].__setitem__(5,'qpnp'))),('tap_bias_resistor_detached',lambda c,p,m,cs:p['rb2'].__setitem__(1,'other')),('nonrail_second_bias_end',lambda c,p,m,cs:p['rb1'].__setitem__(0,'other')),('base_hidden_extra_incidence',lambda c,p,m,cs:p['q7'].__setitem__(3,r['base']))]:
     c,p,m,cs=copy.deepcopy((ctx['cards'],pins,models,by[(r['corpus'],r['id'])]));mut(c,p,m,cs);assert not select(c,p,m,cs),name;checks.append(name)
    negative=[]
    for ident,net,pair in NEGATIVES:
     c=t.load_source(examples/'analoggenie',ident);c['human']['wires']=[w for w in c['human']['wires'] if w['net'] is not None];p,m=ir.nodes(c['cards'],(examples/'analoggenie'/(ident+'.cir')).read_text());assert not select(c['cards'],p,m,by[('analoggenie',ident)])
     row=dict(id=ident,net=net,pins=[[q,1] for q in pair],terms=['b' if q[0]=='q' else 'g' for q in pair]);proof=t.source(c,row);assert proof['status']=='source_disconnected',(ident,proof);negative.append(dict(row,name=t.key(row),source=proof))
    names=[v['corpus']+':'+v['id']+':'+('/'.join(v['transistors']))+':'+v['coil']+':'+('/'.join(v['resistors'])) for v in selected]
    same(names,EXPECTED,'exact selected stage names changed')
    statuses=dict(collections.Counter(v['source']['status'] for v in common))
    same(statuses,{'source_connected':55,'source_disconnected':295},'common-first-path-end source cohort changed')
    checks += ['wire_'+v for v in t.method_checks()]
    checks += ['source_'+v for v in t.source_checks()]
    return dict(scope=scope,all_drawn_transistor_bindings_validated=primitive_count,selected=selected,
                selected_names=names,actual_glyphs=actual,connections=connections,negative_controls=negative,
                common_first_path_end=common,method_checks=checks,dependency_sha256=dependencies(),
                summary=dict(selected_figures=len(selected),source_trees=len(connections),negative_paths=len(negative),
                             common_first_pairs=len(common),common_first_source=statuses),
                source_inventory_sha256=t.digest(HERE/'center_tap_symbols_cases.json'),
                limit='Exactly one source figure. Common-collector/drain examples retain both source-connected and separated pairs. No universal CT/common-control or connection-distance claim.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("examples", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    result = audit(args.examples)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    if args.check:
        same(result, json.loads((HERE / "ct_common_controls_cases.json").read_text()), "frozen common-control evidence changed")
    print(json.dumps(result["summary"], sort_keys=True))


if __name__ == "__main__":
    main()
