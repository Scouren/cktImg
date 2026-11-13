#!/usr/bin/env python3
"""Replay the AG2365 retained-wire / synthetic endpoint interaction.

Existing binaries only. Each trace must match both geometry and report bytes
from its frozen shipping counterpart. The pre-row17 snapshot is separate
from the unchanged iteration15 study. Actual source leads/ink and per-round
foreign barriers, candidate vertices and linesFit decisions are retained.
"""
from pathlib import Path
import argparse,hashlib,json,subprocess
from thin_trace_run import parse
from thin_parts import crossings,piece
from input_resistor_legs import connection
from trunk_rungs import source_loss

sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()

def replay(root,work,diagnostic16,diagnostic17,baseline16,baseline17):
 work.mkdir(parents=True,exist_ok=True)
 rows=[]
 for version,baseline in [('16',baseline16),('17',baseline17)]:
  copy=diagnostic16 if version=='16' else diagnostic17;trace=copy/'out/bin/cktimg-json-trace'
  manifest=json.loads((copy/'manifest.json').read_text())
  for rel,want in manifest['instrumented_sha256'].items():assert sha(copy/rel)==want,rel
  for compact in (False,True):
   out=work/f'trace{version}-compact-{int(compact)}';out.mkdir(exist_ok=True)
   config=out/'layout.zon';config.write_text('.{ .layout = .{ .compact = '+str(compact).lower()+' } }\n')
   for label,binary in [('baseline',baseline),('trace',trace)]:
    cmd=[str(binary),'--config',str(config),'--report',str(out/(label+'.report.json')),str(root/'external/examples/analoggenie/ag-2365.cir'),str(out/(label+'.json'))]
    p=subprocess.run(cmd,capture_output=True,text=True,timeout=90);(out/(label+'.log')).write_text(p.stderr)
    assert p.returncode==0,(version,compact,label,p.stderr[-2000:])
   for suffix in ('.json','.report.json'):assert (out/('baseline'+suffix)).read_bytes()==(out/('trace'+suffix)).read_bytes(),(version,compact,suffix)
   raw=(out/'trace.log').read_text();extra={};current=None;ordinary=[]
   for line in raw.splitlines():
    w=line.split()
    if len(w)>2 and w[:2]==['TRACE','round_begin']:current=int(w[2])
    if len(w)>1 and w[0]=='TRACE' and (w[1] in ('peak','component') or w[1].startswith('trunk_')):
     if current is not None:extra.setdefault(current,[]).append(w[1:])
    else:ordinary.append(line)
   rounds=parse('\n'.join(ordinary))
   for r in rounds:
    assert crossings(r)==sorted((tuple(sorted(c['nets'])),tuple(c['at'])) for c in r['crossings'])
    r['extra']=extra.get(r['round'],[])
    target,=[n for n,meta in r['nets'].items() if meta['name']=='veaout']
    points=[next(p['at'] for p in r['pins'] if p['device']==d and p['index']==1) for d in ('m1','msen')]
    r['target_connection']=connection([[s['a'],s['b']] for s in r['segments'] if s['net']==target],points)
    r['target_style']=r['nets'][target]['style'];r['target_crossings']=[c for c in r['crossings'] if target in c['nets']]
   record=dict(version=version,compact=compact,manifest={k:manifest[k] for k in ('source_sha256','instrumented_sha256','cases')},baseline_binary_sha256=sha(baseline),trace_binary_sha256=sha(trace),geometry_sha256=sha(out/'trace.json'),report_sha256=sha(out/'trace.report.json'),trace_log_sha256=sha(out/'trace.log'),rounds=rounds)
   rows.append(record)
   print(version,compact,'identity OK',[(r['round'],r['target_style'],r['target_connection']['continuous'],[(c['name'],c['before'],c['after'],c['count']) for c in r['changes']]) for r in rounds],flush=True)
 proof=source_loss(root/'external/examples/analoggenie',dict(id='ag-2365',net='veaout',pins=[['m1',1],['msen',1]]),json.loads((work/'trace16-compact-1/trace.json').read_text()),json.loads((work/'trace17-compact-1/trace.json').read_text()))
 return dict(cases=rows,source=proof)


