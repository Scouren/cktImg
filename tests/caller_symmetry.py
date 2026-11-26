#!/usr/bin/env python3
"""Verify layout and hint verdicts on the sixth-groups literal pair and quad."""
import argparse
import json
from pathlib import Path
import subprocess

PAIR = """R1 VDD OUTN 1k
R2 VDD OUTP 1k
M1 OUTN INP tail VSS nch w=2u l=1u
M2 OUTP INN tail VSS nch w=2u l=1u
M5 tail VB VSS VSS nch w=4u l=1u"""
QUAD = """R1 VDD OUTP 1k
R2 VDD OUTN 1k
M1 OUTP INP s1 VSS nch w=2u l=1u
M2 OUTN INN s1 VSS nch w=2u l=1u
M3 OUTP INN s2 VSS nch w=2u l=1u
M4 OUTN INP s2 VSS nch w=2u l=1u
I1 s1 VSS 1m
I2 s2 VSS 1m"""
PM = ["symmetric m1 m2", "symmetric r1 r2", "axis m5"]
QM = ["symmetric m1 m2", "symmetric m3 m4", "symmetric r1 r2", "axis i1", "axis i2"]
GROUPS = ["group pair m1 m2", "group pair m3 m4"]


def draw(binary, out, tag, cards, hints, reverse=False):
    out.mkdir(parents=True, exist_ok=True)
    deck, raw, report, svg = [out / (tag + ext) for ext in (".cir", ".json", ".report.json", ".svg")]
    pins = "VDD VSS INP INN " + ("VB " if cards == PAIR else "") + "OUTP OUTN"
    rows = cards.splitlines()
    if reverse:
        rows.reverse()
    deck.write_text("\n".join(["Caller geometry", ".model nch nmos level=1", ".subckt dut " + pins,
                               *rows, *("*@ " + h for h in hints), ".ends dut", ""]))
    subprocess.run([binary, "--report", report, "--svg", svg, deck, raw], check=True)
    r = json.loads(report.read_text())
    assert not r["gates"], (tag, r["gates"])
    devices = {d["name"]: d for d in json.loads(raw.read_text())["devices"] if not d["name"].startswith("_")}
    source = [card.lower().split() for card in cards.splitlines()]
    assert set(devices) == {row[0] for row in source}
    for name, *fields in source:
        obj = devices[name]
        nodes = [p["net"] for p in obj["pins"]]
        if name.startswith("m"):
            nodes.append(obj["bulk"])
        assert nodes == fields[:len(nodes)]
        assert obj["value"].split() == fields[len(nodes):]
    result = {v["text"][3:]: v for v in r["requests"]}
    return devices, result


def axis_of(devices, a, b):
    left, right = devices[a], devices[b]
    assert [p["term"] for p in left["pins"]] == [p["term"] for p in right["pins"]]
    pos = left["pos"], right["pos"]
    axis = pos[0][0] + pos[1][0]
    for (x, y), (u, v) in [pos, *zip([p["xy"] for p in left["pins"]], [p["xy"] for p in right["pins"]])]:
        if x + u != axis or y != v:
            return None
    return axis


def verdict(rows, line, state="honoured", code="ok", blocker=None):
    v = rows[line]
    assert (v["state"], v["code"]) == (state, code), (line, v)
    if blocker is not None:
        assert v["blocked_by"] == [{"line": rows[blocker]["line"], "alone": True}], (line, v)


