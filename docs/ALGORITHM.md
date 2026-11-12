# Netlist → schematic

This document is the specification of the layout: the order a person draws
in (issue #8). Find the circuit's structure, place the devices by it, then
wire the placement. Placement never moves to make room for a wire, and the
whole layout is one pass, with no relayout rounds.

| stage | files | out |
|---|---|---|
| 1. Roles | `schematic.zig` | a role per net |
| 2. Structure | `structure.zig`, `symmetry.zig`, `hints.zig` | a canonical order, blocks, the left-right symmetry |
| 3. Skeleton | `skeleton.zig`, `levels.zig`, `columns.zig`, `span.zig`, `bridges.zig`, `wrap.zig` | each device's cell on a lattice, its form and gate side |
| 4. Drawing | `sketch.zig`, `canvas.zig`, `wires.zig`, `trunk.zig`, `routes.zig`, `maze.zig` | coordinates, orientations, wires, terminal symbols, labels |
| Result | `placed.zig`, `dots.zig` | `Placed`: plain data in the target's units |

`layout` (in `root.zig`) is stages 2 to 4; `place` is parse, roles, layout
and `Placed.init` in one call. Its lengths and the router's costs are the
`.layout` table of a `lint.zon` file (`config.Layout`, §4), in **units**: one
unit is the symbol set's `unit`, pin end to pin end of a two-pin symbol.
Every symbol's shape is the caller's library (`library.zig`).

## 0. Terms

**Input.** The circuit hypergraph: vertices are **nets**, hyperedges are
**devices**; a device's **pins** are ordered, pin *i* lies on one net. Net 0
is ground.

**Subcircuits.** An `X` card whose `.subckt` is defined in the netlist is one
device, a **block**: the library's class named after the subcircuit, or else a
generated box with the ports on its sides. Comments inside the definition
steer it: `*@ left inp inn` (likewise `right`, `top`, `bottom`) puts those
ports on that side of the generated box, the rest going left and right in
port order; `*@ expand` draws the body instead, flattened with ngspice's
names (`r.x1.r1`, net `x1.a`; ground stays global).

**Rails** are the supply and sink nets (§1).

**Canonical order.** Devices and nets by name, in natural order (`m2` before
`m10`, `structure.nameLess`). Every stage breaks its ties by it, never by the
order of the cards, so a deck draws the same picture whatever order its cards
are in.

**Output.** A `Schematic`: each drawn device placed and oriented, its pins,
**terminal** symbols (a supply, ground, input or output symbol on one pin's
net), **label** nodes (a net's name on a point), and the **routes**, a set of
polylines per net. `Placed` exports it (§5).

## 1. Roles

| id | pattern | rule | example | test |
|----|---------|------|---------|------|
| R1 | a net's name | `gnd vss vee agnd dgnd vssa gnda v-` and net 0 → sink; `vdd* vcc* avdd* dvdd* vpp v+` → supply; `vb* bias*` → bias; `vin* in* vref*` → input (a `vref*` a transistor's drain or collector makes → output: people give 557 of 595 such nets with no drain an input port); `vout* out* vo` → output; otherwise internal | `R1 vdd vin 1k …` | R1 |
| R2 | an internal net joined to the sink by a V source | the source has `ac`, `sin`, `pulse`, `pwl`, `exp`, `sffm`, `am`, `trnoise` or `trrandom` → input; otherwise → bias. A source a `*@ driver <src> inline` line draws in the circuit is passed: it drives no terminal net | `Vs a 0 ac 1` / `Vb b 0 dc 0.5` | R2 |
| R3 | a V source from a supply, input or bias net to the sink; or a device with no pin | not in the circuit: the net's terminal symbols stand for it there. A driver is still drawn, apart (§5) | `Vdd vdd 0 1.8` | R3 |

A circuit of parts (no transistor) with no pin on a sink still stands on a
**reference**: the internal net of two pins or more that most two-pin cards
end on (second pins less first pins; a voltage source's minus and the pin a
current source draws from count double), then the one with the most pins,
then by name. It takes the sink's role, so its parts stand upright on it,
and is drawn as people draw it, the circuit's bottom wire: one bar with no
symbol (`rail <net> plain`). People draw one bottom wire under 172 of 191
such connected pieces of the 5,263 reference drawings, and that score names
it in 77.9%. A `*@ role <net> ground` line names the ground instead, and a
`*@ role <net> internal` line on the reference leaves the circuit without
one.

Roles are an editable input to the layout (`guessRoles` only proposes them).
A bias net is one driven from outside: a `vbias` a diode-connected device
makes is an ordinary internal net by R2, and wired as one.

## 2. Structure

From the connectivity alone (`structure.analyze`): the canonical order, the
blocks, and the symmetry.

### Blocks

The groups a designer draws as one unit, after Massier, Graeb and
Schlichtmann's transistor-pair groups ("The Sizing Rules Method for CMOS and
Bipolar Analog Integrated Circuit Synthesis", IEEE TCAD 27(12), 2008). Found
in this order, each kind in canonical order; a device joins at most one of
the first three, and at most one stack.

| block | recognized when |
|---|---|
| cross-coupled pair | two transistors of one type, each one's gate on the other's drain (neither net a rail, no device's drain its own gate) |
| differential pair | the only two transistor sources on a net that is no rail and holds no gate; one type, distinct gates, distinct drains |
| mirror, bank | two or more transistors of one kind and polarity on one gate net (no rail): a mirror when one of them is diode-connected, else a bank |
| stack | transistors in series: a net (no rail) holding just one's lower end and another's upper end, chained top to bottom |

### Lines

The deck's own word overrides the engine's (issue #7, the steering research:
`docs/research/steering.md`), one `*@ [weak] <verb> <arguments>` line per
decision, read at the deck's top level (`hints.collect`; the lines inside a
`.subckt` are that definition's). Each stage applies the lines it owns and
gives each a verdict (`hints.Verdict`): honoured, relaxed, dropped (with
`blocked_by`, the stronger lines it cannot hold with) or rejected
(malformed, or naming what the deck lacks: nothing changes).

- **Strength.** Lines are admitted strongest first (`hints.admitOrder`):
  strong before `weak`, the later line first. A line that cannot hold with
  those admitted is dropped, `blocked_by` its preferred conflict (Junker:
  from the least preferred admitted line up, each one it still conflicts
  without is left out; `alone` marks a member whose deletion alone admits
  it). Of lines setting one value (a gate's side, a net's style), the
  preferred stands. The engine's own decisions come after every line.
- **Meaning (rung 1).** `group pair|mirror|bank|stack|cross`, `nogroup`,
  `grouping off`: groups stand before recognition (a hinted stack's devices
  join no recognized stack, any other hinted group's no recognized pair,
  mirror or bank; a pair or cross takes two). `symmetric a b` and `axis x`
  pin the symmetry search (`symmetry.find` seeds each pinned pair with a
  colour of its own and keeps only maps that swap it); `symmetry off`
  drops every mate, the blocks' too. `role` sets a net's role
  (`guessRoles`), `driver` a source apart or inline, `class` the symbol a
  device is drawn with, `kind` a device's kind and polarity, `expand` one
  instance flattened (the parser).
- **Relations (rung 2).** `upright` and `bridge` set a two-pin device's
  form; `face <dev> <pin> up|down` which end is up, `face <dev> g
  left|right` a gate's side, mirrored onto an unnamed mate (a line that
  turns a pair out of its mirror ends the drawing's mirror). `row` and
  `above` are difference constraints on rows (`relations.zig`), admitted
  before the engine's column links, which a link that would break one does
  not make, and before mates, blocks and the ground drop, which give way; a
  bridge a `row` line names takes that row. `order` puts columns left to
  right (`sequence.zig`): devices one line names stand in different
  columns, the columns are reordered by a stable topological sort, and a
  bridge goes between its neighbours. Each also states its mirror image on
  mated devices, kept where it fits; a mate an order line moves off its
  mirror is dropped. `label`, `wire [ladder|trunk|route]`, `port`, `rail
  bar|each` and `first` set how a net is drawn (`netlines.zig`): a `wire`
  with no room falls back to names, reported `no_room`. `shelf <columns>`
  sets how many device columns a row of the drawing holds before it wraps
  (8), `shelf off` keeps one row (`wrap.zig`).
- **Checked.** `report.verdicts` gathers every stage's verdicts and tests
  each honoured line on the finished `Placed` (`checks.drawnAs`: a row one
  y, an order increasing x, a gate on its side, a net named or wired): a
  claim the drawing does not show is `not_drawn`, a bug the fuzz hunts.
- **Fixed point.** `report.decisions` writes the engine's decisions on
  rungs 1 to 4 as lines (cells and places as `weak` stays); the deck plus
  them, under `grouping off`, draws the same picture, every line honoured.
  Routes have no export: a net's wires also follow where its ports and
  names go, which no line states.
- **Cells, places, wires (rungs 3 to 5).** `cell <dev> <col> <row>`
  (`cells.zig`) puts a device on a lattice cell in the skeleton's frame
  before its shift to 0 (`Skeleton.origin`), the device there moving to the
  nearest free cell of its row, an unnamed mate to the mirror cell; a mate
  moved off its mirror is a mate no more. `at <dev> <x> <y> [R0..MR270]`
  (`pinned.zig`) puts the class origin there, in symbol units, and turns
  it; an `at` whose symbol would overlap another is dropped (`guarantee`).
  `refdes` sets the side `geom.refdesAnchors` tries first. `route <net>
  <pts>` commits a polyline of the net before any pattern, whole or not at
  all, one of its ends on a pin of the net, each pin it passes made a point
  of it; `via <net> <pts>` runs from the net's top-left pin through each
  point in turn. The router then grows the net's other pins from that wire
  (`routes.attach`); mirrored routing leaves such nets alone. A cell or
  place on a device displaces a relation on it, which the report drops,
  blocked by it.
- **Schemify.** The import hands the engine each device under the
  designer's name (the card's letter before it when it starts with another,
  so nothing depends on the order of the instances), carries every line of
  a subckt into its cell with its device and net names mapped, and logs each
  line the engine does not honour with its verdict and the designer's line
  numbers.

### Symmetry

An involution on devices and nets that maps the circuit onto itself
(`symmetry.find`): devices and nets are the vertices of one graph, a pin an
edge labelled with its terminal. Colour refinement (1-dimensional
Weisfeiler-Leman) with individualization, after McKay and Piperno
("Practical graph isomorphism, II", J. Symbolic Computation 60, 2014): two
copies are refined, a vertex individualized in one and a candidate image in
the other, depth first, until both colourings are discrete, and the map is
read off the colours. Of the maps that are involutions, keep every device's
pins and move a net other than a rail, the one moving the most devices that
are not sources wins (the Gilbert cell has three; the book draws that one).
A device or net the map fixes lies **on the axis**. The search stops after
64 refinements or 16 complete maps: a circuit of many identical cells has
many symmetries, and the first few are as good as any.

## 3. Skeleton

Where each drawn device stands, as a cell of a lattice (`skeleton.place`).
Neighbouring device columns stand eight lattice columns apart (seven bridge
slots between) and device rows two apart, so a channel lies between any two:
bridges and wires go there.

**Drawn and form.** A device is drawn unless it is a driver (R3) or has no
pin. It is **vertical** (current enters at its top and leaves at its
bottom) when it is a transistor, a two-pin device on a rail, a two-pin
device in series (each of its nets holds one other channel element), one on
the way down (one net nearer the supply and the other nearer the ground,
counted through channel elements and never through a gate, a body or
another rail: an emitter's degeneration resistor), or a current source; a
capacitor only on a rail. The two-pin devices are R, C, L, D, V and I
cards, switches, and the current-controlled sources (F, H: their control is
a source's name, and people draw every controlled source as a two-pin
source). Anything else is **horizontal**, a **bridge**
between columns. A two-pin device between two nets the symmetry swaps
(it straddles the axis) bridges, and so does a device whose current path is
shorted (a MOS dummy).

**Ends.** A transistor's upper and lower ends come from its type (an n-type's
drain is its upper end); a two-pin device's from the rails, else the pin
nearer the supply through channel elements.

**Columns** are the chains current flows down: one device's lower end and the
next one's upper end on a net. Where several meet on a net, one link is kept:
a stack block's (hinted or recognized, either way round), else none when
either side is a differential or cross-coupled pair or a mate pair (a tail
stands in a column of its own), else the best free device on each side: a
transistor, one whose chain reaches a rail, the same type, then canonical
order. The symmetry's mate net gets the mirrored link. A link that would
close a loop is not kept.

**Mates.** The symmetry's mates where it has one; else each differential or
cross-coupled pair's, and each two-member mirror's or bank's, carried up and
down their two columns while the devices there are of one kind. Vertical
devices only, and only where every member of a column has its mate in one
column that maps back to it: columns are mirrored whole. A differential or
cross-coupled pair takes its mates first, so its loads are its own before
they are a mirror's other half. A drawing has one axis: block mates fall
into clusters, two mated column pairs in one when the circuit wires them
half to half (a net, no rail or bias, joins a column of one to a column of
the other, and another net joins their two mates: a pair and its folded
branches, two pairs on the same inputs). Where there are several clusters,
the largest holding a differential or cross-coupled pair keeps its mates
and the others lose theirs; none keeps them when none holds such a pair
(mirrors along a chain of stages). Nested about one axis, an unrelated
mirror's two would stand either side of the whole core.

**Rows** (`levels.rows`). A device stands above another when its lower end is
the other's upper end; a device's row is the longest path down those, after
mates and blocks are held level wherever that closes no cycle. Where devices
stand above each other in a loop (a transmission gate's two), only their
column's links count. Then each type's transistors on ground (net 0 or any
net of the ground role: `vss`, `gnd`) drop to that type's lowest row among
them, as the book draws a second stage's current
source beside the first stage's mirror. A two-pin part on ground with nothing
over it (its upper net is no upright device's lower end: a gate's resistor or
source, a load on a net of gates) hangs under its net: a row below the lowest
transistor the net is a gate of, level with a device the net is the upper end
of; mates hang level. People draw such a part's upper pin below its net in
72% of 1,642 pins of the 5,263 reference drawings; longest path alone stood
it on the top row. A transistor whose gate is the only gate on the junction
between two devices of one column takes a row between them, so its gate is
level with the junction and its wire runs straight into the link (69% of
1,443 such gates in the reference drawings; beside the lower device the
wire was a Z of two corners). Two cases keep their row: a transistor of the
lower device's type on the same rail (two common-source stages on ground:
people keep them level in 65% of 184), and a mated transistor of the upper
device's type on the same rail (a fully differential second stage, as the
book draws it).

