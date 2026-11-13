#!/usr/bin/env python3
"""Research-method checks; no engine execution and no production test gate.

The independent fixture spells the six-net loop described in the study.
Mutations isolate its boundaries. Source corruption must fail its actual
lead oracle; a label cannot supply a wire. Run with python3 -B.
"""
import copy
import json
from pathlib import Path
import xml.etree.ElementTree as ET

from converter_loops import select, wire_tree
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
    }.items():
        assert not accepted(text), name
        names.append(name)
    assert wire_tree([[[0, 0], [10, 0]], [[5, 0], [5, 10]]], [[0, 0], [5, 10]]) is not None
    names.append("actual_t_junction")
    assert wire_tree([[[0, 0], [4, 0]], [[6, 0], [10, 0]]], [[0, 0], [10, 0]]) is None
    names.append("label_gap_is_not_continuity")
    assert wire_tree([[[0, 0], [10, 0]]], [[0, 0], [5, 1]]) is None
    names.append("off_ink_target_is_not_continuity")
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
    print(json.dumps(dict(passed=names), indent=2))


if __name__ == "__main__":
    main()
