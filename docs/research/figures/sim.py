"""levels.rows, skeleton.gates and the mate rules transcribed, to predict
what a hint does. Oracle: with no hints it must reproduce every golden
deck's current rows and gate sides (run as a script)."""
import re, sys
from score import REPO, DECKS, read_cells

# tests/structure.zig `expected` (the engine's symmetry and blocks, tested).
STRUCT = {
    "ota_5t": ("", "mirror m3 m4; pair m1 m2; stack m3 m1; stack m4 m2"),
    "two_stage_pmos": ("", "bank m5 m6; mirror m3 m4; pair m1 m2; stack m1 m3; stack m2 m4; stack m6 m7"),
    "fd_two_stage": ("iss m1:m2 m3:m4 m5:m6 m7:m8", "bank m3 m4; bank m7 m8; pair m1 m2; stack m3 m1; stack m4 m2; stack m5 m7; stack m6 m8"),
    "telescopic_fd": ("iss m1:m2 m3:m4 m5:m6 m7:m8", "bank m3 m4; bank m5 m6; bank m7 m8; pair m1 m2; stack m7 m5 m3 m1; stack m8 m6 m4 m2"),
    "folded_cascode": ("iss m1:m2 m3:m4 m5:m6 m7:m8 m9:m10", "bank m3 m4; bank m5 m6; bank m7 m8; bank m9 m10; pair m1 m2; stack m10 m8 m4; stack m9 m7 m3"),
    "strongarm": ("m1:m2 m3:m4 m5:m6 mt s1:s2 s3:s4", "cross m3 m4; cross m5 m6; pair m1 m2; stack m3 m5 m1; stack m4 m6 m2"),
    "gilbert": ("iss m1:m4 m2:m3 m5:m6 rd1:rd2", "pair m1 m2; pair m3 m4; pair m5 m6"),
    "cmfb_two_stage": ("iss m1:m2 m3:m4 m5:m6 m7:m8 r1:r2 r3:r4", "bank m3 m4; bank m7 m8; pair m1 m2; stack m3 m1; stack m4 m2; stack m5 m7; stack m6 m8"),
    "bandgap_ptat": ("", "bank m3 m4 m5; stack m3 q1"),
    "cascode_mirror": ("", "mirror m0 m3; mirror m1 m2; stack m0 m1; stack m3 m2"),
    "wide_swing": ("", "bank m2 m3; mirror m1 m4 m5; stack m1 m2; stack m4 m3"),
    "beta_multiplier": ("", "mirror m1 m2; mirror m3 m4"),
    "diff_pair_resistive": ("iss m1:m2 rd1:rd2", "pair m1 m2"),
    "telescopic_se": ("", "stack m4 m3 m2 m1"),
}
SIGNAL = ("ac", "sin", "pulse", "pwl", "exp", "sffm", "am", "trnoise", "trrandom")


def natkey(s):
    return [int(t) if t.isdigit() else t for t in re.findall(r"\d+|\D+", s)]


def parse(deck):
    models, devs = {}, []
    for line in open(f"{REPO}/tests/golden/{deck}.cir").read().split("\n")[1:]:
        t = line.split()
        if not t or t[0].startswith("*"):
            continue
        if t[0].lower() == ".model":
            models[t[1].lower()] = t[2].lower()
            continue
        if t[0].startswith("."):
            continue
        name = t[0].lower(); k = name[0]
        if k == "m":
            devs.append(dict(name=name, kind="mos", pins=[x.lower() for x in t[1:5]], model=t[5].lower(), card=line))
        elif k == "q":
            devs.append(dict(name=name, kind="bjt", pins=[x.lower() for x in t[1:4]], model=t[4].lower(), card=line))
        elif k in "e":
            devs.append(dict(name=name, kind="vcvs", pins=[x.lower() for x in t[1:5]], card=line))
        elif k == "s":
            devs.append(dict(name=name, kind="vswitch", pins=[x.lower() for x in t[1:5]], card=line))
        else:
            kind = {"r": "resistor", "c": "capacitor", "i": "isource", "v": "vsource"}[k]
            devs.append(dict(name=name, kind=kind, pins=[x.lower() for x in t[1:3]], card=line.lower()))
    for d in devs:
        if "model" in d:
            typ = models[d["model"]]
            d["pol"] = "p" if any(s in typ for s in ("pmos", "pfet", "pnp", "pjf", "pch")) else "n"
    return devs


def roles_of(devs):
    nets = sorted({p for d in devs for p in d["pins"]})
    role = {}
    for n in nets:
        if n in ("0", "gnd", "vss", "vee", "agnd", "dgnd", "vssa", "gnda"):
            r = "sink"
        elif n.startswith(("vdd", "vcc", "avdd", "dvdd")) or n == "vpp":
            r = "supply"
        elif n.startswith(("vb", "bias")):
            r = "bias"
        elif n.startswith(("vin", "in")):
            r = "input"
        elif n.startswith(("vout", "out", "vref")) or n == "vo":
            r = "output"
        else:
            r = "internal"
        role[n] = r
    for d in devs:  # R2
        if d["kind"] == "vsource":
            a, b = d["pins"]
            for net, other in ((a, b), (b, a)):
                if role[net] == "internal" and role[other] == "sink":
                    role[net] = "input" if any(w in d["card"].split() or d["card"].find(w + "(") >= 0 for w in SIGNAL) else "bias"
    return role


