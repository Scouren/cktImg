#!/usr/bin/env python3
"""Research-method checks; no engine execution and no production test gate.

The independent fixture spells the six-net loop described in the study.
Mutations isolate its boundaries. Source corruption must fail its actual
lead oracle; a label cannot supply a wire. Run with python3 -B.
"""
import argparse
import copy
import json
from pathlib import Path
import xml.etree.ElementTree as ET

from converter_loops import bus_spine, select, shunt_return, wire_tree
from cross_caps import actual_glyph


FIXTURE = """.model nch nmos
.model pch pmos
.model diode d
L1 near_in near_out 1n
MIN near_in gin bus vdd pch
MLOW bottom glow bus vdd pch
MOUT output gout near_out vdd pch
MSHUNT near_out gshunt 0 0 nch
CFLY near_in bottom 1p
DLOOP negative bottom diode
COUT output negative 1p
CGROUND output 0 1p
RTOP output feedback 1k
RBOTTOM feedback 0 1k
"""


def accepted(text):
    return [r for r in select(".subckt dut\n" + text + "\n.ends dut\n") if r["admitted"]]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native-crossings", action="store_true")
    args = parser.parse_args()
    names = []
    assert len(accepted(FIXTURE)) == 1
    names.append("six_net_fixture")
    for name, text in {
        "capacitor_pin_order": FIXTURE.replace("CFLY near_in bottom", "CFLY bottom near_in").replace("COUT output negative", "COUT negative output"),
        "channel_pin_order": FIXTURE.replace("MIN near_in gin bus", "MIN bus gin near_in").replace("MLOW bottom glow bus", "MLOW bus glow bottom").replace("MOUT output gout near_out", "MOUT near_out gout output"),
        "card_order": "\n".join(FIXTURE.splitlines()[:3] + list(reversed(FIXTURE.splitlines()[3:]))) + "\n",
    }.items():
        assert len(accepted(text)) == 1, name
        names.append(name)
    for name, text in {
        "duplicate_fly": FIXTURE + "CSECOND near_in bottom 1p\n",
        "duplicate_output_cap": FIXTURE + "CSECOND output negative 1p\n",
        "duplicate_diode": FIXTURE + "DSECOND negative bottom diode\n",
        "reversed_diode_unobserved": FIXTURE.replace("DLOOP negative bottom", "DLOOP bottom negative"),
        "grounded_negative": FIXTURE.replace("negative", "0"),
        "shorted_fly": FIXTURE.replace("bottom", "near_in"),
        "ambiguous_main": FIXTURE + "MSECOND near_in gsecond bus vdd pch\n",
        "ambiguous_coil": FIXTURE + "LSECOND near_in near_out 1n\n",
        "ambiguous_grounded_output": FIXTURE + "CSECOND output 0 1p\n",
        "ambiguous_divider": FIXTURE + "RSECOND output feedback 1k\n",
        "missing_grounded_output": FIXTURE.replace("CGROUND output 0 1p\n", ""),
        "wrong_low_model": FIXTURE.replace("MLOW bottom glow bus vdd pch", "MLOW bottom glow bus vdd nch"),
        "current_path_on_control": FIXTURE.replace("glow", "near_in"),
        "grounded_main_gate_extension": FIXTURE + "CGATE gout 0 1p\n",
        "grounded_coil_extension": FIXTURE + "CCOIL near_out 0 1p\n",
    }.items():
        assert not accepted(text), name
        names.append(name)
    for card, net in (("cgate", "gout"), ("ccoil", "near_out")):
        rows = select(".subckt dut\n" + FIXTURE + f"{card} {net} 0 1p\n.ends dut\n")
        assert len(rows) == 1 and rows[0]["reason"] == "grounded_main_branch_unobserved"
        assert rows[0]["grounded_main_branches"] == [dict(card=card, net=net, ground="0")]
    names.append("grounded_main_branch_evidence_retained")
    second = ("L2 a2 b2 1n\nMI2 a2 gi2 bus2 vdd pch\nML2 bottom2 gl2 bus2 vdd pch\n"
              "MO2 output go2 b2 vdd pch\nMS2 b2 gs2 0 0 nch\nCF2 a2 bottom2 1p\n"
              "D2 bottom2 neg2 diode\nCO2 output neg2 1p\n")
    assert not accepted(FIXTURE + second)
    names.append("reversed_shared_competitor_still_ambiguous")
    assert wire_tree([[[0, 0], [10, 0]], [[5, 0], [5, 10]]], [[0, 0], [5, 10]]) is not None
    names.append("actual_t_junction")
    assert wire_tree([[[0, 0], [4, 0]], [[6, 0], [10, 0]]], [[0, 0], [10, 0]]) is None
    names.append("label_gap_is_not_continuity")
    assert wire_tree([[[0, 0], [10, 0]]], [[0, 0], [5, 1]]) is None
    names.append("off_ink_target_is_not_continuity")
    for name, segments, targets, expected in (
        ("bus_spine_left_of_both", [[[10, 0], [0, 0]], [[0, 0], [0, 20]], [[0, 20], [20, 20]]],
         [[10, 0], [20, 20]], ("strictly_left_of_both", 10)),
        ("bus_spine_on_terminal_column", [[[10, 0], [10, 20]]],
         [[10, 0], [10, 20]], ("on_shared_terminal_column", 0)),
        ("bus_spine_between_terminals_is_not_left", [[[10, 0], [15, 0]], [[15, 0], [15, 20]], [[15, 20], [20, 20]]],
         [[10, 0], [20, 20]], ("other", -5)),
    ):
        evidence = dict(continuous=True, spanning_ink_segments=wire_tree(segments, targets), targets=[dict(xy=p) for p in targets])
        measured = bus_spine(evidence)
        assert (measured["relation"], measured["left_clearance"]) == expected, name
        names.append(name)
    corpus = Path(__file__).resolve().parents[3] / "external/examples/analoggenie"
    human = json.loads((corpus / "ag-1191.human.json").read_text())
    cap = copy.deepcopy(next(d for d in human["devices"] if d["card"] == "cfly"))
    root = ET.parse(corpus / "ag-1191.svg").getroot()
    actual_glyph(root, cap)
    cap["terminals"][next(iter(cap["terminals"]))][0] += 1
    try:
        actual_glyph(root, cap)
    except ValueError:
        names.append("corrupt_cached_lead_rejected")
    else:
        raise AssertionError("actual SVG did not reject corrupt cached lead")
    devices = {d["card"]: copy.deepcopy(d) for d in human["devices"]}
    row = dict(diode="d1", source_glyphs=dict(d1=actual_glyph(root, devices["d1"])))
    shunts = shunt_return(root, devices, row, [dict(card="m4")])
    assert len(shunts) == 1 and shunts[0]["above"]
    assert shunts[0]["ground_pin"] == "S" and shunts[0]["ground_xy"] == [320, 420]
    assert shunts[0]["diode_y"] == 530
    names.append("actual_shunt_ground_above_return")
    devices["m4"]["terminals"]["S"][1] += 1
    try:
        shunt_return(root, devices, row, [dict(card="m4")])
    except ValueError:
        names.append("corrupt_cached_shunt_ground_rejected")
    else:
        raise AssertionError("actual SVG did not reject corrupt shunt ground lead")
    if args.native_crossings:
        from converter_loops import local_crossings
        pair = dict(first=dict(spanning_ink_segments=[[[0, 0], [10, 0]]]),
                    second=dict(spanning_ink_segments=[[[5, -5], [5, 5]]]))
        assert local_crossings(pair) == {"first/second": [(5.0, 0.0)]}
        names.append("native_proper_local_crossing")
        pair["second"]["spanning_ink_segments"] = [[[10, 0], [10, 10]]]
        assert local_crossings(pair) == {"first/second": []}
        names.append("native_local_endpoint_is_not_crossing")
        pair["second"]["spanning_ink_segments"] = None
        assert local_crossings(pair) is None
        names.append("native_disconnected_crossings_unknown")
    print(json.dumps(dict(passed=names), indent=2))


if __name__ == "__main__":
    main()
