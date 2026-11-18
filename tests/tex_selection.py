#!/usr/bin/env python3
"""Compare the coordinates actually emitted by the JSON and TikZ front ends."""
import argparse
from collections import Counter
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
POINT = re.compile(r"\((-?\d+)pt,(-?\d+)pt\)")
LABEL = re.compile(r"\\makebox\[\d+pt\]\[l\]\{([^{}]+)\}")


def point(raw):
    x, y = raw
    return (int(x), -int(y))


def run(json_bin, tex_bin, out, case, deck, *flags):
    files = [out / (case + ext) for ext in (".json", ".tex")]
    for binary, dest in zip((json_bin, tex_bin), files):
        subprocess.run([binary, *flags, deck, dest], check=True)
    drawing = json.loads(files[0].read_text())
    tex = files[1].read_text()
    devices = {d["name"]: d for d in drawing["devices"] if not d["name"].startswith("_")}
    assert Counter(LABEL.findall(tex)) == Counter(devices.keys()), (case, sorted(devices), LABEL.findall(tex))
    emitted = [tuple(point(p) for p in POINT.findall(line)) for line in tex.splitlines() if r"\draw[cktwire]" in line]
    expected = [tuple(map(tuple, seg)) for wire in drawing["wires"] for seg in wire["segments"]]
    assert Counter(emitted) == Counter(expected), (case, "wire coordinates", len(emitted), len(expected))
    dots = [point(POINT.search(l).groups()) for l in tex.splitlines() if "node[circ]{}" in l]
    assert Counter(dots) == Counter(map(tuple, drawing["junctions"])), (case, "junctions")
    # Native CircuiTikZ MOS anchors route to the actual selected library
    # contacts. Device ids are the indices of the shared placed document.
    leads = {(int(d), t.lower()): point((x, y)) for d, t, x, y in
             re.findall(r"\\draw\[cktsym\] \(d(\d+)\.([DGS])\) [|\-]+ \((-?\d+)pt,(-?\d+)pt\)", tex)}
    for i, d in enumerate(drawing["devices"]):
        if d["class"] in ("nmos", "pmos"):
            for pin in d["pins"][:3]:
                assert leads[i, pin["term"]] == tuple(pin["xy"]), (case, d["name"], pin)
    return drawing, devices, tex


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("json", type=Path)
    parser.add_argument("tex", type=Path)
    parser.add_argument("out", type=Path)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    args.json, args.tex = args.json.resolve(), args.tex.resolve()
    def call(case, deck, *flags):
        return run(args.json, args.tex, args.out, case, deck, *flags)
    for case, count in [("ag-1080", 32), ("ag-2212", 6), ("ag-808", 9), ("ag-220", 7)]:
        d, devices, tex = call(case, ROOT / "external/examples/analoggenie" / (case + ".cir"))
        assert len(devices) == count
        if case == "ag-1080":
            from parent_stages import STAGES, criteria
            pins = {(name, i): p["xy"] for name, obj in devices.items() for i, p in enumerate(obj["pins"])}
            for stage in STAGES[case]:
                assert all(criteria(pins, stage, (140, 150)).values()), (case, stage)
        elif case in ("ag-2212", "ag-808"):
            assert devices["x1"]["class"] == "block:opamp"
            assert "{+};" in tex and "{-};" in tex
            if case == "ag-808":
                assert devices["x2"]["class"] == "block:comparator"
        else:
            resistors = [devices[k] for k in ("rs", "rs2")]
            assert all(d["class"] == "res" for d in resistors)
            # The two published series arms form one level bridge.
            assert len({p["xy"][1] for r in resistors for p in r["pins"]}) == 1
    example = ROOT / "external/examples/analoggenie/ag-1080.cir"
    equivalent, _, _ = call("explicit-symbols", example, "--symbols", ROOT / "tests/symbols.zon")
    assert equivalent == json.loads((args.out / "ag-1080.json").read_text())
    flat = ROOT / "examples/latex/cs.cir"
    _, devices, _ = call("flat", flat)
    assert set(devices) == {"m1", "vdd", "vin", "rd"}
    cfg = args.out / "render.zon"
    cfg.write_text('.{ .render = .{ .wire = "4a2399" } }')
    _, _, rendered = call("config", flat, "--config", cfg)
    assert r"\definecolor{cktwire}{HTML}{4A2399}" in rendered
    # A declared caller class has its own marker text and actual endpoints.
    # It falls through CircuiTikZ's built-in bipoles to its selected strokes.
    supplied = args.out / "custom.zon"
    data = (ROOT / "tests/symbols.zon").read_text()
    line = next(l for l in data.splitlines() if '.name = "res"' in l)
    custom = line.replace('.name = "res"', '.name = "long_res"', 1)
    custom = custom.replace('.draw = .{ ', '.draw = .{ .{ .text = .{ .at = .{ .x = 0, .y = 4 }, .s = "CUSTOM", .size = 6 } }, ', 1)
    # Changing a selected stock class withdraws the source-qualified bridge.
    # The ordinary public --from layout independently supplies its new poses.
    changed = custom.replace('.name = "long_res"', '.name = "res"', 1)
    supplied.write_text(data.replace(line, changed))
    bridge = ROOT / "external/examples/analoggenie/ag-220.cir"
    current, _, _ = call("custom-bridge", bridge, "--symbols", supplied)
    previous, ordinary = args.out / "empty.json", args.out / "ordinary.json"
    previous.write_text('{"devices":[]}')
    subprocess.run([args.json, "--symbols", supplied, "--from", previous, bridge, ordinary], check=True)
    assert current == json.loads(ordinary.read_text()) and current != json.loads((args.out / "ag-220.json").read_text())
    supplied.write_text(data.replace(line, line + "\n" + custom))
    circuit = args.out / "custom.cir"
    source = flat.read_text().splitlines()
    circuit.write_text("\n".join([source[0], source[1], ".subckt dut vdd in out",
                                  "*@ class rd long_res", *source[2:], ".ends dut"]) + "\n")
    _, devices, pic = call("custom", circuit, "--symbols", supplied)
    assert devices["rd"]["class"] == "long_res" and "{CUSTOM};" in pic


if __name__ == "__main__":
    main()
