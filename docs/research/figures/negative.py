"""Red checks for hints.py: every proposed line is needed (leave-one-out),
the ground drop as built breaks wide_swing, and the alternative meanings
of `symmetry off` / one-sided gates break gilbert and folded_cascode."""
from score import read_figure, read_cells, compare
from hints import HINTS, apply, invariants
import sim

cells = read_cells()

def verdict(deck, lines, **kw):
    try:
        out, S, below, mate = apply(deck, lines, cells, **kw)
    except ValueError as e:
        return f"ENGINE-ASSERT ({e})"
    fig = read_figure(deck)
    d = dict(x=[10.0 * out[n][0] for n in fig["names"]], y=[-10.0 * out[n][1] for n in fig["names"]],
             gate=[out[n][3] if out[n][3] != "none" else "left" for n in fig["names"]])
    s = compare(fig, d)
    miss = [k for k in ("bad_x", "bad_y", "rows_f", "rows_d", "cols_f", "cols_d", "bad_g", "bad_sym") if s[k]]
    inv = invariants(out, S, below, mate)
    if not miss and not inv:
        return "perfect"
    return "; ".join([f"{k}={s[k]}" for k in miss] + inv)

for deck, lines in HINTS.items():
    for i, l in enumerate(lines):
        rest = lines[:i] + lines[i + 1:]
        v = verdict(deck, rest)
        print(f"{deck:16} without '{l}': {'REDUNDANT' if v == 'perfect' else 'needed -> ' + v[:150]}")

print()
print("wide_swing, ground drop as built:", verdict("wide_swing", HINTS["wide_swing"], drop_respects_hints=False))

# gilbert if `symmetry off` left the blocks' mates (pairMates) in place
orig = sim.mates_of
def block_mates_only(S, below, col, symmetry=True):
    return orig(S, below, col, symmetry=False)
import hints as H
H.mates_of = block_mates_only
lines = HINTS["gilbert"]
out, S, below, mate = apply("gilbert", lines, cells)
print("gilbert, symmetry off keeps block mates: mates", mate, "->", invariants(out, S, below, mate))
H.mates_of = orig
