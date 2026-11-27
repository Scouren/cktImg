#!/usr/bin/env python3
"""Exact reciprocal MOS pair/tail census and actual source straight bars.

Usage: common_source_bars.py EXAMPLES OUTPUT [--check]
Full raw S/S/D incidence precedes actual SVG frame and conductor inspection.
Thirty-one topologies include four horizontal opposed frames in one figure;
this bounded observation is not a universal common-source drawing rule.
"""
from pathlib import Path
import argparse,ast,collections,hashlib,itertools,json,sys
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE));sys.dont_write_bytecode=True
import channel_bridges as channels,input_resistors as inputs,cross_caps,thin_connectivity as ink

def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def topology(cards,pins,models):
 incident=collections.defaultdict(list)
 for d,ps in pins.items():
  for i,n in enumerate(ps):incident[n].append((d,i))
 out=[]
 for n,rows in incident.items():
  if len(rows)!=3 or sorted(i for d,i in rows)!=[0,2,2]:continue
  if len({d for d,i in rows})!=3:continue
  if any(not d.startswith('m') or len(pins[d])!=4 for d,i in rows):continue
  ds=[d for d,i in rows if i==0];pair=sorted(d for d,i in rows if i==2);tail,=ds
  a,b=pair;p,q,t=pins[a],pins[b],pins[tail]
  if p[0]!=q[1] or p[1]!=q[0] or p[3]!=q[3] or t[2:]!=[p[3],p[3]]:continue
  if len({p[0],p[1],n,p[3],t[1]})!=5:continue
  kinds=[models.get(cards[d][5]) for d in pair+[tail]]
  if any(k not in ['nmos','pmos'] for k in kinds) or len(set(kinds))!=1:continue
  if channels.rail(n) or channels.rail(p[3]) not in ['sink','supply']:continue
  out.append(dict(net=n,pair=pair,tail=tail,polarity=kinds[0],raw_incidence=sorted([d,i] for d,i in rows),bindings={d:pins[d] for d in pair+[tail]}))
 return out

def horizontal_interval(segments,y,lo,hi):
 intervals=sorted((min(a[0],b[0]),max(a[0],b[0])) for a,b in segments if a[1]==b[1]==y)
 reach=lo
 for a,b in intervals:
  if a>reach:break
  if b>=reach:reach=b
 return reach>=hi

def source(ctx,raw):
 names=raw['pair']+[raw['tail']];glyphs={}
 for d in names:
  dev=ctx['devices'][d];g=cross_caps.actual_glyph(ctx['root'],dev)
  points=[]
  for i,role in enumerate(['d','g','s']):
   key=ink.terminal(dev,i,role)
   assert dev['nets'][key].lower()==raw['bindings'][d][i]
   points.append(g['terminals'][key])
  assert dev['nets']['B'].lower()==raw['bindings'][d][3]
  glyphs[d]=points
 a,b=[glyphs[d] for d in raw['pair']];t=glyphs[raw['tail']];tips=[a[2],t[0],b[2]]
 collinear=len({p[1] for p in tips})==1
 between=min(a[2][0],b[2][0])<t[0][0]<max(a[2][0],b[2][0])
 vertical=all(g[0][0]==g[2][0] and g[0][1]!=g[2][1] and min(g[0][1],g[2][1])<g[1][1]<max(g[0][1],g[2][1]) for g in [a,b,t])
 sign=lambda v:(v>0)-(v<0)
 opposing=vertical and sign(a[2][1]-a[0][1])==sign(b[2][1]-b[0][1])==-sign(t[0][1]-t[2][1])
 # Unassigned cache wires have no named net; whole SVG ink remains in ctx for negative challenges.
 human={**ctx['human'],'wires':[w for w in ctx['human']['wires'] if isinstance(w.get('net'),str)]}
 segments,missing=ink.verified_segments(human,raw['net'],ctx['ink'])
 keys=[[raw['pair'][0],2],[raw['tail'],0],[raw['pair'][1],2]]
 pairs=[]
 for i,j in itertools.combinations(range(3),2):
  proof=ink.source_connection(ctx,segments,[tips[i],tips[j]])
  pairs.append(dict(pins=[keys[i],keys[j]],tip_indices=[i,j],source=proof))
 eligible=collinear and between and opposing
 straight=eligible and horizontal_interval(segments,tips[0][1],min(p[0] for p in tips),max(p[0] for p in tips))
 return dict(actual_glyphs=glyphs,tips=tips,source_row=collinear,tail_between=between,vertical_opposed_frames=opposing,source_geometry_eligible=eligible,full_horizontal_ink=straight,verified_segments=segments,cache_without_ink=missing,pair_proofs=pairs)