def checks(result):
 passed=[]
 cases={(r['version'],r['compact']):r for r in result['cases']}
 assert list(cases)==[('16',False),('16',True),('17',False),('17',True)]
 passed.append('exact_four_named_states')
 a,b=[cases[v,True]['rounds'] for v in ('16','17')]
 assert a[0]['segments']==b[0]['segments'] and a[0]['pins']==b[0]['pins']
 passed.append('identical_compact_round_zero_ink_and_pins')
 assert [r['target_connection']['continuous'] for r in a]==[False,True,True]
 assert [r['target_connection']['continuous'] for r in b]==[False,False,False]
 passed.append('old_later_round_recovers_new_later_round_does_not')
 for version in ('16','17'):
  assert all(r['target_connection']['continuous'] for r in cases[version,False]['rounds'])
 passed.append('both_noncompact_states_remain_connected')
 changed=lambda r:[(c['name'],c['before'],c['after'],c['count']) for c in r['changes']]
 assert changed(a[0])==[('vz','auto','cut',4),('vctrl','cut','label',3)]
 assert changed(b[0])==[('vz','auto','cut',4)]
 passed.append('exact_greedy_vctrl_promotion_difference')
 n=next(int(n) for n,v in b[0]['nets'].items() if v['name']=='vctrl')
 segs=[[s['a'],s['b']] for s in b[0]['segments'] if s['net']==n]
 reached=set();counts=[]
 for i,s in enumerate(segs):
  if i in reached:continue
  group=piece(segs,s[0]);reached.update(group);ink=[segs[j] for j in group]
  counts.append(sum(bool(piece(ink,c['at'])) for c in b[0]['crossings'] if n in c['nets']))
 assert sorted(counts)==[0,0,1,2]
 passed.append('independent_vctrl_parts_zero_zero_one_two')
 assert all(e[3]=='2' for r in b for e in r['extra'] if e[0]=='peak' and int(e[2])==n)
 passed.append('traced_vctrl_peak_two_matches_raw_geometry')
 barrier=['trunk_barrier','vctrl','270','380','270','720']
 assert barrier in a[0]['extra'] and all(barrier not in r['extra'] for r in a[1:])
 assert all(barrier in r['extra'] for r in b)
 passed.append('actual_barrier_removed_only_in_baseline_later_rounds')
 fit=lambda r:[e[-1] for e in r['extra'] if e[:4]==['trunk_fit','level','570','0']]
 assert all(fit(r) and set(fit(r))=={'true'} for r in a[1:])
 assert all(fit(r) and set(fit(r))=={'false'} for r in b)
 passed.append('same_row_fit_passes_only_after_baseline_barrier_removal')
 expected={(0,0,250,570),(0,1,270,570),(1,0,320,570),(1,1,300,570),(2,0,270,570),(2,1,300,570)}
 for r in a+b:
  points={tuple(map(int,e[4:])) for e in r['extra'] if e[:4]==['trunk_point','level','570','0']}
  assert points==expected
 passed.append('exact_artificial_half_gap_candidate_vertices_retained')
 proof=result['source'];assert proof['source_targets']==[[280,80],[470,150]]
 assert proof['source_connection']['continuous'] and not proof['source_straight']['continuous']
 assert proof['native']['baseline']['connection']['continuous'] and not proof['native']['candidate']['connection']['continuous']
 passed.append('actual_source_bent_connection_lost_natively')
 return passed


def main():
 p=argparse.ArgumentParser(description=__doc__)
 for name in ('diagnostic16','diagnostic17','baseline16','baseline17','work','output'):p.add_argument(name,type=Path)
 p.add_argument('--check',action='store_true');a=p.parse_args()
 result=replay(Path(__file__).resolve().parents[3],a.work,a.diagnostic16,a.diagnostic17,a.baseline16,a.baseline17)
 result['method_checks']=checks(result)
 result['provenance']=dict(baseline_revision='450e4cd0',candidate='uncommitted pre-row17 snapshot, pinned by thin_row_snapshot.json; not a clean16 or corrected17 tree')
 result=json.loads(json.dumps(result))
 if a.check:assert result==json.loads(Path(__file__).with_name('thin_row_cases.json').read_text()),'exact AG2365 companion evidence changed'
 a.output.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
 print('Named checks:',result['method_checks'])

if __name__=='__main__':main()
