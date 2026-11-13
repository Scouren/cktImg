#!/usr/bin/env python3
"""Source gate-facing habits, separated from generated placement predictions.

Usage: gate_facing.py EXAMPLES POWER_STUDY OUTPUT [--native SNAPSHOT]

POWER_STUDY is power_paths.py's named source selection. The upright condition
requires exactly one other active terminal on the gate net, level with the
gate, and to one side of its channel. The horizontal condition requires all
other active terminals to lie strictly on the same side of the channel.
Active terminals are transistor D/S/C/E and explicitly named block outputs;
passive loads and other gates do not vote. No device polarity selects a side.

The oracle is the source gate coordinate relative to its D/S or C/E midpoint.
The native comparison applies the same conditions to generated coordinates,
using the source's electrical terminal identities. It does not feed source
positions to the engine. Missing/ambiguous correspondences remain named.
Related textbook variants are not independent statistical observations.

Source qualification does not imply generated qualification. A controller
drawn below a source power path can currently be generated beside or above
it. Facing that generated driver cannot recover the source's downward gate
until placement recovers the controller row. The optional native summary
separates this geometry qualification from the source observation; it is
not an assessment of complete schematic quality. Native comparisons use
actual terminal coordinates, stricter than a distinct lattice-row proxy.

The converter selection agrees in 107/107 source cases. Across all flat
MOS, the same condition agrees in 139/142. The three named exceptions
AG809:M10, AG813:M7 and AG3103:M12 keep upward labelled controls belonging
to separate drawing groups. Clock-name or polarity guesses cannot resolve
that local-group exception; it remains a limitation of the broader habit.
"""

import argparse
import collections
import hashlib
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
from mos_forms import rail, read_cards


PAIRS = (("D", "S", "G"), ("C", "E", "B"))
OUTPUTS = {"out", "vout", "y", "out+", "out-", "vop", "von", "o", "vo"}
ALIASES = {"out": ("vout", "o", "vo"), "out+": ("vop",), "out-": ("von",)}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def frame(device):
    terminals = device["terminals"]
    for a, b, g in PAIRS:
        if all(k in terminals for k in (a, b, g)):
            first, last = terminals[a], terminals[b]
            if (first[0] == last[0]) == (first[1] == last[1]):
                raise ValueError("ambiguous channel geometry: " + device["card"])
            center = [(first[i] + last[i]) / 2 for i in (0, 1)]
            return a, b, g, center, 0 if first[0] == last[0] else 1
    return None


def direction(value, center, tolerance, axis):
    if abs(value - center) <= tolerance:
        return None
    return ("left", "right")[value > center] if axis == 0 else ("up", "down")[value > center]


def drivers(devices, target, gate_net):
    """Source terminal identities; no coordinate contributes to this selection."""
    result = []
    for device in devices:
        if device["card"] == target:
            continue
        trans = frame(device)
        for terminal, net in device["nets"].items():
            if net != gate_net:
                continue
            active = trans is not None and terminal in trans[:2]
            output = device["card"].startswith("x") and terminal.lower() in OUTPUTS
            if active or output:
                result.append(dict(card=device["card"], terminal=terminal,
                                   kind="transistor" if active else "block",
                                   point=device["terminals"][terminal]))
    return result


def predict(axis, center, gate, points, tolerance):
    """Returns a side only for the bounded upright or horizontal condition."""
    if axis == 0:
        if len(points) != 1 or abs(points[0][1] - gate[1]) > tolerance:
            return None
        return direction(points[0][0], center[0], tolerance, axis)
    sides = {direction(p[1], center[1], tolerance, axis) for p in points}
    return next(iter(sides)) if len(sides) == 1 and None not in sides else None


def native_pin(device, source_terminal, net):
    # netlist.zig canonicalizes the sole accepted ground alias to net zero.
    net = "0" if net == "gnd" else net
    names = (source_terminal.lower(), *ALIASES.get(source_terminal.lower(), ()))
    matches = [p for p in device["pins"] if p["term"].lower() in names and p["net"] == net]
    if not matches:
        matches = [p for p in device["pins"] if p["net"] == net]
    if len(matches) != 1:
        raise ValueError("ambiguous/missing terminal " + device["name"] + ":" + source_terminal)
    return matches[0]["xy"]


def native_prediction(row, human, drawing):
    source = {d["card"]: d for d in human["devices"]}
    native = {d["name"].lower(): d for d in drawing["devices"]}
    target = source[row["card"]]
    a, b, g, _, _ = frame(target)
    placed = native[row["card"]]
    first, last = [native_pin(placed, k, target["nets"][k]) for k in (a, b)]
    if (first[0] == last[0]) == (first[1] == last[1]):
        raise ValueError("ambiguous native channel")
    axis = 0 if first[0] == last[0] else 1
    if axis != row["axis"]:
        return dict(prediction=None, reason="channel orientation differs")
    center = [(first[i] + last[i]) / 2 for i in (0, 1)]
    gate = native_pin(placed, g, row["net"])
    points = [native_pin(native[d["card"]], d["terminal"], row["net"]) for d in row["drivers"]]
    return dict(prediction=predict(axis, center, gate, points, 2),
                current=direction(gate[axis], center[axis], 2, axis),
                center=center, gate=gate, drivers=points)


def summarize(rows):
    selected = [r for r in rows if r["prediction"]]
    good = [r["name"] for r in selected if r["prediction"] == r["gate"]]
    bad = [r["name"] for r in selected if r["prediction"] != r["gate"]]
    return dict(inventory=len(rows), source_gates=dict(collections.Counter(r["gate"] for r in rows)),
                selected=[r["name"] for r in selected], agrees=good, exceptions=bad,
                abstains=[r["name"] for r in rows if r["prediction"] is None])


