#!/usr/bin/env python3
"""Compare complete grounded-source branches against frozen source ink.

Usage: input_branch_native.py <examples-dir> <output.json> --native label=dir

The source companion reselects every deck and verifies its actual SVG ink.
Native pin coordinates and named-net segments supply the measured geometry;
ports and labels never join a wire. Every predicate uses one gate witness.
Repeat --native to retain exact before/after names, not just totals.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path

from input_resistor_legs import audit, connection, gate_anchor
from input_resistors import select
from sampling_cells import channel, pin


def method_checks():
    """Literal native geometry catches net, pin-order and label confusion."""
    row = dict(card="r", source="v", junction="j", gate_net="g", ground="0", mos=["m"])
    def device(name, pins):
        return dict(name=name, pins=[dict(term=t, net=n, xy=p) for t, n, p in pins])
    drawing = dict(devices=[
        device("r", [("a", "j", [10, 0]), ("b", "g", [30, 0])]),
        device("v", [("a", "j", [0, 10]), ("b", "0", [0, 30])]),
        device("m", [("d", "out", [60, -10]), ("g", "g", [50, 0]), ("s", "0", [60, 10])])],
        wires=[dict(net="j", segments=[[[0, 10], [0, 0], [10, 0]]]),
               dict(net="g", segments=[[[30, 0], [50, 0]]])], labels=[])
    expected = ["literal_complete_branch", "semantic_pin_order", "wrong_net_cannot_connect",
                "named_gap_is_disconnected", "continuous_detour_is_not_straight", "ground_above_rejected",
                "wrong_gate_binding_rejected"]
    passed = []
    assert inspect(drawing, row)["complete_branch"]
    passed.append(expected[0])
    changed = copy.deepcopy(drawing)
    for d in changed["devices"]:
        d["pins"].reverse()
    assert inspect(changed, row)["complete_branch"]
    passed.append(expected[1])
    changed = copy.deepcopy(drawing)
    changed["wires"][1]["net"] = "other"
    assert not inspect(changed, row)["complete_branch"]
    passed.append(expected[2])
    changed = copy.deepcopy(drawing)
    changed["wires"][1]["segments"] = [[[30, 0], [38, 0]], [[42, 0], [50, 0]]]
    changed["labels"] = [dict(net="g", at=[38, 0]), dict(net="g", at=[42, 0])]
    assert not inspect(changed, row)["complete_branch"]
    passed.append(expected[3])
    changed["wires"][1]["segments"].append([[38, 0], [38, 5], [42, 5], [42, 0]])
    result = inspect(changed, row)
    assert result["gate_anchors"][0]["continuous"] and not result["complete_branch"]
    passed.append(expected[4])
    changed = copy.deepcopy(drawing)
    changed["devices"][1]["pins"][1]["xy"] = [0, -10]
    assert not inspect(changed, row)["complete_branch"]
    passed.append(expected[5])
    changed = copy.deepcopy(drawing)
    changed["devices"][2]["pins"][1]["net"] = "other"
    try:
        inspect(changed, row)
    except ValueError as error:
        assert "gate binding" in str(error)
    else:
        raise AssertionError("wrong gate binding accepted")
    passed.append(expected[6])
    assert passed == expected
    return passed


def inspect(drawing, row):
    """Measure actual output terminals and physical ink for one branch."""
    devices = {d["name"]: d for d in drawing["devices"]}
    r, v = devices[row["card"]], devices[row["source"]]
    a, b = [pin(r, n, True) for n in (row["junction"], row["gate_net"])]
    signal, ground = [pin(v, n, True) for n in (row["junction"], row["ground"])]
    segments = {}
    for net in (row["junction"], row["gate_net"]):
        segments[net] = [[a, b] for w in drawing["wires"] if w["net"].lower() == net
                         for poly in w["segments"] for a, b in zip(poly, poly[1:])]
    source_leg = connection(segments[row["junction"]], [signal, a])
    source_leg["segments"] = segments[row["junction"]]
    anchors = []
    for name in row["mos"]:
        gate = [p for p in devices[name]["pins"] if p["term"] == "g"]
        if len(gate) != 1 or gate[0]["net"].lower() != row["gate_net"]:
            raise ValueError("native MOS gate binding differs from the source: " + name)
        anchors.append(dict(card=name, **gate_anchor(a, b, signal, channel(devices[name], True)[2],
                                                    segments[row["gate_net"]])))
    geometry = dict(resistor_horizontal=a[1] == b[1] and a[0] != b[0],
                    source_vertical=signal[0] == ground[0], source_ground_below=signal[1] < ground[1],
                    source_signal_at_or_below_resistor=signal[1] >= a[1])
    return dict(resistor_ends=[a, b], source_ends=[signal, ground], geometry=geometry,
                source_leg=source_leg, gate_segments=segments[row["gate_net"]], gate_anchors=anchors,
                complete_branch=all(geometry.values()) and source_leg["continuous"] and
                any(g["admitted"] for g in anchors))


def summarize(rows, label):
    name = lambda row: row["id"] + ":" + row["card"]
    result = {key: [name(r) for r in rows if r[label]["geometry"][key]]
              for key in ("resistor_horizontal", "source_vertical", "source_ground_below",
                          "source_signal_at_or_below_resistor")}
    result.update(source_leg_connected=[name(r) for r in rows if r[label]["source_leg"]["continuous"]],
                  same_anchor_straight_gate=[name(r) for r in rows if any(g["admitted"] for g in r[label]["gate_anchors"])],
                  complete_branch=[name(r) for r in rows if r[label]["complete_branch"]],
                  failed_branch=[name(r) for r in rows if not r[label]["complete_branch"]])
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("examples", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--native", action="append", required=True, metavar="LABEL=DIR")
    args = parser.parse_args()
    natives = {}
    for item in args.native:
        label, directory = item.split("=", 1)
        if not label or label == "source" or label in natives:
            raise ValueError("native labels must be distinct and cannot be source")
        natives[label] = Path(directory)
    source = audit(args.examples)
    baseline = json.loads(Path(__file__).with_name("input_resistor_legs_cases.json").read_text())[source["corpus"]]
    if source != baseline:
        raise ValueError("source differs from frozen actual-ink inventory")
    rows, hashes = [], {label: {} for label in natives}
    for evidence in source["selected"]:
        ident, card = evidence["id"], evidence["card"]
        _, candidates = select((args.examples / (ident + ".cir")).read_text())
        selected = [r for r in candidates if r["card"] == card and r["admitted"]]
        if len(selected) != 1:
            raise ValueError("source branch is no longer unique: " + ident + ":" + card)
        row = dict(id=ident, card=card, topology=selected[0], source=dict(
            geometry=evidence["source_geometry"], source_leg=evidence["source_leg"],
            gate_anchors=evidence["gate_anchors"], complete_branch=evidence["complete_branch"]))
        for label, directory in natives.items():
            path = directory / (ident + ".json")
            raw = path.read_bytes()
            hashes[label][path.name] = hashlib.sha256(raw).hexdigest()
            row[label] = inspect(json.loads(raw), selected[0])
        rows.append(row)
    names = [r["id"] + ":" + r["card"] for r in rows]
    if names != source["summary"]["names"]:
        raise ValueError("exact source branch names changed")
    summary = {label: summarize(rows, label) for label in ["source", *natives]}
    result = dict(corpus=source["corpus"], method_checks=method_checks(), names=names, selected=rows, summary=summary,
                  source_sha256=source["source_sha256"], native_sha256=hashes)
    dependencies = ("input_branch_native.py", "input_resistor_legs.py", "input_resistor_legs_cases.json",
                    "input_resistors.py", "input_resistors_cases.json", "sampling_cells.py",
                    "converter_loops.py", "converter_terminals.py", "cross_caps.py", "channel_bridges.py")
    result["dependency_sha256"] = {name: hashlib.sha256(Path(__file__).with_name(name).read_bytes()).hexdigest()
                                   for name in dependencies}
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps({label: {key: len(value) for key, value in metrics.items()}
                      for label, metrics in summary.items()}, indent=2))


if __name__ == "__main__":
    main()
