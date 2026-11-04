"""tests/golden.zig's scorer, transcribed, plus per-pair disagreement lists.

Oracle check: run as a script; it re-scores every deck from `gallery --cells`
(scoreCells path) and from `gallery --dump` (score path) and asserts the
aggregate line equals `gallery --score` (labels excluded on the cells path).
"""
import os, re, sys

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
HERE = os.path.dirname(os.path.abspath(__file__))
FIG_TOL = 0.2
DRAW_TOL = 2.0
DECKS = ["ota_5t", "two_stage_pmos", "fd_two_stage", "telescopic_fd", "folded_cascode",
         "strongarm", "gilbert", "cmfb_two_stage", "bandgap_ptat", "cascode_mirror",
         "wide_swing", "beta_multiplier", "diff_pair_resistive", "telescopic_se"]


def read_figure(name):
    names, xs, ys, gates, labels = [], [], [], [], []
    for line in open(f"{REPO}/tests/golden/{name}.cir"):
        line = line.rstrip("\n")
        if not line.startswith("*%"):
            continue
        tok = line[2:].split()
        if not tok:
            continue
        if tok[0] == "labels":
            labels += [t.lower() for t in tok[1:]]
            continue
        names.append(tok[0].lower())
        xs.append(float(tok[1])); ys.append(float(tok[2]))
        gates.append({"L": "left", "R": "right", "-": "none"}[tok[3][0]])
    return dict(names=names, x=xs, y=ys, gate=gates, labels=sorted(labels))


def read_cells(path=f"{HERE}/cells.txt"):
    """deck -> {dev: (col, row, form, gate)}; form 'h' bridge / 'v'."""
    out, cur, row = {}, None, 0
    for line in open(path):
        line = line.rstrip("\n")
        if not line.strip():
            continue
        if not line.startswith(".") and " " not in line.strip() and not line.strip()[-1] in "<>=":
            cur, row = line.strip(), 0
            out[cur] = {}
            continue
        for col, tok in enumerate(line.split()):
            if tok == ".":
                continue
            dev, mark = tok[:-1], tok[-1]
            out[cur][dev] = (col, row, "h" if mark == "=" else "v",
                             "right" if mark == ">" else ("left" if mark == "<" else "none"))
        row += 1
    return out


def drawn_from_cells(fig, cells):
    """scoreCells: ten units a cell, y down -> up."""
    xs, ys, gs = [], [], []
    for n in fig["names"]:
        c, r, form, g = cells[n]
        xs.append(10.0 * c); ys.append(-10.0 * r)
        gs.append(g if g != "none" else "left")  # gate_right false for bridges
    return dict(x=xs, y=ys, gate=gs)


def order(r, fd, dd):
    if abs(fd) <= FIG_TOL:
        return None
    r[1] += 1
    ok = abs(dd) > DRAW_TOL and ((dd > 0) == (fd > 0))
    r[0] += ok
    return ok


def overlap(o, in_fig, in_draw):
    if in_fig and in_draw:
        o[0] += 1; return "both"
    if in_draw:
        o[1] += 1; return "drawing_only"
    if in_fig:
        o[2] += 1; return "figure_only"
    return None


def relate(fig, at, sign):
    s = dict(x=[0, 0], y=[0, 0], rows=[0, 0, 0], cols=[0, 0, 0], gates=[0, 0],
             bad_x=[], bad_y=[], rows_d=[], rows_f=[], cols_d=[], cols_f=[], bad_g=[])
    n = len(fig["names"]); N = fig["names"]
    for i in range(n):
        for j in range(i + 1, n):
            fx = fig["x"][j] - fig["x"][i]; fy = fig["y"][j] - fig["y"][i]
            dx = sign * (at["x"][j] - at["x"][i]); dy = at["y"][j] - at["y"][i]
            if order(s["x"], fx, dx) is False: s["bad_x"].append((N[i], N[j]))
            if order(s["y"], fy, dy) is False: s["bad_y"].append((N[i], N[j]))
            k = overlap(s["cols"], abs(fx) <= FIG_TOL, abs(dx) <= DRAW_TOL)
            if k == "drawing_only": s["cols_d"].append((N[i], N[j]))
            if k == "figure_only": s["cols_f"].append((N[i], N[j]))
            k = overlap(s["rows"], abs(fy) <= FIG_TOL, abs(dy) <= DRAW_TOL)
            if k == "drawing_only": s["rows_d"].append((N[i], N[j]))
            if k == "figure_only": s["rows_f"].append((N[i], N[j]))
    for name, want, got in zip(N, fig["gate"], at["gate"]):
        if want == "none":
            continue
        s["gates"][1] += 1
        seen = got if sign > 0 else {"left": "right", "right": "left", "none": "none"}[got]
        if seen == want:
            s["gates"][0] += 1
        else:
            s["bad_g"].append(name)
    return s


def mode(values, tol):
    best, best_n = 0.0, 0
    for a in values:
        k = sum(1 for b in values if abs(a - b) <= tol)
        if k > best_n:
            best, best_n = a, k
    return best, best_n


