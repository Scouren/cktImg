"""Sweep the hand-drawn corpus: draw every deck, gate it, and compare with the person's drawing.

usage: python3 -I tools/corpus.py <examples-dir> [--statements DIR | --stand-in] [--split train|test|all]
                                   [--limit N] [--svg DIR] [--ids id,id,...] [-v] [--people]

  (default)       no statement: the baseline alone
  --statements    <DIR>/<id>.ctl for the circuits that have one (tools/statements: the 48 blind files)
  --stand-in      statements derived from each drawing's structure (the corpus study's stand-in)

  --people        judge the people's drawings instead of the tool's: how often each rule of the
                  contract holds in what people drew (the contract's own evidence)

The corpus is third-party data and is not on this branch: pass its path. Reports, over the
circuits drawn: crashes, illegal drawings (by gate), relations shown, terminals joined by
name for want of a path, and wire crossings beside the person's.
"""
import collections, os, sys, time, traceback
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from corpus_lib import load_all, find_structs, signal_depth, pct
from cktintent import draw, render_svg, judge


def human_crossings(c):
    """Proper crossings between wires of different nets in a person's drawing."""
    nets = collections.defaultdict(list)
    for w in c.wires:
        for (x0, y0), (x1, y1) in w["segments"]:
            nets[w.get("net") or id(w)].append((x0, y0, x1, y1))
    keys, n = list(nets), 0
    for i in range(len(keys)):
        for j in range(i + 1, len(keys)):
            for ax0, ay0, ax1, ay1 in nets[keys[i]]:
                for bx0, by0, bx1, by1 in nets[keys[j]]:
                    d = (ax1 - ax0) * (by1 - by0) - (ay1 - ay0) * (bx1 - bx0)
                    if abs(d) < 1e-9:
                        continue
                    t = ((bx0 - ax0) * (by1 - by0) - (by0 - ay0) * (bx1 - bx0)) / d
                    s = ((bx0 - ax0) * (ay1 - ay0) - (by0 - ay0) * (ax1 - ax0)) / d
                    n += 1e-6 < t < 1 - 1e-6 and 1e-6 < s < 1 - 1e-6
    return n


def stand_in(c):
    """Statements derived from the drawing's structure: rails and ports from its markers,
    match for each pair, cross pair and two-device mirror, flow along the signal path."""
    S = find_structs(c)
    L = []
    if c.supply:
        L.append("net %s : supply" % " ".join(sorted(c.supply)))
    if c.ground:
        L.append("net %s : ground" % " ".join(sorted(c.ground)))
    done = set()
    for a, b in S["pair"] + S["cross"]:
        if a.name not in done and b.name not in done:
            L.append("match %s %s" % (a.card, b.card))
            done.update((a.name, b.name))
    for refs, outs, ms in S["mirror"]:
        if len(ms) == 2 and ms[0].name not in done and ms[1].name not in done:
            L.append("match %s %s" % (ms[0].card, ms[1].card))
            done.update((ms[0].name, ms[1].name))
    ins = [n for n, ps in c.ports.items() if any(d == "input" for d, _ in ps) and n not in c.rails]
    outs = [n for n, ps in c.ports.items() if any(d == "output" for d, _ in ps) and n not in c.rails]
    if ins and outs:
        depth, via = signal_depth(c, ins)
        seen = set()
        for o in outs:
            if o not in via:
                continue
            path, n = [], o
            while n in via:
                v, n = via[n]
                path.append(v)
            path.reverse()
            p2 = []
            for v in path:
                if not p2 or v is not p2[-1]:
                    p2.append(v)
            line = "flow %s -> %s -> %s" % (n, " -> ".join(v.card for v in p2), o)
            if p2 and line not in seen:
                seen.add(line)
                L.append(line)
    return "\n".join(L)


def people(circuits, statements):
    """Print how often each rule of the contract holds in the people's drawings."""
    shown, total = collections.Counter(), collections.Counter()
    for c in circuits:
        for rule, ok, text in judge.check(c, statements(c))[0]:
            if ok is not None:
                total[rule] += 1
                shown[rule] += ok
    for rule in sorted(total):
        print("  %-4s %s" % (rule, pct(shown[rule], total[rule])))
    base = [r for r in total if r[0] == "B"]
    print("  baseline %s; all relations %s" % (pct(sum(shown[r] for r in base), sum(total[r] for r in base)),
                                               pct(sum(shown.values()), sum(total.values()))))
    return 0