def audit(examples_root):
 rows=[];counts={};hashes={}
 for corpus,folder in [('ag','analoggenie'),('ams','amsnet')]:
  examples=examples_root/folder;files=sorted(examples.glob('*.cir'));counts[corpus]=len(files)
  hashes[corpus]={p.name:digest(p) for p in files}
  for deck in files:
   text=deck.read_text();cards=channels.read_cards(text);pins,models=inputs.nodes(cards,text)
   candidates=topology(cards,pins,models)
   if not candidates:continue
   try:ctx=ink.load_source(examples,deck.stem)
   except (ValueError,AssertionError,KeyError) as e:
    rows += [dict(corpus=corpus,name=deck.stem+':'+raw['net'],topology=raw,unsupported=str(e)) for raw in candidates];continue
   for raw in candidates:
    result=dict(corpus=corpus,name=deck.stem+':'+raw['net'],topology=raw,source_sha256=ctx['source_sha256'])
    try:result['source']=source(ctx,raw)
    except (ValueError,AssertionError,KeyError,TypeError) as e:result['unsupported']=type(e).__name__+':'+str(e)
    rows.append(result)
 out=dict(scope='Raw reciprocal same-polarity MOS common-source/tail triads. Actual source geometry is measured, never assumed from topology. Unsupported source glyphs remain named.',script_sha256=digest(Path(__file__)),corpus_counts=counts,corpus_deck_sha256=hashes,rows=rows)
 out['summary']={corpus:dict(raw_names=[r['name'] for r in rows if r['corpus']==corpus],unsupported=[r['name'] for r in rows if r['corpus']==corpus and 'unsupported'in r],source_eligible=[r['name'] for r in rows if r['corpus']==corpus and r.get('source',{}).get('source_geometry_eligible')],straight_eligible=[r['name'] for r in rows if r['corpus']==corpus and r.get('source',{}).get('full_horizontal_ink')]) for corpus in counts}
 out['methods']=methods()
 out['ink_methods']=ink_methods()
 out['dependencies']=dependencies()
 out['limits']=['Four correlated actual horizontal bars in one figure; no population or universal-layout claim.',
  "Source rail eligibility uses the reader's named-rail contract; the engine uses admitted Role values.",
  'Source-body bindings include all four raw MOS pins; only D/G/S have assigned visible endpoints.',
  'Actual conductor support excludes cached-only strokes; unsupported source glyphs remain named and --check cannot hide them.',
  'No native placement, full-circuit physical partition, or visual-equivalence claim follows from the source census.']
 return json.loads(json.dumps(out))

base='''literal common source
.model nch nmos
.model pch pmos
Mleft out_l out_r common vss nch
Mright out_r out_l common vss nch
Mtail common bias vss vss nch
'''
def select(text):
 wrapped=text.splitlines()[:3]+['.subckt dut']+text.splitlines()[3:]+['.ends dut']
 source='\n'.join(wrapped)+'\n'
 cards=channels.read_cards(source);pins,models=inputs.nodes(cards,source)
 return topology(cards,pins,models),pins
