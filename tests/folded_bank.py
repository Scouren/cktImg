"""Read traced source roles from native output or physical Schemify primitive terminals."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
from source_bridge import host_records,native_records


def relations(ps,names=None):
    names=names or {}
    def pins(n):return ps[names.get(n,n)]
    def center(n):
        p=pins(n)
        return tuple((a+b)/2 for a,b in zip(p[0],p[2 if n[0]=='m' else 1]))
    inputs=[center('m'+str(i)) for i in (1,2,3,4)]
    bank=[center('m'+str(i)) for i in (5,6,8,7)]
    return {'transconductor_left':max(x for x,y in inputs)<min(x for x,y in bank),
        'paired_input_columns':inputs[0][0]==inputs[2][0]<inputs[1][0]==inputs[3][0] and inputs[2][1]==inputs[3][1]<inputs[0][1]==inputs[1][1],
        'two_switch_rows':bank[0][1]==bank[1][1]<bank[2][1]==bank[3][1],
        'two_switch_columns':bank[0][0]==bank[2][0]<bank[1][0]==bank[3][0],
        'drains_above_and_below':all((pins('m'+str(i))[0][1]<pins('m'+str(i))[2][1]) == (i in (5,6)) for i in (5,6,8,7)),
        'load_rails_at_opposite_ends':center('r1')[1]<bank[0][1] and bank[2][1]<center('r2')[1],
        'output_capacitor_outside':max(x for x,y in bank)<center('cf')[0] and bank[0][1]<center('cf')[1]<bank[2][1]}


def main(binary,file):
    src=Path(file).read_text()
    with tempfile.TemporaryDirectory() as tmp:
        p=Path(tmp)
        def draw(s):
            (p/'in.cir').write_text(s)
            subprocess.run([binary,'--report',p/'report',p/'in.cir',p/'out'],check=True)
            assert not json.loads((p/'report').read_bytes())['gates']
            return native_records(json.loads((p/'out').read_bytes()))[0]
        baseline=relations(draw(src));assert all(baseline.values()),baseline
        rows=src.splitlines();cards=[r.split() for r in rows if r[:1] in ('C','M','R')]
        names={w[0].lower():w[0][0].lower()+str(30+i*11) for i,w in enumerate(cards)}
        nets={'v1':'aa12','v1p':'bb13','net0':'cc14','net1':'dd15'}
        rev=iter(' '.join([names[w[0].lower()],*(nets.get(k.lower(),k) for k in w[1:])]) for w in reversed(cards))
        shuffled='\n'.join(next(rev) if r[:1] in ('C','M','R') else r for r in rows)+'\n'
        assert all(relations(draw(shuffled),names).values())
        changed=src.replace('.model pch pmos','.model pch pmos\n.model fake npn').replace('Vrf VSS VSS nch','Vrf VSS VSS fake').replace('Vrf_bar VSS VSS nch','Vrf_bar VSS VSS fake')
        assert not all(relations(draw(changed)).values()),'non-MOS input model'
        for a,b in [('Cf Vout Vout_bar','Cf Vout Vrf'),('R6 Vrfdcn Vrf_bar','R6 Vrfdcp Vrf_bar'),
                    ('M8 Vout_bar Vlo V1p','M8 Vout_bar Vlo V1'),('Cd2 net0 Vrf_bar 1p','Cd2 net0 Vrf_bar 2p')]:
            assert not all(relations(draw(src.replace(a,b))).values()),a


if __name__=='__main__':
    if sys.argv[1]=='--host':
        result=relations(host_records(Path(sys.argv[2]),Path(sys.argv[3]))[0]);assert all(result.values()),result
    else:main(*sys.argv[1:])
