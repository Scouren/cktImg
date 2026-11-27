#!/usr/bin/env python3
"""Actual source geometry and conductor ink for parallel CT tank capacitors.

Usage: center_tap_tanks.py <examples-root> <output.json> [--check]

Reselects the complete CT inventory, then verifies every named capacitor's
own SVG leads and both named-net conductor paths. Cached-only wires are
reported and excluded. Five pairs have unique ownership; four observations
in AG1180 share two capacitors and do not authorize the unique-pair rule.
"""
import argparse
import ast
import copy
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import block_aliases as aliases
import center_tap_symbols as ct
import cross_caps
import thin_connectivity as ink

EXPECTED = "ag-1103:xl1--c1 ag-1147:x1--c ag-1151:xl--c ag-1152:xl1--c1 ag-1152:xl2--c2 ag-1180:xle1--ct1 ag-1180:xle2--ct2 ag-1180:xlo1--ct1 ag-1180:xlo2--ct2".split()
UNIQUE = EXPECTED[:5]
TOLERANCE = 1e-6  # Source SVG cardinal transforms have floating serialization.


def same(actual, expected, context):
    if json.loads(json.dumps(actual)) != json.loads(json.dumps(expected)):
        raise ValueError(context)


def near(a, b):
    return abs(a - b) <= TOLERANCE


def axis(a, b):
    if near(a[0], b[0]) and not near(a[1], b[1]):
        return "vertical"
    if near(a[1], b[1]) and not near(a[0], b[0]):
        return "horizontal"
    return "coincident" if all(near(x, y) for x, y in zip(a, b)) else "diagonal"


def geometry(points):
    """Same named ends, midpoint, parallel axis, and opposite tap half-plane."""
    a, b, tap, ca, cb = points
    coil_axis, cap_axis = axis(a, b), axis(ca, cb)
    valid = coil_axis in ("horizontal", "vertical")
    direction = 0 if coil_axis == "horizontal" else 1
    across = 1 - direction
    middle = [(x + y) / 2 for x, y in zip(a, b)]
    cap_middle = [(x + y) / 2 for x, y in zip(ca, cb)]
    return dict(coil_axis=coil_axis, capacitor_axis=cap_axis,
                parallel=valid and coil_axis == cap_axis,
                same_axial_center=valid and near(middle[direction], cap_middle[direction]),
                tap_on_transverse_axis=valid and near(tap[direction], middle[direction]) and
                not near(tap[across], middle[across]),
                matched_net_order=valid and (b[direction] - a[direction]) * (cb[direction] - ca[direction]) > 0,
                cap_opposes_tap=valid and (cap_middle[across] - middle[across]) * (tap[across] - middle[across]) < 0)


def complete(observed):
    return all(observed[k] for k in ("parallel", "same_axial_center", "tap_on_transverse_axis",
                                    "matched_net_order", "cap_opposes_tap"))


def methods():
    good = [[-50, 0], [50, 0], [0, 20], [-20, -40], [20, -40]]
    assert complete(geometry(good))
    names = ["literal_parallel_tank"]
    for name, mutate in (
        ("same_tap_half_plane_rejected", lambda p: [p[0], p[1], p[2], [-20, 40], [20, 40]]),
        ("crossed_outer_bindings_rejected", lambda p: [p[0], p[1], p[2], p[4], p[3]]),
        ("shifted_midpoint_rejected", lambda p: [p[0], p[1], p[2], [-10, -40], [30, -40]]),
        ("skew_capacitor_rejected", lambda p: [p[0], p[1], p[2], p[3], [20, -30]]),
        ("skew_tap_rejected", lambda p: [p[0], p[1], [10, 20], p[3], p[4]]),
        ("collapsed_coil_rejected", lambda p: [p[0], p[0], p[2], p[3], p[4]]),
    ):
        assert not complete(geometry(mutate(copy.deepcopy(good))))
        names.append(name)
    for turn in range(4):
        for mirror in (False, True):
            points = []
            for x, y in good:
                if mirror:
                    x = -x
                for _ in range(turn):
                    x, y = -y, x
                points.append([x + 137, y - 49])
            assert complete(geometry(points))
    names.append("all_eight_poses_and_translation")
    names += ["wire_" + n for n in ink.method_checks()]
    names += ["source_" + n for n in ink.source_checks()]
    return names


def dependencies():
    pending, found = [Path(__file__).name], {}
    while pending:
        name = pending.pop()
        if name in found:
            continue
        path = HERE / name
        found[name] = ink.digest(path)
        for node in ast.walk(ast.parse(path.read_text())):
            modules = [n.name for n in node.names] if isinstance(node, ast.Import) else [node.module] if isinstance(node, ast.ImportFrom) else []
            for module in modules:
                local = (module or "").split(".")[0] + ".py"
                if (HERE / local).is_file() and local not in found:
                    pending.append(local)
    found["center_tap_symbols_cases.json"] = ink.digest(HERE / "center_tap_symbols_cases.json")
    return dict(sorted(found.items()))


