#!/usr/bin/env python3
"""Exercise rejected hints, local caller ownership and CLI mapping on actual parent-output wires."""
import argparse
import json
from pathlib import Path
import subprocess
from parent_output_routes import ROOT, run, target, verify


def inspect(drawing):
    spans = [seg for wire in drawing["wires"] for path in wire["segments"] for seg in zip(path, path[1:])]
    pins = {}
    markers = [(l["net"], l["at"]) for l in drawing["labels"]]
    for d in drawing["devices"]:
        if d["class"] in ("gnd", "vdd", "ipin", "opin"):
            markers.append((d["pins"][0]["net"], d["pins"][0]["xy"]))
        else:
            pins.update({(d["name"], i): pin["xy"] for i, pin in enumerate(d["pins"])})
    return spans, pins, markers


def check_host(out, bin_dir, core, plugin):
    out.mkdir(parents=True, exist_ok=False)
    init = out / "init.lua"
    init.write_text('schemify.pack.add({ { path = ' + json.dumps(str(plugin.resolve())) +
                    ', name = "netlist-import", grant = { "read_project", "write_project" }, fuel = 100000000000 } })\n')
    cli = [bin_dir / "schemify", "-u", init]
    run([*cli, "pack", "sync"], out)
    rejected = ["axis missing", "unknownverb m7", "face m7 g nonsense", "wire rn nonsense", "role rn nonsense"]
    for case in ("ag-1079", "ag-1080"):
        folder = out / case
        (folder / "n2s").mkdir(parents=True)
        deck = folder / "n2s/input.cir"
        text = (ROOT / "external/examples/analoggenie" / (case + ".cir")).read_text()
        deck.write_text(text.replace(".ends dut", "\n".join("*@ " + h for h in [*rejected, "first vdd"]) + "\n.ends dut"))
        result = target(case, argparse.Namespace(bin_dir=bin_dir, core=core), folder, deck, cli)
        print(case, result, flush=True)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=lambda p: Path(p).resolve())
    parser.add_argument("out", type=Path)
    parser.add_argument("--host", nargs=3, type=lambda p: Path(p).resolve(), metavar=("BIN_DIR", "CORE", "PLUGIN"),
                        help="also import and netlist the rejected-hint cases on Schemify")
    a = parser.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)

    def draw(case, key, hint="", flags=()):
        folder = a.out / (case + "-" + key)
        folder.mkdir(exist_ok=True)
        source = (ROOT / "external/examples/analoggenie" / (case + ".cir")).read_text()
        if hint:
            source = source.replace(".ends dut", "*@ " + hint + "\n.ends dut")
        deck, raw, report = [folder / f for f in ("input.cir", "placed.json", "report.json")]
        deck.write_text(source)
        subprocess.run([a.binary, "--report", report, *flags, deck, raw], check=True)
        v = json.loads(report.read_text())
        rows = {h["text"].lower(): h for h in v["requests"]}
        return json.loads(raw.read_text()), rows.get("*@ " + hint.lower())

    mapping = a.out / "target.json"
    mapping.write_text(json.dumps({"target": "example", "version": 1, "unmapped": {"mode": "skip"},
                                   "classes": {k: {"sym": k, "pins": ["s", "d", "g"]} for k in ("pmos", "nmos")}}))
    for case in ("ag-1079", "ag-1080"):
        original, _ = draw(case, "ordinary")
        verify(case, *inspect(original), False)
        for idx, (h, code) in enumerate([
                ("axis missing", "unknown_name"), ("unknownverb m7", "unknown_verb"),
                ("face m7 g nonsense", "bad_args"), ("role rn nonsense", "bad_args"), ("class m7 res", "bad_args"),
                ("wire rn nonsense", "bad_args"), ("order m7 missing", "unknown_name")]):
            d, v = draw(case, str(idx), h)
            assert v["state"] == "rejected" and v["code"] == code, (h, v)
            verify(case, *inspect(d), False)
            assert d == original, h
        for idx, (h, code) in enumerate([("role vdd supply", "ok"), ("first vdd", "ok")]):
            d, v = draw(case, "related-" + str(idx), h)
            assert v["state"] == "honoured" and v["code"] == code, (h, v)
            verify(case, *inspect(d), False)
        for key, flags in [("symbols", ["--symbols", ROOT / "tests/symbols.zon"]), ("target", ["--target", mapping])]:
            d, _ = draw(case, key, flags=flags)
            verify(case, *inspect(d), False)
            if key == "target":
                targets = d.pop("target")["devices"]
                assert targets and all(t["pins"] == [2, 0, 1] for t in targets)
            assert d == original, key

    # A real request on exactly one sibling group returns that pair to
    # ordinary routing. The other pair keeps its two-part routes. The
    # ordinary drawing provides the coordinates for the explicit pose.
    baseline, _ = draw("ag-1080", "anchor")
    device = next(d for d in baseline["devices"] if d["name"] == "m29")
    x, y = (n / 40 for n in device["pos"])
    pose = ("mr" if device["mirror"] else "r") + str(90 * device["rot"])
    for idx, h in enumerate(("role fn1 internal", f"at m29 {x:g} {y:g} {pose}")):
        d, v = draw("ag-1080", "held-" + str(idx), h)
        assert v["state"] == "honoured", (h, v)
        verify("ag-1080", *inspect(d), False, ordinary=("fn1", "fp1"))
        if h.startswith("at "):
            moved = next(r for r in d["devices"] if r["name"] == "m29")
            assert all(moved[k] == device[k] for k in ("pos", "rot", "mirror"))

    d, v = draw("ag-1080", "declined-stay", f"weak at m29 {x:g} {y:g} r0")
    assert (v["state"], v["code"]) == ("dropped", "guarantee")
    verify("ag-1080", *inspect(d), False)

    # A library changing the pin vocabulary cannot prove MOS drain identity.
    # Empty replay stays supply the independent ordinary route for the same
    # class frames.
    changed = []
    for line in (ROOT / "tests/symbols.zon").read_text().splitlines(keepends=True):
        if '.name = "nmos",' in line:
            line = line.replace('.name = "d",', '.name = "drain",', 1)
        changed.append(line)
    custom = a.out / "missing-drain.zon"
    custom.write_text("".join(changed))
    assert '.name = "drain",' in custom.read_text()
    empty = a.out / "empty.json"
    empty.write_text('{"devices":[]}')
    flags = ["--symbols", custom]
    refused, _ = draw("ag-1080", "incompatible", flags=flags)
    ordinary, _ = draw("ag-1080", "incumbent", flags=[*flags, "--from", empty])
    assert refused == ordinary
    if a.host:
        check_host(a.out / "host", *a.host)


if __name__ == "__main__":
    main()
