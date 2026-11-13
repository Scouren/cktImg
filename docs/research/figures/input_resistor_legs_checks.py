#!/usr/bin/env python3
"""Literal and source-mutation oracles for the input resistor ink audit.

Run with python3 -B. No engine execution and no production test gate.
"""
import copy
import json
from pathlib import Path
import xml.etree.ElementTree as ET

from cross_caps import conductor_ink
from input_resistor_legs import connection, gate_anchor, inspect, verified_segments
from input_resistors import actual, select


def main():
    names = []
    a, b, source, gate = [2, 0], [4, 0], [0, 2], [10, 0]
    straight = [[[4, 0], [7, 0]], [[7, 0], [10, 0]]]
    assert gate_anchor(a, b, source, gate, straight)["admitted"]
    names.append("touching_horizontal_pieces")
    assert gate_anchor(a, b, source, gate, straight[::-1])["admitted"]
    names.append("wire_order_independent")
    gap = [[[4, 0], [6, 0]], [[8, 0], [10, 0]]]
    assert not gate_anchor(a, b, source, gate, gap)["continuous"]
    names.append("named_gap_does_not_connect")
    detour = gap + [[[6, 0], [6, 2]], [[6, 2], [8, 2]], [[8, 2], [8, 0]]]
    measured = gate_anchor(a, b, source, gate, detour)
    assert measured["continuous"] and not measured["straight_horizontal"] and not measured["admitted"]
    names.append("continuous_detour_is_not_straight")
    assert not gate_anchor(a, b, source, [10, 1], straight)["admitted"]
    names.append("actual_gate_off_row_rejected")
    assert connection([[[0, 0], [10, 0]], [[5, 0], [5, 5]]], [[0, 0], [5, 5]])["continuous"]
    names.append("endpoint_t_junction_connects")
    human = dict(wires=[dict(net="gate", segments=copy.deepcopy(gap)), dict(net="other", segments=[[[6, 0], [8, 0]]])])
    ink = gap + [[[6, 0], [8, 0]]]
    segments, missing = verified_segments(human, "gate", ink)
    assert segments == gap and not missing and not connection(segments, [b, gate])["continuous"]
    names.append("other_net_ink_does_not_fill_gap")
    human["wires"][0]["segments"].append([[6, 0], [8, 0]])
    segments, missing = verified_segments(human, "gate", gap[:2])
    assert missing == [[[6, 0], [8, 0]]] and not connection(segments, [b, gate])["continuous"]
    names.append("cached_only_bridge_is_retained_but_excluded")
    root = ET.fromstring('<svg><g transform="translate(10,20)"><path data-role="conductor-ink" d="M 0 0 L 10 0"/></g></svg>')
    assert conductor_ink(root) == [[[10, 20], [20, 20]]]
    names.append("actual_conductor_transform_applied")
    split = [gate_anchor(a, b, source, [10, 0], []),
             gate_anchor(a, b, source, [1, 0], [[[4, 0], [1, 0]]]),
             gate_anchor(a, b, source, [10, 2], [[[4, 0], [10, 0]], [[10, 0], [10, 2]]])]
    assert any(g["same_row"] for g in split) and any(g["resistor_between"] for g in split) and any(g["continuous"] for g in split)
    assert not any(g["admitted"] for g in split)
    names.append("different_gates_cannot_supply_separate_witnesses")
    corpus = Path(__file__).resolve().parents[3] / "external/examples/analoggenie"
    source_human = json.loads((corpus / "ag-477.human.json").read_text())
    root = ET.parse(corpus / "ag-477.svg").getroot()
    row, = [r for r in select((corpus / "ag-477.cir").read_text())[1] if r["admitted"]]
    evidence = inspect(copy.deepcopy(source_human), root, row)
    gates = {g["card"]: g for g in evidence["gate_anchors"]}
    assert [n for n, g in gates.items() if g["admitted"]] == ["m1"]
    assert gates["m2"]["same_row"] and not gates["m2"]["continuous"]
    assert gates["m4"]["continuous"] and not gates["m4"]["same_row"]
    names.append("ag477_exact_anchor_and_labelled_remote_gate")
    forged = copy.deepcopy(source_human)
    forged["wires"].append(dict(net="x", segments=[[[180, 230], [340, 230]]]))
    evidence = inspect(forged, root, row)
    assert evidence["gate_net"]["cache_segments_without_ink"] == [[[180, 230], [340, 230]]]
    assert [g["card"] for g in evidence["gate_anchors"] if g["admitted"]] == ["m1"]
    names.append("ag477_forged_cache_gate_link_does_not_connect")
    for role, net in (("source", "net0"), ("gate", "x")):
        broken = copy.deepcopy(source_human)
        broken["wires"] = [w for w in broken["wires"] if w["net"] != net]
        assert not inspect(broken, root, row)["complete_branch"]
        names.append("ag477_missing_" + role + "_net_assignment_rejected")
    for role, stroke in (("source", "M 70 250 L 70 230 L 90 230"),
                         ("gate", "M 130 230 L 150 230")):
        broken_root = copy.deepcopy(root)
        matching = [e for e in broken_root.iter() if e.get("data-role") == "conductor-ink" and stroke in e.get("d", "")]
        assert len(matching) == 1 and matching[0].get("d").count(stroke) == 1
        matching[0].set("d", matching[0].get("d").replace(stroke, ""))
        measured = inspect(copy.deepcopy(source_human), broken_root, row)
        assert not measured["complete_branch"]
        leg = measured["source_leg" if role == "source" else "gate_net"]
        assert leg["cache_segments_without_ink"]
        names.append("ag477_missing_actual_" + role + "_stroke_rejected")
    resistor = copy.deepcopy(next(d for d in source_human["devices"] if d["card"] == "rs"))
    resistor["terminals"][next(iter(resistor["terminals"]))][0] += 1
    try:
        actual(root, resistor)
    except ValueError:
        names.append("corrupted_cached_resistor_lead_rejected")
    else:
        raise AssertionError("actual SVG accepted a corrupted resistor endpoint")
    print(json.dumps(dict(passed=names), indent=2))


if __name__ == "__main__":
    main()