def is_rail(r):
    return r in ("supply", "sink")


def setup(deck, cells):
    devs = parse(deck)
    role = roles_of(devs)
    D = {d["name"]: d for d in devs}
    drawn = {n: not (d["kind"] == "vsource" and any(role[p] in ("supply", "input", "bias") for p in d["pins"]) and any(role[p] == "sink" for p in d["pins"])) for n, d in D.items()}
    form = {n: ("h" if cells[n][2] == "h" else "v") for n in D if drawn[n]}
    # supply distance through channel elements (not capacitors)
    dist = {n: None for n in role}
    q = [n for n in role if role[n] == "supply"]
    for n in q:
        dist[n] = 0
    i = 0
    while i < len(q):
        v = q[i]; i += 1
        for d in devs:
            if not drawn[d["name"]] or d["kind"] == "capacitor" or v not in d["pins"]:
                continue
            if d["kind"] in ("mos", "bjt"):
                chan = (d["pins"][0], d["pins"][2])
            elif d["kind"] in ("resistor", "isource", "vsource", "vswitch"):
                chan = (d["pins"][0], d["pins"][1])
            else:
                continue
            if v not in chan:
                continue
            for w in chan:
                if dist[w] is None:
                    dist[w] = dist[v] + 1; q.append(w)
    upper, lower = {}, {}
    for n, d in D.items():
        if not drawn[n] or form.get(n) != "v":
            continue
        p = d["pins"]
        if d["kind"] in ("mos", "bjt"):
            upper[n], lower[n] = (p[2], p[0]) if d["pol"] == "p" else (p[0], p[2])
        else:
            a, b = p[0], p[1]
            big = 10 ** 9
            da, db = dist[a] if dist[a] is not None else big, dist[b] if dist[b] is not None else big
            a_up = role[a] == "supply" or role[b] == "sink" or (role[b] != "supply" and role[a] != "sink" and da <= db)
            upper[n], lower[n] = (a, b) if a_up else (b, a)
    sym, blk = STRUCT[deck]
    mates = {}
    for tok in sym.split():
        if ":" in tok:
            a, b = tok.split(":"); mates[a] = b; mates[b] = a
        else:
            mates[tok] = tok
    blocks = []
    for b in blk.split("; "):
        t = b.split()
        if t:
            blocks.append((t[0], t[1:]))
    return dict(devs=D, role=role, drawn=drawn, form=form, upper=upper, lower=lower, sym=mates, blocks=blocks)


def links_from_cells(S, cells):
    """chain.below from the engine's cells: same lattice x, consecutive rows, joined lower->upper."""
    below = {}
    vert = [n for n in S["form"] if S["form"][n] == "v"]
    for a in vert:
        same = sorted([b for b in vert if cells[b][0] == cells[a][0] and cells[b][1] > cells[a][1]], key=lambda b: cells[b][1])
        if same and S["lower"][a] == S["upper"][same[0]]:
            below[a] = same[0]
    return below


def columns_of(S, below):
    above = {v: k for k, v in below.items()}
    col = {}
    for n in sorted(S["form"], key=natkey):
        if S["form"][n] != "v" or n in above:
            continue
        k, at = n, n
        while at:
            col[at] = k; at = below.get(at)
    return col


def mates_of(S, below, col, symmetry=True):
    vert = {n for n in S["form"] if S["form"][n] == "v"}
    mate = {}
    if symmetry:
        for d, m in S["sym"].items():
            if d in vert and m in vert:
                mate[d] = m
    if not mate:  # pairMates
        above = {v: k for k, v in below.items()}
        kinds = {n: S["devs"][n]["kind"] for n in S["devs"]}
        for k, ms in S["blocks"]:
            if k in ("stack", "bank") or len(ms) != 2:
                continue
            a0, z0 = ms
            if a0 not in vert or z0 not in vert or col[a0] == col[z0] or a0 in mate or z0 in mate:
                continue
            for up in (True, False):
                a, z, steps = a0, z0, 0
                while a and z and kinds[a] == kinds[z] and steps <= len(vert):
                    steps += 1
                    if a in mate and mate[a] != z:
                        break
                    mate[a] = z; mate[z] = a
                    a = above.get(a) if up else below.get(a)
                    z = above.get(z) if up else below.get(z)
                    if a and z and (a in mate or z in mate):
                        break
    # mirrorable
    while True:
        image = {}
        for d, m in mate.items():
            c = col[d]
            image[c] = col[m] if c not in image or image[c] == col[m] else "conflict"
        changed = False
        for d, m in list(mate.items()):
            if d not in mate:
                continue
            c = col[d]
            ok = image.get(c) != "conflict" and image.get(image.get(c)) == c
            if not ok:
                mate.pop(d, None); mate.pop(m, None); changed = True
        if not changed:
            break
    return mate


