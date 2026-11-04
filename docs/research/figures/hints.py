"""Each deck's proposed `*@` lines, applied through the transcribed engine
(sim.py: links, mates, levels.rows, gates) and scored with the transcribed
golden scorer (score.py). Prints the predicted score and the invariant
checks; a deck whose hints are wrong fails here, not in prose."""
import sys
from score import DECKS, read_figure, read_cells, compare, fmt
from sim import setup, links_from_cells, columns_of, mates_of, rows, gates, natkey

# deck -> hint lines, and how each lands (the design's landing points).
HINTS = {
    "two_stage_pmos": ["cell Rc 19 2", "cell Cc 21 2"],
    "folded_cascode": ["above M9 Iss", "above Iss M7", "above M7 M1", "above M1 M3",
                       "face M3 g left", "face M4 g right", "face M5 g left", "face M6 g right",
                       "face M7 g left", "face M8 g right", "face M9 g left", "face M10 g right"],
    "strongarm": ["above M3 S3", "above S3 M5"],
    "gilbert": ["symmetry off", "order RD1 M1 M5 M2 Iss M3 M6 M4 RD2", "above RD1 RD2",
                "face M2 g left", "face M4 g left"],
    "cmfb_two_stage": ["cell R3 4 5", "cell R4 28 5"],
    "bandgap_ptat": ["face Q3 b left"],
    "wide_swing": ["above Iin Ibias", "above Ibias M4", "above M4 M5", "above M5 M3", "face M5 g right"],
    "beta_multiplier": ["face M5 g left"],
}


def apply(deck, lines, cells, drop_respects_hints=True):
    c = dict(cells[deck])
    S = setup(deck, c)
    above = [tuple(t.lower() for t in l.split()[1:3]) for l in lines if l.startswith("above ")]
    gate_h = {l.split()[1].lower(): l.split()[3] for l in lines if l.startswith("face ") and l.split()[2] in ("g", "b")}
    cell_h = {l.split()[1].lower(): (int(l.split()[2]), int(l.split()[3])) for l in lines if l.startswith("cell ")}
    order = next((l.split()[1:] for l in lines if l.startswith("order ")), None)
    symmetry = "symmetry off" not in lines
    below = links_from_cells(S, c)
    x = {d: c[d][0] for d in c}
    if order:
        # `order` names columns left to right; devices it orders apart are not
        # linked (the engine's link is tentative). Device columns 8 apart.
        names = [n.lower() for n in order]
        for a in names:
            for b in names:
                if below.get(a) == b:
                    del below[a]
        for i, n in enumerate(names):
            x[n] = 8 * i
    col = columns_of(S, below)
    mate = mates_of(S, below, col, symmetry=symmetry) if symmetry else {}
    r = rows(S, below, mate, above_hints=above, drop_respects_hints=drop_respects_hints)
    y = {d: (2 * r[d] if d in r else c[d][1]) for d in c}
    for d, (cx, cy) in cell_h.items():
        x[d], y[d] = cx, cy
    g = gates(S, x, gate_h)
    out = {d: (x[d], y[d], c[d][2], g.get(d, "none")) for d in c}
    return out, S, below, mate


def invariants(out, S, below, mate):
    msgs = []
    seen = {}
    for d, (x, y, f, _) in out.items():
        if (x, y) in seen:
            msgs.append(f"I1 {d} and {seen[(x, y)]} share cell {(x, y)}")
        seen[(x, y)] = d
    vert = [d for d in out if out[d][2] == "v"]
    dev_cols = sorted({out[d][0] for d in vert})
    for d in vert:  # a column is a chain: same x => linked in row order
        for e in vert:
            if d != e and out[d][0] == out[e][0] and out[d][1] < out[e][1]:
                between = [k for k in vert if out[k][0] == out[d][0] and out[d][1] < out[k][1] < out[e][1]]
                if not between and below.get(d) != e:
                    msgs.append(f"chain: {d} over {e} in one column without a link")
    for d, (x, y, f, _) in out.items():
        if f == "h" and x in dev_cols:
            msgs.append(f"bridge {d} on device column {x}")
        if f == "v" and y % 2:
            msgs.append(f"vertical {d} on odd row {y}")
    for d, m in mate.items():
        if out[d][1] != out[m][1]:
            msgs.append(f"I2 mates {d},{m} on rows {out[d][1]},{out[m][1]}")
    sums = {out[d][0] + out[m][0] for d, m in mate.items()}
    if len(sums) > 1:
        msgs.append(f"I2 mates sum to several axes {sorted(sums)}")
    for d, m in mate.items():
        if d != m and out[d][3] == out[m][3] and out[d][3] != "none":
            msgs.append(f"I2 mates {d},{m} gates both {out[d][3]}")
    return msgs


def grid(out):
    w = max(v[0] for v in out.values()) + 1
    h = max(v[1] for v in out.values()) + 1
    rows_ = []
    for r in range(h):
        line = []
        for cc in range(w):
            t = "."
            for d, (x, y, f, g) in out.items():
                if (x, y) == (cc, r):
                    t = d + ("=" if f == "h" else (">" if g == "right" else "<"))
            line.append(f"{t:<7}")
        rows_.append("".join(line).rstrip())
    return "\n".join(rows_)


if __name__ == "__main__":
    cells = read_cells()
    only = set(sys.argv[1:])
    bad = 0
    for deck in DECKS:
        if only and deck not in only:
            continue
        lines = HINTS.get(deck, [])
        out, S, below, mate = apply(deck, lines, cells)
        fig = read_figure(deck)
        drawn = dict(x=[10.0 * out[n][0] for n in fig["names"]], y=[-10.0 * out[n][1] for n in fig["names"]],
                     gate=[out[n][3] if out[n][3] != "none" else "left" for n in fig["names"]])
        s = compare(fig, drawn)
        perfect = (s["x"][0] == s["x"][1] and s["y"][0] == s["y"][1] and s["rows"][1] == s["rows"][2] == 0
                   and s["cols"][1] == s["cols"][2] == 0 and s["sym"][0] == s["sym"][1] and s["gates"][0] == s["gates"][1])
        inv = invariants(out, S, below, mate)
        bad += (not perfect) or bool(inv)
        print(("PERFECT" if perfect else "IMPERFECT"), fmt(deck, s).replace(" labels +[] -[]", ""), f"({len(lines)} lines)")
        for l in lines:
            print("   *@", l)
        for m in inv:
            print("   INVARIANT", m)
        if not perfect:
            for k in ("bad_x", "bad_y", "rows_f", "rows_d", "cols_f", "cols_d", "bad_g", "bad_sym"):
                if s[k]:
                    print("   ", k, s[k])
        if lines and "-v" in sys.argv[0:1] + list(only):
            print(grid(out))
    print("decks failing:", bad)
    sys.exit(1 if bad else 0)
