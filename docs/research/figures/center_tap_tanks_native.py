#!/usr/bin/env python3
"""Measure the five unique source tanks in frozen native corpus outputs.

Usage: center_tap_tanks_native.py <examples-root> <output.json>
       --native LABEL=DIR [--native LABEL=DIR ...] [--require-complete LABEL]
       [--check]

Each native directory has its corpus scorecard and matching executable.
This bounded audit checks all 25 ordered electrical bindings, actual public
terminal geometry and ten physical legs. Labels cannot supply continuity.
Whole source glyph/world-pose equivalence and whole-circuit connectivity
remain separate audits; the four shared-owner source relations are excluded.
"""
import argparse
import copy
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import center_tap_tanks as source
import thin_connectivity as ink


def device(drawing, name):
    matches = [d for d in drawing["devices"] if d["name"] == name]
    if len(matches) != 1:
        raise ValueError("no unique native device: " + name)
    return matches[0]


def inspect(drawing, row):
    coil, cap = device(drawing, row["coil"]), device(drawing, row["capacitor"])
    source.same([(p["term"], p["net"]) for p in coil["pins"]],
                list(zip(row["coil_ports"], row["coil_bindings"])), "ordered native coil bindings")
    source.same([(p["term"], p["net"]) for p in cap["pins"]],
                list(zip(["a", "b"], row["capacitor_bindings"])), "ordered native capacitor bindings")
    named = {p["term"]: (i, p) for i, p in enumerate(coil["pins"])}
    actual, matched, legs = {p: named[p][1]["xy"] for p in ("n1", "n2", "n3")}, [], []
    for term in ("n1", "n2"):
        index, pin = named[term]
        matches = [(i, p) for i, p in enumerate(cap["pins"]) if p["net"] == pin["net"]]
        if len(matches) != 1:
            raise ValueError("ambiguous native outer binding")
        ci, cp = matches[0]
        keys = [(row["coil"], index), (row["capacitor"], ci)]
        pins = {keys[0]: (pin["net"], tuple(pin["xy"]), pin["term"]),
                keys[1]: (cp["net"], tuple(cp["xy"]), cp["term"])}
        components = ink.components(drawing, pin["net"], keys, pins)
        continuous = components[keys[0]] == components[keys[1]]
        legs.append(dict(port=term, net=pin["net"], named_pins=keys, targets=[pin["xy"], cp["xy"]],
                         continuous=continuous, segments=ink.segments(drawing, pin["net"])))
        matched.append(cp["xy"])
    geometry = source.geometry([actual[p] for p in ("n1", "n2", "n3")] + matched)
    return dict(geometry=geometry, actual_coil=actual, actual_capacitor_by_outer_net=matched,
                coil_pose={k: coil[k] for k in ("rot", "mirror")}, legs=legs,
                complete_relative_geometry=source.complete(geometry),
                both_legs_continuous=all(p["continuous"] for p in legs),
                complete_tank=source.complete(geometry) and all(p["continuous"] for p in legs),
                source_world_coil_axis_matches=geometry["coil_axis"] == row["geometry"]["coil_axis"])


def methods():
    def pin(term, net, at):
        return dict(term=term, net=net, xy=at)
    row = dict(coil="x", capacitor="c", coil_ports=["n1", "n2", "n3"],
               coil_bindings=["left", "right", "tap"], capacitor_bindings=["right", "left"],
               geometry=dict(coil_axis="horizontal"))
    drawing = dict(devices=[dict(name="x", rot=0, mirror=False, pins=[pin("n1", "left", [-50, 0]),
        pin("n2", "right", [50, 0]), pin("n3", "tap", [0, 20])]),
        dict(name="c", pins=[pin("a", "right", [20, -40]), pin("b", "left", [-20, -40])])],
        wires=[dict(net="left", segments=[[[-50, 0], [-50, -40], [-20, -40]]]),
               dict(net="right", segments=[[[50, 0], [50, -40], [20, -40]]])], junctions=[], labels=[])
    assert inspect(drawing, row)["complete_tank"]
    names = ["literal_native_tank"]
    for name, mutation in (
        ("wrong_coil_order_rejected", lambda d: d["devices"][0]["pins"].reverse()),
        ("wrong_cap_binding_rejected", lambda d: d["devices"][1]["pins"][0].update(net="other")),
        ("duplicate_native_device_rejected", lambda d: d["devices"].append(copy.deepcopy(d["devices"][0]))),
    ):
        changed = copy.deepcopy(drawing)
        mutation(changed)
        try:
            inspect(changed, row)
        except ValueError:
            names.append(name)
        else:
            raise AssertionError(name)
    changed = copy.deepcopy(drawing)
    changed["wires"][0]["segments"] = [[[-50, 0], [-50, -15]], [[-50, -25], [-50, -40], [-20, -40]]]
    changed["labels"] = [dict(net="left", at=[-50, -15]), dict(net="left", at=[-50, -25])]
    assert not inspect(changed, row)["both_legs_continuous"]
    names.append("labels_cannot_bridge_gap")
    changed["wires"].append(dict(net="other", segments=[[[-50, -15], [-50, -25]]]))
    assert not inspect(changed, row)["complete_tank"]
    names.append("foreign_wire_cannot_bridge_gap")
    changed = copy.deepcopy(drawing)
    changed["devices"][1]["pins"][0]["xy"] = [30, -40]
    assert not inspect(changed, row)["complete_relative_geometry"]
    names.append("off_center_native_rejected")
    changed = copy.deepcopy(drawing)
    changed["devices"][0]["pins"] = [changed["devices"][0]["pins"][i] for i in (2, 1, 0)]
    reordered = dict(row, coil_ports=["n3", "n2", "n1"], coil_bindings=["tap", "right", "left"])
    assert inspect(changed, reordered)["complete_tank"]
    names.append("declared_port_permutation_preserves_semantics")
    return names


