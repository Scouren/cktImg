"""Measure the two-arm degeneration bridge from emitted contacts and wire ink."""
import json
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile


def transformed(p, origin, orientation):
    x, y = p
    if orientation.startswith('M'):
        x = -x
    for _ in range(int(orientation.lstrip('M')[1:]) // 90):
        x, y = -y, x
    return origin[0] + x, origin[1] + y


def host_records(core, comp):
    lines = comp.read_text().splitlines()
    by_name, paths = {}, []
    for i, row in enumerate(lines):
        f = shlex.split(row)
        if not f:
            continue
        if f[0] == 'wire':
            p = list(map(int, f[2:]))
            paths.append(list(zip(p[::2], p[1::2])))
        if f[0] != 'inst':
            continue
        glyph = core / (f[2].split(':')[1] + '.shprim')
        pins = [tuple(map(int, p[3:5])) for s in glyph.read_text().splitlines() if (p := s.split()) and p[0] == 'pin']
        _, x, y, orientation = lines[i + 1].split()
        _, name = lines[i + 2].split()
        by_name[name.lower()] = [transformed(pin, (int(x), int(y)), orientation) for pin in pins]
    return by_name, paths


def native_records(doc):
    devices = {d['name']: [tuple(p['xy']) for p in d['pins']] for d in doc['devices']}
    paths = [path for w in doc['wires'] for path in w['segments']]
    return devices, paths


def check(records, sign=1, ids=('m1', 'm2', 'rs', 'rs2', 'm3', 'r1', 'r2'), outer_pins=(0, 1)):
    pins, paths = records
    edges = set()
    for path in paths:
        for a, b in zip(path, path[1:]):
            delta = [b[i] - a[i] for i in range(2)]
            assert (delta[0] == 0) != (delta[1] == 0)
            current = tuple(a)
            for _ in range(max(map(abs, delta))):
                other = tuple(current[i] + (1 if v > 0 else -1 if v < 0 else 0) for i, v in enumerate(delta))
                edges.add(tuple(sorted((current, other))))
                current = other
    def run(a, b):
        a, b = sorted((a, b))
        if a == b or (a[0] != b[0] and a[1] != b[1]):
            return False
        delta = (int(a[0] != b[0]), int(a[1] != b[1]))
        while a != b:
            next_pt = a[0] + delta[0], a[1] + delta[1]
            if (a, next_pt) not in edges:
                return False
            a = next_pt
        return True
    a, b, ar, br, tail, al, bl = [pins[n] for n in ids]
    if (a[0][1] >= a[2][1]) != (sign < 0) or (b[0][1] >= b[2][1]) != (sign < 0):
        return False
    center_x = tail[0][0]
    if center_x * 2 != a[2][0] + b[2][0] or ar[0][1] != br[0][1]:
        return False
    for branch, resistor, load, outer_idx in zip((a, b), (ar, br), (al, bl), outer_pins):
        outer, inner = resistor[outer_idx], resistor[1 - outer_idx]
        tee, corner = (center_x, outer[1]), (branch[2][0], outer[1])
        if (outer[1] != inner[1] or not abs(outer[0] - center_x) > abs(inner[0] - center_x) > 0
                or (outer[1] - branch[2][1]) * sign <= 0 or (tail[0][1] - outer[1]) * sign <= 0
                or branch[0][0] != load[0][0] or load[0][0] != load[1][0]
                or not all((run(branch[2], corner), run(corner, outer), run(inner, tee), run(tee, tail[0])))):
            return False
    return True


def native(binary, file, single, symbols, repeat, human):
    source = file.read_text()
    with tempfile.TemporaryDirectory() as tmp:
        src, out, report = [Path(tmp) / n for n in ('input.cir', 'drawing.json', 'report.json')]
        def draw(text):
            src.write_text(text)
            subprocess.run([binary, '--report', report, src, out], check=True)
            assert not json.loads(report.read_text())['gates']
            return native_records(json.loads(out.read_text()))
        assert check(draw(source))
        # AMS-Net 530 stores both arms with their ends reversed. Its independently
        # available gallery redrawing supplies actual paths and D/G/S ordering.
        ids = ('m1', 'm2', 'rs1', 'rs2', 'm3', 'r11', 'r12')
        repeated = json.loads(human.read_text())
        contacts = {d['name'].lower(): [tuple(xy) for xy in d['terminals'].values()] for d in repeated['devices']}
        paths = [s for w in repeated['wires'] for s in w['segments']]
        assert check((contacts, paths), ids=ids, outer_pins=(1, 0))
        assert check(draw(repeat.read_text()), ids=ids, outer_pins=(1, 0))
        dual = source.replace('VDD', 'tmp').replace('VSS', 'VDD').replace('tmp', 'VSS').replace('nch', 'pch').replace('nmos', 'pmos')
        assert check(draw(dual), -1)
        # No stage role derives from the order or spelling of any device card.
        cards = [l.split() for l in source.splitlines() if l.startswith(('M', 'R'))]
        alias = {w[0].lower(): w[0][0].lower() + str(i + 71) for i, w in enumerate(cards)}
        reversed_cards = iter(' '.join([alias[w[0].lower()], *w[1:]]) for w in reversed(cards))
        reversed_deck = '\n'.join(next(reversed_cards) if l.startswith(('M', 'R')) else l for l in source.splitlines()) + '\n'
        ids = [alias[n] for n in ('m1', 'm2', 'rs', 'rs2', 'm3', 'r1', 'r2')]
        assert check(draw(reversed_deck), ids=ids)
        reversed_ends = source.replace('RS net2 net1', 'RS net1 net2').replace('RS2 net1 net0', 'RS2 net0 net1')
        assert check(draw(reversed_ends), outer_pins=(1, 0))
        for old, new in [('RS2 net1 net0 1k', 'RS2 net1 net0 2k'), ('RS2 net1 net0 1k', 'RS2 VSS net0 1k'),
                         ('R2 VDD Vout2 1k', 'R2 VDD Vout2 2k'), ('Vin1 net2 VSS', 'VDD net2 VSS'),
                         ('Vb VSS VSS', 'Vout1 VSS VSS'), ('.ends dut', '*@ upright RS\n.ends dut')]:
            assert not check(draw(source.replace(old, new))), (old, new)
        # A target manifest changes the pin lookup side table only. A separately
        # allocated library with the same active frames also preserves geometry.
        src.write_text(source)
        subprocess.run([binary, src, out], check=True)
        original = json.loads(out.read_text())
        target = Path(tmp) / 'pins.json'
        target.write_text(json.dumps({'version': 1, 'target': 'wire-test', 'unmapped': {'mode': 'skip'},
                                     'classes': {'res': {'sym': 'resistor', 'pins': ['b', 'a']}}}))
        subprocess.run([binary, '--target', target, src, out], check=True)
        projected = json.loads(out.read_text())
        mapping = projected.pop('target')
        assert projected == original
        assert {row['name']: row['pins'] for row in mapping['devices']} == {n: [1, 0] for n in ('rs', 'rs2', 'r1', 'r2')}
        stock = symbols.read_text()
        library = Path(tmp) / 'own.zon'
        previous = Path(tmp) / 'previous.json'
        previous.write_text('{"devices":[]}')
        def edit_class(name, change):
            rows = stock.splitlines()
            index = next(i for i, line in enumerate(rows) if '.name = "' + name + '", .terminals' in line)
            old = rows[index]
            rows[index] = change(old)
            assert old != rows[index]
            return '\n'.join(rows) + '\n'
        def long_ink(line):
            return line.replace('.draw = .{', '.draw = .{ .{ .line = .{ .a = .{ .x = 0, .y = 5 }, .b = .{ .x = 0, .y = 85 } } },', 1)
        def edited(*opts):
            subprocess.run([binary, '--symbols', library, *opts, src, out], check=True)
            return json.loads(out.read_text())
        for equivalent in ['// independently supplied\n' + stock, edit_class('cap', long_ink)]:
            library.write_text(equivalent)
            assert edited() == original
        for name, change in [
            ('nmos', lambda l: l.replace('.name = "g", .at = .{ .x = 0,', '.name = "g", .at = .{ .x = 7,', 1)),
            ('res', lambda l: l.replace('.name = "a", .at', '.name = "a", .hidden = true, .at', 1)),
            ('res', long_ink),
        ]:
            library.write_text(edit_class(name, change))
            current = edited()
            incumbent = edited('--from', previous)
            assert current == incumbent, (name, 'unsupported frame changed the ordinary drawing')
        # The incumbent one-resistor bridge remains horizontal with two distinct
        # current sources below it, one per input. It has no shared MOS tail.
        parts, _ = draw(single.read_text())
        assert parts['rs'][0][1] == parts['rs'][1][1]
        assert parts['iss1'][0][1] > parts['m1'][2][1] and parts['iss2'][0][1] > parts['m2'][2][1]


if __name__ == '__main__':
    if sys.argv[1] == '--host':
        assert check(host_records(Path(sys.argv[2]), Path(sys.argv[3])))
    else:
        native(sys.argv[1], *(Path(name) for name in sys.argv[2:]))
