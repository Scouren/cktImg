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
*@ column r5 x1 r4
*@ order r5 nosuch
""", [(8, "*@ upright r5 r4", "honoured", "ok", None),
      (9, "*@ column r5 x1 r4", "rejected", "not_placeable", "x1"),
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
    # A `*@` line on line 1 is the title, as SPICE reads it: nothing taken,
    # and said so (four agents of a hinting trial lost one there silently).
    ("title-line", """*@ shelf off
.model nch nmos
M1 b a 0 0 nch
R1 vdd b 1k
*@ face m1 g right
""", [(1, "*@ shelf off", "rejected", "title", None),
      (5, "*@ face m1 g right", "honoured", "ok", None)]),
    # A net that is also a hidden MOS body is wired by its shown pins: the
    # body takes no wire (bulk-a), as when the body is on another net
    # (bulk-b). `drawn` reads the wires off d.json.
    ("bulk-a", """* wire on a net that is also a hidden bulk
.model pch pmos
*@ wire vin
.subckt dut vss vin vout vg
M1 vout vg vin vin pch
M2 vout vg vin vin pch
R1 vout vss 1k
.ends
""", [(3, "*@ wire vin", "honoured", "ok", None)]),
    ("bulk-b", """* the same, bodies on vss
.model pch pmos
*@ wire vin
.subckt dut vss vin vout vg
M1 vout vg vin vss pch
M2 vout vg vin vss pch
R1 vout vss 1k
.ends
""", [(3, "*@ wire vin", "honoured", "ok", None)]),
    # A place for a driver drawn apart names it: `driver v1 inline` first.
    ("driver-at", """driver
.model nch nmos
V1 vdd 0 1
M1 d g 0 0 nch
R1 vdd d 1k
R2 vdd g 1k
*@ at v1 0 0
*@ cell v1 0 0
""", [(7, "*@ at v1 0 0", "rejected", "not_placeable", "v1"),
      (8, "*@ cell v1 0 0", "rejected", "not_placeable", "v1")]),
    # Drawn inline first, the source takes a place (the form Schemify writes).
    ("driver-inline-at", """driver
.model nch nmos
V1 vdd 0 1
M1 d g 0 0 nch
R1 vdd d 1k
R2 vdd g 1k
*@ driver v1 inline
*@ at v1 -3 0
""", [(7, "*@ driver v1 inline", "honoured", "ok", None),
      (8, "*@ at v1 -3 0", "honoured", "ok", None)]),
]

AG = Path(__file__).resolve().parent.parent / "external" / "examples" / "analoggenie"


def titled(name, lines):
    """Corpus deck `name` with `lines` after its title."""
    text = (AG / (name + ".cir")).read_text()
    head, rest = text.split("\n", 1)
    return head + "\n" + lines + rest


# Decks from a hinting trial, on corpus circuits: each case's verdicts.
CORPUS = [
    # A port at the net's left end stands where `port left` asks: at or past
    # every pin, not strictly past (ag-1108, a hinting trial).
    ("port-end", lambda: titled("ag-1108", "*@ port rfoutp left\n"),
     [(2, "*@ port rfoutp left", "honoured", "ok", None)]),
    # A port line with no room on its side keeps a port symbol, where no line
    # would put it; the line is `no_room` (ag-1108 round 6 drew a bare name).
    ("port-room", lambda: titled("ag-1108", "".join("*@ " + l + "\n" for l in [
        "face mp1 g right", "face mp2 g right", "face mp3 g right", "face mp4 g left",
        "face mp5 g left", "face mp6 g left", "order cf1 rf1 mp3 cg3l cpn3r cpn3l cg3r mp6 rf2 cf2",
        "order mp2 cg2l cpn2r cpn2l cg2r mp5", "order mp1 cnp1r cnp1l mp4", "column cpn3r cpn2r cnp1r",
        "column cpn3l cpn2l cnp1l", "column cg3l cg2l", "column cg3r cg2r", "port rfoutp top"])),
     [(15, "*@ port rfoutp top", "relaxed", "no_room", None)], "*@ port"),
    # An upright part hung beside a gate stands a row lower, its near end
    # within two units of the gate (anchored.3; ag-2500, a hinting trial).
    ("hang-upright", lambda: titled("ag-2500", "".join("*@ " + l + "\n" for l in [
        "shelf off", "role vin supply",
        "order m19 m7 m9 m11 m12 m13 m4 m1 md6 md5 md7 m23 m24 m18 m16 mpt cf1 cm1",
        "column m9 m10", "label vb5", "hang cm2 md1.g"])),
     [(7, "*@ hang cm2 md1.g", "honoured", "ok", None)], "*@ hang"),
]


def drawn_checks(name, d):
    """What the drawing itself must show for case `name`: a list of faults."""
    pins = lambda net: [(dv, p) for dv in d["devices"] if not dv["name"].startswith("_")
                        for p in dv["pins"] if p["net"] == net]
    ports = lambda net: [dv for dv in d["devices"] if dv["class"] in ("ipin", "opin", "iopin")
                         and dv["pins"][0]["net"] == net]
    if name.startswith("bulk"):
        # Oracle: the wires, joined where their points meet, hold every
        # shown pin of vin in one piece.
        segs = [s for w in d["wires"] if w["net"] == "vin" for s in w["segments"]]
        group = {}
        def root(x):
            while group.setdefault(x, x) != x:
                x = group[x]
            return x
        for s in segs:
            for a, b in zip(s, s[1:]):
                group[root(tuple(a))] = root(tuple(b))
        roots = {root(tuple(p["xy"])) for _, p in pins("vin")}
        return [] if len(roots) == 1 else [f"vin in {len(roots)} pieces"]
    if name == "port-end":
        lo = min(p["xy"][0] for _, p in pins("rfoutp"))
        return [] if any(dv["pos"][0] <= lo for dv in ports("rfoutp")) else ["no port at rfoutp's left end"]
    if name == "port-room":
        named = [l for l in d["labels"] if l["net"] == "rfoutp"]
        return [] if ports("rfoutp") and not named else ["rfoutp drawn as a name, not a port"]
    return []


def alone(binary, out):
    """`blocked_by[].alone` against its definition: the deck with that line
    alone made a comment honours the blocked line. Oracle: the decks drawn
    again here, and by hand: at m1 2, m2 6, m3 4 break `order m1 m2 m3`
    at m2 and m3; only freeing m3 admits it (ag-1289, a hinting trial,
    listed 14 blockers all alone, where one was)."""
    deck = """alone
