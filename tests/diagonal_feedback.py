"""Trace the reciprocal gates of AG90 and its orthogonal and caller-controlled alternatives."""
import json
from pathlib import Path
import re
import subprocess
import sys
from tempfile import TemporaryDirectory


def render(binary, deck, output, angled):
    report = output.with_suffix('.report')
    subprocess.run([binary, *(['--allow-45'] if angled else []), '--report', report,
                    '--svg', output.with_suffix('.svg'), deck, output], check=True)
    doc = json.loads(output.read_text())
    decisions = json.loads(report.read_text())
    assert not decisions['gates'], (deck, decisions['gates'])
    return doc, decisions


def cross(a, b, c):
    return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])


def trace(doc):
    slopes = {}
    segments = {}
    for wire in doc['wires']:
        net = wire['net']
        edges = [(tuple(a), tuple(b)) for path in wire['segments'] for a,b in zip(path,path[1:])]
        segments[net] = edges
        for a,b in edges:
            if a[0] == b[0] or a[1] == b[1]:
                continue
            assert abs(a[0]-b[0]) == abs(a[1]-b[1]), (net,a,b)
            assert net not in slopes
            slopes[net] = (a,b)
    assert len(slopes)==2, slopes
    (a,b),(c,d) = slopes.values()
    assert cross(a,b,c)*cross(a,b,d)<0 and cross(c,d,a)*cross(c,d,b)<0
    for net, diagonal in slopes.items():
        pins = [(pin['term'],tuple(pin['xy'])) for dev in doc['devices']
                for pin in dev['pins'] if pin['net']==net]
        assert sorted(term for term,_ in pins)==['d','d','g','p'], (net,pins)
        gate=next(at for name,at in pins if name=='g')
        edges=segments[net]
        # The first segment leaves the gate horizontally. The gate's net reaches
        # both drains and the output by wire alone under an endpoint-only netlister.
        assert any(gate in (a,b) and a[1]==b[1] and (a in diagonal or b in diagonal) for a,b in edges)
        reachable={gate}
        for _ in range(len(edges)):
            for a,b in edges:
                if a in reachable or b in reachable:
                    reachable.update((a,b))
        assert all(pin in reachable for _,pin in pins)
    return slopes


def main():
    binary, positive, *controls = map(Path,sys.argv[1:])
    binary=binary.resolve()
    with TemporaryDirectory() as folder:
        root=Path(folder)
        src=positive.read_text()
        old,_=render(binary,positive,root/'old.json',False)
        now,report=render(binary,positive,root/'new.json',True)
        assert {w['net'] for w in old['wires']}=={w['net'] for w in now['wires']}
        assert old['devices']==now['devices']
        assert set(trace(now))=={'vout1','vout2'}
        assert report['metrics']['crossings']>=1
        for case in controls:
            render(binary,case,root/'before.json',False)
            render(binary,case,root/'after.json',True)
            for suffix in ('.json','.svg','.report'):
                assert (root/('before'+suffix)).read_bytes()==(root/('after'+suffix)).read_bytes(),case
        hold, reverse, unmatched = root/'wire.cir',root/'reversed.cir',root/'different.cir'
        lines=src.splitlines()
        indices=[i for i,line in enumerate(lines) if re.match('^[mM][0-9]+ ',line)]
        for i,line in zip(indices,reversed([lines[i] for i in indices])):
            lines[i]=line
        reverse.write_text('\n'.join(lines)+'\n')
        swapped,_=render(binary,reverse,root/'reversed.json',True)
        assert trace(swapped)==trace(now)
        hold.write_text(src.replace('.ends dut','*@ wire VOUT1\n.ends dut'))
        unmatched.write_text(re.sub(r'(?im)^(M3 .*? w=)1\b',r'\g<1>2',src))
        for deck in [hold,unmatched]:
            assert deck.read_text()!=src
            before,_=render(binary,deck,root/'before.json',False)
            after,_=render(binary,deck,root/'after.json',True)
            assert before==after,deck


if __name__=='__main__':
    main()
