# The complete vocabulary

Reference for [steering.md](steering.md). Full freedom means every decision in
[decisions.md](decisions.md) can be stated as a `*@` line. This file has the
lines, then the proof: every decision maps to a line or to a reason it needs
none.

## Lines

A line is `*@ [weak] <verb> <arguments>`. Device and net names are as written
in the deck, in any case. A *pin* is a terminal name of the device's class
(`g`, `inp`) or a net the device touches (`vin1`); the terminal name decides
when two pins share a net (a diode-connected gate).

| rung | line | decides | validated against | `--decisions` exports it |
|---|---|---|---|---|
| 1 | `role <net> supply\|ground\|input\|output\|bias\|internal` | the net's role (R1 to R3) | — | strong |
| 1 | `kind <dev> nmos\|pmos\|npn\|pnp\|res\|cap\|block` | the device's kind and polarity (an undefined `X` master, a model name misread) | the card's pin count | strong |
| 1 | `class <dev> <class>` | the library class it is drawn with | the class has a terminal per drawn pin | strong |
| 1 | `group pair\|mirror\|bank\|stack\|cross <devs>`, `nogroup <devs>`, `grouping off` | blocks (built, but for `bank`) | known names; a pair or cross of two | strong |
| 1 | `symmetric <a> <b>` (devices or nets), `axis <dev or net>`, `symmetry off` | the left-right mates; what maps to itself; `off` drops every mate, the blocks' too | an involution; mates of one kind and pin count | strong |
| 1 | `driver <dev> apart\|inline` | a source drawn apart (R3) or in the circuit | a V source | strong |
| 1 | `expand <instance>` | one instance flattened (the definition's `*@ expand` does all) | an `X` of a defined `.subckt` | strong |
| 2 | `row <devs>`, `above <a> <b> [<c> ...]` | rows: level; each above the next. A flat device (a bridge, an `X` block) has no row of its own: in `row` it takes the row of the line's anchor, in `above` it stands in the anchor's column, above or below its neighbour (`above r5 x1 r4`: feedback over the block, a part under it). The anchor is the first upright device named, else the first block, else the first device | no cycle with column links (I1) | strong |
| 2 | `order <devs>` | columns left to right. The devices named stand in different columns, so a link the engine chose between them is dropped; a bridge named goes in the channel between its neighbours | no cycle | strong |
| 2 | `group stack <devs>` | a column's chain, top to bottom (built) | shared nets, no loop | strong |
| 2 | `upright <dev>`, `bridge <dev>` | the form | upright: a transistor, or a two-pin device on two nets | strong |
| 2 | `face <dev> <pin> left\|right\|up\|down` | a pin's side: the gate's, the end that is up, a bridge's direction | an orientation of the class has it; a vertical device keeps an end up | strong |
| 2 | `label <net> [at <dev>.<pin>]`, `wire <net> [ladder\|column\|trunk\|route]` | names or a wire, and which pattern or pin | the guarantees; a wire that cannot be drawn is reported, then labels | strong |
| 2 | `port <net> left\|right\|top\|bottom` | an input's or output's port side | — | strong |
| 2 | `rail <net> bar\|each\|plain` | a supply or ground as one bar, a symbol per pin, or one bar with no symbol | — | strong |
| 2 | `first <nets>` | nets wired before the rest, in this order | — | strong |
| 2 | `shelf <columns>\|off` | how many device columns a row of the drawing holds before it wraps into rows (8); `off`: one row | — | strong |
| 3 | `cell <dev> <col> <row>` | the lattice cell, in the skeleton's own frame (before it shifts the drawing to start at 0, so moving one device renumbers nothing); a bridge may take any row | distinct cells (I1) | weak |
| 4 | `at <dev> <x> <y> [R0..MR270]` | coordinates in symbol units (decimals, rounded to the nearest whole target unit: four places are exact for any unit under 5000, so an editor's snapped move reads back exactly), orientation | no symbol overlap (H5); pins clear of other nets | weak |
| 4 | `refdes <dev> left\|right\|above\|below` | where the device's name goes | clear of symbols and wires | weak |
| 5 | `via <net> <x,y> ...` | points the net's wire passes through, in order; the router joins them (libavoid's checkpoints), a point it cannot reach reported | the maze's rules | weak |
| 5 | `route <net> <x,y> <x,y> ...` | a polyline of the net, in symbol units | `Canvas.commit` (I4) | weak |

**Mates.** A line on one device of a mated pair applies to both, mirrored:
`face M3 g left` also turns M4's gate right, `cell M3 2 4` puts M4 at the
mirror cell. Two lines that contradict each other's mirror drop the pair's
mate, reported in `overridden`. The guarantee that mates mirror exactly
(I2) holds for the mates that remain: the symmetry is the engine's
tentative decision, and an agent's line outranks it.

`--decisions <rung>` prints every decision on rungs 1 to `<rung>`, so
`--decisions 3` pins the placement and `--decisions 5` pins everything. A
deck plus its own export draws the same picture with every line honoured,
even under an engine whose heuristics changed, because the lines leave it
nothing to decide.

The decision kinds are one closed enum: role, kind, class, block, mate,
axis, driver, expansion, row, column order, chain, form, pin side, net
pattern, port side, rail style, net order, cell, coordinates, refdes,
via, route. The export switches over it exhaustively, so a new engine decision
without a kind does not compile.

Changed from steering.md's first draft: `gate <dev> left|right` and
`flip <dev>` fold into `face`, which also states which end of a two-pin
device is up and which way a bridge runs; `kind`, `class`, `driver`,
`expand`, `rail`, `first`, `refdes` and `via` are new; `symmetric` takes nets too
(a net pair is routed as mirror images); `label` and `wire` take a pin and
a pattern.

Not built: the engine rejects two forms of this table, and
[ALGORITHM.md](../ALGORITHM.md) lists what it takes: `label <net> at
<dev>.<pin>` (a `label` names the whole net) and `wire <net> column`.

## Coverage

Every decision in decisions.md, by id: the line that states it, or why it
needs none. *Derived*: computed from other decisions, so pinning those pins
it. *Style*: the project's `lint.zon`, the same for every drawing.
*Guarantee*: never a choice. *Pinned outcome*: a search or a tie-break
whose result other lines state, after which nothing is searched.

| decision | line, or why none |
|---|---|
| N.pins (which fields are pins) | the card itself: the deck says what the device is |
| N.prim (an undefined master's kind) | `kind` |
| N.expand | `*@ expand` in the definition, `expand <instance>` for one |
| N.sides (a block's port sides) | `*@ left/right/top/bottom` in the definition (built) |
| L.class | `class` |
| L.side, L.roleclass | the library: a class's geometry and the role classes are the caller's |
| L.form, D.orient | `face`; `at ... <orient>` exactly |
| R.name, R.stim | `role` |
| R.driver, P.island | `driver`; `at` for an island's place |
| S.rank | pinned outcome: names break ties, and every tie's result has a line |
| S.pol | `kind` |
| S.colour, S.symkeep, S.budget | `symmetric`, `axis`, `symmetry off` (given mates, nothing is searched) |
| S.hint, S.cross, S.pair, S.gate, S.stack | `group`, `nogroup`, `grouping off` |
| K.form | `upright`, `bridge` |
| K.ends | `face <dev> <pin> up` |
| K.linkstack, K.linkscore | `group stack` joins; `order` splits; `cell` |
| K.matesrc, K.pairmates, K.mirrorable | `symmetric`; relations that conflict displace the engine's mates (reported) |
| K.rowedge, K.rowlevel, K.rowlong | `row`, `above`; `cell` |
| K.rowground | tentative: yields to a strong `row` or `above` |
| K.colside, K.colaxis, K.freeside, K.colorder, K.colx | `order`, `axis`; `cell` |
| K.br* (bridges) | `cell`, `order`, `row`, `face`: a bridge is a device on a cell |
| K.gate* | `face <dev> <gate> left\|right` |
| K.loop, C.fits | guarantee |
| K.lattice | constant: cells are lattice units |
| D.room, D.collapse | style (`stack`, `series`, `rail`, `terminal`, `label`); `at` exactly |
| D.grid, D.copy, D.mirror, D.nc, J.dots | derived |
| C.label, C.port | `label <net> at`, `port`; stub lengths are style |
| W.order, RT.order | `first` |
| W.dispatch, W.bias, W.ladder, W.column, W.track | `label`, `wire <net> <pattern>`; `route` exactly |
| W.supply | `rail` |
| W.outport | `port` |
| RT.halves, RT.mirror | `symmetric <net> <net>`, `axis <net>`; `route` |
| RT.cost, M.* | style (`clearance`, `bend_cost`, `cross_cost`); `route` |
| P.term | derived (its stub's direction, lost today: a bug to fix, not a line) |
| G.refdes | `refdes` |
| PL.devname | none: the plugin should keep the designer's names (open in steering.md §10) |
| PL.roles | `role`, carried by the import as `group` is |
| PL.budget | the plugin's limit on what it hands the engine, not a layout decision |

Nothing is left over: each decision is a line, a style setting, a guarantee,
derived, a pinned outcome, or the library's.
