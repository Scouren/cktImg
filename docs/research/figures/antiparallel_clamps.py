#!/usr/bin/env python3
"""Unique antiparallel clamps: complete source selection and actual SVG ink.

Usage: antiparallel_clamps.py EXAMPLES OUTPUT [--check]

Reselects both source corpora through the existing channel-bridge certificate,
then independently reads all three actual transistor leads and sixteen local
conductor paths. Two additional AG1149 paths retain the continuity regression.
No common column, fixed gap, absolute row or whole-layout parity is asserted.
"""
import argparse
import ast
import copy
import hashlib
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import channel_bridges as channels
import center_tap_connectivity as source
from cross_caps import actual_glyph
import thin_connectivity as ink

EXPECTED = "ag-1048:m5 ag-1048:m6 ag-1052:m6 ag-1052:m7 ag-1149:q3 ag-1149:q4 ag-739:md1 ag-739:md2".split()
PAIRS = ["ag-1048:m5--m6", "ag-1052:m6--m7", "ag-1149:q3--q4", "ag-739:md1--md2"]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def same(actual, expected, context):
    if json.loads(json.dumps(actual)) != json.loads(json.dumps(expected)):
        raise ValueError(context)


def geometry(pins, labels):
    """Literal spatial relations; channel net identities are checked separately."""
    a, b = [p[labels[0]] for p in pins]
    top = 0 if a[1] < b[1] else 1
    bottom = 1 - top
    return dict(horizontal=all(p[labels[0]][1] == p[labels[2]][1] and
                              p[labels[0]][0] != p[labels[2]][0] for p in pins),
                distinct_channel_rows=a[1] != b[1],
                outward_controls=pins[top][labels[1]][1] < pins[top][labels[0]][1] and
                pins[bottom][labels[1]][1] > pins[bottom][labels[0]][1],
                same_net_order=(pins[0][labels[0]][0] < pins[0][labels[2]][0]) ==
                (pins[1][labels[2]][0] < pins[1][labels[0]][0]))


def methods():
    labels = ("D", "G", "S")
    good = [dict(D=[0, 0], G=[20, -20], S=[40, 0]),
            dict(D=[40, 60], G=[20, 80], S=[0, 60])]
    assert all(geometry(good, labels).values())
    names = ["literal_outward_reversed_channels"]
    mutations = [
        ("inward_control_rejected", 0, "G", [20, 20]),
        ("same_channel_row_rejected", 1, "D", [40, 0]),
        ("skew_channel_rejected", 0, "S", [40, 10]),
        ("unmatched_spatial_net_order_rejected", 1, "S", [80, 60]),
        ("coincident_channel_rejected", 0, "S", [0, 0]),
    ]
    for name, member, pin, point in mutations:
        trial = copy.deepcopy(good)
        trial[member][pin] = point
        assert not all(geometry(trial, labels).values()), name
        names.append(name)
    for name, x_sign, y_sign, stagger, reverse in (
        ("staggered_columns_allowed", 1, 1, 200, False),
        ("horizontal_reflection", -1, 1, 0, False),
        ("vertical_reflection", 1, -1, 0, False),
        ("member_permutation", 1, 1, 0, True),
    ):
        trial = [{p: [x_sign * x + 137 + i * stagger, y_sign * y - 49]
                  for p, (x, y) in member.items()} for i, member in enumerate(good)]
        if reverse:
            trial.reverse()
        assert all(geometry(trial, labels).values()), name
        names.append(name)
    return names + ["wire_" + n for n in ink.method_checks()] + ["source_" + n for n in ink.source_checks()]


def dependencies():
    pending, found = [Path(__file__).name], {}
    while pending:
        name = pending.pop()
        if name in found:
            continue
        path = HERE / name
        found[name] = digest(path)
        for node in ast.walk(ast.parse(path.read_text())):
            modules = [n.name for n in node.names] if isinstance(node, ast.Import) else [node.module] if isinstance(node, ast.ImportFrom) else []
            for module in modules:
                local = (module or "").split(".")[0] + ".py"
                if (HERE / local).is_file() and local not in found:
                    pending.append(local)
    found["center_tap_symbols_cases.json"] = digest(HERE / "center_tap_symbols_cases.json")
    return dict(sorted(found.items()))


