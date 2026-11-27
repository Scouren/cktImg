#!/usr/bin/env python3
"""Check a series stack's physical direction and the public report and decision export."""
import argparse
from pathlib import Path
import json
import subprocess

PAIR = """Caller series stack
.model nch nmos level=1
.subckt dut VDD VSS INP INN VB OUTP OUTN
R1 VDD OUTN 1k
R2 VDD OUTP 1k
M1 OUTN INP tail VSS nch w=2u l=1u
M2 OUTP INN tail VSS nch w=2u l=1u
M5 tail VB VSS VSS nch w=4u l=1u
"""
FORK = """Caller fork
.model nch nmos level=1
.subckt dut VDD G1 G2 G3
M1 vdd g1 n 0 nch
M2 n g2 0 0 nch
M3 n g3 0 0 nch
R1 vdd g3 1k
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=lambda p: Path(p).resolve())
    parser.add_argument("out", type=Path)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    for case, deck, upper, lower in [("pair", PAIR, "m1", "m5"), ("fork", FORK, "m1", "m3")]:
        drawings = []
        for reverse in (False, True):
            name = f"{case}-{'reverse' if reverse else 'forward'}"
            r, j, svg, cir = [args.out / (name + ext) for ext in (".report.json", ".json", ".svg", ".cir")]
            order = [lower, upper] if reverse else [upper, lower]
            request = "*@ group stack " + " ".join(order)
            cir.write_text(deck + request + "\n.ends dut\n")
            subprocess.run([args.binary, "--report", r, "--svg", svg, cir, j], check=True)
            d, report = json.loads(j.read_text()), json.loads(r.read_text())
            drawings.append(d)
            devices = {obj["name"]: obj for obj in d["devices"]}
            assert not report["gates"]
            top, bottom = (devices[k] for k in (upper, lower))
            assert top["pos"][0] == bottom["pos"][0] and top["pos"][1] < bottom["pos"][1]
            assert top["pins"][2]["net"] == bottom["pins"][0]["net"]
            assert top["pins"][2]["xy"][0] == bottom["pins"][0]["xy"][0]
            (v,) = [v for v in report["requests"] if v["text"] == request]
            assert (v["state"], v["code"]) == (("relaxed", "not_drawn") if reverse else ("honoured", "ok")), (name, v)
            assert "*@ group stack " + upper + " " + lower in report["decisions"], name
            assert "*@ group stack " + lower + " " + upper not in report["decisions"], name
        assert drawings[0] == drawings[1], case

    for key, stack, stay, expected in [
            ("strong", "m1 m5", "at m5 -20 -20 r0", ("dropped", "conflict")),
            ("weak", "m5 m1", "weak at m5 -20 -20 r0", ("relaxed", "not_drawn"))]:
        deck = args.out / (key + ".cir")
        report = args.out / (key + ".report.json")
        drawing = args.out / (key + ".json")
        deck.write_text(PAIR + f"*@ group stack {stack}\n*@ {stay}\n.ends dut\n")
        subprocess.run([args.binary, "--report", report, deck, drawing], check=True)
        r = json.loads(report.read_text())
        req = {q["text"]: q for q in r["requests"]}
        v, at = req["*@ group stack " + stack], req["*@ " + stay]
        assert (v["state"], v["code"]) == expected
        if key == "strong":
            assert v["blocked_by"] == [{"line": at["line"], "alone": True}]
            assert at["state"] == "honoured"
            assert not any(line.startswith("*@ group stack") for line in r["decisions"])
        else:
            assert not v["blocked_by"]
            assert (at["state"], at["code"]) == ("dropped", "guarantee")


if __name__ == "__main__":
    main()