cases={
 'complete_known_nmos':(base,1),
 'complete_known_pmos':(base.replace('vss','vdd').replace('nch\n','pch\n'),1),
 'card_permutation':('\n'.join(base.splitlines()[:3]+list(reversed(base.splitlines()[3:])))+'\n',1),
 'net_and_device_rename':(base.replace('Mleft','Mrenamed').replace('common','private_middle').replace('out_l','first'),1),
 'unknown_model':(base.replace('vss nch','vss unknown'),0),
 'mixed_tail_polarity':(base.replace('Mtail common bias vss vss nch','Mtail common bias vss vss pch'),0),
 'mixed_pair_polarity':(base.replace('Mright out_r out_l common vss nch','Mright out_r out_l common vss pch'),0),
 'nonreciprocal_gate':(base.replace('Mleft out_l out_r','Mleft out_l unrelated'),0),
 'extra_resistor_incidence':(base+'Rextra common vss 1k\n',0),
 'extra_hidden_body_incidence':(base+'Mextra x y z common nch\n',0),
 'pair_body_alias':(base.replace('Mleft out_l out_r common vss','Mleft out_l out_r common common'),0),
 'tail_gate_alias':(base.replace('Mtail common bias','Mtail common out_l'),0),
 'tail_source_not_shared_rail':(base.replace('Mtail common bias vss vss','Mtail common bias remote vss'),0),
 'tail_body_not_shared_rail':(base.replace('Mtail common bias vss vss','Mtail common bias vss vdd'),0),
 'one_pair_body_different':(base.replace('Mright out_r out_l common vss','Mright out_r out_l common vdd'),0),
 'missing_tail':(base.replace('Mtail common bias vss vss nch\n',''),0),
 'common_is_rail':(base.replace('common','gnd'),0),
 'body_not_named_rail':(base.replace('vss','internal'),0),
 'extra_competing_source':(base+'Mextra x y common vss nch\n',0),
 'unrelated_device_allowed':(base+'Rextra x y 1k\n',1),
}

def methods():
 results={}
 for name,(text,expected) in cases.items():
  found,pins=select(text)
  assert len(found)==expected,(name,expected,found)
  assert len(pins)>=2,(name,'literal cards lost')
  results[name]={'expected_candidates':expected,'actual':found,'input_sha256':hashlib.sha256(text.encode()).hexdigest()}
 return results

def ink_methods():
 checks={
  'full_split_bar':([((0,0),(5,0)),((5,0),(10,0))],True),
  'one_unit_open_gap':([((0,0),(5,0)),((6,0),(10,0))],False),
  'one_unit_gap_with_detour':([((0,0),(5,0)),((5,0),(5,1)),((5,1),(6,1)),((6,1),(6,0)),((6,0),(10,0))],False),
  'overlapping_bar':([((0,0),(7,0)),((5,0),(10,0))],True),
  'offset_row':([((0,1),(10,1))],False),
 }
 for name,(segments,want) in checks.items():
  assert horizontal_interval(segments,0,0,10)==want,name
  assert horizontal_interval([(b,a) for a,b in reversed(segments)],0,0,10)==want,name
 return {name:dict(segments=segments,straight=want) for name,(segments,want) in checks.items()}

def dependencies():
 found,pending={},[Path(__file__).name]
 while pending:
  name=pending.pop()
  if name in found:continue
  path=HERE/name;found[name]=digest(path)
  for node in ast.walk(ast.parse(path.read_text())):
   modules=[v.name for v in node.names] if isinstance(node,ast.Import) else [node.module] if isinstance(node,ast.ImportFrom) else []
   for module in modules:
    local=(module or '').split('.')[0]+'.py'
    if (HERE/local).is_file():pending.append(local)
 return dict(sorted(found.items()))

def main():
 ap=argparse.ArgumentParser(description=__doc__)
 ap.add_argument('examples',type=Path);ap.add_argument('output',type=Path);ap.add_argument('--check',action='store_true');args=ap.parse_args()
 result=audit(args.examples)
 args.output.write_text(json.dumps(result,sort_keys=True,indent=2)+'\n')
 if args.check and result!=json.loads((HERE/'common_source_bars_cases.json').read_text()):raise ValueError('frozen common-source census differs')
 print(json.dumps({c:{k:len(v) for k,v in s.items()} for c,s in result['summary'].items()},sort_keys=True))
if __name__=='__main__':main()
