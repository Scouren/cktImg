#!/usr/bin/env python3
"""What the report's `requests` say about a deck's `*@` lines (hints.1: each
line is drawn as it says, or the report says why; none is dropped in silence).

Oracle: the decks below, written out by hand: each `*@` line's own 1-based
line in the file, the line's text, and the verdict its verb's contract gives
(docs/research/vocabulary.md). The lists are compared whole, never counted.
"""
import argparse
import json
import subprocess
from pathlib import Path

CASES = [
    # A deck of `.subckt`s only draws its top cell; a line before it or after
    # its `.ends` is one of the top cell's. The top cell's port roles, which
    # cktimg-json adds, are no line of the deck.
    ("subckt-only", """t
*@ frob m1
.subckt dut a b vdd
*@ bogus m1
M1 b a 0 0 nch
R1 vdd b 1k
.ends dut
*@ face m1 g right
""", [(2, "*@ frob m1", "rejected", "unknown_verb", None),
      (4, "*@ bogus m1", "rejected", "unknown_verb", None),
      (8, "*@ face m1 g right", "honoured", "ok", None)]),
    # A file that starts with `.subckt` has no title line: line 1 is its own.
    ("untitled", """.subckt dut a b vdd
*@ bogus m1
M1 b a 0 0 nch
R1 vdd b 1k
.ends dut
*@ frob m1
""", [(2, "*@ bogus m1", "rejected", "unknown_verb", None),
      (6, "*@ frob m1", "rejected", "unknown_verb", None)]),
    # The same with devices at the top level: the deck is drawn as it is.
    ("untitled-top", """.subckt half a b
R1 a b 1k
.ends half
X1 in out half
R2 out 0 1k
*@ bogus x1
""", [(6, "*@ bogus x1", "rejected", "unknown_verb", None)]),
    # A line of several devices names the one it cannot take.
    ("culprit", """culprit
.subckt amp in out
R1 in out 1k
.ends amp
R5 in a 1k
X1 a b amp
R4 b 0 1k
*@ upright r5 r4
*@ above r5 x1 r4
*@ order r5 nosuch
""", [(8, "*@ upright r5 r4", "honoured", "ok", None),
      (9, "*@ above r5 x1 r4", "rejected", "not_placeable", "x1"),
      (10, "*@ order r5 nosuch", "rejected", "unknown_name", "nosuch")]),
    # A group its devices are not joined as: a bank's gates on two nets, a
    # stack's devices on no shared net but a rail. The joined ones stand.
    ("unjoined", """unjoined
.model nch nmos
M1 d1 g1 0 0 nch
M2 d2 g2 0 0 nch
M3 d3 g1 0 0 nch
M4 d4 g1 d3 0 nch
R1 vdd d1 1k
R2 vdd d2 1k
R3 vdd d4 1k
V1 vdd 0 1
V2 g1 0 1
V3 g2 0 1
*@ group bank m1 m2
*@ group stack m1 m2
*@ group stack m4 m3
""", [(13, "*@ group bank m1 m2", "rejected", "unjoined", None),
      (14, "*@ group stack m1 m2", "rejected", "unjoined", None),
      (15, "*@ group stack m4 m3", "honoured", "ok", None)]),
    # A gate turned where its port had no room: a name stands on the pin
    # (ar-2369, a hinting trial's round 1). Only the face lines are compared.
    ("face-port", """* official Analog Canvas netlist; PDK X cards rewritten by convert.py
.model nch nmos
.model pch pmos

.subckt dut VDD VSS VBIAS4 VOUT- VOUT+ VREF_CM VCMFB
MB41 net1 VBIAS4 net6 VDD pch l=0.15 w=1 nf=1 m=1
MB42 net5 VBIAS4 net8 VDD pch l=0.15 w=1 nf=1 m=1
MB43 net2 VBIAS4 net7 VDD pch l=0.15 w=1 nf=1 m=1
MB44 net9 VBIAS4 net0 VDD pch l=0.15 w=1 nf=1 m=1
MB45 VBIAS5 VBIAS4 net4 VDD pch l=0.15 w=1 nf=1 m=1
MB45P VBIAS5 VDD VBIAS4 VBIAS4 nch l=0.15 w=1 nf=1 m=1
MB51 net6 VBIAS5 VDD VDD pch l=0.15 w=1 nf=1 m=1
MB52 net8 VBIAS5 VDD VDD pch l=0.15 w=1 nf=1 m=1
MB53 net7 VBIAS5 VDD VDD pch l=0.15 w=1 nf=1 m=1
MB54 net0 VBIAS5 VDD VDD pch l=0.15 w=1 nf=1 m=1
MB55 net4 VBIAS5 VDD VDD pch l=0.15 w=1 nf=1 m=1
MC1 net3 VOUT- net1 VDD pch l=0.15 w=1 nf=1 m=1
MC2 VCMFB VREF_CM net5 VDD pch l=0.15 w=1 nf=1 m=1
MC3 VCMFB VREF_CM net2 VDD pch l=0.15 w=1 nf=1 m=1
MC4 net3 VOUT+ net9 VDD pch l=0.15 w=1 nf=1 m=1
MC5 net3 net3 VSS VSS nch l=0.15 w=1 nf=1 m=1
MC6 VCMFB VCMFB VSS VSS nch l=0.15 w=1 nf=1 m=1
MR1 net5 VOUT- net1 VDD pch l=0.15 w=1 nf=1 m=1
MR2 net1 VREF_CM net5 VDD pch l=0.15 w=1 nf=1 m=1
MR3 net9 VOUT+ net2 VDD pch l=0.15 w=1 nf=1 m=1
MR4 net2 VREF_CM net9 VDD pch l=0.15 w=1 nf=1 m=1
*@ shelf off
*@ role vout- input
*@ role vout+ input
*@ role vref_cm input
*@ order mb51 mb52 mb53 mb54 mb55
*@ order mc1 mr1 mr2 mc2 mc3 mr4 mr3 mc4
*@ row mc1 mc2 mc3 mc4
*@ row mr1 mr2 mr4 mr3
*@ above mb41 mr1 mc1 mc5
*@ face mr3 g right
*@ face mr2 g right
.ends dut
""", [(36, "*@ face mr3 g right", "relaxed", "no_room", None),
                    (37, "*@ face mr2 g right", "relaxed", "no_room", None)], "*@ face"),
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=lambda p: Path(p).resolve())
    parser.add_argument("out", type=Path)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    bad = []
    for name, deck, want, *only in CASES:
        cir, r, j = [args.out / (name + ext) for ext in (".cir", ".report.json", ".json")]
        cir.write_text(deck)
        subprocess.run([args.binary, "--report", r, cir, j], check=True)
        got = [(q["line"], q["text"], q["state"], q["code"], q.get("name"))
               for q in json.loads(r.read_text())["requests"] if q["text"].startswith(tuple(only) or "")]
        if got != want:
            bad.append(name)
            print(f"{name}:\n  want {want}\n  got  {got}")
    if bad:
        raise SystemExit(f"hint reports wrong: {bad}")


if __name__ == "__main__":
    main()
