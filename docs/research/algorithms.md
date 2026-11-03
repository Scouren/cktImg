# Algorithms for the hard overrides

Reference for [steering.md](steering.md) §2: the overrides a request table
alone cannot carry, each with the algorithm chosen, its guarantees, its cost
at cktImg's sizes (cells of 2 to 120 devices, about 10³ constraint edges,
about 100 lines), and how it reports a conflict. "(Derived)" marks our own
reasoning, to be tested before it is trusted; sources read only as an
abstract are marked so.

## 1. Rows and order, with explanations

Each axis is one difference-constraint graph. `above a b` is
`row_b ≥ row_a + 1`, `row a b` an equality, `cell` two edges to a zero
vertex; the engine's own column links, above/below edges, mates and blocks
are edges too, tentative, each recording its origin. Columns use the same
graph after folding the mirror (a mate's x is axis2 − x), so `order` lines
are edges on one half.

**Admission.** Guarantees, then strong lines (later first), then `weak`
lines (later first), then the engine's edges in today's order (links by
score, mates, blocks). Each goes in when it closes no positive cycle, else
it is dropped. For a strict total order this greedy pass computes the unique
*preferred relaxation*, the lexicographically best consistent subset
([Junker 2004](https://cdn.aaai.org/AAAI/2004/AAAI04-027.pdf), after
Brewka): no number of weaker lines outvotes a stronger one. Rows are then the
longest path, as now.

**The check.** With weights 0 and 1, equalities are union-find classes and an
edge closes a cycle exactly when its head already reaches its tail: what
`levels.level()` and `reaches()` do today, plus recording why. A DFS is
O(n + m). With `cell` rows the weights go negative: keep a feasible
potential and check each edge incrementally, O(m + n log n), returning the
cycle on failure ([Cotton and Maler](http://www-verimag.imag.fr/~maler/Papers/ffdcp.pdf)).
Incremental topological order (Pearce and Kelly;
[Haeupler et al.](https://arxiv.org/abs/0803.0792)) is the upgrade path, not
needed at 120 devices.

**Links join the pass.** Lines go in before links; candidate links then pass
the same check in score order, and a link that would close a cycle with a
line is dropped and listed as overridden. This replaces `closesLoop` and the
device-index order in which mate equalities are accepted today (the latent
card-order dependence of steering.md §10).

**Conflicts.** A dropped line's cycle is minimal over edges, but a line can
add several edges (`order a b c`). The report gives the *preferred
conflict*: walking the admitted lines from least preferred up, drop each
while the rest still conflict with the new line. For a strict order it is
unique, and an independent checker can recompute it by brute force, which
gives the explanations an oracle of their own. Only lines with an edge in
the new line's strongly connected component can belong (derived).

**Correction to steering.md §4.** "Removing any one would let it in" fails
when a line is blocked by two separate cycles: no single removal admits it.
`blocked_by` is the preferred conflict (no proper subset blocks the line),
each member flagged `alone` when deleting it by itself would admit the line.

**Cost.** About 100 lines × 10³ steps, plus 10⁵ for the longest path: well
within the plugin's fuel.

## 2. Forced cells with weak stays

Never pack in two dimensions: keeping orthogonal order while removing
overlap is NP-hard to do compactly
([arXiv 1502.03847](https://arxiv.org/abs/1502.03847)), and the
lattice avoids it, because a vertical device's x is its column's and columns
are ordered. A strong `cell` enters §1 as two equalities, so a clash with a
link, a row or an `order` line comes out as a cycle with its explanation.

**Push.** A pinned column landing on another's x keeps the column order:
columns past it, in the direction it moved, go to `max(old, previous + 2)`,
the rest stay. This is Abacus's PlaceRow
([Spindler et al.](https://pdfs.semanticscholar.org/cad2/9c9485b0e53c547d36a62e71959019c02018.pdf))
and one-dimensional VPSC
([Dwyer et al.](https://people.eng.unimelb.edu.au/pstuckey/papers/gd2005b.pdf)),
with pinned positions as constants rather than heavy weights (libcola's
[`Lock`](https://www.adaptagrams.org/documentation/classcola_1_1Lock.html)).
When the old positions were feasible, the pushed point is the nearest to
them in every coordinate at once, optimal for any distance (derived).
O(columns) per pin. Bridges keep `bridges.zig`'s outward shift, strong slots
marked taken first.

**Mirror.** A pin on a mated device implies its mate's cell (axis2 − c, the
same row), as analog placement's symmetry constraints state
([Lin et al.](https://cc.ee.ntu.edu.tw/~ywchang/Papers/tcad09-analog-placement.pdf)):
admitted as a derived edge with the pin's origin. When the derived cell
collides with something stronger, or a self-symmetric device is pinned off
the axis, the pair's tentative mate goes (`mirrorable` reruns), reported.

**Conflicts.** A moved weak cell is `relaxed`, its residual the distance in
cells, its `blocked_by` the pin that pushed it. The general case (stays on
rows and columns, partial orders) is convex-cost dual network flow
([Ahuja, Hochbaum and Orlin](https://pubsonline.informs.org/doi/10.1287/mnsc.49.7.950.16384),
abstract read): build it when a deck needs it.

## 3. "Always a wire, never a label"

Possible when channels can grow, in both directions. Adding rows alone is
not enough: a cyclic channel "may be unsolvable within the channel, for any
w … Such problems can always be solved by using columns outside the
channel" ([Rivest and Fiduccia](https://people.csail.mit.edu/rivest/pubs/RF83.pdf)).
Layouts sliced by full cuts take any extra edge for two cuts each way
([Eiglsperger, Fekete and Klau](https://users.monash.edu.au/~davidwo/papers/OrthogonalGraphDrawingSurvey-LNCS2025.pdf));
ELK sizes each gap between layers from its routing slots and breaks cycles
with a dogleg ([ELK](https://github.com/eclipse-elk/elk/blob/master/plugins/org.eclipse.elk.alg.layered/src/org/eclipse/elk/alg/layered/p5edges/OrthogonalEdgeRouter.java)).

**`Canvas.stretch(axis, at, by)`.** Moves every point, segment and box past a
lattice line by two clearances. The shift is monotone along the axis, so
every `fits` stays true and nothing is ripped up (derived; a metamorphic
test re-checks every segment). When the maze fails for a pin: a cut beside
the pin's band, beside the target, and along one channel between, at most
2 + 2 cuts; the new lines carry only perpendicular crossings, so a path
exists, and A* finds the cheapest
([Hart, Nilsson and Raphael](https://ieeexplore.ieee.org/document/4082128)).
Mirrored drawings cut in pairs. Cost: at most four cuts per failed
connection, a unit wider and taller.

**Conditions** (derived): a valid cut crosses no symbol; the pin can reach
it without touching another net's point or wire; and no rung-4 or rung-5 pin
lies on the side the cut shifts. Shift the side that has none; when both do,
the cut is blocked, and that is the one place "always a wire" and pinned
coordinates conflict.

**Before drawing**, cheaper and tidier: per channel row, assign the trunks to
tracks by constrained left-edge with a dogleg per cycle, and size `D.room`
by the track count, which moves nothing to another row or column.
PathFinder's negotiated rip-up and reroute
([McMurchie and Ebeling](https://www.cecs.uci.edu/~papers/compendium94-03/papers/1995/fpga95/pdffiles/6a.pdf))
has no completion bound and would need an iteration cap: a refinement, not
the guarantee.

**Conflicts.** A `wire` line that still fails is `relaxed` to labels;
`blocked_by` names the owners of the blocked access, or the pins on both
sides of the cut.

## 4. Four-way junctions and parallel spacing

**Checker (H7):** a point where a net has four directions, counted as
`dots.find` counts them (KiCad's
[`four_way_junction`](https://docs.kicad.org/doxygen/erc__item_8cpp_source.html)).
**Prevention:** a point of a net's tree is a maze target only while it has
at most two arms, so a new branch makes at most a T, and a branch from the
far side lands elsewhere: the staggered pair of T's for free. Patterns run
the same check before they commit. **The ladder:** off the axis, each rung's
right half meets the upright a track lower; on the axis, two uprights a
track either side, joined at one end, so the mirror stays exact (derived).

**Spacing.** libavoid orders the routes on a shared path for the fewest
crossings, then keeps each segment's order while separating them
([Wybrow, Marriott and Stuckey](https://users.monash.edu.au/~mwybrow/papers/wybrow-gd-2009.pdf)).
The canvas never shares a path, so only the spreading applies: per channel,
parallel segments keep their order, move toward an even spread at least a
clearance apart, pins fixed (§2's push), each move checked with `fits` and
undone with `save`/`restore`. Start with a maze cost for running within two
clearances of another net.

## 5. Pinned coordinates and routes

Rung 4 first, then rung 5, then patterns and the maze. `at` fixes its
column's x and row's y as equalities to a zero vertex in the compaction
graph, which `coordinates()` already solves by longest path; two pins too
close close a cycle naming both lines. Then H5: the pinned box against every
other (at most 120² tests). A `route` is validated at the edge (Manhattan,
two points or more), split into pieces of at most six points, and committed
before anything else: the canvas's own test makes validation exact, and
every pin is a point from the start, so a route through another net's pin is
refused. A `fitsWhy` returns every blocker with its owner: each alone is a
minimal conflict, so `blocked_by` lists all of them.

libavoid's checkpoints route "from the source point to the first
checkpoint, to the second", skipping unreachable ones
([ConnRef](https://www.adaptagrams.org/documentation/classAvoid_1_1ConnRef.html)):
the model for a `via <net> <x,y> ...` line between rungs 2 and 5 (the maze
through each point in turn), with a skipped point reported rather than
silent. Unlike libavoid's fixed routes, a pinned route is a hard obstacle,
not a cost.

## 6. Mirrored routing under overrides

Analog routers route one net and mirror it, taking "the union of all the
blockages on both sides" so the mirror cannot fail
([Xiao et al.](https://www.cse.cuhk.edu.hk/~fyyoung/paper/iccad10_analog.pdf));
MAGICAL's router waives a pair's symmetry after repeated failures
([Chen et al.](https://baloneymath.github.io/files/ICCAD20_ar.pdf)); and
SAGERoute guides the second net toward the first's mirror image around
obstacles ([Zhang et al.](https://yibolin.com/publications/papers/ANALOG_DATE2023_Zhang.pdf)).

For cktImg: the maze checks each step twice, the net at a point and its mate
at the mirror point, and keeps the net strictly left of the axis, so
`mirrored()` cannot fail; a pinned route on one net mirrors to its mate as a
derived line; where the image is blocked (an asymmetric obstacle, a
one-sided pin), the mate is routed with a cost for straying from the image,
and the pair is `relaxed` under S5 with the points off the image as its
residual. Self-symmetric nets keep `halves`. Twice the maze's cost.

## Build order

1. **Admission and preferred conflicts (§1):** rungs 1 and 2 and every
   `blocked_by` rest on it, and it removes a card-order dependence.
2. **Four-way junctions (§4):** a hard guarantee broken today by ladders of
   three rungs or more; the checker, the two-arm target rule and the ladder
   fix are small.
3. **Pinned coordinates and routes (§5):** `commit` is already the gate.
4. **The union of blockages (§6):** better symmetry even without lines.
5. **Forced cells (§2)**, once §1 stands.
6. **Channel growth (§3):** the largest change, touching every coordinate
   and meeting pinned coordinates head-on; left-edge trunk tracks sized into
   `D.room` first, `stretch` after.
