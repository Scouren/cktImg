#!/usr/bin/env python3
"""Frozen-CLI side/caller probes. Hints materialize future box-side choices today.

PININFO plugin expectations are code-read relations, never claimed executed
plugin results. Native execution of those comments is recorded separately.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('sixth_proof',HERE/'sixth-symbols-proof.py')
p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)
ROOT=p.ROOT;RUN=p.RUN/'sixth-fixtures'
BIN=ROOT/'.objective/human-schematic-equivalence/runs/iteration21-resume1/resistor-output-integrated-common/zig-out/bin/cktimg-json'

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def rel(path):return str(path.relative_to(ROOT))

def fixtures():
    source=(p.EXAMPLES/'ag-439.cir').read_text()
    sides='*@ left A\n*@ left B\n*@ right QA\n*@ right QB\n'
    def insert(text,family,extra):
        rows=text.splitlines();i=next(i for i,s in enumerate(rows) if s.lower().startswith('.subckt '+family+' '))
        rows.insert(i+1,extra.rstrip());return '\n'.join(rows)+'\n'
    directed=insert(source,'pfd',sides)
    permuted=directed.replace('.subckt PFD A B QA QB','.subckt PFD QB A QA B').replace('XPFD A B QA QB PFD','XPFD QB A QA B PFD')
    assert permuted!=directed
    mirrored=directed.replace('.ends dut','*@ at XPFD -30 -30 mr90\n.ends dut')
    assert mirrored!=directed
    dac=(p.EXAMPLES/'ag-516.cir').read_text()
    gate='* Digital complete-contract probe.\n.subckt xor_gate VDD VSS A B Y\n.ends xor_gate\n.subckt dut VDD VSS I J O\nX1 VDD VSS I J O xor_gate\n.ends dut\n'
    gate_extra=gate.replace('VDD VSS A B Y','VDD VSS A B Y ENABLE').replace('dut VDD VSS I J O','dut VDD VSS I J O CONTROL').replace('I J O xor_gate','I J O CONTROL xor_gate')
    return {
      'pfd-base':(source,'xpfd'),
      'pfd-sides':(directed,'xpfd'),
      'pfd-sides-permuted':(permuted,'xpfd'),
      'pfd-sides-mirrored-fixed':(mirrored,'xpfd'),
      'pfd-pininfo':(insert(source,'pfd','*.PININFO A:I B:I QA:O QB:O\n'),'xpfd'),
      'dac-o-sides':(insert(dac,'dac','*@ right O1\n*@ right O2\n'),'x1'),
      'xor-base':(gate,'x1'),
      'xor-extra-control':(gate_extra,'x1'),
      'xor-unknown-family':(gate.replace('xor_gate','xor_gate_extra'),'x1'),
      'xor-pininfo-conflict':(insert(gate,'xor_gate','*.PININFO A:O B:I Y:I VDD:B VSS:B\n'),'x1'),
      'xor-side-override':(insert(gate,'xor_gate','*@ right A\n'),'x1')}

def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--execute',action='store_true');ap.add_argument('--output',type=Path,required=True);ap.add_argument('--check',type=Path);args=ap.parse_args()
    RUN.mkdir(parents=True,exist_ok=True);rows=[]
    for name,(text,card) in fixtures().items():
        deck=HERE/f'sixth-symbols-{name}.cir';jp=RUN/f'{name}.json';sp=jp.with_suffix('.svg')
        if args.execute:
            deck.write_text(text)
            subprocess.run([str(BIN),'--svg',str(sp),str(deck),str(jp)],capture_output=True,check=True,timeout=30)
        assert deck.read_text()==text
        data=json.loads(jp.read_text())
        # The observational raw-card reader intentionally refuses steering.
        # Hints affect drawing only; remove their comment lines for this
        # independent ordered electrical binding comparison.
        raw='\n'.join(s for s in text.splitlines() if not s.lstrip().startswith('*@'))
        calls=p.calls(raw)
        for call in calls:
            found=[d for d in data['devices'] if d['name']==call['card']];assert len(found)==1
            dev=found[0]
            assert [x['term'] for x in dev['pins']]==call['ports']
            assert [x['net'] for x in dev['pins']]==call['bindings']
        target=next(c for c in calls if c['card']==card)
        # Keep the real raw family separately. A neutral observer disables the
        # prior audit's family-specific A/B/Y assertions for unsupported controls.
        observed=dict(target);observed['family']='probe';observed['source']=dict(body='box',circles=[],open_paths=0)
        shape=p.d.native_ink(data,p.ET.parse(sp).getroot(),observed)
        device=next(d for d in data['devices'] if d['name']==card)
        local={pin['term']:p.d.native.inverse(device,pin['xy']) for pin in device['pins']}
        rows.append(dict(name=name,deck=rel(deck),deck_sha256=sha(deck),json=rel(jp),json_sha256=sha(jp),svg=rel(sp),svg_sha256=sha(sp),
                         all_calls=calls,target=target,device=device,canonical_pins=local,body=shape['body']))
    by={r['name']:r for r in rows};base=by['pfd-base'];sides=by['pfd-sides']
    assert all(xy[0]<0 for xy in base['canonical_pins'].values())
    assert sides['canonical_pins']==by['pfd-sides-permuted']['canonical_pins']
    assert all(sides['canonical_pins'][k][0]<0 for k in ('a','b'))
    assert all(sides['canonical_pins'][k][0]>0 for k in ('qa','qb'))
    assert by['pfd-sides-mirrored-fixed']['canonical_pins']==sides['canonical_pins']
    held=by['pfd-sides-mirrored-fixed']['device'];assert held['pos']==[-1200,-1200] and held['rot']==1 and held['mirror']
    assert by['pfd-pininfo']['svg_sha256']==base['svg_sha256']
    assert all(xy[0]>0 for xy in by['dac-o-sides']['canonical_pins'].values())
    assert by['xor-base']['body']==by['xor-pininfo-conflict']['body']=='polygonal_curve'
    assert by['xor-base']['svg_sha256']==by['xor-pininfo-conflict']['svg_sha256']
    assert all(by[n]['body']=='box' for n in ('xor-extra-control','xor-unknown-family','xor-side-override'))
    result=dict(binary=rel(BIN),binary_sha256=sha(BIN),runs=rows,
                code_read_only_plugin_relations=[
                  'PFD without PININFO: all names fall through portDir to inout, so boxLayout assigns all right; this is not an executed plugin observation.',
                  'PFD with A:I B:I QA:O QB:O: boxLayout produces the two left/two right arrangement; native ignores the comment and remains all left.',
                  'XOR with A:O or Y:I: boxPins rejects the conventional glyph because explicit directions disagree; native ignores PININFO and retains XOR.',
                  'Explicit side directives prevent a conventional glyph in both blockFor and boxPins; registered caller library symbols precede generated choices.'],
                dependencies={rel(x):sha(x) for x in [Path(__file__),HERE/'sixth-symbols-proof.py',ROOT/'tools/schemify/recognize.zig',ROOT/'tools/schemify/spice.zig',ROOT/'src/library.zig']})
    result=json.loads(json.dumps(result))
    if args.check:assert result==json.loads(args.check.read_text())
    args.output.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps(dict(runs=len(rows),names=list(by),complete_X_calls=sum(len(r['all_calls']) for r in rows))))

if __name__=='__main__':main()