def summarize_native(rows):
    selected = [r for r in rows if r.get("native", {}).get("prediction")]
    return dict(selected=[r["name"] for r in selected],
                source_qualified=[r["name"] for r in selected if r["prediction"]],
                would_change=[r["name"] for r in selected
                              if r["native"]["prediction"] != r["native"]["current"]],
                prediction_counts=dict(collections.Counter(r["native"]["prediction"] for r in selected)),
                abstains=[r["name"] for r in rows if not r.get("native", {}).get("prediction")])


def self_test():
    # Independent coordinates: a side-by-side amplifier, a controller below
    # a channel, an ambiguous opposing pair, and an external control only.
    assert predict(0, [100, 40], [70, 40], [[20, 40]], 2) == "left"
    assert predict(0, [100, 40], [70, 40], [[20, 100]], 2) is None
    assert predict(0, [100, 40], [70, 40], [[20, 40], [10, 40]], 2) is None
    assert predict(1, [100, 40], [100, 70], [[20, 100], [20, 140]], 2) == "down"
    assert predict(1, [100, 40], [100, 70], [[20, 100], [20, 0]], 2) is None
    assert predict(1, [100, 40], [100, 70], [], 2) is None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("examples", type=Path)
    parser.add_argument("power_study", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--native", type=Path)
    args = parser.parse_args()
    self_test()
    power = json.loads(args.power_study.read_text())
    power_names = {r["id"] + ":" + r["card"] for r in power["selected"]}
    rows, sources, errors = [], [], []
    native_hashes = {}
    files = sorted(args.examples.glob("*.human.json"))
    if not files:
        parser.error("no human drawings")
    for path in files:
        human = json.loads(path.read_text())
        cid = human["id"]
        deck = path.with_name(cid + ".cir")
        svg = path.with_name(cid + ".svg")
        cards = read_cards(deck.read_text())
        sources.append(dict(id=cid, human_sha256=digest(path), deck_sha256=digest(deck), svg_sha256=digest(svg)))
        drawing = None
        if args.native and (args.native / (cid + ".json")).exists():
            native_path = args.native / (cid + ".json")
            drawing = json.loads(native_path.read_text())
            native_hashes[cid] = digest(native_path)
        for device in human["devices"]:
            f = frame(device)
            if not f:
                continue
            a, b, g, center, axis = f
            name = cid + ":" + device["card"]
            if axis == 1 and not device["card"].startswith("m"):
                continue
            gate_net = device["nets"][g]
            if rail(gate_net):
                continue
            if axis == 1 and len({device["nets"][k] for k in (a, b, g)}) != 3:
                continue
            if device["card"].startswith("m"):
                for terminal, net in zip((a, g, b), cards[device["card"]][1:4]):
                    if device["nets"][terminal] != net:
                        raise ValueError(name + ": source/deck terminal mismatch")
            active = drivers(human["devices"], device["card"], gate_net)
            gate = device["terminals"][g]
            tolerance = human["unit"] / 20
            row = dict(name=name, id=cid, card=device["card"], type=device["type"], axis=axis,
                       net=gate_net, center=center, gate_point=gate, drivers=active,
                       gate=direction(gate[axis], center[axis], tolerance, axis),
                       prediction=predict(axis, center, gate, [d["point"] for d in active], tolerance))
            if args.native:
                try:
                    if drawing is None:
                        raise ValueError("missing native drawing")
                    row["native"] = native_prediction(row, human, drawing)
                except (KeyError, ValueError) as error:
                    row["native"] = dict(error=str(error))
                    errors.append(dict(name=name, error=str(error)))
            rows.append(row)
    rows.sort(key=lambda r: r["name"])
    groups = {"upright_aligned_unique": [r for r in rows if r["axis"] == 0],
              "horizontal_power_unanimous": [r for r in rows if r["name"] in power_names],
              "horizontal_all_unanimous": [r for r in rows if r["axis"] == 1]}
    observed_power = {r["name"] for r in groups["horizontal_power_unanimous"]}
    if observed_power != power_names:
        raise ValueError("power inventory mismatch: " + str(sorted(observed_power ^ power_names)))
    summary = {name: summarize(rs) for name, rs in groups.items()}
    native_summary = {name: summarize_native(rs) for name, rs in groups.items()} if args.native else None
    # Named negative observations prevent accidental promotion to a universal
    # polarity/driver rule. Their disappearance is a study change to review.
    if args.examples.name == "analoggenie":
        assert summary["upright_aligned_unique"]["exceptions"] == ["ag-1702:m4", "ag-1738:m1", "ag-1738:m2"]
        assert summary["horizontal_all_unanimous"]["exceptions"] == ["ag-3103:m12", "ag-809:m10", "ag-813:m7"]
        assert all(n in summary["horizontal_power_unanimous"]["abstains"] for n in ("ag-1191:m1", "ag-1191:m2", "ag-1191:m3"))
    corpus_hash = hashlib.sha256(json.dumps(sources, sort_keys=True).encode()).hexdigest()
    result = dict(schema=1, corpus_sha256=corpus_hash, power_study_sha256=digest(args.power_study),
                  script_sha256=digest(Path(__file__)), sources=sources, summary=summary,
                  native_summary=native_summary, native_sha256=native_hashes,
                  native_errors=errors, rows=rows)
    if args.native and (args.native / "cktimg-json").exists():
        result["native_binary_sha256"] = digest(args.native / "cktimg-json")
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps({name: {"inventory": r["inventory"], "selected": len(r["selected"]),
                            "agrees": len(r["agrees"]), "exceptions": r["exceptions"],
                            "source_gates": r["source_gates"]} for name, r in summary.items()}, indent=2))
    if errors:
        print("named native correspondence errors:", json.dumps(errors), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