def audit(examples):
    inventory = json.loads((HERE / "center_tap_symbols_cases.json").read_text())
    unknown, selected, counts, hashes = ct.scan(examples)
    same(unknown, inventory["unknown_outer_families"], "complete outer-family inventory changed")
    same(counts, inventory["corpus_drawings"], "complete source corpus names changed")
    same(hashes, inventory["corpus_contract_sha256"], "source corpus content changed")
    frozen = {r["id"] + ":" + r["card"]: r for r in inventory["selected"]}
    same(sorted(frozen), ct.EXPECTED, "frozen CT names changed")
    rows, contexts = [], {}
    for row in selected:
        key = row["id"] + ":" + row["card"]
        expected = frozen[key]
        same(row, {k: expected[k] for k in row}, "source ordered CT contract changed: " + key)
        if row["id"] not in contexts:
            contexts[row["id"]] = ink.load_source(examples / row["corpus"], row["id"])
        context = contexts[row["id"]]
        for suffix, digest in expected["source_sha256"].items():
            same(ink.digest(examples / row["corpus"] / (row["id"] + suffix)), digest, "source hash " + key + suffix)
        device, group, parent = aliases.source_group(context["human"], context["root"], row["card"])
        actual = ct.center_tap_ink(ct.primitives(group, parent))
        bound = {"n" + p: net.lower() for p, net in device["nets"].items()}
        same(actual, expected["actual_terminals"], "actual CT own leads " + key)
        same(bound, dict(zip(row["ports"], row["bindings"])), "CT SVG/card binding " + key)
        ends = {bound["n1"], bound["n2"]}
        for name, words in context["cards"].items():
            if not name.startswith("c") or set(words[1:3]) != ends:
                continue
            cap = context["devices"][name]
            glyph = cross_caps.actual_glyph(context["root"], cap)
            same(sorted(glyph["terminals"]), sorted(cap["nets"]), "capacitor actual pin names")
            same(sorted(n.lower() for n in cap["nets"].values()), sorted(words[1:3]), "capacitor SVG/card binding")
            legs, matched = [], []
            for port in ("n1", "n2"):
                net = bound[port]
                names = [p for p, n in cap["nets"].items() if n.lower() == net]
                if len(names) != 1:
                    raise ValueError("ambiguous capacitor binding: " + key + "--" + name)
                targets = [actual[port], glyph["terminals"][names[0]]]
                segments, missing = ink.verified_segments(context["human"], net, context["ink"])
                proof = ink.source_connection(context, segments, targets)
                if not proof["continuous"]:
                    raise ValueError("source tank leg is not actual conductor ink: " + key + "--" + name + ":" + port)
                legs.append(dict(net=net, port=port, capacitor_pin=names[0], actual_targets=targets,
                                 cache_segments_without_ink=missing, verified_segments=segments, connection=proof))
                matched.append(targets[1])
            owners = sorted(q["card"] for q in selected if q["id"] == row["id"] and
                            {dict(zip(q["ports"], q["bindings"]))[p] for p in ("n1", "n2")} == ends)
            capacitors = sorted(n for n, card in context["cards"].items() if n.startswith("c") and set(card[1:3]) == ends)
            observation = geometry([actual[p] for p in ("n1", "n2", "n3")] + matched)
            if not complete(observation):
                raise ValueError("source tank relation changed: " + key + "--" + name)
            rows.append(dict(name=key + "--" + name, id=row["id"], corpus=row["corpus"], coil=row["card"],
                             capacitor=name, coil_ports=row["ports"], coil_bindings=row["bindings"],
                             capacitor_bindings=words[1:3], actual_coil=actual, actual_capacitor=glyph,
                             net_pair=sorted(ends), coils_on_same_outer_pair=owners, capacitors_on_same_outer_pair=capacitors,
                             unique_owner=len(owners) == 1 and len(capacitors) == 1,
                             geometry=observation, connections=legs, source_sha256=expected["source_sha256"]))
    same([r["name"] for r in rows], EXPECTED, "exact tank relation inventory changed")
    same([r["name"] for r in rows if r["unique_owner"]], UNIQUE, "exact unique-owner inventory changed")
    return dict(rows=rows, names=EXPECTED, unique_names=UNIQUE, shared_names=EXPECTED[5:],
                methods=methods(), dependency_sha256=dependencies(),
                summary=dict(relations=len(rows), capacitors=len({(r["id"], r["capacitor"]) for r in rows}),
                             circuits=len({r["id"] for r in rows}), physical_legs=sum(len(r["connections"]) for r in rows)),
                limits="Nine source relations, not a universal LC layout theorem. Four shared-owner observations are excluded from the unique rule. Actual source wire ink excludes cache-only strokes; world coil pose and absolute spacing are separate questions.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("examples", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    result = audit(args.examples)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    if args.check:
        same(result, json.loads((HERE / "center_tap_tanks_cases.json").read_text()), "frozen tank evidence changed")
    print(json.dumps(result["summary"], sort_keys=True))


if __name__ == "__main__":
    main()
