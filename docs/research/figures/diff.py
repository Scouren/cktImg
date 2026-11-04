"""Per deck: the figure's rows and columns, the engine's cells, and every
disagreement the score counts (from the validated scorer in score.py)."""
import sys
from score import DECKS, read_figure, read_cells, drawn_from_cells, compare, FIG_TOL, HERE


def clusters(names, vals):
    order = sorted(range(len(names)), key=lambda i: vals[i])
    groups = []
    for i in order:
        if groups and abs(vals[i] - vals[groups[-1][-1]]) <= FIG_TOL and all(abs(vals[i] - vals[j]) <= FIG_TOL for j in groups[-1]):
            groups[-1].append(i)
        else:
            groups.append([i])
    return [(round(sum(vals[i] for i in g) / len(g), 3), [names[i] for i in g]) for g in groups]


def main(only=None):
    cells = read_cells()
    labels = {l.split()[0]: l.split(" labels ")[1].strip() for l in open(f"{HERE}/score.txt") if l.strip()}
    for d in DECKS:
        if only and d not in only:
            continue
        fig = read_figure(d)
        s = compare(fig, drawn_from_cells(fig, cells[d]))
        N = fig["names"]
        print(f"=== {d}   (best match: {'mirrored' if s['mirrored'] else 'as drawn'})")
        print("  figure rows (top first):", [(y, g) for y, g in reversed(clusters(N, fig["y"]))])
        print("  figure cols (left first):", clusters(N, fig["x"]))
        gl = {n: g[0].upper() for n, g in zip(N, fig["gate"]) if g != "none"}
        print("  figure gates:", gl)
        c = cells[d]
        print("  engine cells (col,row,form,gate):", {n: c[n] for n in N})
        extra = sorted(set(c) - set(N))
        if extra:
            print("  engine cells not in figure:", {n: c[n] for n in extra})
        for k, title in [("bad_x", "x order wrong"), ("bad_y", "y order wrong"), ("rows_f", "rows figure-only"),
                         ("rows_d", "rows drawing-only"), ("cols_f", "cols figure-only"), ("cols_d", "cols drawing-only"),
                         ("bad_g", "gates wrong"), ("bad_sym", "sym wrong")]:
            if s[k]:
                print(f"  {title}: {s[k]}")
        print(f"  labels: {labels[d]}")


if __name__ == "__main__":
    main(set(sys.argv[1:]) or None)
