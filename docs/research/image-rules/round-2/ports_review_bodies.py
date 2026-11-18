#!/usr/bin/env python3
"""Adversarial cross-review: body ties, interfaces, attachment and native roles.

Independent oracles are literal equality partitions, complete synthetic cards,
and a remote marker coordinate visibly detached from AG1014 M1's channel.
The prior failing run is retained separately, never rewritten as a pass.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
from unittest.mock import patch

import bodies_census as c
import bodies_examples as b

HERE=Path(__file__).resolve().parent
PARTITIONS=[
 ('0000',[1,1,1,1]),('0001',[0,0,0,1]),('0010',[1,1,0,0]),
 ('0011',[0,0,1,0]),('0012',[0,0,0,0]),('0100',[1,0,1,1]),
 ('0101',[0,1,0,1]),('0102',[0,0,0,1]),('0110',[1,0,0,0]),
 ('0111',[0,1,1,0]),('0112',[0,0,0,0]),('0120',[1,0,0,0]),
 ('0121',[0,1,0,0]),('0122',[0,0,1,0]),('0123',[0,0,0,0])]


def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def equality_controls():
    out=[]
    for word,bits in PARTITIONS:
        nets=['opaque_'+n for n in word]
        expected=dict(zip(('B=D','B=G','B=S','D=S'),map(bool,bits)))
        assert c.ties(nets)==expected
        expected_primary='B=S' if bits[2] else 'B=D' if bits[0] else 'B=G' if bits[1] else 'B=distinct'
        assert c.relation(nets)==expected_primary
        out.append(dict(partition=word,nets=nets,expected_ties=expected,primary=expected_primary))
    return out


def interface_controls():
    base='.model nm nmos\n.subckt dut d1 d2 g s\nM1 d1 g s well nm\nM2 d2 g s well nm\n.ends dut\n'
    scenarios=[('internal_body_only',base,False,0),
      ('external_body_only',base.replace('dut d1 d2 g s','dut d1 d2 g s well'),True,0),
      ('body_plus_resistor',base.replace('.ends dut','R1 well s 1k\n.ends dut'),False,1),
      ('body_plus_mos_gate',base.replace('.ends dut','M3 d1 well s s nm\n.ends dut'),False,1),
      ('body_plus_X_formal','.subckt aux control\n.ends aux\n'+base.replace('.ends dut','X1 well aux\n.ends dut'),False,1),
      ('internal_name_looks_like_rail',base.replace('well','vdd'),False,0)]
    out=[]
    for name,text,external,n_nonbody in scenarios:
        ports,rows=c.parse(text);inc=c.incidence(rows);body=rows[0]['nets'][3]
        nonbody=[p for p in inc[body] if not(p[0].startswith('m') and p[1]==3)]
        assert (body in ports)==external and len(nonbody)==n_nonbody
        assert inc[body][:2]==[['m1',3,'B'],['m2',3,'B']]
        out.append(dict(name=name,raw=text,body_net=body,body_external=external,
                        body_incidence=inc[body],nonbody_incidence=nonbody,
                        internal_body_only=not external and not nonbody))
    return out


def attachment_controls():
    source=b.EXAMPLES/'ag-1014.human.json';human=json.loads(source.read_text())
    normal=b.inspect('ag-1014');original=next(m for m in normal['mos'] if m['card']=='m1')
    assert original['source_status']=='supported_body_landing'
    mutated=copy.deepcopy(human)
    next(d for d in mutated['devices'] if d['card']=='m1')['terminals']['B']=[60,110]
    reader=Path.read_text
    def substitute(path,*args,**kwargs):
        return json.dumps(mutated) if path==source else reader(path,*args,**kwargs)
    with patch.object(Path,'read_text',substitute):
        result=b.inspect('ag-1014')
    moved=next(m for m in result['mos'] if m['card']=='m1')
    assert moved['source_status']=='detached_cached_body_landing'
    assert not moved['source_geometry']['B_is_own_lead_endpoint']
    assert not moved['source_geometry']['containing_filled_polygons']
    assert moved['source_body_routes']['named_ink_touching_B']
    return dict(original=original,mutated=moved,expected='detached_cached_body_landing',
                mutated_input_sha256=hashlib.sha256(json.dumps(mutated).encode()).hexdigest(),
                source_input_sha256=digest(source),source_svg_sha256=digest(source.with_suffix('.svg')) if source.with_suffix('.svg').exists() else digest(b.EXAMPLES/'ag-1014.svg'))


def native_controls():
    raw=['d','g','s','b']
    visible=dict(name='m1',pins=[dict(term=t,net=n) for t,n in zip(('d','g','s','b'),raw)])
    hidden=dict(name='m1',pins=copy.deepcopy(visible['pins'][:3]),bulk='b')
    b.native_binding(visible,raw);b.native_binding(hidden,raw)
    out=[]
    for name in ('wrong_fourth_role','wrong_bulk_net','drop_fourth_visible','exchange_gate_body'):
        wrong=copy.deepcopy(hidden if name=='wrong_bulk_net' else visible)
        if name=='wrong_fourth_role':wrong['pins'][3]['term']='g'
        elif name=='wrong_bulk_net':wrong['bulk']='wrong'
        elif name=='drop_fourth_visible':wrong['pins'].pop()
        else:wrong['pins'][1]['net'],wrong['pins'][3]['net']=wrong['pins'][3]['net'],wrong['pins'][1]['net']
        try:b.native_binding(wrong,raw)
        except AssertionError:out.append(dict(name=name,input=wrong,rejected=True))
        else:raise AssertionError(name+' accepted')
    return dict(visible_positive=visible,hidden_positive=hidden,mutations=out)


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=Path,required=True);p.add_argument('--check',type=Path);args=p.parse_args()
    prior=json.loads((HERE/'ports_review_failures.json').read_text())
    assert prior['detached_B']['source_status']=='supported_body_landing'
    assert prior['wrong_fourth_role']['accepted']
    result=dict(scope='Cross-review only; no engine changes or target-netlist round-trip claim.',
                prior_failures_sha256=digest(HERE/'ports_review_failures.json'),
                partition_controls=equality_controls(),interface_controls=interface_controls(),
                actual_attachment_control=attachment_controls(),native_controls=native_controls(),
                dependencies={p.name:digest(p) for p in (Path(__file__),Path(b.__file__),Path(c.__file__))})
    if args.check:assert result==json.loads(args.check.read_text())
    args.output.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print('PASS: 15 literal equality partitions; 6 interface cases; actual detached-cache regression; 4 native mutations.')


if __name__=='__main__':main()
