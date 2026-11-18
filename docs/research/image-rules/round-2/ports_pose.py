#!/usr/bin/env python3
"""Integer planning witness for complete nine-port geometry, not engine code.

Oracle: literal reference coordinates and segment intersection arithmetic.
This deliberately roomy frame proves feasibility; it does not choose final
dimensions, label spacing, route ownership, or the source's unobserved VSS pose.
"""
import argparse
import hashlib
import itertools
import json
from pathlib import Path

BODY=[(-6,-6),(-6,6),(6,0)]
TIPS={'negative':(-8,-2),'positive':(-8,2),'output':(8,0),
      'supply':(0,-8),'ground':(-4,8),'bias1':(-2,8),
      'bias2':(0,8),'bias3':(2,8),'bias4':(4,8)}
START={'negative':(-6,-2),'positive':(-6,2),'output':(6,0),
       'supply':(0,-3),'ground':(-4,5),'bias1':(-2,4),
       'bias2':(0,3),'bias3':(2,2),'bias4':(4,1)}
NORMAL={'negative':(-1,0),'positive':(-1,0),'output':(1,0),
        'supply':(0,-1),'ground':(0,1),'bias1':(0,1),
        'bias2':(0,1),'bias3':(0,1),'bias4':(0,1)}


def cross(a,b,c):
    return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])


def on(p,a,b):
    return cross(a,b,p)==0 and all(min(a[i],b[i])<=p[i]<=max(a[i],b[i]) for i in (0,1))


def intersects(a,b,c,d):
    if any((on(p,u,v)) for p,u,v in ((a,c,d),(b,c,d),(c,a,b),(d,a,b))):return True
    return cross(a,b,c)*cross(a,b,d)<0 and cross(c,d,a)*cross(c,d,b)<0


def transform(p,turns,reflect):
    x,y=p
    if reflect:x=-x
    for _ in range(turns):x,y=-y,x
    return (x,y)


def frame(pitch,turns,reflect,positive_above):
    def point(p):return transform((p[0]*pitch,p[1]*pitch),turns,reflect)
    body=list(map(point,BODY));rows=[]
    for role in TIPS:
        slot={'positive':'negative','negative':'positive'}.get(role,role) if positive_above else role
        start=point(START[slot]);tip=point(TIPS[slot]);normal=transform(NORMAL[slot],turns,reflect)
        assert any(on(start,a,b) for a,b in zip(body,body[1:]+body[:1])),role
        assert sum((tip[i]-start[i])*normal[i] for i in (0,1))>0
        assert min(sum((tip[i]-p[i])*normal[i] for i in (0,1)) for p in body)>0
        rows.append(dict(role=role,slot=slot,start=start,tip=tip,normal=normal))
    assert len(set(tuple(r['tip']) for r in rows))==9
    for x,y in itertools.combinations(rows,2):
        assert not intersects(x['start'],x['tip'],y['start'],y['tip']),(x,y)
    return dict(pitch=pitch,quarter_turns=turns,reflect_x=reflect,positive_above_local=positive_above,body=body,ports=rows)


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=Path,required=True);p.add_argument('--check',type=Path);args=p.parse_args()
    assert intersects((0,1),(2,1),(1,0),(1,2))
    assert not intersects((0,0),(1,0),(2,0),(3,0))
    a=frame(1,0,False,False);b=frame(1,0,False,True)
    aa={r['role']:r for r in a['ports']};bb={r['role']:r for r in b['ports']}
    assert aa['positive']['tip']==(-8,2) and bb['positive']['tip']==(-8,-2)
    assert all(aa[r]==bb[r] for r in set(TIPS)-{'positive','negative'})
    reflected_y={r:(pt[0],-pt[1]) for r,pt in TIPS.items()}
    assert reflected_y['positive']==bb['positive']['tip']
    assert reflected_y['supply']!=bb['supply']['tip']
    assert reflected_y['bias4']!=bb['bias4']['tip']
    frames=[frame(p,t,m,s) for p in (1,2,3,4,5,20) for t in range(4) for m in (False,True) for s in (False,True)]
    result=dict(scope='Feasibility witness only. Nine declared ports survive; semantic signed order precedes full pose transform.',
                frames=frames,source_vss='Canonical choice; not an observed source coordinate.',
                controls=['literal_crossing_detected','literal_disjoint_segments_retained','signed_order_moves_only_two_slots',
                          'whole_y_reflection_moves_supply_and_bias4_so_is_not_signed_order'],
                index_range=[0,8],required_index_bits=4,role_count_after_two_new_roles=15,
                script_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest())
    result=json.loads(json.dumps(result))
    if args.check:assert result==json.loads(args.check.read_text())
    args.output.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps(dict(frames=len(frames),ports_per_frame=9,controls=result['controls'])))


if __name__=='__main__':main()
