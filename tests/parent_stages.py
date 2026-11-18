"""Check full-DUT local MOS organization against the two frozen symbol families.

The default invocation consumes cktimg-json and the five circuit paths. With
--host, consume the actual core glyph directory and a directory of imported
ag-<id>/n2s/dut.shcomp projects for all four positive circuits.
"""
import json
from pathlib import Path
import subprocess
import sys
import tempfile


# Input polarity, the paired inputs, their loads in branch order and the tail.
STAGES = {
    'ag-1028': [(1, 'm1', 'm2', 'm3', 'm4', 'm5')],
    'ag-1046': [(1, 'm1', 'm2', 'm3', 'm4', 'mtail1')],
    'ag-1071': [(-1, 'm2', 'm3', 'm4', 'm5', 'm1')],
    'ag-1079': [(1, 'm1', 'm2', 'm3', 'm4', 'm5')],
    'ag-1080': [(1, 'm1', 'm2', 'm3', 'm4', 'm5'), (-1, 'm11', 'm12', 'm13', 'm14', 'm10')],
}


def criteria(pins, stage, max_span):
    sign, *members = stage
    ends = [(pins[(name, 0)], pins[(name, 2)]) for name in members]
    (a, b, l, r, t) = [(d[0], (d[1] + s[1]) / 2) for d, s in ends]
    return {
        'signed_contacts': all(d[0] == s[0] and (s[1] - d[1]) * (-sign if i in (2, 3) else sign) > 0
                               for i, (d, s) in enumerate(ends)),
        'paired_columns': a[0] == l[0] and b[0] == r[0] and a[0] != b[0],
        'level_rows': a[1] == b[1] and l[1] == r[1],
        'interior_tail': min(a[0], b[0]) < t[0] < max(a[0], b[0]),
        'vertical_order': (a[1] - l[1]) * sign > 0 and (t[1] - a[1]) * sign > 0,
        'compact': abs(a[0] - b[0]) <= max_span[0] and max(p[1] for p in (a, b, l, r, t))
                   - min(p[1] for p in (a, b, l, r, t)) <= max_span[1],
    }



