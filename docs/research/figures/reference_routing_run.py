#!/usr/bin/env python3
"""Run built diagnostic copies; exact native/report identity precedes causal claims."""
from pathlib import Path
import argparse,hashlib,json,subprocess,sys
ROOT=Path(__file__).resolve().parents[3]
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT/'docs/research/figures'))
from thin_trace_run import parse
from thin_parts import crossings
from input_resistor_legs import connection
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
from reference_routing_checks import checks
from reference_routing_source import replay,outer_certificate
p=argparse.ArgumentParser(description=__doc__)
for name in ('diagnostic17','diagnostic18','corpus17','corpus18','work','output'):p.add_argument(name,type=Path)
p.add_argument('--check',action='store_true');a=p.parse_args()
frozen=json.loads((HERE/'reference_routing_cases.json').read_text())
losses=replay(ROOT,a.corpus17,a.corpus18,frozen['source_losses']);ids=['ag-2415','ag-2428','ag-2434','ag-2436']
result=dict(source_audit_sha256=frozen['source_audit_sha256'],source_losses=losses,states=[],provenance={})
for version,tag in [('17','iteration17-bounded'),('18','iteration18-reference')]:
 copy=getattr(a,'diagnostic'+version);manifest=json.loads((copy/'manifest.json').read_text());binary=copy/'out/bin/cktimg-json-trace';corpus=getattr(a,'corpus'+version);original=corpus/'cktimg-json'
 for rel,want in manifest['instrumented_sha256'].items():assert sha(copy/rel)==want,rel
 result['provenance'][version]=dict(manifest=manifest,trace_binary_sha256=sha(binary),frozen_binary_sha256=sha(original))
 assert sha(original)==json.loads((corpus/'scorecard.json').read_text())['binary_sha256']
 for ident in ids:
  for compact in [True,False]:
   work=a.work/(ident+'-'+version+'-compact-'+str(int(compact)));work.mkdir(parents=True,exist_ok=True)
   opts=[]
   if not compact:
    conf=work/'layout.zon';conf.write_text('.{ .layout = .{ .compact = false } }\n');opts=['--config',str(conf)]
   for label,exe in [('trace',binary)]+([] if compact else [('frozen',original)]):
    q=subprocess.run([str(exe),*opts,'--report',str(work/(label+'.report.json')),str(ROOT/'external/examples/analoggenie'/(ident+'.cir')),str(work/(label+'.json'))],capture_output=True,text=True,timeout=90)
    (work/(label+'.log')).write_text(q.stderr);assert q.returncode==0,(ident,version,q.stderr[-2000:])
   for suffix in ('.json','.report.json'):
    before=corpus/(ident+suffix) if compact else work/('frozen'+suffix)
    assert (work/('trace'+suffix)).read_bytes()==before.read_bytes(),(ident,version,compact,suffix)
   raw=(work/'trace.log').read_text();extra={};round=None;ordinary=[]
   for line in raw.splitlines():
    w=line.split()
    if w[:2]==['TRACE','round_begin']:round=int(w[2])
    if len(w)>1 and w[0]=='TRACE' and (w[1] in ('peak','component') or w[1].startswith(('trunk_','ported_'))):
     if round is not None:extra.setdefault(round,[]).append(w[1:])
    else:ordinary.append(line)
   rounds=parse('\n'.join(ordinary));pairs=[r for r in losses if r['id']==ident]
   for r in rounds:
    assert crossings(r)==sorted((tuple(sorted(c['nets'])),tuple(c['at'])) for c in r['crossings'])
    r['extra']=extra.get(r['round'],[]);r['source_pairs']=[]
    for pair in pairs:
     n=next(n for n,d in r['nets'].items() if d['name']==pair['net']);targets=[next(p['at'] for p in r['pins'] if [p['device'],p['index']]==t) for t in pair['pins']]
     r['source_pairs'].append(dict(name=pair['name'],style=r['nets'][n]['style'],connection=connection([[s['a'],s['b']] for s in r['segments'] if s['net']==n],targets)))
   result['states'].append(dict(id=ident,version=version,compact=compact,geometry_sha256=sha(work/'trace.json'),report_sha256=sha(work/'trace.report.json'),log_sha256=sha(work/'trace.log'),rounds=rounds))
   print(ident,version,compact,'byte identical; changes',[[[c['name'],c['before'],c['after'],c['count']] for c in r['changes']] for r in rounds],'connected',[[x['connection']['continuous'] for x in r['source_pairs']] for r in rounds],flush=True)
result['named_byte_identity_checks']=[r['id']+':'+r['version']+':compact='+str(r['compact']).lower() for r in result['states']]
result['method_checks'],result['causes']=checks(result)
result['outer_topology_certificate']=outer_certificate(ROOT,a.corpus17,a.corpus18)
result=json.loads(json.dumps(result))
if a.check:assert result==frozen,'frozen routing interaction evidence changed'
a.output.write_text(json.dumps(result,sort_keys=True,indent=2)+'\n')
