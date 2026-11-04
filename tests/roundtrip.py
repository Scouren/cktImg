#!/usr/bin/env python3
"""The Schemify round trip, the main oracle of AGENTS.md, outside `zig build`:
each fixture deck is imported by the cktimg plugin into a fresh project,
netlisted back by Schemify, and compared with Schemify's `spicecmp`.

A deck with a top level is compared whole, through its bench. A deck of
`.subckt`s only is compared cell by cell: each generated component's netlist
(Schemify writes its body flat) against a probe, that subckt's body at the
top level with the subckts it instantiates.

usage: python3 tests/roundtrip.py <schemify-bin-dir> [deck ...]
       (decks default to every fixture in tests/fixtures.zig)

Needs a Schemify build (`schemify`, `spicecmp`) that loads the plugin ABI of
tools/schemify/abi.zig, and the committed cktimg.wasm. Exit status 1 when a
deck differs, fails, or its refusal is not the one `REFUSED` names.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Decks the plugin refuses by design, by name: over its 200-card import cap.
# One that imports fails until it leaves this list.
REFUSED = {
    "rstring_ladder.spice": "279 element cards, over the plugin's 200",
    "write_dac.spice": "280 element cards, over the plugin's 200",
}


def logical(text):
    """The deck's lines, `+` continuations joined."""
    out = []
    for raw in text.splitlines():
        if raw.startswith("+") and out:
            out[-1] += " " + raw[1:].strip()
        else:
            out.append(raw)
    return out


def split(text):
    """The top-level lines, and each subckt's header and body by name."""
    top, subs, cur = [], {}, None
    for line in logical(text):
        w = line.split()
        if w and w[0].lower() == ".subckt":
            cur = w[1].lower()
            subs[cur] = (line, [])
        elif w and w[0].lower() == ".ends":
            cur = None
        elif cur is not None:
            subs[cur][1].append(line)
        else:
            top.append(line)
    return top, subs


def probe(text, name):
    """Subckt `name` of `text` as a top-level deck: its parameters as
    `.param`s, the subckts it instantiates (transitively) as definitions."""
    top, subs = split(text)
    header, body = subs[name]
    used, todo = set(), [name]
    while todo:
        for line in subs[todo.pop()][1]:
            w = line.lower().split()
            if not w or not w[0].startswith("x"):
                continue
            for t in w[1:]:
                if "=" not in t and t in subs and t not in used:
                    used.add(t)
                    todo.append(t)
    keep = (".model", ".param", ".global", ".include", ".lib", ".option")
    lines = ["* probe " + name]
    lines += [l for l in top[1:] if l.strip().lower().startswith(keep)]
    for other, (h, b) in subs.items():
        if other in used and other != name:
            lines += [h] + b + [".ends"]
    lines += [".param " + t for t in header.split()[2:] if "=" in t]
    lines += [l for l in body if not l.strip().lower().startswith(".end")]
    return "\n".join(lines + [".end"]) + "\n"


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    bindir = sys.argv[1]
    decks = sys.argv[2:]
    if not decks:
        with open(os.path.join(ROOT, "tests", "fixtures.zig")) as f:
            found = re.findall(r'@embedFile\("(fixtures/[^"]+)"\)', f.read())
        decks = [os.path.join(ROOT, "tests", p) for p in found]
    schemify = os.path.join(bindir, "schemify")
    spicecmp = os.path.join(bindir, "spicecmp")
    work = tempfile.mkdtemp(prefix="cktimg-roundtrip-")
    init = os.path.join(work, "init.lua")
    with open(init, "w") as f:
        f.write('schemify.pack.add({ { path = "%s", name = "cktimg", '
                'grant = { "read_project", "write_project" }, fuel = 100000000000 } })\n' % ROOT)
    subprocess.run([schemify, "-u", init, "pack", "sync"], capture_output=True, check=True)

    def run(args, cwd):
        r = subprocess.run([schemify, "-u", init] + args, cwd=cwd, capture_output=True, text=True, timeout=1800)
        return r.returncode, " ".join((r.stdout + r.stderr).split())

    def compare(label, ref, back, cwd):
        r = subprocess.run([spicecmp, ref, back], cwd=cwd, capture_output=True, text=True)
        print("SAME" if r.returncode == 0 else "DIFF", label + ":", " ".join((r.stdout + r.stderr).split())[:300])
        return r.returncode == 0

    bad = refused = 0
    for i, deck in enumerate(decks):
        base = os.path.basename(deck)
        proj = os.path.join(work, "p%d" % i)
        os.makedirs(os.path.join(proj, "n2s"))
        with open(os.path.join(proj, "schemify.project"), "w") as f:
            f.write("schemify 1 project\n")
        shutil.copy(deck, os.path.join(proj, "n2s", base))
        code, log = run(["cmd", proj, "cktimg.import", "n2s/" + base], proj)
        if code != 0:
            ok = base in REFUSED
            print("REFUSED" if ok else "FAIL", base + ":", REFUSED.get(base, log[-300:]))
            bad += not ok
            refused += ok
            continue
        if base in REFUSED:
            print("FAIL", base + ": imported; remove it from REFUSED")
            bad += 1
            continue
        made = os.listdir(os.path.join(proj, "n2s"))
        benches = [f for f in made if f.endswith(".shbench")]
        if benches:
            code, log = run(["netlist", "n2s/" + benches[0], "--dialect", "ngspice", "-o", "back.sp"], proj)
            ok = code == 0 and compare(base, "n2s/" + base, "back.sp", proj)
            if code != 0:
                print("FAIL", base + ": netlist:", log[-300:])
            bad += not ok
            continue
        with open(deck) as f:
            text = f.read()
        comps = {f[: -len(".shcomp")].lower(): f for f in made if f.endswith(".shcomp")}
        for name in split(text)[1]:
            label = "%s %s" % (base, name)
            if name not in comps:
                print("FAIL", label + ": no component")
                bad += 1
                continue
            code, log = run(["netlist", "n2s/" + comps[name], "--dialect", "ngspice", "-o", name + ".back.sp"], proj)
            if code != 0:
                print("FAIL", label + ": netlist:", log[-300:])
                bad += 1
                continue
            with open(os.path.join(proj, name + ".probe.sp"), "w") as f:
                f.write(probe(text, name))
            bad += not compare(label, name + ".probe.sp", name + ".back.sp", proj)
    if bad:
        print("%d failed; the projects are in %s" % (bad, work))
        sys.exit(1)
    shutil.rmtree(work)
    print("%d decks the same circuit after the round trip; %d refused, as REFUSED names" % (len(decks) - refused, refused))


if __name__ == "__main__":
    main()
