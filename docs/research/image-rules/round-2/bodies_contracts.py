#!/usr/bin/env python3
"""Run frozen CLI with three caller symbol contracts; no engine compilation."""
import argparse
import json
from pathlib import Path
import subprocess
from bodies_census import ROOT, BASE, sha
from bodies_examples import native_binding


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('output',type=Path)
    args=ap.parse_args(); args.output=args.output.resolve()
    run=args.output.parent/'contracts';run.mkdir(parents=True,exist_ok=True)
    binary=BASE/'resistor-output-integrated-common/zig-out/bin/cktimg-json'
    original=BASE/'resistor-output-integrated-common/tests/symbols.zon'
    text=original.read_text()
    source=run/'literal.cir'
    source.write_text('literal fourth terminal\n.model nm nmos\n.subckt dut d g s b\nM1 d g s b nm\nR1 b 0 1k\n.ends dut\n')
    cases=[]
    for mode in ('three','four_visible','four_hidden'):
        lines=text.splitlines()
        if mode!='three':
            k=next(i for i,line in enumerate(lines) if '.name = "nmos",' in line)
            old='.name = "s", .at = .{ .x = -20, .y = 0 } }'
            new=old+', .{ .name = "b", .at = .{ .x = 0, .y = 20 }, .hidden = '+('true' if mode=='four_hidden' else 'false')+' }'
            assert lines[k].count(old)==1
            lines[k]=lines[k].replace(old,new)
            anchor='.draw = .{'
            lines[k]=lines[k].replace(anchor,anchor+' .{ .line = .{ .a = .{ .x = 0, .y = -3 }, .b = .{ .x = 0, .y = 20 } } },',1)
        symbols=run/(mode+'.zon');symbols.write_text('\n'.join(lines)+'\n')
        output=run/(mode+'.json');svg=run/(mode+'.svg')
        subprocess.run([str(binary),'--symbols',str(symbols),'--svg',str(svg),str(source),str(output)],check=True)
        doc=json.loads(output.read_text());m=next(d for d in doc['devices'] if d['name']=='m1')
        native_binding(m,['d','g','s','b'])
        assert len(m['pins'])==(3 if mode=='three' else 4)
        body=m['pins'][3]['xy'] if len(m['pins'])==4 else None
        touch=[]
        for wire in doc['wires']:
            if wire['net']=='b':
                touch += [poly for poly in wire['segments'] if body in poly]
        assert bool(touch)==(mode=='four_visible')
        cases.append(dict(mode=mode,ordered_DGSB_preserved=True,body_xy=body,
                          body_has_route_endpoint=bool(touch),mos_json=m,
                          files={str(p.relative_to(ROOT)):sha(p) for p in (source,symbols,output,svg)}))
    args.output.write_text(json.dumps(dict(binary_sha256=sha(binary),baseline_symbols_sha256=sha(original),
        script_sha256=sha(Path(__file__)),cases=cases,
        limitation='CLI/JSON/actual class drawing contract only; no C ABI execution or Schemify roundtrip'),indent=2)+'\n')
    print('PASS literal DGSB with absent, visible, and hidden fourth class terminal; only visible fourth terminal routed')


if __name__=='__main__':main()
