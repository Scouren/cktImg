"""Check signed frames from final pins, caller poses, source bindings and editor records."""

import argparse
from pathlib import Path
import json
import re
import shlex
import subprocess

ROOT = Path(__file__).resolve().parents[1]
FORMALS = ("vdd", "vss", "inn", "inp", "out")
MIXED = ("xreg", "xsample")
UNIFORM = ("xa", "xb")


def run(*args, cwd=None):
    subprocess.run(args, cwd=cwd, check=True, stdout=subprocess.DEVNULL)


def cards(text):
    return {
        w[0].lower(): tuple(x.lower() for x in w[1:])
        for line in text.splitlines()
        if (w := line.split()) and w[0][0].lower() == "x"
    }


def at(base, point, turns, mirror):
    x, y = point
    if mirror:
        x = -x
    for _ in range(turns):
        x, y = -y, x
    return [base[0] + x, base[1] + y]


def local_frame(d, upper, binding, formals=FORMALS):
    assert [pin["term"] for pin in d["pins"]] == list(formals)
    assert tuple(pin["net"] for pin in d["pins"]) == binding
    ordinates = {
        "vdd": (0, -60),
        "vss": (0, 60),
        "out": (60, 0),
        "inn": (-60, 20 if upper else -20),
        "inp": (-60, -20 if upper else 20),
    }
    assert [pin["xy"] for pin in d["pins"]] == [
        at(d["pos"], ordinates[k], d["rot"], d["mirror"]) for k in formals
    ], (d["name"], upper, d)


def switched(text):
    lines = text.splitlines()
    first = (
        next(i for i, s in enumerate(lines) if s.lower().startswith(".subckt dut")) + 1
    )
    return (
        "\n".join(lines[:first] + list(reversed(lines[first:-1])) + lines[-1:]) + "\n"
    )


def cases():
    m, u = [
        (ROOT / "tests/shared_frames" / f"{stem}.cir").read_text()
        for stem in ("mixed", "uniform")
    ]

    def hint(deck, line):
        return deck.replace(".ends dut", line + "\n.ends dut")

    return [
        ("mixed", m, MIXED, (True, False)),
        ("uniform", u, UNIFORM, (True, True)),
        ("reversed", switched(m), MIXED, (True, False)),
        ("fixed-reg", hint(m, "*@ at XREG -30 -30 r90"), MIXED, (False, False)),
        ("fixed-peer", hint(u, "*@ at XB -30 -30 r90"), UNIFORM, (True, False)),
        ("weak-bad-pose", hint(m, "*@ at XREG 1 1 unknown"), MIXED, (True, False)),
        ("other-fixed", hint(m, "*@ at MS1 -30 -30 r90"), MIXED, (True, False)),
        ("invalid-pose", hint(u, "*@ at XA 1 1 impossible"), UNIFORM, (True, True)),
        ("invalid-class", hint(u, "*@ class XA missing"), UNIFORM, (True, True)),
        (
            "unrelated-pose",
            hint(u, "CP VINA VSS 1p\n*@ at CP -20 -20 r0"),
            UNIFORM,
            (True, True),
        ),
        ("extra-tap", hint(u, "CX fba VSS 1p"), UNIFORM, (False, True)),
        ("extra-gate", hint(u, "CX gateb VSS 1p"), UNIFORM, (True, False)),
        (
            "shared-bulk",
            m.replace("MS1 SIN PHI1 sj VSS", "MS1 SIN PHI1 sj fb"),
            MIXED,
            (False, False),
        ),
        ("wrong-model", m.replace("nch nmos", "nch pmos"), MIXED, (False, False)),
        (
            "renamed",
            m.replace("XREG", "XF2")
            .replace("XSAMPLE", "XF1")
            .replace("MREG", "MZ")
            .replace("fb ", "z8 "),
            ("xf2", "xf1"),
            (True, False),
        ),
    ]


