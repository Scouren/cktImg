#!/usr/bin/env python3
"""Three source resistor-loaded differential stages: topology and actual ink.

Usage: resistor_load_stages.py EXAMPLES OUTPUT [--check]

Topology selects first; exact names are a census oracle, never a selector.
All glyph envelopes are nominal geometry, not stroke or typography bounds.
This study proposes no general rail-routing or absolute-distance policy.
"""
from pathlib import Path
import argparse,ast,collections,copy,itertools,json,math,re,sys
sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
import thin_connectivity as ink
import input_resistors as resistors
import channel_bridges as channels
import block_aliases as aliases
import controller_glyphs as glyph
EXPECTED=['ag-1048:m19','ag-1052:m12','ag-1052:m8']

def select(cards,pins,models):
 inc=collections.defaultdict(list)
 for n,ps in pins.items():
  for i,p in enumerate(ps):inc[p].append((n,i))
 result=[]
 def model(n):return models.get(cards[n][len(pins[n])+1])
 for load,p in pins.items():
  if load[0]!='m' or len(p)!=4 or model(load)!='pmos' or p[0]!=p[1] or p[2]!=p[3] or channels.rail(p[2])!='supply' or channels.rail(p[0]):continue
  raw=[q for q,i in inc[p[0]] if q!=load]
  if len(inc[p[0]])!=4 or len(raw)!=2 or len(set(raw))!=2 or any(q[0]!='r' or len(pins[q])!=2 or pins[q][0]==pins[q][1] for q in raw):continue
  rs=sorted(raw); ends=[next(x for x in pins[r] if x!=p[0]) for r in rs]
  if len(set(ends))!=2 or any(channels.rail(x) for x in ends):continue
  ds=[]
  for end in ends:
   choices=[q for q,ps in pins.items() if q[0] in 'mq' and len(ps)>=3 and ps[0]==end]
   if len(choices)!=1:break
   q=choices[0];ps=pins[q]
   if q[0]!='m' or len(ps)!=4 or model(q)!='nmos' or len(set(ps[:3]))!=3 or channels.rail(ps[3])!='sink':break
   ds.append(q)
  if len(ds)!=2 or ds[0]==ds[1]:continue
  a,b=[pins[d] for d in ds]
  if a[2]!=b[2] or a[3]!=b[3] or a[1]==b[1] or channels.rail(a[2]):continue
  tail=[q for q,i in inc[a[2]] if q not in ds]
  if len(inc[a[2]])!=3 or len(tail)!=1:continue
  t=tail[0];ts=pins[t]
  if t[0]!='m' or len(ts)!=4 or model(t)!='nmos' or ts[0]!=a[2] or ts[2]!=a[3] or ts[3]!=a[3] or len(set(ts[:3]))!=3:continue
  members=[load,*rs,*ds,t]
  if len(set(members))!=6:continue
  result.append(dict(load=load,resistors=rs,drivers=ds,tail=t,load_net=p[0],outputs=ends,tail_net=a[2],supply=p[2],ground=a[3],members=members,binding={n:pins[n] for n in members},complete_incidence={n:inc[n] for n in [p[0],*ends,a[2]]}))
 return result

def frame(row,actual):
 load=actual[row['load']]['terminals'];tail=actual[row['tail']]['terminals']
 drivers=[actual[d]['terminals'] for d in row['drivers']]
 order=sorted(range(2),key=lambda i:drivers[i]['D'][0]);ds=[drivers[i] for i in order]
 rr=[]
 for i in order:
  n=row['resistors'][i];g=actual[n]['terminals'];terms=list(g)
  rr.append([g[terms[row['binding'][n].index(net)]] for net in (row['load_net'],row['outputs'][i])])
 return dict(load_supply_above=load['S'][0]==load['D'][0] and load['S'][1]<load['G'][1]<load['D'][1],
  resistors_vertical_down=all(a[0]==b[0] and a[1]<b[1] for a,b in rr),
  resistor_rows_equal=rr[0][0][1]==rr[1][0][1] and rr[0][1][1]==rr[1][1][1],
  drivers_vertical_down=all(d['D'][0]==d['S'][0] and d['D'][1]<d['G'][1]<d['S'][1] for d in ds),
  driver_rows_equal=all(ds[0][p][1]==ds[1][p][1] for p in ('D','G','S')),
  drivers_gates_outward=ds[0]['G'][0]<ds[0]['D'][0]<ds[1]['D'][0]<ds[1]['G'][0],
  resistor_output_columns=all(r[1][0]==d['D'][0] for r,d in zip(rr,ds)),
  load_between_columns=ds[0]['D'][0]<load['D'][0]<ds[1]['D'][0],
  load_not_below_resistors=load['D'][1]<=min(r[0][1] for r in rr),
  resistors_above_drivers=all(r[1][1]<d['D'][1] for r,d in zip(rr,ds)),
  tail_vertical_down=tail['D'][0]==tail['S'][0] and tail['D'][1]<tail['G'][1]<tail['S'][1],
  tail_below_drivers=tail['D'][1]>max(d['S'][1] for d in ds),
  tail_between_columns=ds[0]['S'][0]<tail['D'][0]<ds[1]['S'][0])

