#!/usr/bin/env python3
"""Replay four source-continuity interactions with the initial17 part budget.

Existing16/pre17 diagnostic copies only; no builds. Every geometry and report
must exactly match its frozen corpus. Named terminal contracts bind native
pin indices to deck nodes, cached terminals and actual transformed SVG leads.
Missing cache ink cannot connect terminals. Exact original source-separated
pairs are negative evidence, not a request to reconnect the whole named net.
"""
import argparse,hashlib,json,subprocess
from pathlib import Path
import xml.etree.ElementTree as ET
from channel_bridges import read_cards
from converter_loops import wire_tree
from cross_caps import conductor_ink
from input_resistors import actual
from input_resistor_legs import verified_segments,connection
from thin_trace_run import parse
from thin_parts import crossings,piece
from trunk_rungs import pins,segments

CASES = {
 'ag-1170': ('q-', [('m4.0','m8.0')]),
 'ag-2486': ('vx', [('m16.0','m17.0'),('m16.0','m18.0'),('m16.0','m18.1'),('m16.0','m22.1'),('m17.0','m18.0'),('m17.0','m18.1'),('m17.0','m22.1'),('m18.0','m18.1'),('m18.0','m22.1')]),
 'ag-2571': ('vout', [('c2.1','m1.0'),('c2.1','m2.2'),('c2.1','r2.0')]),
 'ag-989': ('net4', [('cc.1','m11.0'),('cc.1','m4.0'),('cc.1','m6.1'),('m11.0','m4.0'),('m11.0','m6.1'),('m4.0','m6.1')]),
}
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def key(text):
 name,index=text.rsplit('.',1)
 return name,int(index)

def source(examples,ident,net,pair,before,after):
 paths=[examples/(ident+s) for s in ('.cir','.human.json','.svg')]
 cards=read_cards(paths[0].read_text());human=json.loads(paths[1].read_text());root=ET.parse(paths[2]).getroot()
 devices={d['card']:d for d in human['devices']};glyphs={};targets=[]
 for text in pair:
  name,index=key(text);term=('D','G','S')[index] if name[0]=='m' else ('1','2')[index]
  assert cards[name][1+index]==net and devices[name]['nets'][term].lower()==net,(ident,text)
  expected=term.lower() if name[0]=='m' else ('a','b')[index]
  for drawing in (before,after):
   p=pins(drawing)[name,index];assert p[0]==net and p[2].lower()==expected,(ident,text,p)
  glyphs[name]=actual(root,devices[name]);targets.append(glyphs[name]['terminals'][term])
 ink=conductor_ink(root);verified,missing=verified_segments(human,net,ink)
 proof=connection(verified,targets)
 if not proof['continuous']:assert wire_tree(ink,targets) is None,(ident,pair,'unassigned ink connects negative')
 native={label:connection(segments(d,net),[list(pins(d)[key(t)][1]) for t in pair]) for label,d in [('baseline',before),('candidate',after)]}
 assert native['baseline']['continuous'] and not native['candidate']['continuous'],(ident,pair)
 return dict(name=ident+':'+net+':'+','.join(pair),pins=[key(t) for t in pair],source_sha256={p.name:sha(p) for p in paths},source_glyphs=glyphs,source_connection=proof,verified_ink=verified,cache_only_ink=missing,native=native,native_labels={label:[x for x in d['labels'] if x['net']==net] for label,d in [('baseline',before),('candidate',after)]})

def parse_trace(raw):
 extra={};current=None;ordinary=[]
 for line in raw.splitlines():
  w=line.split()
  if w[:2]==['TRACE','round_begin']:current=int(w[2])
  if len(w)>1 and w[0]=='TRACE' and (w[1] in ('peak','component') or w[1].startswith('trunk_')):
   if current is not None:extra.setdefault(current,[]).append(w[1:])
  else:ordinary.append(line)
 rounds=parse('\n'.join(ordinary))
 for r in rounds:
  assert crossings(r)==sorted((tuple(sorted(c['nets'])),tuple(c['at'])) for c in r['crossings'])
  r['extra']=extra.get(r['round'],[])
 return rounds

def part_counts(r,name,removed=()):
 n=next(n for n,d in r['nets'].items() if d['name']==name)
 ss=[[s['a'],s['b']] for s in r['segments'] if s['net']==n];seen=set();counts=[]
 for i,s in enumerate(ss):
  if i in seen:continue
  group=piece(ss,s[0]);seen.update(group);ink=[ss[j] for j in group]
  counts.append(sum(bool(piece(ink,c['at'])) for c in r['crossings'] if n in c['nets'] and not set(c['names'])&set(removed)))
 return sorted(counts)

