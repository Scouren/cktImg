#!/usr/bin/env python3
"""Exact rational certificate for a bounded integer source-coil approximation.

Usage: center_tap_curves.py OUTPUT.json [--check]

Checks the frozen source paths, a rational subdivision/rounding certificate,
and the current runtime integer table. This is not a native rendering audit.
The exact bound applies at unit 40 / pitch 20; other pitches add integer
rescaling error. Raster stroke widths and world placement are outside scope.
"""
import argparse
import copy
from fractions import Fraction as F
from pathlib import Path
from math import isqrt
import hashlib,json,re

HERE=Path(__file__).resolve().parent
INVENTORY=HERE/'center_tap_symbols_cases.json'
IMPLEMENTATION=HERE.parents[2]/'src/center_tap.zig'
CASES=HERE/'center_tap_curves_cases.json'
LEFT='0e036faf054f5c1384b8e77d6418a8a76efcb855f0cdf10b55f897893b22b6e0'
RIGHT='a2613494f578a215cefc1c7f9e3f9b9208b3bfb11f82c86c7306456716e08267'
TOL=F(1,10)
CAPACITY=64
EXPECTED='ag-1103:xl1 ag-1114:x1 ag-1131:x1 ag-1146:x1 ag-1147:x1 ag-1149:xlp ag-1151:xl ag-1152:xl1 ag-1152:xl2 ag-1153:xl1 ag-1153:xl2 ag-1168:x1 ag-1168:x2 ag-1180:xle1 ag-1180:xle2 ag-1180:xlo1 ag-1180:xlo2 ag-1187:xtb ag-1190:x1'.split()
EXPECTED_CHECKS='perpendicular_distance capsule_endpoint_distance independent_bernstein_interval_identity collinear_trace_preserved backtracking_is_retained turn_is_retained strict_svg_capacity exact_winding_endpoints rejects_changed_leaf_control rejects_missing_leaf rejects_overlapping_partition rejects_shifted_integer_vertex rejects_removed_turn rejects_wrong_endpoint rejects_capacity_overflow rejects_hidden_backtracking rejects_changed_second_winding rejects_tampered_source_hash rejects_changed_runtime_table'.split()

def add(a,b):return tuple(x+y for x,y in zip(a,b))
def sub(a,b):return tuple(x-y for x,y in zip(a,b))
def mul(a,k):return tuple(x*k for x in a)
def dot(a,b):return sum(x*y for x,y in zip(a,b))
def mix(a,b,t):return add(mul(a,1-t),mul(b,t))
def dist2(p,a,b):
 d=sub(b,a);q=sub(p,a);den=dot(d,d);u=dot(q,d)
 if not den or u<=0:return dot(q,q)
 if u>=den:return dot(sub(p,b),sub(p,b))
 return dot(q,q)-u*u/den

def parse(text):
 ts=re.findall(r'[MLC]|[-+]?(?:\d*\.\d+|\d+)(?:[eE][-+]?\d+)?',text)
 i=0;at=None;out=[]
 while i<len(ts):
  kind=ts[i];i+=1;n=6 if kind=='C' else 2
  values=list(map(F,ts[i:i+n]));i+=n;ps=list(zip(values[::2],values[1::2]))
  if kind!='M':out.append((kind,tuple([at]+ps)))
  at=ps[-1]
 return out

def subdivide(c,lo=F(0),hi=F(1),depth=0):
 assert depth<=20
 flat=max(dist2(p,c[0],c[-1]) for p in c[1:-1])
 if flat<=TOL*TOL:return [(lo,hi,c)]
 a,b,d=mix(c[0],c[1],F(1,2)),mix(c[1],c[2],F(1,2)),mix(c[2],c[3],F(1,2))
 e,f=mix(a,b,F(1,2)),mix(b,d,F(1,2));m=mix(e,f,F(1,2));mid=(lo+hi)/2
 return subdivide((c[0],a,e,m),lo,mid,depth+1)+subdivide((m,f,d,c[3]),mid,hi,depth+1)

def bernstein(c,t):
 u=1-t
 return tuple(u**3*c[0][k]+3*u*u*t*c[1][k]+3*u*t*t*c[2][k]+t**3*c[3][k] for k in range(2))
def derivative(c,t):
 u=1-t
 return tuple(3*(u*u*(c[1][k]-c[0][k])+2*u*t*(c[2][k]-c[1][k])+t*t*(c[3][k]-c[2][k])) for k in range(2))
