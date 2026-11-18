#!/usr/bin/env python3
"""Literal nine-port/bias-neighbour width witness; no Zig execution claim."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import re

import ports_contracts as p
from bodies_census import parse,incidence

HERE=Path(__file__).resolve().parent


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--output',type=Path,required=True);ap.add_argument('--check',type=Path);args=ap.parse_args()
    fixture=HERE/'third-ports-width.cir';text=fixture.read_text();cards=p.a.read_cards(text);defs=p.digital.declarations(text)
    calls=p.prior.calls(cards,defs);amp=next(c for c in calls if c['card']=='xamp');peer=next(c for c in calls if c['card']=='xbias')
    assert p.candidate(amp)=='four_bias_signed'
    assert amp['ports']==['vdd','vss','inn','inp','out','vb4','vb3','vb2','vb1']
    assert amp['bindings']==['vdd','vss','feedback','vin','vout','vb4','vb3','vb2','private_bias']
    assert peer['ports']==['vdd','vss','nb'] and peer['bindings']==['vdd','vss','private_bias']
    outer,rows=parse(text);inc=incidence(rows)
    assert inc['private_bias']==[['xamp',8,'vb1'],['xbias',2,'nb']]
    assert 'private_bias' not in outer
    assert all(net in outer for formal,net in zip(amp['ports'],amp['bindings']) if formal in ('vb2','vb3','vb4'))
    source=p.ROOT/'src/bias_neighbors.zig';code=source.read_text()
    assert re.search(r'pins:\s*\[2\]u3',code)
    assert '.pins = .{ @intCast(i), bias_pin.? }' in code
    assert 8>2**3-1 and 2<=2**3-1
    permuted=copy.deepcopy(amp)
    for key in ('ports','bindings'):permuted[key][7],permuted[key][8]=permuted[key][8],permuted[key][7]
    assert dict(zip(permuted['ports'],permuted['bindings']))==dict(zip(amp['ports'],amp['bindings']))
    assert p.candidate(permuted)=='four_bias_signed' and permuted['ports'].index('vb1')==7
    result=dict(scope='A future nine-port glyph reaches an existing bias-neighbour u3 cast. This is a raw/type-capacity witness, not executed Zig.',
                fixture_sha256=sha(fixture),production_source_sha256=sha(source),amplifier=amp,peer=peer,
                private_raw_incidence=inc['private_bias'],amplifier_index=8,peer_index=2,current_pair_index_bits=3,
                required_amplifier_index_bits=4,peer_bound=4,paired_permutation_control=permuted,
                owners=['Pair','find','place','orders','turn','tip'],script_sha256=sha(Path(__file__)))
    if args.check:assert result==json.loads(args.check.read_text())
    args.output.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n');print('PASS raw index-8/private-peer witness; existing u3 cannot hold amplifier index8.')


if __name__=='__main__':main()