def path_proof(context, names, indices):
    net = context["cards"][names[0]][indices[0] + 1]
    same(context["cards"][names[1]][indices[1] + 1], net, "different named source nets")
    terms = [("d", "g", "s") if n[0] == "m" else ("c", "b", "e") if n[0] == "q"
             else ("n1", "n2", "n3") if n[0] == "x" else ("a", "b") for n in names]
    row = dict(id=context["human"]["id"], net=net, pins=list(zip(names, indices)),
               terms=[ts[i] for ts, i in zip(terms, indices)])
    proof = source.source(context, row)
    same(proof["status"], "source_connected", "actual source conductor missing: " + str(row))
    return dict(row, proof=proof)


def audit(examples):
    scans = {name: channels.study(examples / name, None) for name in ("analoggenie", "amsnet")}
    selected = [r for r in scans["analoggenie"]["selected"] if "antiparallel_diode_connected" in r["families"]]
    same([r["id"] + ":" + r["card"] for r in selected], EXPECTED, "exact AG cohort changed")
    same([r for r in scans["amsnet"]["selected"] if "antiparallel_diode_connected" in r["families"]], [], "AMS exclusion changed")
    rows, paths = [], []
    for ident in sorted({r["id"] for r in selected}):
        pair = [r for r in selected if r["id"] == ident]
        assert len(pair) == 2 and pair[0]["mates"] == [pair[1]["card"]]
        context = source.native.load_source(examples / "analoggenie", ident)
        human = {r["card"]: r for r in context["human"]["devices"]}
        actual = [actual_glyph(context["root"], human[r["card"]]) for r in pair]
        names = [r["card"] for r in pair]
        cards = [context["cards"][name] for name in names]
        same(cards[0][1:4], [cards[1][3], cards[1][3], cards[1][1]], "own control or reversed net binding changed")
        same(cards[1][1], cards[1][2], "second own control changed")
        labels = ("D", "G", "S") if names[0][0] == "m" else ("C", "B", "E")
        pins = [a["terminals"] for a in actual]
        relations = geometry(pins, labels)
        if not all(relations.values()):
            raise ValueError("actual source relation changed: " + ident)
        midpoint = [sum(p[t][0] for t in (labels[0], labels[2])) / 2 for p in pins]
        rows.append(dict(name=ident + ":" + "--".join(names), id=ident, names=names, cards=cards,
                         source=pair, actual_glyphs=actual, relations=relations,
                         same_midpoint_column=midpoint[0] == midpoint[1], source_sha256=context["source_sha256"]))
        for name in names:
            paths.append(path_proof(context, [name, name], [0, 1]))
        paths.append(path_proof(context, names, [0, 2]))
        paths.append(path_proof(context, names, [2, 0]))
    same([r["name"] for r in rows], PAIRS, "exact source pair names changed")
    centers, _ = source.glyph.replay_source(examples)
    for row in centers:
        source.register(row)
    context = source.native.load_source(examples / "analoggenie", "ag-1149")
    physical = [path_proof(context, ["c2", "q1"], [1, 1]), path_proof(context, ["q3", "xlp"], [0, 1])]
    return dict(selected_names=EXPECTED, pair_names=PAIRS, ams_selected_names=[], rows=rows,
                group_paths=paths, ag1149_regression_paths=physical, methods=methods(),
                corpus_sha256={n: r["corpus_sha256"] for n, r in scans.items()},
                corpus_names={n: sorted(p.name.removesuffix(".human.json") for p in (examples / n).glob("*.human.json")) for n in scans},
                dependency_sha256=dependencies(),
                limits="Eight devices in four correlated AG circuits, none in AMS. No same-column, exact-gap, absolute-row, inductive cross-cap or whole-source equivalence claim. Source label identity never joins conductor ink.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("examples", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    result = audit(args.examples)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    if args.check:
        same(result, json.loads((HERE / "antiparallel_clamps_cases.json").read_text()), "every frozen clamp source field")
    print(json.dumps(dict(names=result["pair_names"], methods=result["methods"],
                         physical_paths=[r["id"] + ":" + r["net"] + ":" + str(r["pins"]) for r in result["group_paths"] + result["ag1149_regression_paths"]]), sort_keys=True))


if __name__ == "__main__":
    main()
