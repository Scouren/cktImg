#!/usr/bin/env python3
"""Import command compatibility through the real Schemify host.

Oracle: both names produce identical cells and Schemify's spicecmp verifies
their netlists against the input resistor. Schemify's 2026-11-07 command rename
maps cktimg.import to netlist.import before lookup; both host generations must
work with the same plugin.

Usage: python3 tests/schemify_commands.py <schemify-bin-dir>
Requires the built cktimg.wasm and a Schemify build with the cmd command.
"""
import json
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
DECK = "* command compatibility\n.subckt alias a b\nR1 a b 1k\n.ends\n"


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    bindir = Path(sys.argv[1]).resolve()
    with tempfile.TemporaryDirectory(prefix="cktimg-commands-") as tmp:
        work = Path(tmp)
        init = work / "init.lua"
        init.write_text(
            'schemify.pack.add({ { path = %s, name = "cktimg", '
            'grant = { "read_project", "write_project" }, '
            'fuel = 100000000000 } })\n' % json.dumps(str(ROOT)))
        cli = [str(bindir / "schemify"), "-u", str(init)]

        def run(args, cwd):
            result = subprocess.run(args, cwd=cwd, capture_output=True,
                                    text=True, timeout=120)
            if result.returncode:
                sys.exit("FAILED %s\n%s%s" % (
                    " ".join(args), result.stdout, result.stderr))

        run(cli + ["pack", "sync"], work)
        cells = []
        for command in ("cktimg.import", "netlist.import"):
            project = work / command
            source = project / "n2s"
            source.mkdir(parents=True)
            (project / "schemify.project").write_text("schemify 1 project\n")
            (source / "alias.sp").write_text(DECK)
            run(cli + ["cmd", str(project), command, "n2s/alias.sp"], project)
            cell = source / "alias.shcomp"
            cells.append(cell.read_bytes())
            run(cli + ["netlist", "n2s/alias.shcomp", "--dialect", "ngspice",
                       "-o", "back.sp"], project)
            (project / "expected.sp").write_text("* resistor\nR1 a b 1k\n.end\n")
            run([str(bindir / "spicecmp"), "expected.sp", "back.sp"], project)
        if cells[0] != cells[1]:
            sys.exit("FAILED: command aliases produced different cells")
    print("Both import commands produce the same cell and round-trip circuit")


if __name__ == "__main__":
    main()