def panel_order(pins, name, aliases=None):
    if name not in ('ag-1079', 'ag-1080'):
        return
    aliases = aliases or {}
    def channel(i):
        n = 'm' + str(i)
        a, b = (pins[(aliases.get(n, n), t)] for t in (0, 2))
        return (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
    # Frozen upstream Book1079/Book1080. Both put a differential stage on
    # the left and its complementary receiving stacks on the right. The
    # NMOS-input row is uppermost when both input polarities occur.
    panels = [[(1, 2, 3, 4, 5), ((8, 6), (9, 7))]]
    if name == 'ag-1080':
        panels.append([(10, 11, 12, 13, 14), ((15, 17), (16, 18))])
    rows = []
    for members, stacks in panels:
        left = [channel(i) for i in members]
        right = []
        for top, bottom in stacks:
            a, b = channel(top), channel(bottom)
            assert a[0] == b[0] and a[1] < b[1], (name, 'receiving column', top, bottom, a, b)
            right.extend((a, b))
        assert max(p[0] for p in left) < min(p[0] for p in right), (name, 'successive stages share a row', left, right)
        assert max(min(p[1] for p in side) for side in (left, right)) < min(max(p[1] for p in side) for side in (left, right))
        rows.append(left + right)
    lower = range(11, 21) if name == 'ag-1079' else range(19, 33)
    rows.append([channel(i) for i in lower])
    for before, after in zip(rows, rows[1:]):
        assert max(p[1] for p in before) < min(p[1] for p in after), (name, 'independent tiers', before, after)


def native_pins(doc):
    terms = {'d': 0, 's': 2}
    return {(d['name'], terms[p['term']]): p['xy'] for d in doc['devices'] for p in d['pins'] if p['term'] in terms}


def renamed_reversed(source):
    lines = source.splitlines()
    devices = [line.split() for line in lines if line.startswith('M')]
    names = {w[0].lower(): f'mnew{i * 19 + 11}' for i, w in enumerate(devices)}
    reversed_cards = iter(' '.join([names[w[0].lower()], *w[1:]]) for w in reversed(devices))
    return '\n'.join(next(reversed_cards) if line.startswith('M') else line for line in lines) + '\n', names


def native(binary, paths):
    assert set(STAGES) == {Path(p).stem for p in paths}
    with tempfile.TemporaryDirectory() as tmp:
        for file in map(Path, paths):
            out = Path(tmp) / 'drawing.json'
            report = Path(tmp) / 'report.json'
            subprocess.run([binary, '--report', report, file, out], check=True)
            pins = native_pins(json.loads(out.read_bytes()))
            assert not json.loads(report.read_bytes())['gates'], file
            panel_order(pins, file.stem)
            for stage in STAGES[file.stem]:
                result = criteria(pins, stage, (140, 150))
                assert all(result.values()) == (file.stem != 'ag-1028'), (file, stage, result)
            if file.stem != 'ag-1028':
                source, names = renamed_reversed(file.read_text())
                renamed = Path(tmp) / 'renamed.cir'
                renamed.write_text(source)
                subprocess.run([binary, '--report', report, renamed, out], check=True)
                assert not json.loads(report.read_bytes())['gates'], file
                pins = native_pins(json.loads(out.read_bytes()))
                panel_order(pins, file.stem, names)
                for sign, *members in STAGES[file.stem]:
                    result = criteria(pins, [sign, *(names[n] for n in members)], (140, 150))
                    assert all(result.values()), (file, members, result)
            if file.stem == 'ag-1046':
                for directive in ['axis missing_device', 'imaginary verb', 'refdes m9 right', 'at m9 -40 -40 R0']:
                    amended = Path(tmp) / 'request.cir'
                    amended.write_text(file.read_text().replace('.ends dut', f'*@ {directive}\n.ends dut'))
                    subprocess.run([binary, '--report', report, amended, out], check=True)
                    drawing = json.loads(out.read_bytes())
                    actual = next(r for r in json.loads(report.read_bytes())['requests']
                                  if r['text'] == '*@ ' + directive.lower())
                    expected = 'rejected' if directive.startswith(('axis', 'imaginary')) else 'honoured'
                    assert actual['state'] == expected, (directive, actual)
                    result = criteria(native_pins(drawing), STAGES[file.stem][0], (140, 150))
                    assert all(result.values()), (directive, result)
            if file.stem == 'ag-1080':
                held = Path(tmp) / 'held.cir'
                held.write_text(file.read_text().replace('.ends dut', '*@ at m5 -40 -40 R270\n.ends dut'))
                subprocess.run([binary, '--report', report, held, out], check=True)
                requests = json.loads(report.read_bytes())['requests']
                assert any(r['text'] == '*@ at m5 -40 -40 r270' and r['state'] == 'honoured' for r in requests), requests
                devices = {d['name']: d for d in json.loads(out.read_bytes())['devices']}
                assert devices['m5']['pos'] == [-1600, -1600], devices['m5']


def host(core, projects):
    from parent_output_routes import host_geometry, verify
    for name, stages in STAGES.items():
        if name == 'ag-1028':
            continue
        geom = host_geometry(Path(projects) / name / 'n2s/dut.shcomp', Path(core))
        for stage in stages:
            result = criteria(geom[1], stage, (280, 210))
            assert all(result.values()), (name, stage, result)
        panel_order(geom[1], name)
        if name in ('ag-1079', 'ag-1080'):
            verify(name, *geom, True)


if __name__ == '__main__':
    if sys.argv[1] == '--host':
        host(*sys.argv[2:])
    else:
        native(sys.argv[1], sys.argv[2:])
