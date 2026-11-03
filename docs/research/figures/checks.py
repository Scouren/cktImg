"""(1) every orientation-implied row edge against each figure's y;
(2) gilbert if `symmetry off` left the blocks' mates (pairMates) in place."""
from score import DECKS, read_figure, read_cells
from hints import HINTS, apply, invariants
import sim
cells = read_cells()
total = rev_all = 0
for deck in DECKS:
    fy = dict(zip(read_figure(deck)["names"], read_figure(deck)["y"]))
    S = sim.setup(deck, cells[deck])
    vert = [n for n in S["form"] if S["form"][n] == "v"]
    edges = [(u, l) for u in vert if not sim.is_rail(S["role"][S["lower"][u]])
             for l in vert if l != u and S["upper"][l] == S["lower"][u]]
    rev = [e for e in edges if fy[e[0]] <= fy[e[1]]]
    total += len(edges); rev_all += len(rev)
print(f"orientation edges: {total} checked, {rev_all} reversed by a figure")
c = dict(cells["gilbert"]); S = sim.setup("gilbert", c)
below = {k: v for k, v in sim.links_from_cells(S, c).items() if k not in ("rd1", "rd2")}
mate = sim.mates_of(S, below, sim.columns_of(S, below), symmetry=False)
out, S2, below2, _ = apply("gilbert", HINTS["gilbert"], cells)
print("gilbert, block mates kept:", mate, "->", invariants(out, S2, below2, mate))