**Column order** (`columns.order`). Mated columns are the core: one of each
pair on the left, its mate mirrored on the right. A column the mates map to
itself, a pair's tail, or a column wired to both halves stands on the axis
(where several share a row, a pair's tail first, the device on the net the
pair's two end on, then by rank; the rest go free). The left
half's order is the one whose wired nets span least (rails, bias nets and
nets driven from outside aside: they are symbols or labels; a bridge between
two wired nets counts the gap between their columns, so a column only a
coupling capacitor joins to the rest stands beside it), tried
exhaustively up to six columns, else by moving one column at a time while
that helps. A column with no mate goes to the side of the core's half it
shares more wired nets with (people: 70.4% of 1,459 such columns in the
5,263 reference drawings); one neither half pulls goes right of the core
when it reaches an output or a wired net joins it to a free column going
right (a mirror's two stand on one side), else left of it; each side is
ordered the same way. A circuit with no
core (no mated column, none on an axis) has all its columns ordered at
once, first by the signal's way: as few pins as can be stand left of the
transistor or controlled source that drives their net (a gate before its
driver, a load before its stage), so stages stand in the order the signal
passes them, a mirror's reference left of its copies, and a loop is cut
once; then by span, then by rank. The row is turned so that the columns an
input reaches stand left of those that drive an output.

**Bridges** (`bridges.place`). Two-pin bridges in series (through nets that
join just the two of them, gates aside) share the slots between the nearest
columns of the chain's two end nets, in order, at the first end's tap row, or
under the drawing when a column between runs through that row. Where no
channel ends on either end net, the chain takes the row of the one gate an
end net is on, its wire straight into the gate (people draw a flat part
level with the gate it joins in 597 of 1,198 such nets of the 5,263
reference drawings). A chain whose
tips stand on one column (or one end on none) stands beside it: toward the
axis when an end net lies on it, else toward an input's side or away from the
axis; the member whose tip is on that column stands next to it. Any other bridge (an op-amp) stands midway between the nearest
columns of its first and its last net that is no rail: its input and its
output, as a subcircuit lists its ports (not the supply an op-amp's first
port is on). A chain whose mate stands already mirrors it; taken slots
move it outward.

**Shelves** (`wrap.shelves`). A row of more than eight device columns (a
person's page: their drawings of over 30 devices are 20 units wide at the
median over 5,263 hand-drawn schematics, where one row of columns was 37)
is cut into shelves of equal width, one under the other. Each cut goes to
the gap within a third of a shelf of its place that the fewest nets pass
(rails aside), never between a device and its mirror image: the mirrored
core stays whole and keeps its x, and every other shelf starts at its left
edge. An internal net between two shelves is joined by name, each shelf's
pins of it wired (as a net over the crossing budget is). No cut parts the
devices a `row` or `order` line names together, and a deck with `cell` or
`at` lines is not wrapped: those are places of the drawing as it stands (a
`weak at` stay aside: relaid, a deck wraps as it did). The shelves are read
off the cells, bands of rows six lattice rows apart, so the engine's own
decisions pasted back give the shelves they came from; rows of the whole
that are empty in a shelf are closed up in it, so two of its rows never
stand a shelf's gap apart. The width is the
layout's `shelf` key (8; 0 keeps one row); `*@ shelf <columns>` sets it for
one deck, `*@ shelf off` keeps one row.

**Gates.** Every transistor's gate faces the rest of its gate net, or away
from the middle when that is a rail or it has none; then a differential
pair's face out, the two of a mirror, bank or cross-coupled pair face each
other, and a larger mirror's or bank's all face left, as along one gate line.

A symmetric circuit's cells are an exact mirror image: every mate pair's
columns sum to the axis (asserted), and no two devices share a cell.

## 4. Drawing

From the skeleton to a laid-out `Schematic` (`sketch.lay`).

**Orientation.** A vertical device takes its class turned a quarter left (a
MOSFET drawn drain right, gate up, source left stands drain up, gate left,
source down), then the first of the four flips that puts its upper end up
and its gate on the skeleton's side. A bridge takes its class as drawn, its
first pin on the side where its first net's other devices stand (by their
mean column). Two things come first: a pin on a net the bridge shares with
one other flat part of its row faces that part (two parts in series are one
line: people draw 52.7% of 1,397 such pairs so, and the mean of a far outer
net turned one end for end in 201), and a bridge with one pin alone on its
net (a port's) turns the other pin toward that pin's net.

| id | pattern | rule | example | test |
|----|---------|------|---------|------|
| O0 | a MOS bulk, a BJT substrate; a controlled source's out− on the sink; a card pin past the class's terminals | a pin of its net, drawn on the symbol with no wire (the op-amp symbol has no reference pin) | `M1 d g s b nch`, `E1 out 0 in fb 1e5` | O0 |

**Coordinates.** Each lattice column is as wide as its widest device's reach
on each side, plus a stub and a unit where a side pin on an input, bias,
output or rail net faces that side (room for its port, label or symbol);
each row as tall as its tallest device (its pins' reach, or its body where that reaches more than `stack` past them: a block with pins on its sides only), plus a stub where such a pin faces up
or down (the supply's bar over the top aside). Neighbouring columns stand
`series` apart and rows `stack` apart; an empty lattice column takes no room,
but a channel row does, so two stacked devices stand two `stack`s apart plus
their ports' room (closing up, below, brings them to one). Mirrored columns are as wide as each other, so the drawing
keeps the skeleton's symmetry exactly. Every length is rounded up to a whole
target unit, at least 1, so every coordinate is an integer. A pin whose
terminal is off its device's line for that side (an op-amp's second input)
gets a copy node on its own line.

| `.layout` key | default | the length of |
|---|---|---|
| `stack` | 0.5 | the space between neighbouring rows |
| `series` | 1 | the space between neighbouring columns |
| `rail` | 0.5 | a pin's stub to its supply or ground symbol; the supply bar over its pins |
| `terminal` | 0.5 | a pin's stub to its input or output port |
| `label` | 0.5 | a pin's stub to its net label |
| `tap` | 0.5 | pins facing one way to the trunk that joins them |
| `clearance` | 0.25 | the router's room to another net's wire or point |
| `bend_cost` | 1 | what the router, and a trunk choosing its track, pay for a bend, in wire |
| `cross_cost` | 2 | what the router pays to cross another net's wire, in wire |
| `compact` | true | whether the drawing is closed up (below) |
| `cross_max` | 3 | the most wires of other nets one internal net's wire may cross before the net is cut and joined by name (below); 3 writes about as many names as people do |
| `shelf` | 8 | device columns a row of the drawing holds before it wraps into rows of columns (Shelves, above); 0 keeps one row; a deck's `*@ shelf` line says otherwise for that deck |

A length moves nothing to another row or column: rows, columns and order are
the skeleton's (tested by stretching every one). The defaults are a person's
pitch: in 5,274 hand-drawn schematics two devices in series stand half a
unit apart, pin to pin, when nothing else is on the node and about one when
a gate or a branch joins there (two pieces of `tap`), a wire runs half a
unit from a pin to its trunk, and a ground symbol hangs half a unit under
its pin. `.layout = .{ .stack = 1, .rail = 1, .terminal = 1, .tap = 1 }` is
the roomier drawing of before.

**Closing up** (`compact.zig`, when `compact` is on). The lattice leaves
room for every wire it might draw, and a drawn circuit needs less: a person
draws a mirror's two columns a symbol and a half apart. So the circuit is
wired once on the lattice as a scratch drawing, and its empty room taken
out by one-dimensional constraint-graph compaction (Lengauer 1990, ch. 10),
along x toward the mirror axis (the left edge when there is none), then
along y toward the top. Every coordinate along the axis is a track, and
what is on one track stays on it; a symbol's tracks move as one, and so
does a stub with its port, rail symbol or name. Two things that would touch
sliding past each other keep their order and the smaller of the gap they
have and `clearance`; a wire between two symbols, bends or junctions keeps
`tap`; two devices keep their order, and `series` (along x) or `stack`
(along y) between their symbols. A row is its column's: along y, two
symbols at least `series` apart along x keep only their order, so a tall
block stands beside the stack it joins and does not hold a band of its
own. And a column is its row's: along x, two symbols at least `stack` apart
along y keep only their order, so a pair's halves close over the tail
between them and a stage stands half under its neighbour's load, as people
draw them (neighbouring columns of a block stand 1.98 units apart at the
mean in the 5,263 reference drawings; with `series` between every two
symbols the engine's stood 2.95). A supply pin's wire up to the bar is a stub, and moves with its
device, only when it is no longer than `rail`: a longer one, from a lower
row, is a wire like any other. Each track then goes as near the anchor as
that allows (a longest path, by relaxation), in steps of a quarter unit.
The two coordinates equally far from the mirror axis are one track, so both
halves answer the same constraints and the drawing stays mirrored. Only the
devices' places are kept: the wires are then drawn again on them, through
the canvas, so every guarantee of §6 holds of the closed drawing as of the
lattice's. Where two symbols would overlap after closing, the lattice's
places stand. A deck that places every device itself (`*@ at`) is not
closed up: its places are already the answer.

**Thinning** (`thin.zig`). A person seldom lets one net's wire cross more
than two others: of 43,282 wired nets in 5,263 hand-drawn reference
schematics (the Analog Canvas gallery), 423 do; past that they join the net
by name. And they cut only the far connection: 75% of the nets they name
keep the pins standing near each other wired. So after the drawing is
wired, the internal net whose wires cross the most wires of other nets,
when over `cross_max`, is **cut**, its mirror image with it, and the
crossings are counted again without it until none is over; then the drawing
is wired again, up to three times, since a wire gone may free a path. A cut
net's pins fall into parts, each pin within reach of another of its part
(3 units between two gates, 5.5 from a gate to another pin, 7.5 otherwise:
the lengths that tell the connections people wire from those they name,
right on 93.6% of held-out nets); a part of two pins or more is one trunk
with one name at a free end, a pin alone carries its name, and a net that
is all one part is named at every pin. A cut net whose parts still cross
more than two wires is named at every pin the next time round. A rail's wires are not counted (a
gate line crosses the longer stubs up to the supply bar, as the book draws it),
and a rail, a port and a net a `wire` line names keep their wires. The
default of 6 names about as many nets as the reference drawings do; 2 is
their own limit and draws a third of the crossings, with twice the names.

**Relaying** (`relay.zig`, when the deck has `weak at` stays: a previous
drawing's places, which `cktimg-json --from` reads out of its JSON). The
drawing is not made again; the stays are set against the lattice the deck
gives now. A lattice column keeps its x when its stays agree on one, and
the columns that keep theirs stand in the skeleton's order: the heaviest
such set, by devices (a longest increasing subsequence); rows likewise.
Everything else is the **radius of change** and is laid again: a device
new to the deck, one the structure now puts on another line (a pair it
mirrors, a row it joins). A line with no place of its own stands the
lattice's pitch after the line before it, and where that leaves no room
the lines after it move along as one, so a mirrored drawing stays
mirrored. A device's turn is always the skeleton's: one the structure
turns is turned where it stands. No scratch drawing is wired and nothing
is closed up, so a relaid drawing is wired once; a deck that did not
change gets its drawing back exactly (§6, the fixed point). Should two
symbols overlap, the stays are let go and the deck is laid afresh. The
wires are all drawn again: only places are carried over.

**The canvas** (`canvas.zig`) is what is drawn so far, and its `commit` the
one way to draw a wire. A wire is drawn only where it fits: through no
device's body, along no other net's wire, onto no other net's point (a pin,
an O0 pin, a wire's end or bend, a symbol or label), and with no end on
another net's wire; crossing another net's wire is allowed. Every pin is a
point of its net from the start. So no wire is ever on another net's point,
and nothing drawn is moved or repaired afterwards.

**Wires** (`wires.wire`). Nets go rails first, then inputs and bias nets,
then the rest, each group in canonical order. A **stub** is a short wire out
from a pin along its side (`rail` long to a rail symbol, `terminal` to a
port, `label` to a label); where a symbol's stub does not fit, a label goes
on the pin instead. A label off a pin goes only where no other net's wire
crosses, so a label never joins two nets.

| net | drawn as |
|---|---|
| ground | a ground symbol on a stub at each pin: one per branch, as the book draws it (`rail <net> bar`: one bar under the pins as at a supply; `plain`, and a reference by default: the bar with no symbol, every pin facing down brought to it however far, and the net's name on each piece where it cannot be one wire). No other net's wire crosses the stub: a person's symbol sits on its pin (3 of 16,030 rail stubs of half a unit or less are crossed in the 5,263 reference drawings) |
| supply | its pins facing up, no more than two units below the bar: stubs to a bar `rail` above the highest, one supply symbol on each unbroken run of the bar, at its middle stub; any other supply pin, and one farther from the bar (97% of people's upright supply runs are two units or less), a symbol of its own. A stub of `rail` is crossed by no wire, as at ground, and neither is the bar (about 12 wires cross a supply's level run in the reference drawings) |
| input | its pins on one wire (a column or a trunk, as below) with one port out from the wire's left end, or its right, when the box around the pins is no more than 6 units around half and the port's stub has room, as people draw 87% of their inputs of two pins or more; else a port on a stub at each pin |
| bias | a gate line between the two facing gates of one row, named at its middle; else its pins on one trunk with one input port out from a free end, when the box around them is no more than 6 units around half (people wire 187 of 215 such nets with one port); else an input port on a stub at each pin, as people draw a bias: of 4,378 nets named `vb*` or `bias*` in the 5,263 reference drawings, 3,228 carry port symbols and none a written name |
| internal, output | the first pattern that fits: a **ladder** (pins facing each other in pairs along rows, one pair a row on two rows or more: a rung between each pair, and an upright through them all at the axis, or the middle, as a CMFB midpoint meets its gate line); a **column** (pins standing in one column, joined in order); a **trunk** (each pin brought to one line: of the tracks that fit, the one that costs the least as the router counts a path, its wire's length and `bend_cost` a corner, the first on a tie; a turn at a pin is a corner unless the wire also leaves the way the pin faces. The rows tried, in order: the row of a pin facing sideways that every pin facing down stands over and every pin facing up under, so that pin is joined straight (a gate level with a column's junction, or the gate a lone drain comes down to); the net's tap row, midway between the lowest pin facing down and the highest facing up, else `tap` past the pins; a quarter or half unit either side; half a unit past the pins' devices; each pin's own row. A net of at most 12 pins with no port or name on its wire may take an upright trunk instead: down the column of a pin facing up or down (the link between two devices of a column, a gate a straight stub to it), midway between two neighbouring pins, half a unit either side of a pin, or on a pin facing sideways). An output's port goes out from the outer end of its trunk or column. A net no pattern fits waits for the router |

**Routes** (`routes.draw`), for the nets waiting, in canonical order:

- A net the symmetry maps to itself: its left pins joined to each other or to
  the axis, the axis between the points reached (and the net's pins on it) as
  a spine, then the left half's mirror image.
- A net and its mate: the net joined, then the mate drawn as its mirror image
  (the cross-coupled pair's X: each output runs to the opposite gates across
  the near gate tie).
- Else, or where those do not fit: from the topmost (then leftmost) pin, the
  unjoined pin nearest a joined one next, each by the cheapest path to the
  net's wires. A pin no path reaches gets a label, and then so does the
  first; an output's port goes out from the topmost of its wires' outermost
  points.

**The maze** (`maze.route`): the cheapest orthogonal path from a pin to its
net's wires, after Wybrow, Marriott and Stuckey ("Orthogonal Connector
Routing", Graph Drawing 2009). The grid is a lattice of a quarter unit (at
least 1) over the drawing, plus every coordinate a pin, a box edge or a wire
has, so a path meets any of them exactly. A step costs its length, a bend
`bend_cost`, crossing another net's wire `cross_cost` (a rail's, a quarter of
that). A path never runs inside a box, along or within `clearance` of another
net's wire or point, or through
a point of its own net that is no target; it crosses straight, never ends on
another net's wire, and enters its target pin from the pin's side. Routing one
half of a symmetric net, it keeps left of the axis and may end on it. The
search runs in a window round the pin and its nearest target first, then
round the whole net, then over the whole drawing.

**No-connects.** A device pin with no other pin on its net gets a no-connect
cross.

## 5. The result

The library draws nothing: `Placed` says where everything went, in integer
coordinates, and a target draws it (`tests/svg.zig`, the TikZ emitter, a C
consumer).

- **Devices.** A drawn device's class sits with its origin at its node,
  placed by its `Orient` (a mirror, then quarter turns); every card pin is at
  its terminal's placed anchor.
- **Wires.** Every route is a polyline of its net. Where a class's pin is not
  on the line the layout routed to (the second input of an op-amp, on its own
  copy), a short lead joins the two, along the pin's side first: every wire
  ends exactly on its pin.
- **Terminals.** Each terminal symbol becomes a device of the library's class
  for its role (`power_rail`, `ground_rail`, `input_port`, `output_port`),
  unnamed, its net on its one pin; with no such class, a label.
- **Junctions.** A net's polylines are split at every point where another of
  its wires meets them, so each piece ends on the junction: tools that
  connect only at ends (xschem) see the same net. A dot marks a point where
  one net's wires leave in three or more directions (a device lead counts as
  one; `dots.find`), a four-way junction as much as a T, as the book draws an
  op-amp's output node; and where a net's wire crosses another of its own,
  which joins them there, so no crossing of one net reads as two nets
  crossing.
- **Drivers (R3).** Each driver stands apart, left of the circuit and in
  order of name: its terminal net's symbol on top, the source upright (the
  pin on that net up), a ground symbol below. A simulator's schematic keeps
  its sources; the circuit keeps its terminal symbols. `cktimg-json` draws
  a top cell's voltage sources in the circuit (`*@ weak driver <src>
  inline` each): a cell has no bench, and people wire 971 of the 972 such
  sources in the 5,263 reference drawings where they stand.
- **Names.** Label nodes become labels (a point, and the side the text runs
  to); a no-connect is a point. Where each device's name goes is
  `geom.refdesAnchors`: beside the symbol, above or below that, then the
  other side, clear of symbols, wires and the names placed before it.

## 6. What is guaranteed, and what is open

**The book is the oracle.** `tests/golden.zig` holds 14 transistor-level
figures from the owner's analog notes, each a netlist whose device names
match its figure and the figure's device positions, gate sides and labelled
nets in `*%` comments. A drawing is scored by relations that hold at any
scale: the left/right order of every device pair (up to a mirror of the whole
drawing), their above/below order, the rows and columns pairs share, the
pairs drawn mirror-symmetric, gate sides, and the nets drawn as names. The
scores are recorded in the test, so a change either way fails until the
numbers in the tree are the measured ones. Every symmetric figure is drawn
exactly symmetric (`sym n/n`), and no figure is drawn with a label the book
does not draw (`labels +[]`).

Checked by the tests, for every textbook and golden drawing, every AnalogIOC
cell, every cell the Schemify import hands the engine, 150 random netlists
(`tests/cases.zig`) and 4000 more (`zig build fuzz`, in CI):

- every device is drawn exactly once, and every net is **one piece** as a
  netlister reads it (wires meeting at their ends, a pin joining the wire
  that ends on it, a label the wire it lies on, the net's labels and port
  and rail symbols joined by name);
- **dots exactly where a net's wires meet**: three or more arms, or a net
  crossing itself, and nowhere else (`support.dots`, which counts the arms
  itself);
  these three are `checks.find`, which `cktimg-json --report` lists;
- **no wire touches another net's point** (a pin, a MOS body, a wire's end or
  bend, a label);
- **one picture per circuit:** the same deck draws the same picture; every
  textbook and golden deck places each device the same with its cards
  reversed or rotated, and the 4000 random netlists draw the same with their
  cards reversed, device by device and wire by wire;
- the layout ends: it runs once, and each search in it (symmetry, column
  order, maze) is bounded.

**Speed.** The 107 cells of the plugin fixtures lay out in 205 ms in all, the
longest in 120 ms (`zig build bench`, ReleaseFast; the wire-first layout took
2245 ms), and the Schemify plugin built on them is 424,118 bytes.

Open, from the recorded scores: the folded cascode's, the StrongARM latch's
and the wide-swing mirror's above/below orders and gate sides, the Gilbert
cell's columns, and the shared rows the two-stage op-amp's figure has and
its drawing does not. A net whose wire cannot be drawn without running
through a device or touching another net is a label at its pins.

## 7. Test index

| what | tests |
|------|-------|
| R1–R3, O0 | `tests/cases.zig`: `R1 roles by net name`, `R1 a reference is an input, unless a drain makes it`, `R2 a net driven from ground…`, `R3 drivers of terminal nets are not drawn`, `O0 hidden pins…`; `tests/api.zig`: `placed: a driver stands apart…`; `tools/json.zig`: `deck: a top cell's voltage source is a device of the circuit…` |
| structure, hints | `tests/structure.zig`: `structure: each golden figure's symmetry and blocks`, `structure: the order of the cards changes nothing`, `hints: a hinted group stands as written…`, `hints: nogroup keeps a device out of every group…`, `hints: a name the deck does not have…`; `src/hints.zig`: `read: the forms, weak…`, `admitOrder: strong before weak…` |
| skeleton | `tests/skeleton.zig`: `skeleton: each golden figure's cells score what is recorded`, `skeleton: the order of the cards changes no cell`, `skeleton: a symmetric circuit stands as its exact mirror image`, `skeleton: a stack hint picks the link its column keeps`, `skeleton: a resistor on the way down stands upright under the emitter it leaves…`, `skeleton: a column only a bridge joins to the rest stands beside the column the bridge leads to`, `skeleton: a row of more than eight columns wraps into shelves, a pair never parted; `*@ shelf` sets the width` |
| drawing | `tests/sketch.zig`: `sketch: every drawing keeps its devices, is connected, and shorts nothing`, `sketch: every AnalogIOC cell…`, `sketch: a symbol set whose unit is under four…`, `sketch: a mirror the pair's halves are not wired to stands side by side…`, `` sketch: a ground by any name: transistors on `vss` stand as those on net 0 do ``, `sketch: stages stand in the order the signal passes them…`, `sketch: closing up reorders nothing, widens nothing…`, `sketch: a lower crossing budget names more nets and draws no more crossings`, `sketch: a net over the crossing budget keeps its near pins wired, one name a part`, `sketch: no wire crosses a rail symbol's stub or a supply bar, and no supply stub is longer than two units`, `sketch: a bias gate carries a port symbol, not a written name`, `sketch: a bias net's pins standing near each other share one wire and one port`, `sketch: two blocks stacked in one column stand clear, no pin of one on a pin of the other`, `sketch: a net between two shelves is joined by name, a shelf's own nets by wire`, `thin.zig`: `name: the net crossing the most wires is named first…`, `lines: a deck relaid from its last drawing lays again only what its structure moved`, `relay.zig`: `axis: kept lines stay…`, `sketch: a net crossing its own wire is joined there, with a dot`, `sketch: lengths space the drawing and move nothing to another row or column`, `` sketch: `stack` lengthens the wire…``; `tests/report.zig`: `report: a deck plus its exported decisions…`, `report: the five-transistor OTA's report…`; `src/maze.zig`: `maze: …` (4); `src/canvas.zig`: `lengths: units scale…`; `src/config.zig`: `config: …` (3) |
| lines | `tests/lines.zig`: each verb drawn as it says and each refusal's verdict (`above`/`row`/`weak`, `face` mirrored, `order` splitting a column, the symmetry verbs, `role`/`driver`/`class`, `kind`/`expand`, the net lines, malformed and unbuilt lines); `tests/steering.zig`: each golden figure's lines draw it in full, every line honoured, none redundant; `tests/report.zig`: the fixed point at rungs 1 and 2; `zig build fuzz`: random lines on random netlists |
| the book | `tests/golden.zig`: `golden: every figure scores what is recorded`, `golden: the score sees a device the figure moves…`, `golden: the drawing does not depend on the order of the cards` |
| suite | `tests/cases.zig`: `textbook: the same deck draws the same picture`, `random netlists: they end…` |
| result | `tests/api.zig`: the tiers agree, `Placed` is well-formed and loses no device, every net is one piece, no wire on another net's point, leads, generated boxes, subcircuit blocks; `tests/abi_test.c`: the C ABI |
| Schemify import | `tests/schemify.zig`: every fixture converts, deterministically; every cell the engine is handed draws connected and short-free; a subckt's hints reach the engine; a hint naming a device the subckt lacks is a log line naming it |

Run with `zig build test` (with `-Dlatex_renderer=false` and `=true`);
`zig build fuzz` runs the random sample, `zig build bench` times the
fixture cells.