def native(binary, out):
    for name, text, members, expected in cases():
        deck, data, svg = (out / (name + e) for e in (".cir", ".json", ".svg"))
        deck.write_text(text)
        run(binary, "--svg", svg, deck, data)
        opts = {d["name"]: d for d in json.loads(data.read_text())["devices"]}
        for dev, want in zip(members, expected):
            local_frame(opts[dev], want, cards(text)[dev][:-1])
            assert opts[dev]["class"] == (
                "block:opamp:reference-above" if want else "block:opamp"
            )
        if name == "mixed":
            marks = [
                (float(y), mark)
                for y, mark in re.findall(
                    r'<text x="[^"]+" y="([^"]+)"[^>]*>([+-])</text>', svg.read_text()
                )
            ]
            assert len(marks) == 4
            assert tuple(mark for _, mark in sorted(marks[:2])) == ("+", "-")
            assert tuple(mark for _, mark in sorted(marks[2:])) == ("-", "+")
        if name.startswith("fixed-"):
            d = opts["xreg" if name == "fixed-reg" else "xb"]
            assert d["pos"] == [-1200, -1200] and (d["rot"], d["mirror"]) == (1, False)
    # Explicit side/pin directions and caller-owned family frames remain
    # authoritative even though the same electrical embedding survives.
    original = cases()[0][1]
    for name, directives in [
        ("sides", "*@ right INN\n*@ left INP"),
        ("pininfo", "*.pininfo INN:O INP:I OUT:O"),
    ]:
        deck, outfile = out / (name + ".cir"), out / (name + ".json")
        deck.write_text(original.replace(".ends opamp", directives + "\n.ends opamp"))
        run(binary, deck, outfile)
        devs = {d["name"]: d for d in json.loads(outfile.read_text())["devices"]}
        for name in MIXED:
            assert devs[name]["class"] == "block:opamp"
            assert (
                tuple(p["net"] for p in devs[name]["pins"])
                == cards(original)[name][:-1]
            )
    # Swapping the formal declaration and the corresponding actual slots
    # preserves the role map and reverses the electrical index, in both uses.
    src = (
        cases()[0][1]
        .replace("INN INP OUT", "INP INN OUT")
        .replace("fb VREF gate", "VREF fb gate")
        .replace("sn VSS SOUT", "VSS sn SOUT")
    )
    deck, outfile = out / "formal.cir", out / "formal.json"
    deck.write_text(src)
    run(binary, deck, outfile)
    devs = {d["name"]: d for d in json.loads(outfile.read_text())["devices"]}
    for dev, want in zip(MIXED, (True, False)):
        local_frame(
            devs[dev], want, cards(src)[dev][:-1], ("vdd", "vss", "inp", "inn", "out")
        )
    # A declared custom frame belongs to its caller. Immutable generated
    # alternatives must never change its terminals or orientation.
    symbols, custom, data = (
        out / n for n in ("symbols.zon", "custom.cir", "custom.json")
    )
    stock = (ROOT / "tests/symbols.zon").read_text()
    marker = (
        '.{ .name = "caller_amp", .terminals = .{ '
        + ", ".join(
            '.{ .name = "%s", .at = .{ .x = %d, .y = %d } }' % z
            for z in [
                ("vdd", 0, -90),
                ("vss", 0, 90),
                ("inn", -80, 30),
                ("inp", -80, -30),
                ("out", 80, 0),
            ]
        )
        + " } },"
    )
    start = stock.index(".classes = .{") + len(".classes = .{")
    symbols.write_text(stock[:start] + "\n" + marker + stock[start:])
    text = cases()[1][1].replace(".ends dut", "*@ class XB caller_amp\n.ends dut")
    custom.write_text(text)
    run(binary, "--symbols", symbols, custom, data)
    devs = {d["name"]: d for d in json.loads(data.read_text())["devices"]}
    local_frame(devs["xa"], True, cards(text)["xa"][:-1])
    assert devs["xb"]["class"] == "caller_amp" and devs["xb"]["pins"][0]["xy"] == at(
        devs["xb"]["pos"], (0, -90), devs["xb"]["rot"], devs["xb"]["mirror"]
    )
    symbols.write_text(
        (stock[:start] + "\n" + marker + stock[start:]).replace("caller_amp", "opamp")
    )
    custom.write_text(cases()[0][1])
    run(binary, "--symbols", symbols, custom, data)
    devs = {d["name"]: d for d in json.loads(data.read_text())["devices"]}
    for member in MIXED:
        d = devs[member]
        assert d["class"] == "opamp" and d["pins"][0]["xy"] == at(
            d["pos"], (0, -90), d["rot"], d["mirror"]
        )


