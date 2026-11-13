#!/usr/bin/env python3
"""Input-source branch ink, with one gate satisfying every anchor condition.

Usage: input_resistor_legs.py <examples-dir> <output.json> [--check]

This companion preserves input_resistors.py and its frozen inventory. It
reselects every deck, compares exact selected names, checks source hashes,
and verifies actual transformed R/V/MOS leads. Cached wire segments supply
net assignments only when the same segment exists in SVG conductor ink.
Unverified cache pieces remain named evidence and cannot connect a leg.
--check compares every evidence row and input hash with the companion's
committed inventory; script dependency hashes are reported separately.
"""
import argparse
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET

from converter_loops import wire_tree
from converter_terminals import close
from cross_caps import conductor_ink
from input_resistors import actual, select
from sampling_cells import channel, pin


def verified_segments(human, net, ink):
    """Partition exact named-net cache pieces by actual SVG stroke support."""
    verified, missing = [], []
    for wire in human["wires"]:
        if wire["net"].lower() != net:
            continue
        for line in wire["segments"]:
            for a, b in zip(line, line[1:]):
                present = any((close(a, c) and close(b, d)) or
                              (close(a, d) and close(b, c)) for c, d in ink)
                (verified if present else missing).append([a, b])
    return verified, missing


def connection(segments, targets):
    """Retain a literal endpoint/T-junction path without using labels."""
    tree = wire_tree(segments, targets)
    return dict(targets=targets, continuous=tree is not None, spanning_ink_segments=tree)


def gate_anchor(a, b, source, gate, segments):
    """Require the same actual gate to supply row, interval and straight ink."""
    row = a[1] == b[1] == gate[1]
    between = min(source[0], gate[0]) < (a[0] + b[0]) / 2 < max(source[0], gate[0])
    full = connection(segments, [b, gate])
    horizontal = [s for s in segments if s[0][1] == s[1][1] == b[1]]
    straight = connection(horizontal, [b, gate])
    return dict(point=gate, same_row=row, resistor_between=between,
                continuous=full["continuous"], spanning_ink_segments=full["spanning_ink_segments"],
                straight_horizontal=straight["continuous"], straight_ink_segments=straight["spanning_ink_segments"],
                admitted=row and between and straight["continuous"])


def inspect(human, root, row):
    """Measure a selected topology against actual symbol and conductor ink."""
    devices = {d["card"]: d for d in human["devices"]}
    names = [row["card"], row["source"]] + row["mos"]
    glyphs = {n: actual(root, devices[n]) for n in sorted(names)}
    for name, glyph in glyphs.items():
        devices[name]["terminals"].update(glyph["terminals"])
    r, v = devices[row["card"]], devices[row["source"]]
    a, b = [pin(r, n) for n in (row["junction"], row["gate_net"])]
    signal, ground = [pin(v, n) for n in (row["junction"], row["ground"])]
    ink = conductor_ink(root)
    legs = {}
    for role, net in (("source", row["junction"]), ("gate", row["gate_net"])):
        segments, missing = verified_segments(human, net, ink)
        legs[role] = dict(net=net, verified_ink_segments=segments, cache_segments_without_ink=missing)
    legs["source"].update(connection(legs["source"]["verified_ink_segments"], [signal, a]))
    anchors = [dict(card=name, **gate_anchor(a, b, signal, channel(devices[name])[2],
                                           legs["gate"]["verified_ink_segments"])) for name in row["mos"]]
    geometry = dict(resistor_horizontal=a[1] == b[1] and a[0] != b[0],
                    source_vertical=signal[0] == ground[0], source_ground_below=signal[1] < ground[1],
                    source_signal_at_or_below_resistor=signal[1] >= a[1])
    return dict(id=human["id"], card=row["card"], source=row["source"],
                source_glyphs=glyphs, source_geometry=geometry, source_leg=legs["source"],
                gate_net=legs["gate"], gate_anchors=anchors,
                complete_branch=all(geometry.values()) and legs["source"]["continuous"] and any(g["admitted"] for g in anchors))


def summarize(rows):
    def key(row):
        return row["id"] + ":" + row["card"]
    return dict(names=[key(r) for r in rows],
                source_leg_connected=[key(r) for r in rows if r["source_leg"]["continuous"]],
                same_anchor_straight_gate=[key(r) for r in rows if any(g["admitted"] for g in r["gate_anchors"])],
                complete_branch=[key(r) for r in rows if r["complete_branch"]],
                admitted_anchors=[key(r) + ":" + g["card"] for r in rows for g in r["gate_anchors"] if g["admitted"]],
                disconnected_anchors=[key(r) + ":" + g["card"] for r in rows for g in r["gate_anchors"] if not g["continuous"]],
                off_row_anchors=[key(r) + ":" + g["card"] for r in rows for g in r["gate_anchors"] if not g["same_row"]],
                cache_only_segments=sum(len(r[k]["cache_segments_without_ink"]) for r in rows for k in ("source_leg", "gate_net")),
                verified_terminals=sum(len(g["terminals"]) for r in rows for g in r["source_glyphs"].values()))


def audit(examples):
    """Scan every paired deck, failing on any frozen cohort/input mismatch."""
    baseline = Path(__file__).with_name("input_resistors_cases.json")
    expected = json.loads(baseline.read_text())[examples.name]
    paths = sorted(examples.glob("*.human.json"))
    if len(paths) != expected["corpus_drawings"]:
        raise ValueError("paired source circuit count changed")
    selected, hashes = [], {}
    for hp in paths:
        ident = hp.name.removesuffix(".human.json")
        deck, svg = [hp.with_name(ident + suffix) for suffix in (".cir", ".svg")]
        _, rows = select(deck.read_text())
        rows = [r for r in rows if r["admitted"]]
        if not rows:
            continue
        for p in (hp, deck, svg):
            digest = hashlib.sha256(p.read_bytes()).hexdigest()
            if expected["source_sha256"].get(p.name) != digest:
                raise ValueError("source differs from frozen input study: " + p.name)
            hashes[p.name] = digest
        human = json.loads(hp.read_text())
        root = ET.parse(svg).getroot()
        selected.extend(inspect(human, root, r) for r in rows)
    summary = summarize(selected)
    if summary["names"] != expected["summary"]["names"]:
        raise ValueError("exact selected input-resistor names changed")
    return dict(corpus=examples.name, paired_circuits=len(paths), summary=summary,
                selected=selected, source_sha256=hashes)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("examples", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    result = audit(args.examples)
    if args.check:
        frozen = json.loads(Path(__file__).with_name("input_resistor_legs_cases.json").read_text())
        if result != frozen[result["corpus"]]:
            raise ValueError("input branch ink differs from exact companion inventory")
    dependencies = ("input_resistor_legs.py", "input_resistors.py", "input_resistors_cases.json",
                    "channel_bridges.py", "cross_caps.py", "converter_loops.py", "converter_terminals.py", "sampling_cells.py")
    result["dependency_sha256"] = {n: hashlib.sha256(Path(__file__).with_name(n).read_bytes()).hexdigest() for n in dependencies}
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps(result["summary"], indent=2))


if __name__ == "__main__":
    main()
