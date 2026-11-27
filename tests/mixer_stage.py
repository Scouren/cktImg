"""Compare ordered MOS channel positions to the independently traced AG517 switching bank."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile


def relations(pins, alias=None):
    """Use physical D/S and both passive tips. Roles follow the published drawing."""
    alias = alias or {}
    def part(name):
        return pins[alias.get(name, name)]
    def center(name):
        row = part(name)
        end = 2 if name.startswith('m') else 1
        return tuple((a+b)/2 for a,b in zip(row[0],row[end]))
    inputs = [center(n) for n in ('m1', 'm2')]
    names = ('m4', 'm3', 'm5', 'm6')
    bank = [center(n) for n in names]
    xs = [p[0] for p in bank]
    loads = [(center(r),center(l)) for r,l in [('r1','l1'),('r2','l2')]]
    return {'input_pair_left': max(p[0] for p in inputs) < min(xs),
            'one_switch_row': len({p[1] for p in bank}) == 1,
            'separate_input_stage': inputs[0][1] == inputs[1][1] < bank[0][1],
            'nested_sources': min(xs[0], xs[3]) < min(xs[1], xs[2]) < max(xs[1], xs[2]) < max(xs[0], xs[3]),
            'outward_gates': all((part(n)[1][0] < center(n)[0]) == (i<2) for i,n in enumerate(names)),
            'bias_above_inputs': all(center(n)[0]==p[0] and center(n)[1]<p[1] for n,p in zip(('i1','i2'), inputs)),
            'horizontal_bridge': part('rs')[0][1]==part('rs')[1][1] and min(inputs[0][0],inputs[1][0])<center('rs')[0]<max(inputs[0][0],inputs[1][0]),
            'paired_loads_above_bank': all(r[1]==l[1]<bank[0][1] and min(r[0],l[0])<=x<=max(r[0],l[0]) for (r,l),x in zip(loads,(xs[0],xs[-1]))),
            'sinks_below_switches': all(center(n)[1]>bank[0][1] and center(n)[0] in xs for n in ('i3','i4'))}


def main(executable, path):
    path = Path(path)
    with tempfile.TemporaryDirectory() as tmp:
        d = Path(tmp)
        def run(text):
            (d/'input.cir').write_text(text)
            subprocess.run([executable, '--report', d/'report', d/'input.cir', d/'out'], check=True)
            assert not json.loads((d/'report').read_bytes())['gates']
            from source_bridge import native_records
            return native_records(json.loads((d/'out').read_bytes()))[0]
        source = path.read_text()
        passed = relations(run(source))
        assert all(passed.values()), passed
        # Preserve original formal ordering, reverse every card and rename
        # all devices/private nets while transporting the independent roles.
        names = {}
        lines = source.splitlines()
        cards = [line.split() for line in lines if line and line[0] in 'MRLI']
        for i, w in enumerate(cards):
            names[w[0].lower()] = w[0][0].lower() + str(i * 17 + 31)
        nets = {'p':'a77', 'q':'b90', 'net0':'nn4', 'net1':'nn7'}
        rev = iter(' '.join([names[w[0].lower()], *(nets.get(t.lower(), t) for t in w[1:])]) for w in reversed(cards))
        shuffled = '\n'.join(next(rev) if line and line[0] in 'MRLI' else line for line in lines) + '\n'
        assert all(relations(run(shuffled), names).values())
        for edited in [source.replace('I4 Q VSS DC 1m', 'I4 Q VSS DC 2m'),
                       source.replace('M4 VRF+ LO Q', 'M4 VRF+ CLK Q'),
                       source.replace('R2 VDD VRF- 1k', 'R2 VDD VRF- 2k'),
                       source.replace('.ends dut', 'M7 VRF+ LO Q VSS nch w=2\n.ends dut')]:
            assert not all(relations(run(edited)).values())
        explicit = run(source.replace('.ends dut', '*@ at m1 100 100 R0\n.ends dut'))
        assert not all(relations(explicit).values())


if __name__ == '__main__':
    if sys.argv[1]=='--host':
        from source_bridge import host_records
        result = relations(host_records(Path(sys.argv[2]),Path(sys.argv[3]))[0])
        assert all(result.values()), result
    else:
        main(*sys.argv[1:])