def envelope(ctx,name):
 d,g,parent=aliases.source_group(ctx['human'],ctx['root'],name);points=[];primitives=[]
 for node,t,_ in glyph.walk(g,parent):
  tag=node.tag.rsplit('}',1)[-1];ps=[]
  if tag=='g':continue
  if tag=='line':ps=[glyph.point(t,[float(node.get(x)),float(node.get(y))]) for x,y in [('x1','y1'),('x2','y2')]]
  elif tag in ('polyline','polygon'):
   v=glyph.numbers(node.get('points',''));assert len(v)>=4 and len(v)%2==0;ps=[glyph.point(t,q) for q in zip(v[::2],v[1::2])]
  elif tag=='path':
   text=node.get('d','');assert not re.sub(r'[MLZmlz]|[-+0-9.eE,\s]','',text);tokens=re.findall(r'[A-Za-z]|[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?',text);i=0
   while i<len(tokens):
    command=tokens[i];i+=1
    if command=='Z':continue
    assert command in ('M','L') and i+1<len(tokens);ps.append(glyph.point(t,[float(tokens[i]),float(tokens[i+1])]));i+=2
  elif tag=='circle':
   c=glyph.point(t,[float(node.get('cx','0')),float(node.get('cy','0'))]);r=float(node.get('r'));assert r>0
   dx=r*math.hypot(t[0],t[2]);dy=r*math.hypot(t[1],t[3]);ps=[(c[0]-dx,c[1]-dy),(c[0]+dx,c[1]+dy)]
  else:raise ValueError((name,'unsupported primitive',tag))
  points.extend(ps);primitives.append(dict(tag=tag,points=ps))
 assert points
 return dict(object=g.get('data-object-id'),bounds=[min(p[0] for p in points),min(p[1] for p in points),max(p[0] for p in points),max(p[1] for p in points)],primitives=primitives)

def overlaps(a,b):return max(a[0],b[0])<min(a[2],b[2])-1e-6 and max(a[1],b[1])<min(a[3],b[3])-1e-6

def straight(segments,a,b):
 if a==b:return False
 if a[0]==b[0]:axis=1
 elif a[1]==b[1]:axis=0
 else:return False
 lo,hi=sorted([a[axis],b[axis]]);cursor=lo
 intervals=sorted(sorted([c[axis],d[axis]]) for c,d in segments if c[1-axis]==d[1-axis]==a[1-axis])
 for x,y in intervals:
  if y<cursor:continue
  if x>cursor+1e-6:break
  cursor=max(cursor,y)
 return cursor>=hi-1e-6

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
 return dict(sorted(found.items()))


def actual_scene(ctx,pins,text):
 definitions={}
 for line in text.lower().splitlines():
  words=line.split()
  if words and words[0]=='.subckt':
   definitions[words[1]]=[]
   for word in words[2:]:
    if word=='params:' or '=' in word:break
    definitions[words[1]].append(word)
 actual={};missing=[];bindings={}
 for name,device in ctx['devices'].items():
  g=resistors.actual(ctx['root'],device)
  declared=(['D','G','S','B'] if name[0]=='m' else definitions[ctx['cards'][name][len(pins[name])+1]] if name[0]=='x' else [ink.terminal(device,i,('a','b')[i]) for i in range(len(pins[name]))])
  verified={}
  for i,term in enumerate(declared):
   matches=[n for n in g['terminals'] if n.lower()==term.lower()]
   if not matches:
    missing.append(dict(device=name,index=i,terminal=term,net=pins[name][i]));continue
   assert len(matches)==1
   source_term=matches[0]
   assert device['nets'][source_term].lower()==pins[name][i],(name,source_term,'binding')
   verified[source_term]=g['terminals'][source_term]
   bindings[name,source_term]=(i,pins[name][i])
  actual[name]=dict(g,terminals=verified)
 return actual,bindings,missing


