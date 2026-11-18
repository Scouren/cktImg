---
name: cktimg
description: Draw a SPICE netlist as a schematic with cktImg (SVG, TikZ, JSON, Schemify cells), fix a cktImg drawing, or hint one to hand-drawn quality.
---

cktImg lays a netlist out the way a textbook draws it and keeps the drawing
clean. You steer it on a **ladder** of rungs, from the names in the deck down
to lines that override what it recognizes. Work from the top and **descend**
one rung only for a **complaint** the rung above cannot fix.

For a TikZ figure, `cktimg-tex deck.cir figure.tex` uses the same selected
top cell and symbol library as `cktimg-json`. Pass the same `--symbols` and
`--config` options to compare the two drawings.

## Steps

1. **Write the deck so its names carry its meaning** (Roles, below): matched
   devices numbered side by side (`M1`/`M2`), one `.subckt` per block. Done
   when `cktimg-json deck.sp d.json` exits 0.

2. **Draw:** `cktimg-json --svg d.svg --report r.json deck.sp d.json`. Done
   when you hold all three files.

3. **Review against [CHECKLIST.md](CHECKLIST.md)**, reading `r.json`, then
   `d.json`, then the image (Reading a drawing, below). Done when every
   checklist item is *ok* or carries a complaint naming its devices or nets
   ("`m3` and `m4` in different rows").

4. **Fix each complaint on the highest rung that fixes it** (the ladder):
   change the names, add the line (start from the matching one in
   `cktimg-json --decisions 4 deck.sp`), or set the length; redraw. Done
   when every complaint is gone or is open (no rung here fixes it), and
   every line you wrote is `honoured` in `r.json`'s `requests` (Lines,
   below).

5. **Stop** when the checklist passes, or after three rounds that fixed
   nothing. Hand over the drawing, `r.json`, the deck with its `*@` lines and
   any `lint.zon`, and each open complaint.

A drawing that must stand beside a hand drawing (no crossing or corner a
person would not draw) goes on from step 5 with
[HINTING.md](HINTING.md): the intent a netlist does not carry, as lines.

## The ladder

| rung | you change | how | for a complaint like |
|---|---|---|---|
| 0 names | net and device names | Roles, below | a net in the wrong role: a label where a port belongs, a bias line wired as a signal |
| 1 meaning | what the circuit is | `*@ group pair\|mirror\|bank\|stack\|cross <devs>`, `nogroup <devs>`, `grouping off`; `symmetric <a> <b>`, `axis <dev>`, `symmetry off`; `role <net> supply\|ground\|input\|output\|bias\|internal`; `driver <src> apart\|inline`; `class <dev> <symbol>`; `kind <dev> nmos\|pmos\|npn\|pnp\|res\|cap\|block`; `expand <instance>` | matched devices not side by side; the wrong mirror image; a net or device misread |
| 2 relations | where things stand to each other | `*@ above <devs>` (top down), `row <devs>` (level; a bridge takes the row), `order <devs>` (left to right; a bridge goes between its neighbours, bridges named in a row in that order); `face <dev> g left\|right`, `face <dev> <pin> up`, `face <flat part> <pin> left\|right` (which end is left); `upright\|bridge <dev>`; `label <net>`, `wire <net> [ladder\|trunk\|route]`, `port <net> left\|right\|top\|bottom`, `rail <net> bar\|each\|plain` (`plain`: one bar, no symbol), `first <nets>`; `shelf <columns>\|off` (how many device columns a row holds before the drawing wraps into rows, 8; `off`: one row) | the parts are right, their arrangement is not; a drawing too wide or wrapped too soon |
| 3 cells | a device's lattice cell | `*@ cell <dev> <col> <row>` (the frame `--decisions 3` prints) | one device must stand on a given row and column |
| 4 geometry | exact place, turn, name side | `*@ at <dev> <x> <y> [R0..MR270]` (symbol units), `refdes <dev> left\|right\|above\|below` | the lattice cannot say it |
| 5 wires | a net's exact path | `*@ route <net> x,y x,y ...` (one end on a pin of the net), `via <net> x,y ...` | the router's path for one net is wrong |
| style | lengths for every drawing of the project | a `lint.zon` with `.{ .layout = .{ .stack = 1.5, .terminal = 2 } }`, passed as `--config lint.zon` | crowded or sprawling |

Descend to rungs 3 to 5 for one device or net at a time: a cell or place
on a device overrides the relations on it.

## Reference

- **Reading a drawing.** `r.json` first:
  - `gates`: the checklist's first item.
  - `requests`: each of your lines' state (Lines, below).
  - `grid`: each lattice row, top down, each device `name@column`.
  - `decisions`: cktImg's choices as `*@` lines (below).
  - `metrics`: crossings, bends, and the nets drawn as names.

  Then `d.json`: each device's `pos` (y grows down; names starting `_` are
  the rail and port symbols cktImg drew), its `pins` and their nets. Then
  the image (`magick -density 110 d.svg d.png` when you read PNG).
