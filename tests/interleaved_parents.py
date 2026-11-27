"""Freeze two independently traced channel-bound interleavings and their memberships."""
import json
from itertools import combinations
from pathlib import Path
import subprocess
import sys
from source_bridge import host_records,native_records

# Each entry is a set of source-card owners. Pairs are the intersections
# measured from the transformed original D/S lead ends. Positive area only.
CASES={
    'ag-364': ([(1,2,3,4,5,6,7,8,13),(9,10,11,12)], {(0,1)}),
    'ag-1016': ([(9,10,11,12,13,14,15,16),(17,18,23,24),(19,20,21,22),(5,6),(7,8)],
                {(0,1),(0,2),(0,3),(0,4),(1,2),(1,4),(2,3)}),
}


def check(name,pins):
    groups,expected=CASES[name]
    assert len({i for g in groups for i in g})==sum(map(len,groups))
    bounds=[]
    for g in groups:
        points=[pins['m'+str(i)][t] for i in g for t in (0,2)]
        bounds.append([min(p[0] for p in points),min(p[1] for p in points),
                       max(p[0] for p in points),max(p[1] for p in points)])
    pairs={(i,j) for (i,a),(j,b) in combinations(enumerate(bounds),2)
           if max(a[0],b[0])<min(a[2],b[2]) and max(a[1],b[1])<min(a[3],b[3])}
    assert pairs==expected,(name,pairs,expected)
    if name=='ag-364':
        inner,outer=bounds
        assert outer[0]<inner[0]<inner[2]<outer[2],bounds
        for branch in [(9,11),(10,12),(1,3,5,7),(2,4,6,8)]:
            xs={pins['m'+str(i)][t][0] for i in branch for t in (0,2)}
            assert len(xs)==1,(branch,xs)


if __name__=='__main__':
    if sys.argv[1]=='--host':
        for name in CASES:
            pins,_=host_records(Path(sys.argv[2]),Path(sys.argv[3])/name/'n2s/dut.shcomp')
            check(name,pins)
    else:
        binary,*paths=sys.argv[1:]
        assert {Path(p).stem for p in paths}==set(CASES)
        for path in paths:
            pins,_=native_records(json.loads(subprocess.check_output([binary,path])))
            name=Path(path).stem
            check(name,pins)
            # A disjoint-room packing of one owner cannot pass the same oracle.
            changed=dict(pins)
            for i in CASES[name][0][1]:
                n='m'+str(i);changed[n]=[(x+10000,y) for x,y in pins[n]]
            try:check(name,changed)
            except AssertionError:pass
            else:raise AssertionError((name,'failed to reject separated owner'))