def rows(S, below, mate, above_hints=(), row_hints=(), drop_respects_hints=True):
    vert = sorted([n for n in S["form"] if S["form"][n] == "v"], key=natkey)
    up, lo, role = S["upper"], S["lower"], S["role"]
    edges = []
    for u in vert:
        if is_rail(role[lo[u]]):
            continue
        for l in vert:
            if l != u and up[l] == lo[u]:
                edges.append((u, l))
    forced = list(above_hints)
    cls = {d: d for d in vert}

    def find(d):
        while cls[d] != d:
            d = cls[d]
        return d

    def reaches(es, a, b):
        seen, st = {a}, [a]
        while st:
            k = st.pop()
            if k == b:
                return True
            for e in es:
                if find(e[0]) == k and find(e[1]) not in seen:
                    seen.add(find(e[1])); st.append(find(e[1]))
        return False

    edges = [e for e in edges if below.get(e[0]) == e[1] or not reaches(edges, e[1], e[0])]
    edges += forced  # strong lines: kept (a cycle with them is a conflict to report)
    for a, b in row_hints:  # strong equalities before the engine's
        ka, kb = find(a), find(b)
        if ka != kb:
            if reaches(edges, ka, kb) or reaches(edges, kb, ka):
                raise ValueError(f"row {a} {b} closes a cycle")
            cls[ka] = kb

    def level(a, b):
        ka, kb = find(a), find(b)
        if ka == kb or reaches(edges, ka, kb) or reaches(edges, kb, ka):
            return
        cls[ka] = kb

    for d in sorted(mate, key=natkey):  # device-index order ~ card order; ties never matter here
        if mate[d] != d and d in cls and mate[d] in cls:
            level(d, mate[d])
    for k, ms in S["blocks"]:
        if k == "stack":
            continue
        for d in ms[1:]:
            if d in cls and ms[0] in cls:
                level(ms[0], d)
    rank = {d: 0 for d in vert}
    for _ in range(len(vert) + 1):
        changed = False
        for u, l in edges:
            if find(u) == find(l):
                raise ValueError(f"edge {u}->{l} inside one class")
            if rank[find(l)] < rank[find(u)] + 1:
                rank[find(l)] = rank[find(u)] + 1; changed = True
        if not changed:
            break
    else:
        raise ValueError("cycle")
    r = {d: rank[find(d)] for d in vert}
    # ground drop
    for pol in ("n", "p"):
        on = [d for d in vert if S["devs"][d]["kind"] in ("mos", "bjt") and S["devs"][d]["pol"] == pol and lo[d] == "0"]
        if not on:
            continue
        low = max(r[d] for d in on)
        for d in on:
            k = find(d)
            if all(e in on for e in vert if find(e) == k):
                if drop_respects_hints and any(u == d for u, _ in forced):
                    continue
                r[d] = low
    for u, l in edges:
        if r[l] <= r[u]:
            raise ValueError(f"row order broken on {u}->{l}: {r[u]} {r[l]}")
    return r


def gates(S, x, gate_hints=None):
    devs, role = S["devs"], S["role"]
    drawn = [n for n in devs if S["drawn"][n]]
    xs = [x[n] for n in drawn]
    lo_, hi_ = min(xs), max(xs)
    g = {}
    for d in drawn:
        if S["form"][d] != "v" or devs[d]["kind"] not in ("mos", "bjt"):
            continue
        gn = devs[d]["pins"][1]
        others = [] if is_rail(role[gn]) else [v for v in drawn if v != d and gn in devs[v]["pins"]]
        own = 2 * x[d]
        if others:
            g[d] = (2 * sum(x[v] for v in others)) // len(others) > own
        else:
            g[d] = own > lo_ + hi_
    for k, ms in S["blocks"]:
        if k == "stack":
            continue
        if len(ms) > 2:
            for d in ms:
                g[d] = False
            continue
        a, z = (ms[0], ms[1]) if x[ms[0]] <= x[ms[1]] else (ms[1], ms[0])
        if x[a] == x[z]:
            continue
        g[a] = k != "pair"; g[z] = k == "pair"
    for d, side in (gate_hints or {}).items():
        g[d] = side == "right"
    return {d: ("right" if v else "left") for d, v in g.items()}


if __name__ == "__main__":
    cells = read_cells()
    bad = 0
    for deck in DECKS:
        c = cells[deck]
        S = setup(deck, c)
        below = links_from_cells(S, c)
        col = columns_of(S, below)
        mate = mates_of(S, below, col)
        r = rows(S, below, mate, drop_respects_hints=False)
        want_r = {d: c[d][1] // 2 for d in r}
        x = {d: c[d][0] for d in c}
        g = gates(S, x)
        want_g = {d: c[d][3] for d in g}
        ok = r == want_r and g == want_g
        bad += not ok
        print("ok " if ok else "BAD", deck, "mates", {k: v for k, v in sorted(mate.items(), key=lambda t: natkey(t[0]))})
        if r != want_r:
            print("   rows", r, "\n   want", want_r)
        if g != want_g:
            print("   gates", g, "\n   want ", want_g)
    print("mismatches", bad)
    sys.exit(1 if bad else 0)