def tree(ctx,net,targets):
 segments,missing=ink.verified_segments(ctx['human'],net,ctx['ink'])
 proof=ink.source_connection(ctx,segments,[t['point'] for t in targets])
 whole=None if proof['continuous'] else ink.source_connection(ctx,ctx['ink'],[t['point'] for t in targets])
 if whole is not None:assert not whole['continuous'],(net,'cache misses physical path')
 return dict(net=net,terminals=targets,proof=proof,whole_ink=whole,cache_only=missing)


def local_evidence(ctx,row,actual,bindings,envelopes):
 boxes=[envelopes[n]['bounds'] for n in row['members']]
 box=[min(b[0] for b in boxes),min(b[1] for b in boxes),max(b[2] for b in boxes),max(b[3] for b in boxes)]
 foreign=[n for n,g in envelopes.items() if n not in row['members'] and overlaps(g['bounds'],box)]
 trees=[];full=[]
 for net in [row['load_net'],*row['outputs'],row['tail_net']]:
  targets=[dict(device=n,index=bindings[n,t][0],term=t,point=p) for n,g in actual.items() for t,p in g['terminals'].items() if bindings[n,t][1]==net]
  full.append(tree(ctx,net,targets));trees.append(tree(ctx,net,[t for t in targets if t['device'] in row['members']]))
  assert trees[-1]['proof']['continuous']
 corridors=[];nearest=[]
 rs=row['resistors'];ds=row['drivers']
 named=[(row['load_net'],rs,[next(t for t in actual[n]['terminals'] if bindings[n,t][1]==row['load_net']) for n in rs])]
 for i,(r,d) in enumerate(zip(rs,ds)):
  named.append((row['outputs'][i],[r,d],[next(t for t in actual[r]['terminals'] if bindings[r,t][1]==row['outputs'][i]),'D']))
 for net,names,terms in named:
  targets=[dict(device=n,index=bindings[n,t][0],term=t,point=actual[n]['terminals'][t]) for n,t in zip(names,terms)]
  proof=tree(ctx,net,targets);segments,_=ink.verified_segments(ctx['human'],net,ctx['ink'])
  assert straight(segments,*[t['point'] for t in targets]),(row['id'],names,terms)
  corridors.append(proof)
  if net in row['outputs']:
   origin=targets[0];others=next(t['terminals'] for t in full if t['net']==net)
   distances=[dict(target=t,distance_l1=sum(abs(a-b) for a,b in zip(origin['point'],t['point'])),connection=tree(ctx,net,[origin,t])) for t in others if t!=origin]
   distances.sort(key=lambda d:(d['distance_l1'],d['target']['device'],d['target']['index']))
   assert distances[0]['target']==targets[1] and (len(distances)==1 or distances[0]['distance_l1']<distances[1]['distance_l1'])
   nearest.append(dict(origin=origin,candidates=distances))
 return dict(actual={n:actual[n] for n in row['members']},geometry=frame(row,actual),occupied_envelope=box,foreign_overlaps=foreign,local_trees=trees,full_trees=full,straight_corridors=corridors,nearest_output_terminals=nearest)


def partitions(ctx,actual,bindings):
 result={}
 for net in sorted(set(n for i,n in bindings.values())):
  targets=[dict(device=d,index=bindings[d,t][0],terminal=t,point=p) for d,g in actual.items() for t,p in g['terminals'].items() if bindings[d,t][1]==net]
  parent=list(range(len(targets)))
  def find(x):
   while parent[x]!=x:x=parent[x]
   return x
  evidence=[]
  for a,b in itertools.combinations(range(len(targets)),2):
   proof=tree(ctx,net,[targets[a],targets[b]])
   if proof['proof']['continuous']:parent[find(a)]=find(b)
   evidence.append(dict(indices=[a,b],proof=proof))
  groups=collections.defaultdict(list)
  for i,t in enumerate(targets):groups[find(i)].append([t['device'],t['index']])
  result[net]=dict(targets=targets,components=sorted(groups.values()),pairs=evidence)
 return result