- **Decisions.** `--decisions 4` (and the report's `decisions`) states the
  engine's choices as lines, cells and places as `weak` stays; a pasted line
  holds that choice, an edited one changes it. The deck plus every line and
  `*@ grouping off` draws the same picture.
- **Relaying.** After editing a deck you already drew (or moving devices in
  its `d.json`), draw with `--from d.json`: devices stay where that drawing
  has them, and only what the deck's structure now puts elsewhere, or is
  new, is laid again. An unchanged deck gives the same bytes. `*@ weak at
  <dev> <x> <y> [turn]` lines are the same stays written by hand; they
  anchor the device's column and row, where a strong `*@ at` fixes the
  device itself.
- **Lines** (`*@ [weak] <verb> <args>`) sit at the deck's top level. A
  line beats the engine; a later line beats an earlier one, a strong one a
  `weak` one (a stay). `requests` gives each line a state: `honoured`;
  `relaxed` (a `wire` or `port` with no room, drawn as names); `dropped`
  `guarantee` (an `at`, `route` or `via` that would break the drawing);
  `dropped`,
  `blocked_by` the lines it cannot hold with (`alone`: deleting that one
  admits it), so delete or change a blocker; `rejected` (malformed, or a
  name the deck lacks). `relaxed not_drawn` is a cktImg bug: report it.
  Inside a `.subckt`, lines are that cell's for the Schemify import, which
  logs every line it does not honour.
  Shelves preserve accepted `row`, `order` and `above` relations. An
  `above` chain may cross shelves when their top-to-bottom order agrees;
  a cut that would reverse it is forbidden. Rejected or dropped relation
  lines do not change shelf cuts.
- **Roles.** A net's name decides its role: supply `vdd*` or `v+`, ground
  `0`, `gnd`, `vss` or `v-`, inputs `in*`/`vin*` (and a `vref*` no drain makes), outputs `out*`/`vout*`,
  bias `vb*`/`bias*`.
  A V source from ground makes its net an input when it carries a signal
  (`ac`, `sin`, `pulse`, `pwl`, ...), else a bias; a V source from a supply,
  input or bias net to ground is a driver, drawn apart at the left. In a
  file of only `.subckt`s the top cell's V sources are devices of the
  circuit, wired where they stand (`*@ driver <src> apart` sets one apart).
  A circuit of R, C, L, D and sources with no ground gets a reference: the
  net most parts end on becomes its bottom wire, drawn with no ground
  symbol. `*@ role <net> ground` names another, with ground symbols. A
  `vee*` net is drawn with the supply glyph below its pin.
- **Blocks.** An `X` instance of a `.subckt` is one block. In the body,
  `*@ left|right|top|bottom <ports>` puts ports on a side of the generated
  box, and `*@ expand` draws the devices instead. With no such line:
  supplies on top, grounds and bias lines (`vb`, `vb1`, ...) below, an
  output (`out*`, `vout*`, `vo`, `vop`, `von`, `o`) right, the rest left.
  A circuit of only amplifier blocks and two-pin parts is drawn along its
  signal (inverting input on top, feedback over the block, input part level
  with its pin), not on the lattice. The amplifier is known by its port
  names: `inp`/`vip`/`in+`/`vp`, `inn`/`in-`/`vn`, a single `in`/`vin`/`a`,
  `out`/`vout`/`y`/`o`, the rest rails (`vdd*`, `vcc*`, `vss*`, `gnd*`,
  `vee*`); any other port name keeps the lattice. One placing line
  (`upright`, `bridge`, `row`, `above`, `order`, `face`, `cell`, a strong
  `at`) turns that placement off for the whole deck, so fix such a drawing
  from `--decisions 4`: it gives every device as a strong `*@ at` line,
  paste all and edit the ones to move. `--from` places such a deck afresh.
- **Lengths** (`.layout`, in units of the symbol set's two-pin length) space
  the drawing and keep every row and column; `src/config.zig` lists each
  with its default: a person's pitch, half a unit between stacked
  devices and from a pin to its trunk or a transistor's rail symbol (a
  two-pin part's rail symbol stands on its pin; `.stack = 1, .tap = 1,
  .rail = 1, .terminal = 1` for a roomier drawing). The drawing is closed up
  to those lengths
  (`.compact = true`, the default); `.compact = false` keeps the roomier
  lattice, every row and column a full pitch apart. `.cross_max` (3) is the
  most other wires one internal net's wire may cross before the net is
  joined by name (its near pins stay wired, one name a group): lower it (2) for a drawing with too many crossings, raise
  it (6) for one with too many names; `*@ wire <net>` keeps one net wired.
  `.rail_past` (true) draws a supply bar as a named rail, no symbol on it,
  running on past its outer pins, its name at the right end; `false` draws
  the bar with its supply symbol, ended on its outer pins.
  `.shelf` (8) is how many device columns a row holds before the drawing
  wraps into rows of columns: raise it for a wider page, `0` for one row;
  `*@ shelf <columns>|off` says so in one deck.
- **Schemify:** `schemify cmd --trust <project> netlist.import n2s/deck.sp`
  imports a deck as editable cells, laid out the same way. `cktimg.import`
  is still accepted but no longer declared, so the palette never lists it.
