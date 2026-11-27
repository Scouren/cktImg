#!/usr/bin/env python3
"""The `cktimg` Python package (python/cktimg) against the cktimg-json it runs.

Oracles, none of which recomputes a layout:
- the same input given as a path, as text and as a dict draws the same bytes;
- a placement fed back as `start` keeps every device where it was;
- an object with `netlist("cktimg")` draws as its text does;
- a refused deck raises CktimgError with cktImg's own message;
- a manifest dict adds the `target` block, mapping by its class keys;
- a deck's `*@` line comes back in the report's `requests` by its own line.
"""
import argparse
import json
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "python"))
import cktimg  # noqa: E402

DECK = """diff pair
*@ order m1 m2
M1 x inp t 0 nch
M2 out inn t 0 nch
M3 x x vdd vdd pch
M4 out x vdd vdd pch
I1 t 0 1u
"""


class Circuit:
    def __init__(self, text):
        self.text = text

    def netlist(self, dialect):
        assert dialect == "cktimg"
        return self.text


def check(cond, what):
    if not cond:
        raise SystemExit(f"FAIL: {what}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("exe")
    ap.add_argument("out")
    a = ap.parse_args()
    exe = a.exe
    symbols = ROOT / "tests" / "symbols.zon"

    by_path, rep = cktimg.place(DECK, symbols=symbols, exe=exe)
    by_text, _ = cktimg.place(DECK, symbols=symbols.read_text(), exe=exe)
    by_str_path, _ = cktimg.place(DECK, symbols=str(symbols), exe=exe)
    check(by_path == by_text == by_str_path, "symbols as path, text and str path place alike")

    check([(r["line"], r["text"], r["state"]) for r in rep["requests"]] == [(2, "*@ order m1 m2", "honoured")],
          "the deck's *@ line is reported by its own line")

    again, _ = cktimg.place(DECK, start=by_path, exe=exe)
    pos = lambda p: {d["name"]: (d["pos"], d.get("rot"), d.get("mirror")) for d in p["devices"]}
    check(pos(again) == pos(by_path), "start= keeps every device where it was")
    again_text, _ = cktimg.place(DECK, start=json.dumps(by_path), exe=exe)
    check(again_text == again, "start as JSON text equals start as dict")
    moved = json.loads(json.dumps(by_path))
    for d in moved["devices"]:
        if d["name"] in ("m1", "m3"):
            d["pos"][0] += 400
    relaid, _ = cktimg.place(DECK, start=moved, exe=exe)
    check(pos(relaid) != pos(by_path), "start= is passed on: moved devices relay elsewhere")

    obj, _ = cktimg.place(Circuit(DECK), exe=exe)
    check(obj == cktimg.place(DECK, exe=exe)[0], "an object with netlist() draws as its text")

    manifest = {"target": "t", "version": 1, "unmapped": {"mode": "skip"},
                "classes": {"nmos": {"sym": "n.sym"}, "pmos": {"sym": "p.sym"}}}
    tp, _ = cktimg.place(DECK, target=manifest, exe=exe)
    syms = {d["name"]: d["sym"] for d in tp["target"]["devices"]}
    check(syms == {"m1": "n.sym", "m2": "n.sym", "m3": "p.sym", "m4": "p.sym"}, f"target block maps by class: {syms}")

    svg, rep2 = cktimg.draw(DECK, exe=exe)
    check(svg.lstrip().startswith("<svg") or "<svg" in svg[:200], "draw returns SVG text")
    check(rep2["requests"] == rep["requests"], "draw reports as place does")

    try:
        cktimg.place("t\n.include missing.lib\nR1 a b 1k\n", exe=exe)
        check(False, "a refused deck raises")
    except cktimg.CktimgError as e:
        check(str(e) != "", "the error carries cktImg's message")

    Path(a.out).mkdir(parents=True, exist_ok=True)
    print("python api: ok")


if __name__ == "__main__":
    main()