def host(host, plugin, out):
    init = out / "init.lua"
    init.write_text(
        f'schemify.pack.add({{ {{ path = "{plugin}", name = "netlist-import", grant = {{ "read_project", "write_project" }}, fuel = 100000000000 }} }})\n'
    )
    run(host, "-u", init, "pack", "sync", cwd=out)
    for case in (
        "mixed",
        "uniform",
        "reversed",
        "extra-tap",
        "fixed-peer",
        "invalid-pose",
        "invalid-class",
        "unrelated-pose",
    ):
        _, text, members, decision = next(row for row in cases() if row[0] == case)
        project = out / case
        circuit = project / "n2s"
        circuit.mkdir(parents=True, exist_ok=True)
        (project / "schemify.project").write_text("schemify 1 project\n")
        (circuit / "input.cir").write_text(text)
        run(
            host,
            "-u",
            init,
            "cmd",
            project,
            "netlist.import",
            "n2s/input.cir",
            cwd=project,
        )
        run(
            host,
            "-u",
            init,
            "netlist",
            "n2s/dut.shcomp",
            "--dialect",
            "ngspice",
            "-o",
            "returned.sp",
            cwd=project,
        )
        netlist = (project / "returned.sp").read_text()
        assert cards(netlist) == cards(text) and re.search(
            r"(?im)^\.subckt opamp VDD VSS INN INP OUT$", netlist
        )
        comp = (circuit / "dut.shcomp").read_text()
        for member in members:
            assert re.search(
                r"(?im)^inst \S+ \./opamp\n  at [^\n]+\n  name " + member[1:] + r"$",
                comp,
            )
        assert {f.name for f in circuit.glob("*.shcomp")} == {
            "dut.shcomp",
            "opamp.shcomp",
        }
        # Round-trip every ordered terminal of every original instance,
        # MOS channel/gate/bulk/model, passive with value, and callee.
        original = (
            text.split(".subckt dut", 1)[1].split("\n", 1)[1].split(".ends dut")[0]
        )
        lines = [s for s in original.splitlines() if s and s[0] != "*"]

        def rows(source):
            result = {}
            for line in source.splitlines():
                words = line.lower().split()
                if words and words[0][0] in "mxrc":
                    result[words[0]] = tuple(w for w in words[1:] if w != "m=1")
            return result

        assert rows(netlist) == rows(original)
        (project / "want.sp").write_text(
            "* expected\n.model nch nmos\n"
            + "\n".join(lines)
            + "\n.subckt opamp VDD VSS INN INP OUT\n.ends opamp\n.end\n"
        )
        (project / "got.sp").write_text("* actual\n.model nch nmos\n" + netlist)
        run(host.with_name("spicecmp"), "want.sp", "got.sp", cwd=project)
        glyph = (circuit / "opamp.shcomp").read_text()
        pins = [shlex.split(l)[1:] for l in glyph.splitlines() if l.startswith("pin ")]
        assert tuple(row[0].lower() for row in pins) == FORMALS
        points = {n.lower(): (int(x), int(y)) for n, _, x, y in pins}
        marks = {
            m: (int(x), int(y))
            for x, y, m in re.findall(r"^stext (-?\d+) (-?\d+) R0 ([+-])$", glyph, re.M)
        }
        assert (
            points["vdd"] == (0, -60)
            and points["vss"] == (0, 60)
            and points["out"] == (60, 0)
        )
        assert points["inp"][1] == marks["+"][1] and points["inn"][1] == marks["-"][1]
        assert (points["inp"][1] < points["inn"][1]) == all(decision), (case, points)


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("cli", type=lambda s: Path(s).resolve())
    p.add_argument("out", type=lambda s: Path(s).resolve())
    p.add_argument("--host", type=lambda s: Path(s).resolve())
    p.add_argument("--plugin", type=lambda s: Path(s).resolve())
    args = p.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    if args.host:
        host(args.host, args.plugin, args.out)
    else:
        native(args.cli, args.out)
