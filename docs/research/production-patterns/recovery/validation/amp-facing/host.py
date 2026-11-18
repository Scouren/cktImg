from pathlib import Path
import os,shutil,subprocess,re,sys
root=Path('/tmp/cktimg-rest-frames')
h=Path('/home/omare/Documents/Projects/EDA-Tools/Schematic/Plugins/cktImg/.objective/human-schematic-equivalence/runs/iteration21-resume1/host-target/debug/schemify')
a=Path('/tmp/cktimg-rest-facing-evidence/host');a.mkdir(exist_ok=True)
cfg=a/'init.lua';cfg.write_text('schemify.pack.add({ { path = "'+str(root)+'", name = "netlist-import", grant = { "read_project", "write_project" }, fuel = 100000000000 } })\n')
env=dict(os.environ)
for k in ['CONFIG','CACHE','DATA','STATE']:env['XDG_'+k+'_HOME']=str(a/k)
def run(*args,cwd):return subprocess.run([h,'-u',cfg,*args],cwd=cwd,env=env,check=True,capture_output=True,text=True)
run('pack','sync',cwd=a)
for n in [1237,1349,1242,2212]:
 w=a/f'ag-{n}';d=w/'n2s';d.mkdir(exist_ok=True,parents=True);(w/'schemify.project').write_text('schemify 1 project\n')
 shutil.copy(root/'external/examples/analoggenie'/f'ag-{n}.cir',d/'input.cir')
 run('cmd',w,'netlist.import','n2s/input.cir',cwd=w)
 run('netlist',d/'dut.shcomp','--dialect','ngspice','-o',w/'returned.sp',cwd=w)
 run('cmd',d/'dut.shcomp','file.image_export.svg_export',w/'drawing.svg',cwd=w)
 t=(d/'dut.shcomp').read_text()
 print(n,[(ref,pos) for ref,pos in re.findall(r'^inst \S+ (\./\S+)\n  at (.*)$',t,re.M)],flush=True)
 for name in ('ea','isr'):
  f=next((p for p in d.glob('*.shcomp') if p.stem.lower()==name),None)
  if f:print(name,[(pin,x,y) for pin,x,y in re.findall(r'^pin (\S+) \S+ (-?\d+) (-?\d+)$',f.read_text(),re.M)],flush=True)
