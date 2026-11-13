#!/usr/bin/env python3
"""Certified converter input buses -> actual auxiliary-branch ink evidence.

Usage: converter_bus.py <examples-dir> <output.json> [--native label=json-dir]

Reuses the loop inventory and topology-only PMOS bus certificate. Every
extra branch is selected by channel membership, never by its name. Source
hashes, actual D/G/S glyph leads and actual conductor strokes are checked.
Repeat --native to retain named before/after snapshots and exact differences.
This study measures physical continuity; equal labels never join ink, and
source preferences do not imply every native distant branch must be wired.
"""
import argparse
import collections
import hashlib
import json
from pathlib import Path
from xml.etree import ElementTree as ET

import converter_loops as loops
import power_paths as power


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def branches(text, bus, local):
    """Existing gate-only PMOS channel certificate, excluding local switches."""
    selected, _ = power.classify(text)
    members = sorted(n for n, r in selected.items() if r["unrestricted_bus"] and
                     bus in (r["nets"][0], r["nets"][2]))
    if any(selected[n]["type"] != "pmos" or not selected[n]["gate_only"] for n in members):
        raise ValueError("input-bus certificate admitted an unsupported channel")
    return members, sorted(set(members) - set(local))


def relation(main, lower, extra, other, gate):
    return dict(horizontal=extra[1] == other[1], bus_left=extra[0] < other[0],
                above_main=extra[1] < main[1], between_rows=main[1] < extra[1] < lower[1],
                below_lower=extra[1] > lower[1], same_main_row=extra[1] == main[1],
                same_lower_row=extra[1] == lower[1], same_terminal_column=extra[0] == main[0] == lower[0],
                gate_down=gate[1] > max(extra[1], other[1]), gate_up=gate[1] < min(extra[1], other[1]))


def geometry(devices, local, extra, bus, native=False):
    names = [*local, extra]
    main, lower, point = [loops.path_pin(devices[n], bus, native) for n in names]
    device = devices[extra]
    if native:
        other = next(p["xy"] for p in device["pins"] if p["term"].upper() in ("D", "S") and p["net"].lower() != bus)
        gate = next(p["xy"] for p in device["pins"] if p["term"].upper() == "G")
    else:
        other = next(device["terminals"][p] for p in ("D", "S") if device["nets"][p] != bus)
        gate = device["terminals"]["G"]
    return dict(targets=[dict(card=n, xy=p) for n, p in zip(names, [main, lower, point])],
                other=other, gate=gate, relation=relation(main, lower, point, other, gate))


def connect(evidence, segments):
    """Exact terminal-to-terminal ink path; labels and ports supply no edge."""
    evidence["segments"] = segments
    evidence["spanning_segments"] = loops.wire_tree(segments, [p["xy"] for p in evidence["targets"]])
    evidence["continuous"] = evidence["spanning_segments"] is not None
    return evidence


def summarize(rows, versions):
    name = lambda r: r["id"] + ":" + r["card"]
    result = {}
    for version in versions:
        result[version] = dict(continuous=[name(r) for r in rows if r[version]["continuous"]],
                              disconnected=[name(r) for r in rows if not r[version]["continuous"]],
                              relations={k: [name(r) for r in rows if r[version]["relation"][k]]
                                         for k in rows[0][version]["relation"]})
    return result


