"""Verify the editable Schemify bus against the original scalar SPICE interface."""

import argparse
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
CASE = ROOT / "external/examples/analoggenie/ag-1146.cir"
BITS = ["B_3_", "B_2_", "B_1_", "B_0_"]
PORTS = ["Von", "Vop", *BITS, "Vcn", "Vcp"]
EXPR = ",".join(BITS)


def run(*args, cwd, env=None):
    return subprocess.run(
        args, cwd=cwd, env=env, capture_output=True, text=True, check=True
    ).stdout


def main(host, plugin, out):
    out.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    for key in ("CONFIG", "CACHE", "DATA", "STATE"):
        env[f"XDG_{key}_HOME"] = str(out / key.lower())
    init = out / "init.lua"
    init.write_text(
        f'schemify.pack.add({{ {{ path = "{plugin}", name = "netlist-import", grant = {{ "read_project", "write_project" }}, fuel = 100000000000 }} }})\n'
    )
    run(host, "-u", init, "pack", "sync", cwd=out, env=env)
    raw = CASE.read_text()
    for key, source, grouped in (
        ("original", raw, True),
        ("consumer", raw.replace(".ends dut", "Rextra B_2_ Vcn 1k\n.ends dut"), False),
        ("permuted", raw.replace("X2 Von Vop B_3_ B_2_", "X2 Von Vop B_2_ B_3_"), False),
        ("called", raw + "Xtop dd ss cm n p a b c3 c2 c1 c0 dut\n", False),
    ):
        proj = out / key
        n2s = proj / "n2s"
        n2s.mkdir(parents=True, exist_ok=True)
        (proj / "schemify.project").write_text("schemify 1 project\n")
        (n2s / "input.cir").write_text(source)
        run(host, "-u", init, "cmd", proj, "netlist.import", "n2s/input.cir", cwd=proj, env=env)
        run(host, "--clean", "netlist", "n2s/dut.shcomp", "--dialect", "ngspice", "-o", "returned.sp", cwd=proj, env=env)
        returned = (proj / "returned.sp").read_text()
        assert re.search(r"^\.subckt Varactor_Switched_caps (.*)$", returned, re.M)[1].split() == PORTS
        original_call = re.search(r"^X2 (.*)$", source, re.M)[1].split()
        assert re.search(r"^X2 (.*)$", returned, re.M)[1].split() == original_call
        for cell in ("Varactor_Switched_caps", "dut"):
            comp = n2s / (cell + ".shcomp")
            text = comp.read_text()
            pins = re.findall(r"^pin (\S+) \S+ (-?\d+) (-?\d+)$", text, re.M)
            names = [p[0] for p in pins]
            assert (EXPR in names) == grouped
            if grouped:
                assert f" {EXPR}\n" in text and f" B<3:0>\n" in text
                assert all(n not in names for n in BITS)
            else:
                assert all(n in names for n in BITS)
            if cell == "Varactor_Switched_caps":
                assert [n for p in names for n in p.split(",")] == PORTS
                assert len(pins) == (5 if grouped else 8)
                assert len(re.findall(r"^line ", text, re.M)) == len(pins)
        dut = (n2s / "dut.shcomp").read_text()
        assert re.search(r"^inst \S+ \./Varactor_Switched_caps\n  at [^\n]+\n  name 2$", dut, re.M)
        run(host, "--clean", "cmd", n2s / "dut.shcomp", "file.image_export.svg_export", proj / "drawing.svg", cwd=proj, env=env)
        print(key, "five contacts" if grouped else "eight contacts", original_call, flush=True)


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    for arg in ("host", "plugin", "out"):
        p.add_argument(arg, type=lambda s: Path(s).resolve())
    args = p.parse_args()
    main(args.host, args.plugin, args.out)
