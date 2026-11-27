"""Original ordered-incidence oracle for bounded degeneration attachments."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile


# Hand-traced source members and attachments. Direct-source relations record
# their complete raw occurrences, without awarding the outside drain as a tail.
EXPECTED = {
    'ag-220': [(('m1', 'm2'), 'equal_arms_tail', ('rs', 'rs2', 'm3'))],
    'ag-396': [(('m1', 'm2'), 'paired_rail_sources', ('rs', 'iss1', 'iss2'))],
    'ag-459': [(('m1', 'm2'), 'paired_rail_sources', ('r1', 'i1', 'i2')),
               (('m3', 'm4'), 'paired_rail_sources', ('r2', 'i3', 'i4'))],
    'ag-517': [(('m1', 'm2'), 'paired_rail_sources', ('rs', 'i1', 'i2')),
               (('m3', 'm5'), 'direct_source', ()), (('m4', 'm6'), 'direct_source', ())],
    'ag-558': [(('m1', 'm2', 'm3'), 'other_source_count', ()), (('m4', 'm5', 'm6'), 'other_source_count', ())],
    'ag-718': [(('m1', 'm2'), 'paired_rail_sources', ('r1', 'i1', 'i2')),
               (('m3', 'm4'), 'paired_rail_sources', ('r2', 'i3', 'i4'))],
}


def card_occurrences(text, nets):
    result = []
    for line in text.lower().splitlines():
        w = line.split()
        if not w or w[0][0] not in 'mrilc' or line.startswith('.'):
            continue
        for i, n in enumerate(w[1:5] if w[0].startswith('m') else w[1:3]):
            if n in nets:
                result.append((w[0], i, n))
    return sorted(result)


def check(binary, paths):
    def run(file):
        return json.loads(subprocess.check_output([binary, file], text=True))

    paths = {Path(p).stem: Path(p) for p in paths}
    assert set(paths) == set(EXPECTED)
    with tempfile.TemporaryDirectory() as temp:
        scratch = Path(temp) / 'test.cir'
        for case, file in paths.items():
            source = file.read_text()
            actual = run(file)
            assert actual['source_region_scope'] == 'selected_cell'
            seen = {tuple(sorted(r['members'])): r for r in actual['source_regions']}
            assert set(seen) == {k for k, _, _ in EXPECTED[case]}, case
            for core, decision, attachments in EXPECTED[case]:
                row = seen[core]
                assert row['disposition'] == decision, (case, row)
                assert sorted(row['owned']) == (sorted((*core, *attachments)) if attachments else []), (case, row)
                cards = {w[0].lower(): w for l in source.lower().splitlines() if (w := l.split())}
                proof = {c['device']: c for c in row['attachment_cards']}
                assert set(proof) == set(attachments), (case, proof)
                for name, record in proof.items():
                    width = 4 if name.startswith('m') else 2
                    w = cards[name]
                    assert record['ordered_nets'] == w[1:1 + width], (case, record)
                    params = [a for t in w[1 + width:] for a in t.replace('=', ' = ').split()]
                    assert record['parameters'] == params, (case, record)
                terminals = {w[0].lower(): w[3].lower() for line in source.splitlines() if (w := line.split()) and w[0].startswith('M')}
                nets = {terminals[k] for k in core}
                if case == 'ag-220':
                    nets.add('net1')
                assert sorted(map(tuple, row['incidence'])) == card_occurrences(source, nets), (case, row)
            # Device order and the spelling of every device/internal net carry
            # no source-membership information. Preserve distinguished rails.
            cards = [l.split() for l in source.splitlines() if l and l[0].upper() in 'MRILC']
            aliases = {w[0].lower(): w[0][0].lower() + str(i + 100) for i, w in enumerate(reversed(cards))}
            aliases.update({n: 'opaque_' + str(i) for i, n in enumerate(sorted({w.lower() for c in cards for w in c[1:5] if w.lower().startswith('net')}))})
            mapped = [' '.join(aliases.get(w.lower(), w) for w in c) for c in reversed(cards)]
            it = iter(mapped)
            raw = '\n'.join(next(it) if l and l[0].upper() in 'MRILC' else l for l in source.splitlines()) + '\n'
            scratch.write_text(raw)
            rev = {v: k for k, v in aliases.items()}
            normalized = {}
            for row in run(scratch)['source_regions']:
                core = tuple(sorted(rev[n] for n in row['members']))
                normalized[core] = (row['disposition'], sorted(rev[n] for n in row['owned']),
                                    sorted((rev[n], i, rev.get(net, net)) for n, i, net in row['incidence']))
            assert normalized == {c: (r['disposition'], sorted(r['owned']), sorted(map(tuple, r['incidence']))) for c, r in seen.items()}, case
            if case == 'ag-459':
                changes = [
                    ('I1 net0 VSS DC 1m', 'I1 net0 VSS DC 2m'),
                    ('I1 net0 VSS DC 1m', 'I1 VSS net0 DC 1m'),
                    ('I1 net0 VSS DC 1m', 'I1 net0 net2 DC 1m'),
                    ('R1 net0 net1 1k', 'R1 net0 net1 1k\nCextra net0 VSS 1p'),
                    ('M2 Voutn Vin1n net1 VSS', 'M2 Voutn Vin1n net1 net0'),
                ]
                for i, (old, new) in enumerate(changes):
                    assert old in source
                    scratch.write_text(source.replace(old, new))
                    rows = {tuple(sorted(r['members'])): r for r in run(scratch)['source_regions']}
                    assert rows['m1', 'm2']['owned'] == [], (new, rows)
                    sibling = rows['m3', 'm4']
                    assert bool(sibling['owned']) == (i != 2), (new, sibling)
                scratch.write_text(source.replace('.ends dut', 'Qx elsewhere bias VSS net0 qmod\n.ends dut'))
                assert run(scratch)['source_region_scope'] != 'selected_cell'
            if case == 'ag-220':
                scratch.write_text(source.replace('RS2 net1 net0 1k', 'RS2 net1 net0 2k'))
                assert run(scratch)['source_regions'][0]['disposition'] == 'unresolved'


if __name__ == '__main__':
    check(sys.argv[1], sys.argv[2:])
