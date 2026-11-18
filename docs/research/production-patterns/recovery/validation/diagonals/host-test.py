"""Run the real Schemify plugin, independent netlist and comparison. Keep all files."""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import subprocess, shutil, sys, json, os, shlex
base=Path('/tmp/cktimg-n0-figures')
root=Path('/home/omare/Documents/Projects/EDA-Tools/Schematic/Plugins/cktImg')
host=root/'.objective/human-schematic-equivalence/runs/iteration21-resume1/host-target/debug'
work=base/sys.argv[1];work.mkdir(exist_ok=True)
plugin=Path(sys.argv[2])
init=work/'init.lua';init.write_text('schemify.pack.add({ { path = '+json.dumps(str(plugin))+', name = "netlist-import", grant = { "read_project", "write_project" }, fuel = 100000000000 } })\n')
cli=[str(host/'schemify'),'-u',str(init)]
def run(cmd,cwd):
 rr=subprocess.run(cmd,cwd=cwd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True);(cwd/'commands.log').open('a').write(shlex.join(map(str,cmd))+'\n'+rr.stdout+'\n');rr.check_returncode()
run(cli+['pack','sync'],work)
def case(name):
 p=work/name; cells=p/'n2s';cells.mkdir(parents=True,exist_ok=True)
 (p/'schemify.project').write_text('schemify 1 project\n')
 src=base/f'{name}.cir'
 shutil.copy2(src,cells/'input.cir');run(cli+['cmd',str(p),'netlist.import','--allow-45','n2s/input.cir'],p)
 run(cli+['netlist','n2s/dut.shcomp','--dialect','ngspice','-o','dut.back.sp'],p)
 bench=next(cells.glob('*.shbench'));run(cli+['netlist','n2s/'+bench.name,'--dialect','ngspice','-o','bench.back.sp'],p)
 def cards(text, src):
  rows={};inside=not src
  for line in text.lower().splitlines():
   w=line.split()
   if not w:continue
   if w[:2]==['.subckt','dut']:inside=True;continue
   if w[0]=='.ends':inside=False;continue
   if inside and w[0].startswith('m'):
    rows[w[0]]=(w[1:5],w[5],{*w[6:]})
  return rows
 original=src.read_text();back=(p/'dut.back.sp').read_text()
 assert cards(original,True)==cards(back,False),(name,'ordered card drift')
 keep=lambda l: l.startswith('.model')
 declared='\n'.join(l for l in (p/'bench.back.sp').read_text().lower().splitlines() if keep(l))+'\n'
 (p/'actual.sp').write_text('* actual\n'+declared+back)
 models='\n'.join(l for l in original.lower().splitlines() if keep(l))+'\n'
 (p/'expected.sp').write_text('* expected\n'+models+'\n'.join(l for l in original.splitlines() if l and l[0].lower()=='m')+'\n.end\n')
 run([host/'spicecmp',p/'expected.sp',p/'actual.sp'],p)
 print(name,'ordered cards',len(cards(back,False)),'and spicecmp passed',flush=True)
with ThreadPoolExecutor(max_workers=2) as pool: list(pool.map(case,sys.argv[3:]))
