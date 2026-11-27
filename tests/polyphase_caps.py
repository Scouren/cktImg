"""Check actual capacitor tips against the AG493 redraw and the literal ordered cards."""
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile


def run(binary, deck, extra=()):
    with tempfile.TemporaryDirectory() as tmp:
        src, out, report = [Path(tmp) / f for f in ('input.cir', 'out.json', 'report.json')]
        src.write_text(deck)
        subprocess.run([binary, *extra, '--report', report, src, out], check=True, capture_output=True)
        data = json.loads(out.read_text())
        assert not json.loads(report.read_text())['gates']
        return {d['name']: d for d in data['devices']}


def check(devices, human):
    by_name = {d['card']: d for d in human['devices']}
    origins = set()
    for name, expected in by_name.items():
        got = devices[name]
        origins.add(tuple(got['pos'][i] - expected[k] for i, k in enumerate(('x', 'y'))))
        assert [p['net'] for p in got['pins']] == list(expected['nets'].values()), name
        ordered = list(expected['terminals'].values())
        for p, ref in zip(got['pins'], ordered):
            for i, k in enumerate(('x', 'y')):
                assert p['xy'][i] - got['pos'][i] == round(ref[i] - expected[k]), (name, p, ref)
    assert len(origins) == 1, origins


def main(binary, deck, reference, control):
    source = deck.read_text()
    human = json.loads(reference.read_text())
    check(run(binary, source), human)
    # Reordering cards cannot select a different place or reverse a polarized
    # terminal. A renamed or split internal net cannot qualify on appearance.
    cards = [s for s in source.splitlines() if s.startswith(('R', 'C'))]
    inverse = iter(cards[::-1])
    shuffled = '\n'.join(next(inverse) if s in cards else s for s in source.splitlines()) + '\n'
    check(run(binary, shuffled), human)
    reversed_gold = copy.deepcopy(human)
    reversed_cards = source
    for name in ('C2', 'R5'):
        row = next(l for l in source.splitlines() if l.startswith(name + ' '))
        words = row.split()
        words[1], words[2] = words[2], words[1]
        reversed_cards = reversed_cards.replace(row, ' '.join(words))
        expected = next(d for d in reversed_gold['devices'] if d['name'] == name)
        for key in ('nets', 'terminals'):
            expected[key]['1'], expected[key]['2'] = expected[key]['2'], expected[key]['1']
    check(run(binary, reversed_cards), reversed_gold)
    for contrary in (source.replace('C5 net0', 'C5 split'), source.replace('.ends dut', '*@ class C1 cap\n.ends dut'),
                     source.replace('.ends dut', '*.PININFO Vin1:O\n.ends dut'), control.read_text()):
        devices = run(binary, contrary)
        assert all(d['class'] != 'cap_oblique' for d in devices.values())


if __name__ == '__main__':
    main(sys.argv[1], *map(Path, sys.argv[2:]))
