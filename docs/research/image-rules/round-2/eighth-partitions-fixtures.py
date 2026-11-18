#!/usr/bin/env python3
"""Frozen caller distribution controls; reads complete outer ordered bindings."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
RUN = ROOT / '.objective/human-schematic-equivalence/runs/iteration21-resume1/image-rule-round-2/ports/eighth-partitions'
BINARY = ROOT / '.objective/human-schematic-equivalence/runs/iteration21-resume1/resistor-output-integrated-common/zig-out/bin/cktimg-json'
CASES = [('1080-base',1080,''),('928-base',928,''),('921-base',921,''),('1479-base',1479,''),
         ('1080-wire-net0',1080,'*@ wire net0'),('1080-wire-fn1',1080,'*@ wire fn1'),
         ('1080-label-fn1',1080,'*@ label fn1'),('1080-rail-each',1080,'*@ rail VDD each'),
         ('1080-rail-bar',1080,'*@ rail VDD bar'),('928-label-vbias',928,'*@ label VBIAS'),
         ('928-wire-vbias',928,'*@ wire VBIAS')]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rel(path):
    return str(path.relative_to(ROOT))


def cards(text):
    defs, rows, scope = {}, {}, None
    for line in text.lower().splitlines():
        w = line.split()
        if not w or w[0].startswith('*'):
            continue
        if w[0] == '.subckt':
            assert scope is None and w[1] not in defs
            scope = w[1]
            defs[scope] = w[2:]
        elif w[0] == '.ends':
            assert scope == w[1]
            scope = None
        elif scope == 'dut':
            assert w[0] not in rows and w[0][0] in 'mqrxi'
            rows[w[0]] = w
    assert scope is None and 'dut' in defs
    return defs, rows


def bindings(native, defs, rows):
    actual = {d['name']: d for d in native['devices'] if d['name'] in rows}
    assert len(actual) == len(rows)
    result = []
    for name, row in sorted(rows.items()):
        dev = actual[name]
        if name[0] in 'mq':
            raw = row[1:5]
            assert [p['net'] for p in dev['pins']] == raw[:3]
            assert dev['bulk'] == raw[3]
        elif name[0] == 'x':
            formals = defs[row[-1]]
            raw = row[1:-1]
            assert len(raw) == len(formals)
            assert [p['net'] for p in dev['pins']] == raw
            assert [p['term'] for p in dev['pins']] == formals
        else:
            raw = row[1:3]
            assert [p['net'] for p in dev['pins']] == raw
        result.append(dict(name=name, card=row, raw_bindings=raw, actual=dev))
    return result


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--execute', action='store_true')
    ap.add_argument('--output', type=Path, default=HERE/'eighth-partitions-fixtures.json')
    ap.add_argument('--check', type=Path)
    args = ap.parse_args()
    assert sha(BINARY) == 'bf7b0749bde5822a68aa93fd9df69eb6e007dee0c24d5e9961ff65b187483560'
    RUN.mkdir(parents=True, exist_ok=True)
    result = []
    for name, number, hint in CASES:
        source = ROOT/f'external/examples/analoggenie/ag-{number}.cir'
        text = source.read_text()
        if hint:
            text = text.replace('.ends dut',hint+'\n.ends dut')
        deck = HERE/('eighth-partitions-'+name+'.cir')
        if deck.exists():
            assert deck.read_text() == text
        else:
            deck.write_text(text)
        prefix = RUN/name
        command = [str(BINARY),'--svg',str(prefix.with_suffix('.svg')),'--report',str(prefix.with_suffix('.report.json')),str(deck),str(prefix.with_suffix('.json'))]
        if args.execute:
            run = subprocess.run(command,cwd=ROOT,capture_output=True,text=True)
            assert run.returncode == 0,(name,run.stderr)
        native = json.loads(prefix.with_suffix('.json').read_text())
        report = json.loads(prefix.with_suffix('.report.json').read_text())
        defs, rows = cards(text)
        original_defs, original_rows = cards(source.read_text())
        assert defs == original_defs and rows == original_rows
        outputs = {suffix:dict(path=rel(prefix.with_suffix(suffix)),sha256=sha(prefix.with_suffix(suffix))) for suffix in ('.json','.svg','.report.json')}
        if not hint:
            expected = ROOT/f'docs/research/image-rules/figures/grouping/ag-{number}.native.svg'
            assert prefix.with_suffix('.svg').read_bytes() == expected.read_bytes()
        result.append(dict(name=name, source_id=number, source=rel(source), source_sha256=sha(source), deck=rel(deck), deck_sha256=sha(deck),
                           hint=hint,definitions=defs, complete_bindings=bindings(native,defs,rows),report=report,
                           outputs=outputs,command=[rel(Path(x)) if x.startswith(str(ROOT)) else x for x in command]))
    output = dict(binary=rel(BINARY),binary_sha256=sha(BINARY),script_sha256=sha(Path(__file__)),runs=result)
    if args.check:
        assert json.loads(args.check.read_text()) == output
    args.output.write_text(json.dumps(output,indent=2,sort_keys=True)+'\n')
    print(json.dumps(dict(runs=len(result),ordered_bindings=sum(len(b['raw_bindings']) for r in result for b in r['complete_bindings']))))


if __name__ == '__main__':
    main()
