from pathlib import Path
import json,subprocess,itertools,sys
out=Path('/tmp/cktimg-rest-facing-evidence')
base='/tmp/cktimg-series-final-native'
for n in [1237,1349,1242,2212]:
 raw=Path('external/examples/analoggenie/ag-%d.cir'%n).read_text()
 variants={'base':raw}
 if n in (1237,1349):
  px,py,cx,cy,dx=(160,320,200,300,410) if n==1237 else (170,310,220,330,380)
  for gap,move in itertools.product([20,30,40,50,60,80,100],(True,False)):
   ax=cx+gap+60 if move else (540 if n==1237 else 470)
   lines=f'*@ at x1 {px/40} {py/40} MR0\n*@ at x2 {ax/40} {cy/40} MR0\n'
   variants[f'{gap}-{int(move)}']=raw.replace('.ends dut',lines+'.ends dut')
 for k,source in variants.items():
  f=out/f'ag{n}-{k}'
  f.with_suffix('.cir').write_text(source)
  subprocess.run([base,'--report',f.with_suffix('.report.json'),'--svg',f.with_suffix('.svg'),f.with_suffix('.cir'),f.with_suffix('.json')],capture_output=True,check=True)
  d=json.loads(f.with_suffix('.json').read_text());r=json.loads(f.with_suffix('.report.json').read_text());ds={x['name']:x for x in d['devices']}
  if n not in (1237,1349):continue
  p=next(q for q in ds['x2']['pins'] if q['term']=='out')
  peer=next(q for q in ds['x1']['pins'] if q['term']=='ctrl')
  wire=[w for w in d['wires'] if w['net']==p['net']]
  print(n,k,ds['x1']['pos'],ds['x1']['mirror'],ds['x2']['pos'],ds['x2']['mirror'],p['xy'],peer['xy'],r.get('metrics',r.get('scores')),r.get('findings'),wire,flush=True)
