#!/usr/bin/env python3
"""Check the six published intermediate-output partitions and their controls.

native reads normal cktimg-json output. target imports the unchanged circuits
into Schemify, then reads its actual symbol anchors, wires, labels and netlist.
Both commands retain their source decks, generated output and per-case logs.
"""
import argparse
import json
from pathlib import Path
import shlex
import subprocess
from xml.etree import ElementTree

ROOT = Path(__file__).resolve().parents[1]
# Ordered names are PMOS drain, NMOS drain, and the gate in the next stage.
EXPECTED = {
    "ag-1053": {"net1": ("mp5", "mn5", "mp0"), "net3": ("mp4", "mn4", "mp1")},
    "ag-1079": {"rn": ("m9", "m7", "m11"), "rp": ("m8", "m6", "m12")},
    "ag-1080": {
        "rn": ("m9", "m7", "m27"), "rp": ("m8", "m6", "m28"),
        "fn1": ("m16", "m18", "m29"), "fp1": ("m15", "m17", "m31"),
    },
}
CASES = (*EXPECTED, "ag-1080-wire", "ag-1080-label")


def run(args, directory):
    result = subprocess.run(args, cwd=directory, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    with (directory / "commands.log").open("a") as log:
        log.write(shlex.join(map(str, args)) + "\n" + result.stdout + "\n")
    result.check_returncode()


def on(point, a, b):
    x, y = point
    if a[0] == b[0]:
        return x == a[0] and min(a[1], b[1]) <= y <= max(a[1], b[1])
    assert a[1] == b[1], (a, b)
    return y == a[1] and min(a[0], b[0]) <= x <= max(a[0], b[0])


def verify(case, segments, pins, markers, target):
    parent = list(range(len(segments)))

    def root(i):
        while i != parent[i]:
            i = parent[i]
        return i

    def location(point):
        hits = {root(i) for i, (a, b) in enumerate(segments) if on(point, a, b)}
        assert len(hits) <= 1, ("ambiguous crossing", point, hits)
        return next(iter(hits), ("point", tuple(point)))

    # A T contact has a wire endpoint. A proper crossing has none.
    for i, (a, b) in enumerate(segments):
        for j, (c, d) in enumerate(segments[:i]):
            if on(a, c, d) or on(b, c, d) or on(c, a, b) or on(d, a, b):
                parent[root(i)] = root(j)
    contacts = {key: location(point) for key, point in pins.items()}
    names = [(name, location(point)) for name, point in markers]
    family = "-".join(case.split("-")[:2])
    actual = {}
    for net, (p, n, g) in EXPECTED[family].items():
        keys = [(p, 0), (n, 0), (g, 1)]
        islands = {}
        for key in keys:
            islands.setdefault(contacts[key], []).append(key)
        expect = [keys[:2], keys[2:]]
        if family == "ag-1053" or (case.endswith("-wire") and net == "fn1"):
            expect = [keys]
        elif case.endswith("-label") and net == "fn1":
            expect = [[k] for k in keys]
        elif case != family and net == "fp1":
            # Caller intent on FN1 returns its reflected sibling to ordinary routing.
            expect = [keys] if target else [[k] for k in keys]
        canon = lambda groups: sorted(sorted(group) for group in groups)
        assert canon(islands.values()) == canon(expect), (case, net, islands, expect)
        assert {k for k, part in contacts.items() if part in islands} == set(keys), (case, net, "foreign pin")
        for part in islands:
            reachable = [name for name, i in names if i == part]
            assert all(name == net for name in reachable), (case, net, "foreign name", reachable)
            if len(islands) > 1:
                assert reachable == [net], (case, net, "each part needs one attached name", reachable)
        assert all(i in islands for name, i in names if name == net), (case, net, "detached name")
        actual[net] = len(islands)
    return actual


def native(case, args, project, deck):
    out = project / "drawing.json"
    svg = project / "drawing.svg"
    run([args.binary, "--svg", svg, deck, out], project)
    drawing = json.loads(out.read_text())
    spans = [segment for w in drawing["wires"] for path in w["segments"] for segment in zip(path, path[1:])]
    pins, marks = {}, [(label["net"], label["at"]) for label in drawing["labels"]]
    for dev in drawing["devices"]:
        if dev["class"] in ("gnd", "vdd", "ipin", "opin"):
            marks.append((dev["pins"][0]["net"], dev["pins"][0]["xy"]))
            continue
        for i, pin in enumerate(dev["pins"]):
            pins[dev["name"].lower(), i] = pin["xy"]
    result = verify(case, spans, pins, marks, False)
    visible = [e.text for e in ElementTree.parse(svg).iter("{http://www.w3.org/2000/svg}text")]
    for name, parts in result.items():
        if parts > 1:
            assert visible.count(name) == parts, (case, name, "visible SVG labels")
    return result


def core_pins(core, name):
    lines = [row.split() for row in (core / f"{name}.shprim").read_text().splitlines() if row.strip()]
    pins = {r[1]: tuple(map(int, r[3:5])) for r in lines if r[0] == "pin"}
    assert list(pins) == ["d", "g", "s", "b"], (name, pins)
    strokes = [(tuple(map(float, r[1:3])), tuple(map(float, r[3:5]))) for r in lines if r[0] == "line"]
    for tip in (pins[k] for k in ("d", "g", "s")):
        own = [s for s in strokes if tip in s]
        assert len(own) == 1, (name, tip)
        a, b = own[0]
        attach = b if a == tip else a
        assert any(on(attach, c, d) for c, d in strokes if (c, d) != (a, b)), (name, tip, attach)
    return list(pins.values())


def host_geometry(doc, core):
    glyphs = {f"core:{name}": core_pins(core, name) for name in ("nmos4", "pmos4")}
    spans, pins, marks, instances = [], {}, [], []
    inst = None
    for line in doc.read_text().splitlines():
        t = shlex.split(line)
        if not t:
            continue
        if not line[0].isspace():
            inst = None
        if t[0] == "inst":
            inst = {"class": t[-1]}
            instances.append(inst)
        elif inst is not None and t[0] in ("at", "name"):
            inst[t[0]] = t[1:]
        elif t[0] == "wire":
            values = list(map(int, t[2:]))
            assert len(values) >= 4 and len(values) % 2 == 0
            points = list(zip(values[::2], values[1::2]))
            spans.extend(zip(points, points[1:]))
        elif t[0] in ("port", "label"):
            marks.append((t[-1].lower(), tuple(map(int, t[2:4]))))
    for inst in instances:
        ax, ay, ori = inst["at"]
        for i, (x, y) in enumerate(glyphs[inst["class"]]):
            if ori.startswith("M"):
                x = -x
            for _ in range(int(ori.lstrip("M")[1:]) // 90):
                x, y = -y, x
            pins[inst["name"][0].lower(), i] = (int(ax) + x, int(ay) + y)
    return spans, pins, marks


def mos_cards(text):
    result = {}
    for line in text.lower().splitlines():
        row = line.split()
        if not row or not row[0].startswith("m"):
            continue
        assert row[0] not in result and all("=" in token for token in row[6:])
        params = dict(x.split("=", 1) for x in row[6:])
        assert len(params) == len(row[6:]), (row[0], "duplicate parameter")
        result[row[0]] = (row[1:5], row[5], params)
    return result


def target(case, args, project, deck, cli):
    (project / "schemify.project").write_text("schemify 1 project\n")
    run([*cli, "cmd", project, "netlist.import", "n2s/input.cir"], project)
    comp = project / "n2s/dut.shcomp"
    outcome = verify(case, *host_geometry(comp, args.core), True)
    run([*cli, "netlist", comp.relative_to(project), "--dialect", "ngspice", "-o", "returned.sp"], project)
    (bench,) = (project / "n2s").glob("*.shbench")
    run([*cli, "netlist", bench.relative_to(project), "--dialect", "ngspice", "-o", "bench.sp"], project)
    source, back = deck.read_text(), (project / "returned.sp").read_text()
    assert mos_cards(source) == mos_cards(back), (case, "ordered terminals, model or parameters")
    declarations = [line for line in (project / "bench.sp").read_text().splitlines() if line.lower().startswith(".model")]
    expected = [line for line in source.splitlines() if line.lower().startswith((".model", "m"))]
    (project / "expected.sp").write_text("* expected\n" + "\n".join(expected) + "\n.end\n")
    (project / "actual.sp").write_text("* actual\n" + "\n".join(declarations) + "\n" + back)
    run([args.bin_dir / "spicecmp", "expected.sp", "actual.sp"], project)
    return outcome


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="mode", required=True)
    cli = commands.add_parser("native")
    cli.add_argument("binary", type=lambda p: Path(p).resolve())
    host = commands.add_parser("target")
    host.add_argument("bin_dir", type=lambda p: Path(p).resolve(), help="schemify and spicecmp binaries")
    host.add_argument("core", type=Path, help="same host checkout's core MOS .shprim directory")
    host.add_argument("--plugin", type=lambda p: Path(p).resolve(), default=ROOT)
    for command in (cli, host):
        command.add_argument("out", type=lambda p: Path(p).resolve(), help="fresh artifacts directory")
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=False)
    host_cmd = []
    if args.mode == "target":
        init = args.out / "init.lua"
        init.write_text('schemify.pack.add({ { path = ' + json.dumps(str(args.plugin)) +
                        ', name = "netlist-import", grant = { "read_project", "write_project" }, fuel = 100000000000 } })\n')
        host_cmd = [args.bin_dir / "schemify", "-u", init]
        run([*host_cmd, "pack", "sync"], args.out)
    for case in CASES:
        project = args.out / case
        (project / "n2s").mkdir(parents=True)
        family = "-".join(case.split("-")[:2])
        text = (ROOT / "external/examples/analoggenie" / f"{family}.cir").read_text()
        if family != case:
            text = text.replace(".ends dut", f"*@ {case.split('-')[-1]} fn1\n.ends dut")
        deck = project / "n2s/input.cir"
        deck.write_text(text)
        result = native(case, args, project, deck) if args.mode == "native" else target(case, args, project, deck, host_cmd)
        print(case, result, flush=True)


if __name__ == "__main__":
    main()