def audit(examples, native):
    study = source.audit(examples)
    source.same(study, json.loads((HERE / "center_tap_tanks_cases.json").read_text()), "source study differs from frozen inventory")
    rows = [r for r in study["rows"] if r["unique_owner"]]
    result = dict(names=source.UNIQUE, excluded_shared_names=source.EXPECTED[5:],
                  methods=methods(), runs={}, transitions={},
                  dependency_sha256={**source.dependencies(), **{n: ink.digest(HERE / n) for n in
                      ("center_tap_tanks_native.py", "center_tap_tanks_cases.json")}})
    for label, directory in native.items():
        score = json.loads((directory / "scorecard.json").read_text())
        source.same(ink.digest(directory / "cktimg-json"), score["binary_sha256"], "native binary differs from scorecard")
        source.same(ink.digest(examples / "analoggenie" / "index.json"), score["index_sha256"], "source index differs from scorecard")
        observed, hashes = [], {}
        for row in rows:
            ident = row["id"]
            entry = score["results"][ident]
            path = directory / (ident + ".json")
            paths = dict(deck_sha256=examples / row["corpus"] / (ident + ".cir"),
                         source_sha256=examples / row["corpus"] / (ident + ".human.json"),
                         preview_sha256=examples / row["corpus"] / (ident + ".svg"),
                         geometry_sha256=path, report_sha256=directory / (ident + ".report.json"))
            for field, value in paths.items():
                source.same(ink.digest(value), entry[field], "scored artifact changed: " + ident + ":" + field)
            hashes[ident] = {field: ink.digest(value) for field, value in paths.items()}
            observed.append(dict(name=row["name"], **inspect(json.loads(path.read_text()), row)))
        source.same([r["name"] for r in observed], source.UNIQUE, "exact native pair names changed")
        result["runs"][label] = dict(rows=observed, hashes=hashes, binary_sha256=score["binary_sha256"],
            scorecard_sha256=ink.digest(directory / "scorecard.json"),
            summary={k: [r["name"] for r in observed if r[k]] for k in
                     ("complete_relative_geometry", "both_legs_continuous", "complete_tank", "source_world_coil_axis_matches")},
            failed_relative=[r["name"] for r in observed if not r["complete_relative_geometry"]],
            failed_legs=[r["name"] + ":" + p["port"] for r in observed for p in r["legs"] if not p["continuous"]])
    labels = list(native)
    for label in labels[1:]:
        before = result["runs"][labels[0]]["rows"]
        after = result["runs"][label]["rows"]
        result["transitions"][label] = dict(baseline=labels[0],
            coil_pose_changes=[a["name"] for a, b in zip(before, after) if a["coil_pose"] != b["coil_pose"]],
            gains=[a["name"] for a, b in zip(before, after) if not a["complete_tank"] and b["complete_tank"]],
            losses=[a["name"] for a, b in zip(before, after) if a["complete_tank"] and not b["complete_tank"]])
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("examples", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--native", action="append", required=True, metavar="LABEL=DIR")
    parser.add_argument("--require-complete", action="append", default=[])
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    native = {}
    for item in args.native:
        label, directory = item.split("=", 1)
        if not label or label in native:
            raise ValueError("native labels must be nonempty and unique")
        native[label] = Path(directory)
    result = audit(args.examples, native)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    if args.check:
        source.same(result, json.loads((HERE / "center_tap_tanks_native_cases.json").read_text()), "native tank inventory changed")
    for label in args.require_complete:
        source.same(result["runs"][label]["summary"]["complete_tank"], source.UNIQUE, "incomplete native tanks: " + label)
    print(json.dumps({label: {k: len(v) for k, v in run["summary"].items()} for label, run in result["runs"].items()}, sort_keys=True))


if __name__ == "__main__":
    main()