def interval_controls(c,lo,hi):
 # Independent of recursive De Casteljau generation.
 a,b=bernstein(c,lo),bernstein(c,hi);scale=(hi-lo)/3
 return (a,add(a,mul(derivative(c,lo),scale)),sub(b,mul(derivative(c,hi),scale)),b)

def on(b,a,c):
 v,w=sub(b,a),sub(c,a)
 return v[0]*w[1]-v[1]*w[0]==0 and all(min(x,z)<=y<=max(x,z) for x,y,z in zip(a,b,c))
def simplify(points):
 out=[];removed=[]
 for p in points:
  if out and p==out[-1]:
   removed.append(dict(kind='duplicate',point=p));continue
  while len(out)>=2 and on(out[-1],out[-2],p):
   removed.append(dict(kind='collinear',triple=[out[-2],out[-1],p]));out.pop()
  out.append(p)
 return out,removed

def sqrt_upper(q,places=12):
 scale=10**places;n=isqrt(q.numerator*scale*scale//q.denominator)
 if F(n*n,scale*scale)<q:n+=1
 result=F(n,scale)
 assert result*result>=q and (result-F(1,scale))**2<q
 return result

def encode(v):
 if isinstance(v,F):return str(v)
 if isinstance(v,tuple):return [encode(x) for x in v]
 if isinstance(v,list):return [encode(x) for x in v]
 if isinstance(v,dict):return {k:encode(x) for k,x in v.items()}
 return v

def certify(ops):
 points=[ops[0][1][0]];curves=[];flat_max=F(0)
 for index,(kind,control) in enumerate(ops):
  assert points[-1]==control[0]
  if kind=='L':points.append(control[-1]);continue
  leaves=subdivide(control);end=F(0);records=[]
  for lo,hi,c in leaves:
   assert lo==end and lo<hi and c==interval_controls(control,lo,hi)
   assert points[-1]==c[0]
   flat=max(dist2(p,c[0],c[-1]) for p in c[1:-1]);assert flat<=TOL*TOL
   flat_max=max(flat_max,flat);points.append(c[-1]);end=hi
   records.append(dict(interval=[lo,hi],control=c,control_capsule_distance_squared=flat))
  assert end==1
  curves.append(dict(source_command=index,leaves=records))
 quantized=[tuple(round(v) for v in p) for p in points]
 error2=max(dot(sub(p,q),sub(p,q)) for p,q in zip(points,quantized))
 simplified,removed=simplify(quantized)
 assert len(simplified)<CAPACITY
 assert simplified[0]==(-45,0) and simplified[-1]==(-5,0)
 assert all(-128<=v<=127 for p in simplified for v in p)
 for r in removed:
  if r['kind']=='collinear':assert on(r['triple'][1],r['triple'][0],r['triple'][2])
 # The capsule around a segment is convex, so the curve is inside it.
 # Its projection continuously reaches both endpoints; every chord point
 # therefore has a curve point at its projection within the same bound.
 # Matched linear interpolation of rounded endpoints adds at most the
 # largest endpoint displacement. Removing collinear subdivisions does
 # not alter the polyline point-set. Triangle inequality gives Hausdorff.
 rounding_upper=sqrt_upper(error2)
 bound=TOL+rounding_upper
 return dict(table=simplified,point_count=len(simplified),point_capacity=CAPACITY,
   raw_chord_vertices=len(points),quantized_vertex_count=len(quantized),trace_preserving_removals=removed,
   flatness_limit=TOL,flatness_max_squared=flat_max,rounding_max_squared=error2,
   rounding_upper=rounding_upper,hausdorff_upper_source_units=bound,
   hausdorff_upper_decimal=float(bound),curves=curves,
   quantization=[dict(source=p,integer=q) for p,q in zip(points,quantized)])

def verify_trace(original,table):
 # Independent of the stack simplifier: each retained segment must consume
 # a contiguous monotone collinear run of the original polyline.
 assert original and table and original[0]==table[0]
 index=0
 for a,b in zip(table,table[1:]):
  assert a!=b and original[index]==a
  direction=sub(b,a);previous=F(0)
  while original[index]!=b:
   index+=1;assert index<len(original)
   point=original[index];assert on(point,a,b)
   progress=dot(sub(point,a),direction)
   assert progress>=previous
   previous=progress
 while index+1<len(original) and original[index+1]==table[-1]:index+=1
 assert index==len(original)-1

def verify(ops,proof):
 # Reconstruct every cubic restriction using endpoint values/derivatives,
 # independently of the recursive generator, and validate the whole proof.
 assert [r['source_command'] for r in proof['curves']]==[i for i,(k,_) in enumerate(ops) if k=='C']
 records=iter(proof['curves']);points=[ops[0][1][0]];flat_max=F(0)
 for index,(kind,control) in enumerate(ops):
  assert points[-1]==control[0]
  if kind=='L':points.append(control[-1]);continue
  curve=next(records);assert curve['source_command']==index
  end=F(0)
  for row in curve['leaves']:
   lo,hi=row['interval'];assert lo==end and 0<=lo<hi<=1
   expected=interval_controls(control,lo,hi)
   assert row['control']==expected and points[-1]==expected[0]
   flat=max(dist2(p,expected[0],expected[-1]) for p in expected[1:-1])
   assert flat==row['control_capsule_distance_squared'] and flat<=TOL*TOL
   flat_max=max(flat_max,flat);points.append(expected[-1]);end=hi
  assert end==1
 assert proof['raw_chord_vertices']==proof['quantized_vertex_count']==len(points)
 assert proof['flatness_limit']==TOL and proof['flatness_max_squared']==flat_max
 assert [q['source'] for q in proof['quantization']]==points
 integers=[q['integer'] for q in proof['quantization']]
 assert integers==[tuple(round(v) for v in p) for p in points]
 error2=max(dot(sub(p,q),sub(p,q)) for p,q in zip(points,integers))
 assert error2==proof['rounding_max_squared']
 assert proof['rounding_upper']==sqrt_upper(error2)
 assert proof['hausdorff_upper_source_units']==TOL+proof['rounding_upper']
 assert proof['hausdorff_upper_decimal']==float(proof['hausdorff_upper_source_units'])
 table=proof['table']
 assert proof['point_count']==len(table)<proof['point_capacity']==CAPACITY
 assert table[0]==(-45,0) and table[-1]==(-5,0)
 assert all(type(v)==int and -128<=v<=127 for p in table for v in p)
 verify_trace(integers,table)
 for row in proof['trace_preserving_removals']:
  if row['kind']=='duplicate':assert row['point'] in integers
  else:
   assert row['kind']=='collinear'
   a,b,c=row['triple'];assert on(b,a,c)

def translated(left,right):
 assert len(left)==len(right)
 for (kind,a),(other,b) in zip(left,right):
  assert kind==other and len(a)==len(b)
  assert all(add(p,(F(50),F(0)))==q for p,q in zip(a,b))

def source_path(inventory,key):
 text=inventory['source_paths'][key]['path']
 assert hashlib.sha256(text.encode()).hexdigest()==key
 ops=parse(text)
 assert sum(kind=='C' for kind,_ in ops)==23
 assert sum(kind=='L' for kind,_ in ops)==2
 return ops

def runtime_table(text):
 match=re.search(r'const winding = \[_\]\[2\]i8\{(.*?)\n\};',text,re.S)
 assert match
 return [tuple(map(int,m)) for m in re.findall(r'\.\{\s*(-?\d+)\s*,\s*(-?\d+)\s*\}',match[1])]

def rejected(call):
 try:call()
 except AssertionError:return
 raise AssertionError('mutation unexpectedly accepted')

def checks(ops,proof):
 names=[]
 # Literal exact reference arithmetic and removal semantics.
 assert dist2((F(1),F(2)),(F(0),F(0)),(F(2),F(0)))==4;names.append('perpendicular_distance')
 assert dist2((F(3),F(4)),(F(0),F(0)),(F(1),F(0)))==20;names.append('capsule_endpoint_distance')
 c=((F(0),F(0)),(F(1),F(2)),(F(3),F(-1)),(F(4),F(0)))
 assert interval_controls(c,F(0),F(1))==c
 assert interval_controls(c,F(0),F(1,2))==((F(0),F(0)),(F(1,2),F(1)),(F(5,4),F(3,4)),(F(2),F(3,8)))
 names.append('independent_bernstein_interval_identity')
 assert simplify([(0,0),(1,0),(2,0)])[0]==[(0,0),(2,0)];names.append('collinear_trace_preserved')
 assert simplify([(0,0),(2,0),(1,0)])[0]==[(0,0),(2,0),(1,0)];names.append('backtracking_is_retained')
 assert simplify([(0,0),(1,1),(2,0)])[0]==[(0,0),(1,1),(2,0)];names.append('turn_is_retained')
 assert proof['point_count']<CAPACITY;names.append('strict_svg_capacity')
 assert proof['table'][0]==(-45,0) and proof['table'][-1]==(-5,0);names.append('exact_winding_endpoints')
 for name,mutate in (
  ('rejects_changed_leaf_control',lambda p:p['curves'][0]['leaves'][0].update(control=((F(99),F(0)),)*4)),
  ('rejects_missing_leaf',lambda p:p['curves'][0]['leaves'].pop()),
  ('rejects_overlapping_partition',lambda p:next(c for c in p['curves'] if len(c['leaves'])>1)['leaves'][1].update(interval=[F(0),F(1)])),
  ('rejects_shifted_integer_vertex',lambda p:p['table'].__setitem__(4,(0,99))),
  ('rejects_removed_turn',lambda p:(p['table'].pop(1),p.update(point_count=p['point_count']-1))),
  ('rejects_wrong_endpoint',lambda p:p['table'].__setitem__(0,(-44,0))),
  ('rejects_capacity_overflow',lambda p:(p['table'].extend([p['table'][-1]]*3),p.update(point_count=64))),
 ):
  altered=copy.deepcopy(proof);mutate(altered);rejected(lambda:verify(ops,altered));names.append(name)
 rejected(lambda:verify_trace([(0,0),(2,0),(1,0)],[(0,0),(1,0)]));names.append('rejects_hidden_backtracking')
 right=[(k,tuple(add(p,(F(50),F(0))) for p in c)) for k,c in ops]
 changed=copy.deepcopy(right);changed[0]=('L',(changed[0][1][0],(F(99),F(0))))
 rejected(lambda:translated(ops,changed));names.append('rejects_changed_second_winding')
 rejected(lambda:source_path({'source_paths':{LEFT:{'path':'M -45 0 L -5 0'}}},LEFT));names.append('rejects_tampered_source_hash')
 altered=copy.deepcopy(proof);altered['table']=runtime_table('const winding = [_][2]i8{\n.{ -45, 0 },\n.{ -5, 0 },\n};');altered['point_count']=2
 rejected(lambda:verify(ops,altered));names.append('rejects_changed_runtime_table')
 assert names==EXPECTED_CHECKS
 return names

def main():
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('output',type=Path)
 parser.add_argument('--source-inventory',type=Path,default=INVENTORY)
 parser.add_argument('--implementation',type=Path,default=IMPLEMENTATION)
 parser.add_argument('--check',action='store_true')
 args=parser.parse_args()
 inventory=json.loads(args.source_inventory.read_text());left=source_path(inventory,LEFT);right=source_path(inventory,RIGHT)
 translated(left,right)
 names=sorted(r['id']+':'+r['card'] for r in inventory['selected'])
 assert names==EXPECTED
 for row in inventory['selected']:
  assert [p['path_sha256'] for p in row['primitives'] if p['tag']=='path']==[LEFT,RIGHT]
  circles=[p for p in row['primitives'] if p['tag']=='circle'];assert len(circles)==1
  assert circles[0]['attributes']['fill']=='#000' and circles[0]['attributes']['stroke']=='none'
  assert F(circles[0]['attributes']['r'])==F('3.77907')
 proof=certify(left);verify(left,proof)
 assert runtime_table(args.implementation.read_text())==proof['table']
 result=dict(audit_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
  source_inventory_sha256=hashlib.sha256(args.source_inventory.read_bytes()).hexdigest(),
  source_path_sha256=[LEFT,RIGHT],selected_names=names,source_cubic_commands=23,
  second_winding_translation=[50,0],coils=proof,method_checks=checks(left,proof),
  radius=dict(source='3.77907',integer=4,absolute_error=str(F(4)-F('3.77907'))),
  scaling='At standard unit40, pitch20, one table coordinate equals one source unit. Ideal uniform pitch/20 scaling multiplies the bound; integer rescaling requires an additional rounding certificate. AG1190 outer leads±60 differ from canonical±50; this coil proof concerns only common cubic winding ink.',
  proof='Exact rational cubic subintervals independently verified by Bernstein values/derivatives. Convex segment-capsule flatness bounds Hausdorff both ways by continuity of projection. Quantized corresponding vertices add their maximum displacement; collinear/duplicate removal preserves the polyline trace exactly. Bound applies to both winding point-sets at standard scale, not raster stroke thickness or source world placement.')
 encoded=encode(result)
 if args.check:assert encoded==json.loads(CASES.read_text()),'every frozen curve proof field'
 args.output.write_text(json.dumps(encoded,indent=2,sort_keys=True)+'\n')
 print(json.dumps(dict(points=proof['point_count'],capacity=CAPACITY,bound_source_units=float(proof['hausdorff_upper_source_units']),rounding_upper=float(proof['rounding_upper']),raw_vertices=proof['raw_chord_vertices'],checks=result['method_checks']),indent=2))
if __name__=='__main__':main()