def main(argv):
    """Run the sweep the arguments ask for. -> 1 when a deck crashed or a drawing is illegal, else 0."""
    root = argv[0]
    opt = {"split": "test", "limit": 0, "svg": None, "statements": None, "ids": None}
    stand, verbose = "--stand-in" in argv, "-v" in argv
    for key in list(opt):
        if "--" + key in argv:
            opt[key] = argv[argv.index("--" + key) + 1]
    ids = set(opt["ids"].split(",")) if opt["ids"] else None
    if opt["statements"] and not ids:
        ids = {f[:-4] for f in os.listdir(opt["statements"]) if f.endswith(".ctl")}
    T = collections.Counter()
    gates_hit, crashes, slow, missed = collections.Counter(), [], [], collections.Counter()
    src = {"ag": "analoggenie", "amsnet": "amsnet", "ar": "analogretriever", "ct": "circuitthink"}

    def statements(c):
        path = os.path.join(opt["statements"] or "", c.id + ".ctl")
        if opt["statements"] and os.path.exists(path):
            with open(path) as f:
                return f.read()
        return stand_in(c) if stand else ""
    circuits = (c for c in load_all(root, None if (ids or opt["split"] == "all") else opt["split"], ids=ids) if c.clean())
    if "--people" in argv:
        return people(circuits, statements)
    for c in circuits:
        if opt["limit"] and T["circuits"] >= int(opt["limit"]):
            break
        with open(os.path.join(root, src[c.id.split("-")[0]], c.id + ".cir")) as f:
            deck = f.read()
        text = statements(c)
        T["circuits"] += 1
        t0 = time.time()
        try:
            r = draw(deck, text)
        except Exception as e:                      # the sweep's job is to find these
            crashes.append((c.id, "%s: %s" % (type(e).__name__, e), traceback.format_exc().splitlines()[-3].strip()))
            continue
        dt = time.time() - t0
        T["seconds"] += dt
        if dt > 5:
            slow.append((c.id, dt))
        T["drawn"] += 1
        T["devices"] += len(r.schema["devices"])
        T["legal"] += not r.findings
        for g in {g for g, text_ in r.findings}:
            gates_hit[g] += 1
        for rule, s, t in r.outcome:
            if s is False:
                missed[rule] += 1
                if verbose:
                    print("%-11s NOT SHOWN %-4s %s" % (c.id, rule, t[:100]))
        shown = [s for rule, s, t in r.outcome if s is not None]
        T["relations"] += len(shown)
        T["relations shown"] += sum(shown)
        T["all relations shown"] += all(shown)
        lost = sum(int(n.split(":")[1].split()[0]) for n in r.notes if "joined by name, no clear path" in n)
        T["terminals joined by name for want of a path"] += lost
        T["circuits with such a terminal"] += lost > 0
        T["crossings"] += r.schema.get("crossings", 0)
        T["crossings in the person's drawing"] += human_crossings(c)
        if verbose and (r.findings or lost):
            print("%-11s %2d devices  %s  %s" % (c.id, len(r.schema["devices"]), "; ".join(t for g, t in r.findings)[:110], "lost %d" % lost if lost else ""))
        if opt["svg"]:
            os.makedirs(opt["svg"], exist_ok=True)
            with open(os.path.join(opt["svg"], c.id + ".svg"), "w") as f:
                f.write(render_svg(r.schema, r.circuit))
    n = T["circuits"]
    print("circuits %d, drawn %s, legal %s" % (n, pct(T["drawn"], n), pct(T["legal"], T["drawn"])))
    print("  illegal by gate: %s" % (dict(gates_hit) or "none"))
    print("  relations shown %s; every relation shown in %s" % (pct(T["relations shown"], T["relations"]), pct(T["all relations shown"], T["drawn"])))
    print("  not shown, by rule: %s" % (dict(sorted(missed.items())) or "none"))
    print("  terminals joined by name for want of a path: %d, in %s" % (T["terminals joined by name for want of a path"], pct(T["circuits with such a terminal"], T["drawn"])))
    print("  wire crossings: %d (the people's drawings: %d)" % (T["crossings"], T["crossings in the person's drawing"]))
    print("  %.1f s in all, %.2f s per circuit; slower than 5 s: %s" % (T["seconds"], T["seconds"] / max(T["drawn"], 1), slow[:5]))
    for cid, err, where in crashes[:12]:
        print("  CRASH %-11s %s   [%s]" % (cid, err[:90], where[:70]))
    if len(crashes) > 12:
        print("  ... %d crashes in all" % len(crashes))
    return 1 if crashes or T["legal"] != T["drawn"] else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