def check(binary, out):
    stored = {}
    for name, cards, hints, reverse in [
        ("quad-relations", QUAD, QM, False), ("quad-groups", QUAD, QM + GROUPS, False),
        ("quad-groups-reversed", QUAD, QM + GROUPS, True), ("quad-axis-alone", QUAD, ["axis i2"], False),
        ("quad-axis-reversed", QUAD, QM[3:][::-1] + QM[:3], True),
        ("pair-relations", PAIR, PM, False), ("pair-relations-reversed", PAIR, PM, True),
        ("pair-fixed", PAIR, PM + ["at m1 -20 -20 r0"], False),
        ("quad-fixed", QUAD, QM + ["at m3 -20 -20 r0"], False),
        ("pair-fixed-weak", PAIR, PM + ["weak at m1 -20 -20 r0"], False),
        ("pair-fixed-weak-compatible", PAIR, PM + ["weak at m1 -20 -20 r270"], False),
    ]:
        ds, rows = draw(binary, out, name, cards, hints, reverse)
        axis = axis_of(ds, "r1", "r2")
        assert axis is not None
        strong = name in ("pair-fixed", "quad-fixed")
        fixed = "m1" if cards == PAIR else "m3"
        for h in hints:
            words = h.split()
            if words[0] == "symmetric":
                if strong and words[1] == fixed:
                    assert axis_of(ds, *words[1:]) != axis
                    verdict(rows, h, "dropped", "conflict", hints[-1])
                    continue
                assert axis_of(ds, *words[1:]) == axis
            if words[0] == "axis":
                assert 2 * ds[words[1]]["pos"][0] == axis, (name, h, ds[words[1]]["pos"], axis)
            if "at" in words:
                d = ds[words[words.index("at") + 1]]
                assert d["pos"] == [-800, -800]
                if name == "pair-fixed-weak":
                    assert (d["rot"], d["mirror"]) != (0, False)
                    verdict(rows, h, "dropped", "guarantee")
                    continue
                assert (d["rot"], d["mirror"]) == (3 if name.endswith("compatible") else 0, False)
            verdict(rows, h)
        if cards == QUAD:
            assert ds["i1"]["pos"][0] == ds["i2"]["pos"][0] and ds["i1"]["pos"][1] != ds["i2"]["pos"][1]
        stored[name] = ds
    assert stored["quad-groups"] == stored["quad-groups-reversed"] == stored["quad-axis-reversed"]
    assert stored["pair-relations"] == stored["pair-relations-reversed"]
    for h in ("row i1 i2", "order i1 i2", "above i2 i1", "cell i2 80 12", "at i2 -20 -20 r0"):
        ds, rows = draw(binary, out, h.replace(" ", "-"), QUAD, [*QM, h])
        i1, i2 = ds["i1"]["pos"], ds["i2"]["pos"]
        if h.startswith("above"):
            assert i2[1] < i1[1] and i2[0] == i1[0]
            verdict(rows, "axis i2")
        elif h.startswith(("cell", "at")):
            assert i2[0] != i1[0]
            verdict(rows, "axis i2", "dropped", "conflict", h)
        else:
            if h.startswith("order"):
                assert i1[0] < i2[0]
            else:
                assert i1[1] == i2[1]
            assert 2 * i2[0] != axis_of(ds, "r1", "r2")
            verdict(rows, "axis i2", "relaxed", "not_drawn")
        verdict(rows, h)
    for h in ("row absent i2", "order absent i2", "at i2 x x"):
        ds, rows = draw(binary, out, h.replace(" ", "-"), QUAD, [*QM, h])
        assert ds == stored["quad-relations"]
        verdict(rows, h, "rejected", "bad_args" if h.startswith("at") else "unknown_name")
    for reverse in (False, True):
        hs = ["symmetric m1 m2", "symmetric m1 m3"][::(-1 if reverse else 1)]
        ds, rows = draw(binary, out, f"quad-mate-conflict-{int(reverse)}", QUAD, hs)
        verdict(rows, hs[0], "dropped", "conflict", hs[1])
        verdict(rows, hs[1])
        assert axis_of(ds, *hs[1].split()[1:]) is not None
    for h, code, state in [("axis absent", "unknown_name", "rejected"), ("symmetric m1 r1", "asymmetric", "dropped"),
                           ("axis m1", "asymmetric", "dropped")]:
        _, rows = draw(binary, out, h.replace(" ", "-"), PAIR, [PM[0], h])
        verdict(rows, h, state, code)
    ds, rows = draw(binary, out, "quad-net-axis", QUAD, ["axis s2", "symmetric outp outn", "axis i2"])
    for h in rows:
        verdict(rows, h)
    assert ds == stored["quad-axis-alone"]
    _, rows = draw(binary, out, "pair-off", PAIR, PM + ["symmetry off"])
    for h in PM:
        verdict(rows, h, "dropped", "conflict", "symmetry off")
    verdict(rows, "symmetry off")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("binary", type=lambda p: Path(p).resolve())
    ap.add_argument("out", type=Path)
    args = ap.parse_args()
    check(args.binary, args.out)
