import shutil,re,subprocess,itertools
from pathlib import Path
root=Path('/tmp/cktimg-rest-bus-evidence')
host='/home/omare/Documents/Projects/EDA-Tools/Schematic/Plugins/cktImg/.objective/human-schematic-equivalence/runs/iteration21-resume1/host-target/debug/schemify'
full='B_3_,B_2_,B_1_,B_0_'
for outer,inner in itertools.product((False,True),repeat=2):
    dst=root/('expr-'+str(int(outer))+str(int(inner)))
    shutil.copytree(root/'host-before',dst,dirs_exist_ok=True)
    for f in ('Varactor_Switched_caps','dut'):
        p=dst/'n2s'/(f+'.shcomp')
        rows=[]
        for l in p.read_text().splitlines():
            if l.startswith('pin B_') and (f!='dut' or outer):
                if not l.startswith('pin B_3_'): continue
                l=l.replace('B_3_',full)
            if l.startswith('port ') and (f=='dut' or inner) and re.search(r' B_[0-3]_$',l):
                if not l.endswith('B_3_'):continue
                l=l[:-4]+full
            if f!='dut' and l.startswith('line 80 ') and l.split()[2] in ('-10','10','30'):continue
            rows.append(l)
        p.write_text('\n'.join(rows)+'\n')
    proc=subprocess.run([host,'netlist','n2s/dut.shcomp','--dialect','ngspice','-o','expr.sp'],cwd=dst,capture_output=True,text=True)
    print(dst.name,proc.returncode,proc.stderr[:220],flush=True)
    if (dst/'expr.sp').is_file():
        print('\n'.join(s for s in (dst/'expr.sp').read_text().splitlines() if s.startswith(('X2','.subckt Varactor'))),flush=True)
        print('match', (dst/'expr.sp').read_bytes()==(dst/'returned.sp').read_bytes(),flush=True)