def symmetric(fig, at):
    n = len(fig["names"]); G = fig["gate"]; N = fig["names"]
    pairs, axes = [], []
    for i in range(n):
        for j in range(i + 1, n):
            mirrored = (G[i] == "none" and G[j] == "none") or (G[i] != "none" and G[j] != "none" and G[i] != G[j])
            if N[i][0] != N[j][0] or not mirrored:
                continue
            if abs(fig["y"][i] - fig["y"][j]) > FIG_TOL or abs(fig["x"][i] - fig["x"][j]) <= FIG_TOL:
                continue
            pairs.append((i, j)); axes.append((fig["x"][i] + fig["x"][j]) / 2)
    axis, on_axis = mode(axes, FIG_TOL / 2)
    if on_axis < 2:
        return [0, 0], [], None
    used = [False] * n
    sums, level, items = [], [], []
    for (i, j), a in zip(pairs, axes):
        if abs(a - axis) > FIG_TOL / 2 or used[i] or used[j]:
            continue
        used[i] = used[j] = True
        sums.append(at["x"][i] + at["x"][j]); level.append(abs(at["y"][i] - at["y"][j]) <= DRAW_TOL)
        items.append((N[i], N[j]))
    for i in range(n):
        if used[i] or abs(fig["x"][i] - axis) > FIG_TOL / 2:
            continue
        sums.append(2 * at["x"][i]); level.append(True); items.append((N[i],))
    drawn_axis, _ = mode(sums, DRAW_TOL)
    r = [0, len(sums)]; bad = []
    for s_, lv, it in zip(sums, level, items):
        ok = lv and abs(s_ - drawn_axis) <= DRAW_TOL
        r[0] += ok
        if not ok:
            bad.append(it)
    return r, bad, (axis, items)


def compare(fig, at):
    a = relate(fig, at, 1); m = relate(fig, at, -1)
    better = m["x"][0] > a["x"][0] or (m["x"][0] == a["x"][0] and m["gates"][0] > a["gates"][0])
    out = m if better else a
    out["mirrored"] = better
    out["sym"], out["bad_sym"], out["sym_items"] = symmetric(fig, at)
    return out


def fmt(name, s, plus="", minus=""):
    return (f"{name} x {s['x'][0]}/{s['x'][1]} y {s['y'][0]}/{s['y'][1]} "
            f"rows {s['rows'][0]}+{s['rows'][1]}-{s['rows'][2]} cols {s['cols'][0]}+{s['cols'][1]}-{s['cols'][2]} "
            f"sym {s['sym'][0]}/{s['sym'][1]} gates {s['gates'][0]}/{s['gates'][1]} labels +[{plus}] -[{minus}]")


def read_dump(name):
    """dev -> (x, y_up, gate, form) from `gallery --dump`: a MOS/BJT's drain
    line and gate row are its node (grid offset 0 for d/s at x=0, g at y=0);
    a two-pin's or switch's a/b midpoint is its node."""
    nodes, pins = {}, {}
    for line in open(f"{HERE}/dump_{name}.txt"):
        m = re.match(r"node \d+ device (\S+) group \d+ at \{ (-?[\d.]+), (-?[\d.]+) \}", line)
        if m and m.group(1) not in nodes:  # later nodes are off-line pin copies
            nodes[m.group(1)] = (float(m.group(2)), float(m.group(3)))
        m = re.match(r"pin \d+ (\S+)\.(\d+) net (\S+) side (\S+) home", line)
        if m and m.group(1) != "-":
            pins.setdefault(m.group(1), {})[int(m.group(2))] = (m.group(3), m.group(4))
    return nodes, pins


def drawn_from_dump(fig, name):
    nodes, pins = read_dump(name)
    xs, ys, gs = [], [], []
    for n in fig["names"]:
        x, y = nodes[n]
        g = "none"
        if n[0] in "mqjz":
            g = pins[n][1][1]
            assert g in ("left", "right"), (n, g)
        elif n == "ea1":
            # cvsource drawn r0 (route ends: out+ (x+20,y), in+ (x-20,y-20),
            # in- (x-20,y+20)); out- at (x,y+20). Mean of the four card pins.
            x, y = x - 5, y + 5
        elif n[0] not in "rclivdsw":
            raise SystemExit(f"{name}: {n} needs its pin mean")
        xs.append(x); ys.append(-y); gs.append(g)
    return dict(x=xs, y=ys, gate=gs)


if __name__ == "__main__":
    cells = read_cells()
    want = {l.split()[0]: l.strip() for l in open(f"{HERE}/score.txt") if l.strip()}
    bad = 0
    for d in DECKS:
        fig = read_figure(d)
        s = compare(fig, drawn_from_cells(fig, cells[d]))
        got = fmt(d, s)
        w = re.sub(r" labels .*", "", want[d]); g = re.sub(r" labels .*", "", got)
        flag = "ok " if w == g else "BAD"
        bad += w != g
        print(flag, "cells", g)
        if w != g:
            print("    want", w)
        try:
            s2 = compare(fig, drawn_from_dump(fig, d))
            g2 = re.sub(r" labels .*", "", fmt(d, s2))
            print("ok " if g2 == w else "BAD", "dump ", g2)
            bad += g2 != w
        except SystemExit as e:
            print("skip dump:", e)
    print("mismatches", bad)
    sys.exit(1 if bad else 0)