.model nch nmos
M1 d1 g 0 0 nch
M2 d2 g 0 0 nch
M3 d3 g 0 0 nch
R1 vdd d1 1k
R2 vdd d2 1k
R3 vdd d3 1k
V1 g 0 1
*@ order m1 m2 m3
*@ at m1 2 10
*@ at m2 6 10
*@ at m3 4 10
"""
    def request(text, line):
        cir, r, j = [out / ("alone" + ext) for ext in (".cir", ".report.json", ".json")]
        cir.write_text(text)
        subprocess.run([binary, "--report", r, cir, j], check=True)
        return next(q for q in json.loads(r.read_text())["requests"] if q["line"] == line)
    got = [(b["line"], b["alone"]) for b in request(deck, 10)["blocked_by"]]
    bad = [] if got == [(11, False), (12, False), (13, True)] else [f"alone: got {got}"]
    lines = deck.split("\n")
    for b, said in got:
        freed = "\n".join("*" if k == b - 1 else l for k, l in enumerate(lines))
        if (request(freed, 10)["state"] == "honoured") != said:
            bad.append(f"alone: line {b} said {said}")
    return bad


def unmoved(binary, out):
    """A strong `at` on the place a device holds moves nothing (relay.6).
    Oracle: the drawing of the deck plus its own `--decisions 4`, each
    `weak at` made strong in turn: every device stands where it did
    (ag-1350, a hinting trial: one moved four others)."""
    cir = AG / "ag-1350.cir"
    base, lines = out / "unmoved.json", out / "unmoved.lines"
    subprocess.run([binary, "--decisions", "4", cir, base], check=True, stdout=lines.open("w"))
    pos = lambda path: {dv["name"]: (dv["pos"], dv["rot"], dv["mirror"]) for dv in json.loads(path.read_text())["devices"]}
    want = pos(base)
    stays = [l for l in lines.read_text().splitlines() if l.startswith("*@ weak at ")]
    bad = []
    for stay in stays:
        deck = out / "unmoved.cir"
        deck.write_text(cir.read_text() + "\n".join(l if l != stay else l.replace("weak ", "") for l in lines.read_text().splitlines()) + "\n*@ grouping off\n")
        got = out / "unmoved.got.json"
        subprocess.run([binary, deck, got], check=True)
        moved = sorted(k for k, v in pos(got).items() if want.get(k) != v)
        if moved:
            bad.append(f"strong {stay[11:]} moved {moved}")
    return bad



def unpinned(binary, out):
    """A device no `at` places gives way to one that does. Oracle: the
    deck's own `--decisions 4` places, all strong but one device's: every
    line is honoured (ag-1067 without m4: two lines were dropped as
    `guarantee`, the lattice having stood m4 on a pinned place; a Schemify
    round trip that pinned all but one device hit the same)."""
    cir = AG / "ag-1067.cir"
    lines = out / "unpinned.lines"
    subprocess.run([binary, "--decisions", "4", cir, out / "unpinned.base.json"], check=True, stdout=lines.open("w"))
    ats = [l.replace("weak ", "") for l in lines.read_text().splitlines() if l.startswith("*@ weak at ") and not l.startswith("*@ weak at m4 ")]
    deck, r = out / "unpinned.cir", out / "unpinned.report.json"
    deck.write_text(cir.read_text() + "\n".join(ats) + "\n")
    subprocess.run([binary, "--report", r, deck, out / "unpinned.json"], check=True)
    return [f"{q['text']}: {q['state']} {q['code']}" for q in json.loads(r.read_text())["requests"] if q["state"] != "honoured"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=lambda p: Path(p).resolve())
    parser.add_argument("out", type=Path)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    bad = []
    for name, deck, want, *only in CASES + [(n, f(), w, *o) for n, f, w, *o in CORPUS]:
        cir, r, j = [args.out / (name + ext) for ext in (".cir", ".report.json", ".json")]
        cir.write_text(deck)
        subprocess.run([args.binary, "--report", r, cir, j], check=True)
        got = [(q["line"], q["text"], q["state"], q["code"], q.get("name"))
               for q in json.loads(r.read_text())["requests"] if q["text"].startswith(tuple(only) or "")]
        faults = drawn_checks(name, json.loads(j.read_text()))
        if got != want or faults:
            bad.append(name)
            print(f"{name}:\n  want {want}\n  got  {got}\n  {faults}")
    for check in (alone, unmoved, unpinned):
        faults = check(args.binary, args.out)
        if faults:
            bad.append(check.__name__)
            print(f"{check.__name__}: {faults}")
    if bad:
        raise SystemExit(f"hint reports wrong: {bad}")


if __name__ == "__main__":
    main()
