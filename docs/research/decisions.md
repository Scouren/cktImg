# Every decision the layout makes

Reference for [steering.md](steering.md): each place the engine chooses among
alternatives, what holds the result, and where an override would be injected.
Read from the code at commit 6afa8c1 (`src/` unless a path says otherwise;
`plugin/` is `tools/schemify/`). Line numbers drift; the function names do not.

Columns: **id**, **where**, **decides** (and the data holding it), **rule**,
**override at** (the cheapest injection point). Invariant numbers refer to the
table at the end.

## 0. Input and library

| id | where | decides | rule | override at |
|---|---|---|---|---|
| N.pins | netlist.zig:601-625 | which card fields are pins (`graph.members`) | Q/M/D: minimum count unless a later field names a known `.model`; E/G: 2 pins for `value=`/behavioural words, else 4 | deck text |
| N.prim | netlist.zig:315-330, 540-599 | an undefined `X` master's kind | a `_` word nfet/pfet/nmos/pmos with 4 nodes is a MOS, res/cap a R/C; else a block with ports `p1..pN` | a master→kind table at :542 |
| N.expand | netlist.zig:910-916, 552-566 | flatten or block | `*@ expand` per definition; ngspice names; depth ≤ 32 | exists; per instance needs a set at :552 |
| N.sides | netlist.zig:917-925; library.zig:388-397, 475-487 | port side and order of a generated block | `*@ left/right/top/bottom` in order; else vdd* top, gnd/vss/0 bottom, out*/o right, rest left | exists (ignored when a class has the subckt's name) |
| N.hints | hints.zig; netlist.zig:271 | grouping hints | top level of the first source; lines in a `.subckt` are its own (lost when expanded) | exists |
| L.class | library.zig:499-525, 349-431 | the class a device is drawn as | by kind and model: MOS p when the model starts with `p` or holds pfet/pmos; unregistered → `generic<n>`; subckt → its class, else `block:<name>` | register classes; per-device class table at schematic.zig:227 |
| L.side | library.zig:163-168, 222-234 | the side a pin faces | `Terminal.side`, else the larger of abs(x), abs(y) of the placed anchor | class geometry |
| L.form | schematic.zig:317-321; library.zig:92-125 | the two base frames | vertical: the class turned a quarter left; horizontal: as drawn; flips make all 8 | (orientation, flip_x, flip_y) |
| L.roleclass | library.zig:343-347; placed.zig:458-469 | a terminal's symbol | the first class registered with that role; else a label | registration order |

## 1. Roles

| id | where | decides | rule | override at |
|---|---|---|---|---|
| R.name | schematic.zig:198-202, 330-349 | role per net (`roles[]`) | R1 by name | **exists**: the `roles` slice (Zig API only; not the C ABI, not the plugin) |
| R.stim | schematic.zig:204-213, 351-358 | an internal net a V source drives from the sink | R2: signal words → input, else bias | `roles` |
| R.driver | schematic.zig:294-306 (used at skeleton.zig:195, sketch.zig:94, placed.zig:287) | not drawn in the circuit | R3, recomputed at three sites | one table first, then a per-device override |

## 2. Structure

| id | where | decides | rule | override at |
|---|---|---|---|---|
| S.rank | structure.zig:125-126, 146-192 | canonical order (`device_rank`) | natural sort; net order is recomputed at skeleton.zig:104 and wires.zig:82-96 | permutation after :125; nets need one shared table first |
| S.pol | symmetry.zig:120-129 | n / p / other | model substrings pmos/pfet/pnp/pjf/pch → p, nmos/nfet/npn/njf/nch → n, else first letter. **Disagrees with L.class** (`lvtpch`: p ends, `nmos` symbol) | per-device table at 5 call sites |
| S.colour | symmetry.zig:168-226 | which vertices may map onto each other | devices by kind, polarity, pin count; nets by role (input ≡ bias) | key override (pin a device to the axis) |
| S.symkeep | symmetry.zig:331-406 | the symmetry (`device_mate`, `net_mate`) | involutions that keep pins and move a non-rail net; most non-source devices moved wins | write the mates after structure.zig:130; must stay involutions |
| S.budget | symmetry.zig:41-46 | when the search stops | 64 refinements, 16 maps | constants |
| S.hint | structure.zig:224-228, 347-404 | hinted blocks, exclusions | nogroup first; hints in line order, first claim wins | **exists** (`*@ group/nogroup/grouping off`; no `bank` verb) |
| S.cross / S.pair / S.gate / S.stack | structure.zig:230-339 | recognized blocks | ALGORITHM.md §2 | hints |

## 3. Skeleton

| id | where | decides | rule | override at |
|---|---|---|---|---|
| K.form | skeleton.zig:212-226 | vertical or bridge (`form[]`) | ALGORITHM.md §3; vertical only for a transistor or a two-pin device on distinct nets | table after :102 (validate) |
| K.ends | skeleton.zig:229-295 | `upper[]`, `lower[]` | type, rails, supply distance | table after :103 (upper ≠ lower) |
| K.linkstack | skeleton.zig:332-339, 393-400 | a stack block's link first | either way round, lowest rank | `*@ group stack` |
| K.linkscore | skeleton.zig:402-456 | the other links (`chain.below/above`) | transistor, reaches a rail, same type, rank | seed links after the clear at :324; a forbid set in `choose` |
| K.loop | skeleton.zig:346-371 | links that close a loop | refused | validate forced links with `closesLoop` |
| K.matesrc / K.pairmates / K.mirrorable | skeleton.zig:458-535 | `mate[]` | the symmetry's, else blocks' carried down columns; dropped unless columns mirror whole | replace at :133, then rerun `mirrorable` |
| K.rowedge / K.rowlevel | levels.zig:43-74, 126-135 | above/below edges; held-level classes | longest path; equalities kept when they close no cycle, **accepted greedily in device-index order** (a latent card-order dependence; no failing case found) | forced edges and equalities in `level()`, refusals reported |
| K.rowlong | levels.zig:76-96 | `rank[]` (rows); y = 2·rank | longest path over the held-level classes; asserts each device's row below the one above it | forced rows after skeleton.zig:135, validated (strictly increasing down a column, mates level) |
| K.rowground | levels.zig:98-124 | ground drop | transistors on net 0 drop to their type's lowest row (net 0 only, not every sink) | per-device opt-out |
| K.colside / K.colaxis / K.freeside | columns.zig:92-330 | left/right, axis, free columns | hops from a reference device; outputs right | forced side after columns.zig:92 |
| K.colorder | columns.zig:349-414 | order within each list | all orders up to 6 columns (Heap's; the `steps < 1000` assert ties this to 6), else adjacent swaps | forced order (skip `best`) |
| K.colx | columns.zig:131-167 | `col_x[]` | axis 0, halves ±1 or ±2, step 2 | forced x after skeleton.zig:141 (validate mirror pairs) |
| K.lattice | skeleton.zig:75-77, 143-147 | lattice cell | x = 4·col_x (neighbouring device columns 8 apart, 7 bridge slots), y = 2·row | constant |
| K.br* | bridges.zig:44-275 | bridge chains, slots, rows, mirror, collisions | ALGORITHM.md §3; collisions shift outward | pre-mark forced cells at :44-49 |
| K.gate* | skeleton.zig:537-578 | `gate_right[]` | face the rest of the gate net; block rules | table after :156 |

## 4. Drawing

| id | where | decides | rule | override at |
|---|---|---|---|---|
| D.orient | sketch.zig:83-146 | `flip_x`, `flip_y` | first of four flips that fits; a bridge's pin 0 toward its net; 3+-pin bridges never flipped | per device before `settleDevices` |
| D.room | sketch.zig:148-198 | room per lattice column and row | reach, +2 gaps beside a port/label/rail pin, +1 gap up/down | room table before :199 |
| D.collapse | sketch.zig:214-228 | lattice → coordinates | empty columns take no room; **rows never collapse** | — |
| C.fits | canvas.zig:91-112 | whether a wire may be drawn | no other net's point inside; no end on another net's wire; no overlap; not through a box | the one gate: pinned routes go through `commit` |
| C.label / C.port | canvas.zig:127-148 | label and port stubs | half a gap / a gap, else on the pin | per-net offset |
| W.order | wires.zig:79-96 | net order | rails, inputs and bias, the rest; by name | forced priority |
| W.dispatch | wires.zig:99-109 | pattern family per net | by role | **forced pattern table here** |
| W.supply / W.bias / W.ladder / W.column / W.track | wires.zig:131-389 | rails, gate lines, ladders, columns, trunk tracks | ALGORITHM.md §4 | per pattern (bar y, upright x, track y) |
| W.outport | wires.zig:262-296 | output port side | nearer side of the drawing's middle | forced side |
| RT.* | routes.zig:38-282 | routing order, halves, mirrored mates, pin order, costs, failures | ALGORITHM.md §4 | per-net query; forced order |
| M.* | maze.zig | grid, legal moves, costs, window, ties, cap (65 536 points) | ALGORITHM.md §4 | Query fields |

## 5. Result and plugin

| id | where | decides | rule | override at |
|---|---|---|---|---|
| J.dots | dots.zig:21-88 | junction dots | ≥ 3 directions | derived |
| P.island | placed.zig:280-341 | driver islands | left of the circuit, by name | forced order/position |
| P.term | placed.zig:218-259 | exported terminal symbols | the role class at `r0`; **the stub's direction is not exported** | orientation table |
| G.refdes | geom.zig:45-97 | name anchors | first clear spot, placed in `Placed` order (**card order**) | forced anchors first |
| PL.budget | plugin/layout.zig:37-48, 342-346 | engine or labelled grid | > 120 wired devices a cell, > 400 an import | constants |
| PL.devname | plugin/layout.zig:312, 422-434 | the engine's device names | `<letter><row>`: the canonical order follows **instance order**, so a Schemify import's drawing depends on card order | name by the designer's names, or by their rank |
| PL.roles | plugin/layout.zig:349 | roles | `engine.place` guesses them; the plugin cannot pass roles | a `*@ role` verb, with net-name remapping in plugin/hints.zig |

## Invariants, and what an override can break

| # | invariant | enforced by | broken by a careless override of |
|---|---|---|---|
| I1 | each drawn device once, on a cell of its own | skeleton.zig:158 assert; tests/cases.zig random netlists; the plugin's dropped-device assert | rows within a column, column x, axis assignment, bridge cells, `drawn` |
| I2 | a symmetric circuit is an exact mirror image | skeleton.zig:160, columns.zig:168 asserts; tests/skeleton.zig | any one-sided x, row, gate, orientation, room or bridge override; mates injected without `mirrorable` |
| I3 | every net is one piece | `support.expectConnected` (sketch, cases, fuzz, api, schemify tests) | pinned routes that strand a pin with no label; a "never label" policy |
| I4 | no wire on another net's point | `support.shorts`; `Canvas.fits` | drawing outside `commit`; moving anything after `Canvas.init`; maze step or clear under 1 |
| I5 | one picture per circuit | golden, skeleton, structure card-order tests; fuzz (reversed cards) | requests keyed by card index; greedy loops in card order |
| I6 | the same deck gives the same bytes | tests/cases.zig, tests/schemify.zig | hash-map iteration in an override table |
| I7 | the layout ends | budgets with paired asserts; no relayout loop | raising a budget alone; any relayout loop |
| I8 | golden scores as recorded | tests/golden.zig, tests/skeleton.zig | changing the default path |
| I9 | internal contracts | involutions, upper ≠ lower, row order, mutual sides, monotone coordinates, every pattern and maze path commits | any override reaching them unvalidated: validate at the edge and return an error |

## Magic constants

| constant | value | where |
|---|---|---|
| gap | the symbol set's `unit` (40 in the tests, 60 in the plugin) | library.zig:294; plugin/layout.zig:51 |
| lattice | spread 4, row factor 2, col_x step 2 | skeleton.zig:77, 146; columns.zig:135-166 |
| link score | 4, 2 (upper); 8, 4, 2 (lower); ×10⁶ − rank | skeleton.zig:407-423 |
| symmetry | 64 refinements, 16 maps | symmetry.zig:45-46 |
| column search | 6 columns exhaustive; greedy rounds < len² | columns.zig:50, 377, 398 |
| room and stubs | +2 gaps per side pin, +1 up/down; terminal and port 1 gap, label ½ gap, supply bar 1 gap up; trunk tracks ±¼, ±½ gap | sketch.zig:182-226; wires.zig:122-413; canvas.zig:133, 142 |
| ladder | minimum overlap 2 target units (not scaled) | wires.zig:232 |
| maze | step and clear ¼ gap (at least 1), bend 1 gap, cross 2 gaps (a rail's ½ gap), window +8 steps, 65 536 grid points | routes.zig:121-126; maze.zig |
| text | char_w 5, text_h 7, label_gap 3 (not scaled) | geom.zig:18-24 |
| plugin | 400 / 120 devices; fallback rows 24 units | plugin/layout.zig:42, 48, 765 |