def linked_stages(rows,scenes):
 result=[]
 for upstream,downstream in itertools.permutations(rows,2):
  if upstream['id']!=downstream['id']:continue
  bias=upstream['binding'][upstream['tail']][1]
  if downstream['binding'][downstream['tail']][1]!=bias:continue
  gates=[downstream['binding'][n][1] for n in downstream['drivers']]
  if set(upstream['outputs'])!=set(gates):continue
  a=upstream['actual'][upstream['tail']]['terminals'];b=downstream['actual'][downstream['tail']]['terminals']
  rows_equal=all(a[p][1]==b[p][1] for p in ('D','G','S'))
  gates_left=a['G'][0]<a['D'][0] and b['G'][0]<b['D'][0]
  axes=[sum(r['actual'][n]['terminals']['D'][0] for n in r['drivers'])/2 for r in (upstream,downstream)]
  boxes=[r['occupied_envelope'] for r in (upstream,downstream)]
  box=[min(b[0] for b in boxes),min(b[1] for b in boxes),max(b[2] for b in boxes),max(b[3] for b in boxes)]
  members=upstream['members']+downstream['members'];scene=scenes[upstream['id']]
  foreign=[n for n,e in scene['envelopes'].items() if n not in members and overlaps(e['bounds'],box)]
  bias_parts=scene['physical_partitions'][bias]
  assert rows_equal and gates_left and axes[0]<axes[1] and not foreign
  assert sorted(bias_parts['components'])==sorted([[[upstream['tail'],1]],[[downstream['tail'],1]]])
  result.append(dict(id=upstream['id'],upstream=upstream['load'],downstream=downstream['load'],members=members,bias=bias,tail_rows_equal=rows_equal,tail_gates_left=gates_left,local_axes=axes,occupied_envelope=box,foreign_overlaps=foreign,bias_source_components=bias_parts['components']))
 assert [(r['id'],r['upstream'],r['downstream']) for r in result]==[('ag-1052','m8','m12')]
 return result


def checks(row,ctx,pins,models):
 names=[]
 def has(c,p,m):return any(r['load']==row['load'] for r in select(c,p,m))
 changes=[
  ('extra_load_incidence',lambda c,p,m:(c.update(rextra=['rextra']),p.update(rextra=[row['load_net'],'remote']))),
  ('extra_tail_incidence',lambda c,p,m:(c.update(rextra=['rextra']),p.update(rextra=[row['tail_net'],'remote']))),
  ('unknown_competing_driver',lambda c,p,m:(c.update(mextra=['mextra',row['outputs'][0],'g','s','vss','unknown']),p.update(mextra=[row['outputs'][0],'g','s','vss']))),
  ('unknown_load_model',lambda c,p,m:c[row['load']].__setitem__(5,'unknown')),
  ('unshared_input_sources',lambda c,p,m:p[row['drivers'][0]].__setitem__(2,'other')),
  ('wrong_input_body',lambda c,p,m:p[row['drivers'][0]].__setitem__(3,'other')),
  ('wrong_load_supply',lambda c,p,m:p[row['load']].__setitem__(2,'other')),
  ('unknown_tail_model',lambda c,p,m:c[row['tail']].__setitem__(5,'unknown')),
  ('diode_input',lambda c,p,m:p[row['drivers'][0]].__setitem__(1,row['outputs'][0])),
 ]
 for name,mut in changes:
  c,p,m=copy.deepcopy((ctx['cards'],pins,models));mut(c,p,m);assert not has(c,p,m),name;names.append(name)
 assert has(dict(reversed(list(ctx['cards'].items()))),dict(reversed(list(pins.items()))),models);names.append('card_permutation')
 p=copy.deepcopy(pins)
 for resistor in row['resistors']:p[resistor].reverse()
 selected=next(r for r in select(ctx['cards'],p,models) if r['load']==row['load']);assert selected['outputs']==row['outputs'];names.append('resistor_end_reversal')
 for name,device,term,point in [('resistor_column',row['resistors'][0],'1',[400,40]),('inward_input',row['drivers'][0],'G',[280,140]),('load_outside',row['load'],'D',[400,20]),('tail_above',row['tail'],'D',[260,100])]:
  actual=copy.deepcopy(row['actual']);actual[device]['terminals'][term]=point
  assert not all(frame(row,actual).values()),name;names.append(name)
 good=[[[0,0],[10,0]],[[10,0],[20,0]]]
 assert straight(good,[0,0],[20,0]) and straight(list(reversed(good)),[20,0],[0,0]);names.append('straight_interval_reverse')
 assert not straight([[[0,0],[9,0]],[[11,0],[20,0]]],[0,0],[20,0]);names.append('straight_gap')
 assert not straight([[[0,0],[10,0]],[[10,1],[20,1]]],[0,0],[20,0]);names.append('off_row_interval')
 assert overlaps([0,0,20,20],[19,0,30,20]) and not overlaps([0,0,20,20],[20,0,30,20]);names.append('nominal_envelope_contact')
 box=row['occupied_envelope'];cx=(box[0]+box[2])/2;cy=(box[1]+box[3])/2
 assert overlaps(box,[cx-1,cy-1,cx+1,cy+1]);names.append('foreign_glyph_inside_group_envelope')
 bent=[[[0,0],[0,10]],[[0,10],[20,10]],[[20,10],[20,0]]]
 assert ink.source_connection({'junctions':[]},bent,[[0,0],[20,0]])['continuous'] and not straight(bent,[0,0],[20,0]);names.append('connected_tail_need_not_be_straight')
 crossing=[[[0,0],[20,0]],[[10,-10],[10,10]]];targets=[[0,0],[10,10]]
 assert not ink.source_connection({'junctions':[]},crossing,targets)['continuous']
 assert ink.source_connection({'junctions':[{'xy':[10,0],'object':'literal-dot'}]},crossing,targets)['continuous'];names.append('proper_crossing_needs_actual_junction_dot')
 return names