def method_checks():
    text = """.model p pmos
.model n nmos
.subckt dut
L1 a b 1n
MI a gi bus vdd p
ML bottom gl bus vdd p
MO out go b vdd p
MS b gs 0 0 n
MA other ga bus vdd p
.ends dut
"""
    names = []
    assert branches(text, "bus", ["mi", "ml"]) == (["ma", "mi", "ml"], ["ma"])
    names.append("extra_channel_selected")
    assert branches(text.replace("MA other ga bus", "MA bus ga other"), "bus", ["mi", "ml"])[1] == ["ma"]
    names.append("channel_card_order")
    for kind, card in (("gate", "MX x bus y vdd p"), ("body", "MX x gx y bus p")):
        assert branches(text.replace(".ends dut", card + "\n.ends dut"), "bus", ["mi", "ml"])[1] == ["ma"]
        names.append(kind + "_incidence_is_not_channel")
    assert branches(text.replace("MA other ga bus vdd p", "MA other ga bus vdd n"), "bus", ["mi", "ml"])[1] == []
    names.append("wrong_polarity_breaks_bus_certificate")
    assert loops.wire_tree([[[0, 0], [0, 20]], [[0, 10], [10, 10]]], [[0, 0], [0, 20], [10, 10]]) is not None
    names.append("auxiliary_t_join")
    assert loops.wire_tree([[[0, 0], [0, 20]], [[2, 10], [10, 10]]], [[0, 0], [0, 20], [10, 10]]) is None
    names.append("same_net_gap_is_not_continuity")
    return names


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("examples", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--loops", type=Path, default=Path(__file__).with_name("converter_loops_cases.json"))
    parser.add_argument("--native", action="append", default=[], metavar="LABEL=DIR")
    args = parser.parse_args()
    natives = {}
    for item in args.native:
        label, directory = item.split("=", 1)
        if not label or label == "source" or label in natives:
            raise ValueError("native snapshot labels must be distinct and cannot be source")
        natives[label] = Path(directory)
    inventory = json.loads(args.loops.read_text())[args.examples.name]
    for name, expected in inventory["source_sha256"].items():
        if sha(args.examples / name) != expected:
            raise ValueError("stale source certificate: " + name)
    rows, groups, source_hashes, native_hashes = [], [], {}, {label: {} for label in natives}
    for group in inventory["selected"]:
        ident, net = group["id"], group["nets"]["bus"]
        local = [group["main"][0], group["low"]]
        deck, human_path, svg = [args.examples / (ident + ext) for ext in (".cir", ".human.json", ".svg")]
        members, extra = branches(deck.read_text(), net, local)
        groups.append(dict(id=ident, coil=group["coil"], bus=net, local=local, all_bus_branches=members, auxiliary=extra))
        source_hashes.update({p.name: sha(p) for p in (deck, human_path, svg)})
        human = json.loads(human_path.read_text())
        devices = {d["card"]: d for d in human["devices"]}
        root = ET.parse(svg).getroot()
        for name, glyph in group["source_glyphs"].items():
            devices[name]["terminals"].update(glyph["terminals"])
        bus = loops.connections(group, human, devices, loops.conductor_ink(root))["bus"]
        if bus != group["source_connections"]["bus"]:
            raise ValueError("stale source conductor certificate: " + ident)
        drawings = {}
        for label, directory in natives.items():
            path = directory / (ident + ".json")
            drawing = json.loads(path.read_text())
            drawings[label] = drawing, {d["name"].lower(): d for d in drawing["devices"]}
            native_hashes[label][path.name] = sha(path)
        for name in extra:
            verified = loops.actual_glyph(root, devices[name])
            devices[name]["terminals"].update(verified["terminals"])
            row = dict(id=ident, coil=group["coil"], card=name, net=net, source_glyph=verified)
            row["source"] = connect(geometry(devices, local, name, net), bus["verified_ink_segments"])
            for label, (drawing, drawn) in drawings.items():
                segments = [[a, b] for w in drawing["wires"] if w["net"].lower() == net
                            for line in w["segments"] for a, b in zip(line, line[1:])]
                row[label] = connect(geometry(drawn, local, name, net, True), segments)
            rows.append(row)
    if not rows:
        raise ValueError("no auxiliary branches in selected source inventory")
    versions = ["source", *natives]
    summary = summarize(rows, versions)
    transitions = {}
    for before, after in zip(natives, list(natives)[1:]):
        old, new = [set(summary[label]["continuous"]) for label in (before, after)]
        transitions[before + "->" + after] = dict(lost=sorted(old - new), gained=sorted(new - old))
    source_comparison = {}
    connected = set(summary["source"]["continuous"])
    separate = set(summary["source"]["disconnected"])
    for label in natives:
        joined = set(summary[label]["continuous"])
        apart = set(summary[label]["disconnected"])
        source_comparison[label] = dict(agree=sorted((connected & joined) | (separate & apart)),
                                        source_connected_native_separate=sorted(connected & apart),
                                        source_separate_native_connected=sorted(separate & joined))
    result = dict(study="converter auxiliary input-bus branches", loop_inventory=dict(file=args.loops.name, sha256=sha(args.loops)),
                  source_sha256=source_hashes, native_sha256=native_hashes, groups=groups, rows=rows,
                  method_checks=method_checks(), summary=summary, transitions=transitions,
                  source_comparison=source_comparison,
                  extra_branch_counts=dict(collections.Counter(len(g["auxiliary"]) for g in groups)))
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps(dict(groups=len(groups), branches=len(rows), extra_branch_counts=result["extra_branch_counts"],
                          continuous={label: len(summary[label]["continuous"]) for label in versions},
                          source_agreement={label: len(value["agree"]) for label, value in source_comparison.items()},
                          transitions={label: {k: len(v) for k, v in value.items()} for label, value in transitions.items()},
                          method_checks=result["method_checks"]), indent=2))


if __name__ == "__main__":
    main()