def audit(root,diagnostic16,diagnostic17,corpus16,corpus17,work):
 work.mkdir(parents=True,exist_ok=True);cases=[];sources=[];provenance={};cross_checks=[]
 for ident,(net,pairs) in CASES.items():
  originals=[json.loads((d/(ident+'.json')).read_text()) for d in (corpus16,corpus17)]
  sources.extend(source(root/'external/examples/analoggenie',ident,net,pair,*originals) for pair in pairs)
  for version,copy,corpus in [('16',diagnostic16,corpus16),('pre17',diagnostic17,corpus17)]:
   manifest=json.loads((copy/'manifest.json').read_text());binary=copy/'out/bin/cktimg-json-trace'
   for rel,want in manifest['instrumented_sha256'].items():assert sha(copy/rel)==want,rel
   provenance[version]={k:manifest[k] for k in ('source_sha256','instrumented_sha256')}
   provenance[version].update(diagnostic_binary_sha256=sha(binary),shipping_binary_sha256=sha(corpus/'cktimg-json'))
   out=work/(ident+'-'+version);out.mkdir(exist_ok=True)
   p=subprocess.run([str(binary),'--report',str(out/'trace.report.json'),str(root/'external/examples/analoggenie'/(ident+'.cir')),str(out/'trace.json')],capture_output=True,text=True,timeout=90)
   (out/'trace.log').write_text(p.stderr);assert p.returncode==0,(ident,version,p.stderr[-2000:])
   for suffix in ('.json','.report.json'):assert (out/('trace'+suffix)).read_bytes()==(corpus/(ident+suffix)).read_bytes(),(ident,version,suffix)
   rounds=parse_trace(p.stderr)
   for r in rounds:
    cross_checks.append(ident+':'+version+':round='+str(r['round']))
    n=next(n for n,d in r['nets'].items() if d['name']==net);r['targets']=[]
    for pair in pairs:
     targets=[next(p['at'] for p in r['pins'] if (p['device'],p['index'])==key(t)) for t in pair]
     r['targets'].append(dict(pins=pair,style=r['nets'][n]['style'],connection=connection([[s['a'],s['b']] for s in r['segments'] if s['net']==n],targets)))
   cases.append(dict(id=ident,version=version,geometry_sha256=sha(out/'trace.json'),report_sha256=sha(out/'trace.report.json'),trace_sha256=sha(out/'trace.log'),rounds=rounds))
   print(ident,version,'exact geometry/report identity',flush=True)
 return dict(provenance=provenance,named_crossing_checks=cross_checks,sources=sources,cases=cases)

def checks(result):
 passed=[];cases={(r['id'],r['version']):r['rounds'] for r in result['cases']}
 assert list(cases)==[(n,v) for n in CASES for v in ('16','pre17')];passed.append('exact_eight_named_states')
 changes=lambda r:[(c['name'],c['before'],c['after'],c['count']) for c in r['changes']]
 continuous=lambda rs:[[t['connection']['continuous'] for t in r['targets']] for r in rs]
 for ident in CASES:
  a,b=[cases[ident,v] for v in ('16','pre17')]
  assert a[0]['segments']==b[0]['segments'] and a[0]['pins']==b[0]['pins'];passed.append(ident+'_identical_initial_ink_and_pins')
  assert all(continuous(a)[-1]) and not any(continuous(b)[-1]);passed.append(ident+'_exact_final_source_pair_loss')
 a,b=[cases['ag-989',v] for v in ('16','pre17')]
 assert part_counts(a[0],'net0')==[1,2] and part_counts(a[0],'net4')==[0,3]
 assert changes(a[0])==[('net0','cut','label',3)] and changes(b[0])==[('net4','cut','label',3)]
 passed.append('ag989_competing_connected_part_loses_greedy_choice')
 a,b=[cases['ag-2486',v] for v in ('16','pre17')]
 assert part_counts(a[0],'net2')==[0,2,2] and part_counts(a[0],'vx')==[4]
 assert changes(a[0])==[('net2','cut','label',4)] and changes(b[0])==[('vx','auto','cut',4)] and 'vx' in b[1]['part_all_label']
 passed.append('ag2486_retained_parts_shift_auto_cut_then_whole_part_labels')
 a,b=[cases['ag-2571',v] for v in ('16','pre17')]
 assert part_counts(a[0],'n3')==[1,2] and changes(a[0])==[('n3','cut','label',3)] and changes(b[0])==[] and len(b)==1
 assert not any(continuous(a)[0]) and all(continuous(a)[1]);passed.append('ag2571_no_style_change_stops_before_output_recovers')
 a,b=[cases['ag-1170',v] for v in ('16','pre17')]
 assert part_counts(a[1],'i+',('q-',))==[2,2]
 assert changes(a[1])==[('q-','auto','cut',9),('i+','cut','label',4)] and changes(b[1])==[('q-','auto','cut',9)]
 assert continuous(a)==[[True],[True],[True]] and continuous(b)==[[True],[True],[False]]
 passed.append('ag1170_retained_parts_block_later_drain_connection')
 negatives=[r['name'] for r in result['sources'] if not r['source_connection']['continuous']]
 assert negatives==['ag-2486:vx:m16.0,m22.1','ag-2486:vx:m17.0,m22.1','ag-2486:vx:m18.0,m22.1']
 passed.append('exact_three_source_separated_label_pairs')
 assert not any(r['cache_only_ink'] for r in result['sources']);passed.append('every_named_source_cache_stroke_has_actual_ink')
 result['source_connected_names']=[r['name'] for r in result['sources'] if r['source_connection']['continuous']]
 result['source_separated_names']=negatives
 return passed

def main():
 p=argparse.ArgumentParser(description=__doc__)
 for name in ('diagnostic16','diagnostic17','corpus16','corpus17','work','output'):p.add_argument(name,type=Path)
 p.add_argument('--check',action='store_true');a=p.parse_args()
 r=audit(Path(__file__).resolve().parents[3],a.diagnostic16,a.diagnostic17,a.corpus16,a.corpus17,a.work)
 r['method_checks']=checks(r);r=json.loads(json.dumps(r))
 if a.check:assert r==json.loads(Path(__file__).with_name('thin_interactions_cases.json').read_text()),'frozen interaction evidence changed'
 a.output.write_text(json.dumps(r,sort_keys=True,indent=2)+'\n');print('Named checks:',r['method_checks'])
if __name__=='__main__':main()