def audit(examples):
 scope={};rows=[];scenes={}
 for corpus in ('analoggenie','amsnet'):
  paths=sorted((examples/corpus).glob('*.human.json'));assert paths
  scope[corpus]=dict(names=[p.stem.removesuffix('.human') for p in paths],source_sha256={},index_sha256=ink.digest(examples/corpus/'index.json'))
  for path in paths:
   ident=path.stem.removesuffix('.human');deck=path.with_name(ident+'.cir');text=deck.read_text();cards=ink.read_cards(text);pins,models=resistors.nodes(cards,text)
   scope[corpus]['source_sha256'][ident]={s:ink.digest(path.with_name(ident+s)) for s in ('.cir','.human.json','.svg')}
   for row in select(cards,pins,models):
    ctx=ink.load_source(path.parent,ident);actual,bindings,missing=actual_scene(ctx,pins,text)
    envelopes={n:envelope(ctx,n) for n in ctx['devices']}
    row.update(id=ident,corpus=corpus,source_sha256=ctx['source_sha256'])
    row.update(local_evidence(ctx,row,actual,bindings,envelopes))
    assert all(row['geometry'].values()) and not row['foreign_overlaps'],ident
    rows.append(row)
    if ident not in scenes:scenes[ident]=dict(source_sha256=ctx['source_sha256'],envelopes=envelopes,unknown_source_terminals=missing,physical_partitions=partitions(ctx,actual,bindings))
 assert [r['id']+':'+r['load'] for r in rows]==EXPECTED
 row=rows[0];ctx=ink.load_source(examples/row['corpus'],row['id']);pins,models=resistors.nodes(ctx['cards'],(examples/row['corpus']/(row['id']+'.cir')).read_text())
 methods=checks(row,ctx,pins,models)
 return dict(scope=scope,rows=rows,scenes=scenes,linked_stages=linked_stages(rows,scenes),methods=methods,dependency_sha256=dependencies(),summary=dict(corpus_drawings=sum(len(s['names']) for s in scope.values()),stages=len(rows),circuits=len(scenes),names=EXPECTED,source_relations={k:sum(r['geometry'][k] for r in rows) for k in rows[0]['geometry']},clear_nominal_envelopes=sum(not r['foreign_overlaps'] for r in rows),straight_corridors=sum(len(r['straight_corridors']) for r in rows),local_trees=sum(len(r['local_trees']) for r in rows),disconnected_full_output_trees=[r['id']+':'+t['net'] for r in rows for t in r['full_trees'] if not t['proof']['continuous']]),limits=['Three correlated stages in two figures; no broad load, rail, absolute-gap or world-placement rule.','Envelopes are nominal geometric primitives, not stroked pixel bounds or text extents.','VDD and VOP/VON source-separated pieces remain separate physical evidence; local stage continuity cannot join them by inference.','Declared terminals without visible source leads, including MOS bodies and inverter VDD/VSS, retain named unknown entries; no positions are invented.'])


def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('examples',type=Path);parser.add_argument('output',type=Path);parser.add_argument('--check',action='store_true');args=parser.parse_args()
 result=audit(args.examples);inventory=HERE/'resistor_load_stages_cases.json'
 if args.check:
  if json.loads(json.dumps(result))!=json.loads(inventory.read_text()):raise ValueError('source evidence changed')
 args.output.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n');print(json.dumps(result['summary'],indent=2))

if __name__=='__main__':main()
