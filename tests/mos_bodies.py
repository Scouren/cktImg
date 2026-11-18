"""Check MOS body occurrences against literal source cards and physical wire components."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile


def path_component(paths, start, contacts):
    segments = [(tuple(a), tuple(b)) for path in paths for a, b in zip(path, path[1:])]
    points = {start, *contacts, *(point for segment in segments for point in segment)}

    def on(point, a, b):
        return (a[0] == point[0] == b[0] and min(a[1], b[1]) <= point[1] <= max(a[1], b[1])
                or a[1] == point[1] == b[1] and min(a[0], b[0]) <= point[0] <= max(a[0], b[0]))

    seen = {start}
    while True:
        previous = len(seen)
        for a, b in segments:
            if any(on(point, a, b) for point in seen):
                seen.update(point for point in points if on(point, a, b))
        if len(seen) == previous:
            return seen


def occurrences(text):
    cards = text.lower().split('.subckt dut ', 1)[1].split('.ends', 1)[0].splitlines()[1:]
    return {words[0]: words[1:5] for card in cards if (words := card.split()) and words[0].startswith('m')}


def draw(binary, content, directory, extra=(), hints=''):
    deck, doc, report = [directory / name for name in ('deck.cir', 'draw.json', 'report.json')]
    deck.write_text(content.replace('.ends dut', hints + '\n.ends dut'))
    subprocess.run([binary, *extra, '--report', report, deck, doc], check=True, capture_output=True)
    drawing = json.loads(doc.read_text())
    devices = {d['name']: d for d in drawing['devices']}
    for name, pins in occurrences(content).items():
        dev = devices[name]
        emitted = [pin['net'] for pin in dev['pins']]
        if 'bulk' in dev:
            emitted.append(dev['bulk'])
        assert emitted == pins, (name, emitted, pins)
    return drawing, devices, json.loads(report.read_text())


def body(devices, name):
    dev = devices[name]
    assert [p['term'] for p in dev['pins']] == ['d', 'g', 's', 'b'], (name, dev)
    return tuple(dev['pins'][3]['xy'])


def well(drawing, devices, names, net, require_wire=False):
    contacts = [body(devices, name) for name in names]
    paths = [p for wire in drawing['wires'] if wire['net'] == net for p in wire['segments']]
    labels = {tuple(l['at']) for l in drawing['labels'] if l['net'] == net}
    pieces = [path_component(paths, p, set(contacts) | labels) for p in contacts]
    assert contacts[1] in pieces[0] or (not require_wire and all(piece & labels for piece in pieces)), (names, net, contacts, labels)
    assert all(dev['class'] not in ('ipin', 'opin') or dev['pins'][0]['net'] != net for dev in devices.values())


def main(binary, mixed, omitted, explicit, split, stock):
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        view, devices, report = draw(binary, mixed.read_text(), tmp)
        for name in ('m1', 'm2'):
            body(devices, name)
        for name in ('m3', 'm4'):
            assert devices[name]['bulk'] == 'vb', devices[name]
        for file, names, net in [(omitted, ('mp2', 'mp3'), 'net8'), (explicit, ('mp7', 'mp8'), 'net4'),
                                 (split, ('m3', 'm4'), 'net4')]:
            view, devices, _ = draw(binary, file.read_text(), tmp)
            well(view, devices, names, net)
        view, devices, report = draw(binary, omitted.read_text(), tmp,
                                     hints='*@ class mp2 pmos\n*@ class mp3 pmos')
        assert all(devices[n]['bulk'] == 'net8' for n in ('mp2', 'mp3'))
        class_requests = {r['text'].strip(): r['state'] for r in report['requests'] if 'class mp' in r['text']}
        assert len(class_requests) == 2 and set(class_requests.values()) == {'honoured'}
        rows = {(r['device'], r['net'], r['reason']) for r in report['unshown_bodies']}
        assert {('mp2', 'net8', 'no_contact'), ('mp3', 'net8', 'no_contact')} <= rows
        view, devices, _ = draw(binary, split.read_text(), tmp, hints='*@ wire net4')
        well(view, devices, ('m3', 'm4'), 'net4', require_wire=True)
        # Supplying only three terminals cannot create a fallback landing. Preserve
        # all source card occurrences, including the two self-source cases.
        compact = tmp / 'three.zon'
        compact.write_text('\n'.join(l for l in stock.read_text().splitlines() if '_body"' not in l))
        _, devices, report = draw(binary, mixed.read_text(), tmp, extra=('--symbols', compact))
        assert all(devices[n]['bulk'] == 'vb' for n in ('m1', 'm2', 'm3', 'm4'))
        assert {(r['device'], r['terminal'], r['net'], r['reason']) for r in report['unshown_bodies']} == {
            ('m1', 'b', 'vb', 'no_contact'), ('m2', 'b', 'vb', 'no_contact')}
        # A four-contact caller can suppress or expose B, also for B=S.
        lines = stock.read_text().splitlines()
        visible = next(l for l in lines if '.name = "nmos_body"' in l)
        visible = visible.replace('"nmos_body", .body_for = "nmos"', '"nmos"')
        for hidden in (True, False):
            replacement = visible.replace('.name = "b", .at =', '.name = "b", .hidden = true, .at =') if hidden else visible
            selected = tmp / 'caller.zon'
            selected.write_text('\n'.join(replacement if '.name = "nmos",' in l else l
                                          for l in lines if '_body"' not in l))
            _, devices, report = draw(binary, mixed.read_text(), tmp, extra=('--symbols', selected))
            assert all(devices[n]['pins'][3]['net'] == 'vb' for n in ('m1', 'm2', 'm3', 'm4'))
            reasons = {(r['device'], r['reason']) for r in report.get('unshown_bodies', [])}
            assert reasons == ({('m1', 'hidden'), ('m2', 'hidden')} if hidden else set())
        # Existing backend declares a three-terminal MOS. The added default
        # cannot change its arity or leave its physical body wires dangling.
        manifest = tmp / 'target.json'
        mapped = {'nmos': {'sym': 'custom/nmos', 'pins': ['s', 'g', 'd']}}
        for full in (False, True):
            if full:
                mapped['nmos_body'] = {'sym': 'custom/nmos4', 'pins': ['s', 'g', 'd', 'b']}
            manifest.write_text(json.dumps({'target': 'tester', 'version': 1, 'unmapped': {'mode': 'skip'}, 'classes': mapped}))
            view, devices, _ = draw(binary, mixed.read_text(), tmp, extra=('--target', manifest))
            exported = {d['name']: d['pins'] for d in view['target']['devices']}
            for n in ('m1', 'm2', 'm3', 'm4'):
                active = full and n in ('m1', 'm2')
                assert exported[n] == ([2, 1, 0, 3] if active else [2, 1, 0])
                assert ('bulk' not in devices[n]) == active
        # A mislabeled fourth terminal cannot register as the B capability.
        bad = tmp / 'wrong.zon'
        bad.write_text('\n'.join(l.replace('.name = "b",', '.name = "x",') if '_body"' in l else l for l in lines))
        rejected = subprocess.run([binary, '--symbols', bad, mixed], capture_output=True, text=True)
        assert rejected.returncode != 0 and 'IncompatibleBody' in rejected.stderr



if __name__ == '__main__':
    main(sys.argv[1], *map(Path, sys.argv[2:]))
