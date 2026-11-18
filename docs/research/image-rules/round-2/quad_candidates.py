#!/usr/bin/env python3
"""Raw four-MOS source/drain rectangles, followed by a bounded gate pattern.

No placement admission. Count every competing MOS in each D/S slot before
model, parameter, body or gate filtering. The exact candidate names are an
independent frozen census expectation; source images decide geometric claims.
"""

import argparse
import collections
import copy
import hashlib
import itertools
import json
from pathlib import Path

import bodies_census

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
EXPECTED = [80, 82, 496, 500, 504, 511, 512, 514, 515, 516, 517, 557, 570,
            572, 574, 584, 647, 660, 786, 805, 813, 1044, 1091, 1092, 1093, 1098]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def candidates(rows):
    on = collections.defaultdict(lambda: collections.defaultdict(list))
    for row in rows:
        if row["kind"] == "m":
            on[row["nets"][2]][row["nets"][0]].append(row)
    result = []
    for s, t in itertools.combinations(sorted(on), 2):
        for d, e in itertools.combinations(sorted(on[s].keys() & on[t].keys()), 2):
            if len({s, t, d, e}) != 4:
                continue
            slots = [sorted(on[x][y], key=lambda r: r["card"])
                     for x in (s, t) for y in (d, e)]
            reasons = []
            quad = [slot[0] for slot in slots] if all(len(slot) == 1 for slot in slots) else []
            if not quad:
                reasons.append("competing_MOS_in_D_S_slot")
            else:
                gates = [r["nets"][1] for r in quad]
                if len({tuple(r["nonterminal_tokens"]) for r in quad}) != 1:
                    reasons.append("different_model_or_parameters")
                if len({r["nets"][3] for r in quad}) != 1:
                    reasons.append("different_body_binding")
                if len(set(gates)) != 2 or set(gates) & {s, t, d, e}:
                    reasons.append("not_two_distinct_nonchannel_gate_nets")
                elif not (gates[0] == gates[3] and gates[1] == gates[2]):
                    reasons.append("gate_assignments_not_crossed")
            members = sorted(r["card"] for slot in slots for r in slot)
            result.append({"sources": [s, t], "drains": [d, e],
                           "raw_slots": [[r["card"] for r in slot] for slot in slots],
                           "members": members, "reasons": reasons,
                           "status": "decline" if reasons else "raw_shape_only",
                           "ordered_bindings": {r["card"]: r["nets"] for r in quad}})
    return result


def selected(rows):
    return [r for r in candidates(rows) if r["status"] == "raw_shape_only"]


def controls():
    _, rows = bodies_census.parse(""".model n nmos
.subckt dut a b x y u v bulk
M1 x a u bulk n w=1
M2 y b u bulk n w=1
M3 x b v bulk n w=1
M4 y a v bulk n w=1
.ends dut
""")
    assert len(selected(rows)) == 1
    assert selected(rows)[0]["members"] == ["m1", "m2", "m3", "m4"]
    checks = ["literal_complete_quad"]
    for name, edit in (
        ("gate_changed", lambda q: q[0]["nets"].__setitem__(1, "third_gate")),
        ("drain_source_swapped", lambda q: q[0]["nets"].__setitem__(slice(0, 3, 2), ["u", "x"])),
        ("body_changed", lambda q: q[0]["nets"].__setitem__(3, "other_body")),
        ("model_changed", lambda q: q[0]["nonterminal_tokens"].__setitem__(0, "other_model")),
        ("parameter_changed", lambda q: q[0]["nonterminal_tokens"].__setitem__(1, "w=2")),
    ):
        changed = copy.deepcopy(rows)
        edit(changed)
        assert not selected(changed), name
        checks.append(name + "_declines")
    for wrong_model in (False, True):
        changed = copy.deepcopy(rows)
        competitor = copy.deepcopy(changed[0])
        competitor["card"] = "m5"
        if wrong_model:
            competitor["nonterminal_tokens"][0] = "unmatched_model"
        changed.append(competitor)
        raw = candidates(changed)
        assert len(raw) == 1 and raw[0]["reasons"] == ["competing_MOS_in_D_S_slot"]
        checks.append("raw_competitor_before_model_filter_" + str(wrong_model))
    assert candidates(list(reversed(rows))) == candidates(rows)
    checks.append("card_order_invariant")
    changed = copy.deepcopy(rows)
    netmap = {n: "node_" + str(i) for i, n in enumerate(reversed(sorted({n for r in rows for n in r["nets"]})))}
    invnet = {v: k for k, v in netmap.items()}
    for i, row in enumerate(changed):
        row["card"] = "m" + str(20 - i)
        row["nets"] = [netmap[n] for n in row["nets"]]
    renamed = selected(changed)
    assert len(renamed) == 1
    restored = sorted(tuple(invnet[n] for n in pins) for pins in renamed[0]["ordered_bindings"].values())
    assert restored == sorted(tuple(r["nets"]) for r in rows)
    return checks + ["bijective_name_transport_preserves_ordered_bindings"]


def collect():
    manifest = json.loads((HERE / "manifest.json").read_text())
    inventory_path = Path(manifest["prior_audit"]) / "all-images.json"
    assert digest(inventory_path) == manifest["frozen_inventory_sha256"]
    rows, hits, hashes = [], [], {}
    for item in json.loads(inventory_path.read_text()):
        path = Path(item["netlist"])
        assert digest(path) == item["netlist_sha256"]
        _, cards = bodies_census.parse(path.read_text())
        raw = candidates(cards)
        hashes[item["id"]] = digest(path)
        for candidate in raw:
            candidate = {"id": item["id"], **candidate}
            rows.append(candidate)
            if candidate["status"] == "raw_shape_only":
                hits.append(candidate)
    assert [r["id"] for r in hits] == ["ag-" + str(n) for n in EXPECTED]
    return {"scope": __doc__, "script_sha256": digest(Path(__file__)),
            "parser_sha256": digest(HERE / "bodies_census.py"),
            "inventory_sha256": digest(inventory_path), "deck_sha256": hashes,
            "controls": controls(), "raw_candidates": rows, "shape_candidates": hits}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--check", type=Path)
    args = parser.parse_args()
    result = collect()
    if args.check:
        assert result == json.loads(args.check.read_text())
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"raw_candidates": len(result["raw_candidates"]),
                      "shape_candidates": [r["id"] for r in result["shape_candidates"]],
                      "controls": result["controls"]}))


if __name__ == "__main__":
    main()
