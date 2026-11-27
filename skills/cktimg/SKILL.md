---
name: cktimg
description: Draw a SPICE netlist as a schematic with cktImg (SVG, TikZ, JSON, Schemify cells), or steer a drawing you dislike with `*@` hint lines and `lint.zon`, up to hand-drawn quality.
---

cktImg lays a netlist out the way a textbook draws it and keeps the drawing
clean. You steer it on a **ladder** of rungs, from the names in the deck down
to lines that override what it recognizes. Work from the top and **descend**
one rung only for a **complaint** the rung above cannot fix.

For a TikZ figure, `cktimg-tex deck.cir figure.tex` uses the same selected
top cell and symbol library as `cktimg-json`. Pass the same `--symbols` and
`--config` options to compare the two drawings.

Use `--allow-45` with `cktimg-json` or `cktimg-tex` when the consuming editor or figure accepts oblique wires. In Schemify, pass `netlist.import --allow-45 n2s/deck.sp`. This enables a pair of 45-degree feedback segments in a verified reciprocal differential stage. A wire or label instruction on either output retains the caller's routing. The ordinary invocation uses Manhattan wires.

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
| 2 relations | where things stand to each other | `*@ above <devs>` (top down: the vertical order only, not one column; a flat part or `X` block stands in the column of the first upright device named, else the first block: `above r5 x1 r4` puts r5 over x1, r4 under it), `column <devs>` (one column, each directly over the next; parallel devices too), `row <devs>` (level, in no left-to-right order: add `order` for that; a bridge or block takes that device's row; the row is the lowest any of them needs, never raised, and a mate of one comes along), `order <devs>` (left to right; a bridge goes between its neighbours, bridges named in a row in that order); `stage <name> <devs>` (a unit: `row`, `order` and `repeat <stages>` take its name and move it whole, nothing else; `repeat` lays each stage as the first, member by member, level and left to right); `face <dev> g left\|right`, `face <dev> <pin> up`, `face <flat part> <pin> left\|right` (which end is left); `face <block> <port> left\|right\|up\|down` (turns or mirrors an `X` block so that port faces that side; `symmetric <block> <block>` draws the second as the first's mirror image); `upright\|bridge <dev>` (`bridge <mos>` lays a pass device flat between two columns: `face <mos> g up\|down` turns its gate, `face <mos> d left` its channel); `hang <part> <dev>.<pin>` (any device's pin: under a lower end, over an upper end, beside a gate, out past a flat part's end, out on a block port's side: `hang cg m3.g`, `hang ic m9.d`, `hang rb cg.a` (a chain: write the anchor's line first), `hang rf x1.outp`; beside a gate an upright part stands a row lower, its near end within two units of the gate; a second part on one pin stands a row under it); `label <net>`, `label <net> at <dev>.<pin> ...` (those pins named, the rest drawn as before: wired, unless it crosses too much), `wire <net> at <dev>.<pin> <dev>.<pin> ...` (those pins one wire with one name, the rest drawn apart and named once; one line a piece: a net split where you say), `wire <net> [ladder\|trunk\|route\|over\|under]` (on an input: one wire, one port; `ladder`: facing pins joined in pairs, the pairs by a rung; `trunk`: one straight wire along a row, every pin brought to it, a bank's gate bus; `route`: the router, pin to pin; `over`/`under`: round the top or bottom of the drawing), `port <net> left\|right\|top\|bottom` (the port at the net's end on that side or beyond it: no pin of the net past it; with no room there, the port stands where it would with no line, and the line is `no_room`), `rail <net> bar\|each\|plain` (`plain`: one bar, no symbol), `first <nets>`; `shelf <columns>\|off` (how many device columns a row holds before the drawing wraps into rows, 8; `off`: one row) | the parts are right, their arrangement is not; a drawing too wide or wrapped too soon |
| 3 cells | a device's lattice cell | `*@ cell <dev> <col> <row>` (the frame `--decisions 3` prints) | one device must stand on a given row and column |
| 4 geometry | exact place, turn, name side | `*@ at <dev> <x> <y> [R0..MR270]` (symbol units: `d.json`'s `pos` over 40 with the built-in symbols, over the file's `.unit` with `--symbols`), `refdes <dev> left\|right\|above\|below` | the lattice cannot say it |
| 5 wires | a net's exact path | `*@ route <net> x,y x,y ...` (symbol units, as `at`; one end on a pin of the net), `via <net> x,y ...` | the router's path for one net is wrong |
| style | lengths for every drawing of the project | a `lint.zon` with `.{ .layout = .{ .stack = 1.5, .terminal = 2 } }`, passed as `--config lint.zon` | crowded or sprawling |

Descend to rungs 3 to 5 for one device or net at a time: a cell or place
on a device overrides the relations on it.

## Reference

- **Reading a drawing.** `r.json` first:
  - `gates`: the checklist's first item.
  - `text_overlaps`: each name (`of` device, port, rail or label; `symbol`: two texts of one block, its title and a port name) drawn
    `over` a symbol, another name or another net's wire (a label: its own
    net's wire too), with the `other`
    thing's name and the text box's lower-left `at`. Not a gate yet; a
    finding is a cktImg bug, and a `refdes` or `port` line can steer it.
  - `requests`: each of your lines' state (Lines, below).
  - `grid`: each lattice row, top down, each device `name@column`.
  - `decisions`: cktImg's choices as `*@` lines (below).
  - `metrics`: crossings, bends, the nets drawn as names (`labelled`) and
    the nets drawn as a port at two pins or more (`ported`).

  Then `d.json`: each device's `pos` (y grows down; names starting `_` are
  the rail and port symbols cktImg drew), its `pins` and their nets. Then
  the image (`magick -density 110 d.svg d.png` when you read PNG).
- **Decisions.** `--decisions 4` (and the report's `decisions`) states the
  engine's choices as lines, cells and places as `weak` stays; a pasted line
  holds that choice, an edited one changes it. The deck plus every line and
  `*@ grouping off` draws the same picture on most circuits, not all: of
  200 corpus decks, a device moved in 6 at rung 1, 35 at rung 2, 14 at
  rung 3 and 8 at rung 4. A line naming a part of a recognised converter
  or stage turns that stage's own placement off, so rungs 2 and 3 redraw
  it otherwise (ag-1289: all 19 devices move); there paste rung 4, and
  read `requests` (a stay that moved is `dropped conflict`).
- **Relaying.** After editing a deck you already drew (or moving devices in
  its `d.json`), draw with `--from d.json`: devices stay where that drawing
  has them, and only what the deck's structure now puts elsewhere, or is
  new, is laid again. An unchanged deck gives the same bytes. `*@ weak at
  <dev> <x> <y> [turn]` lines are the same stays written by hand; they
  anchor the device's column and row; a strong `*@ at` fixes the device
  itself and anchors them too, so making a pasted stay strong moves
  nothing else. A device no `at` places that the lattice stands on a
  pinned place steps right off it, so pinning all devices but a new one
  keeps every `at`. A driver drawn apart takes no `at`: write
  `*@ driver <src> inline` before it.
- **Lines** (`*@ [weak] <verb> <args>`) sit at the deck's top level. A
  line beats the engine; a later line beats an earlier one, a strong one a
  `weak` one (a stay). Arguments split at blanks and commas. In a deck of
  only `.subckt`s, which draws its last `.subckt` (the top cell), a line
  before that `.subckt`, in its body or after its `.ends` is the top
  cell's; a line in another `.subckt`'s body is that block's (Blocks,
  below), and `requests` does not list it, so check those by eye. The
  Schemify import reads every `.subckt` as a cell of its own and a line as
  the cell's it is written in, so a deck both draw alike keeps the top
  cell's lines inside its body; it logs every line it does not honour.
  Each entry in `requests` has the line's 1-based `line` in the file, its
  `text`, a `state`, a `code`, `name` when one argument of several is at
  fault (`*@ column r5 x1 r4` rejected `not_placeable` names `x1`), and
  `blocked_by` (the stronger lines it cannot hold with, each with `alone`:
  `true` when the deck drawn again with that one line made a comment
  honours this line, which `cktimg-json` tries for up to 32 blocking lines
  per deck; `false` when it does not, past those 32, or for a line 0).
  Lines `cktimg-json` adds itself (a top cell's port roles and sources,
  `--from`'s stays) are not listed; a `blocked_by` line 0 is one of them.
  A `*@` line on the file's first line is the title, as SPICE reads it:
  it takes nothing and is listed `rejected title`. Act on the code:

  | code | state | what it means | your move |
  |---|---|---|---|
  | `ok` | honoured | drawn as written | none |
  | `unknown_verb`, `bad_args` | rejected | misspelt verb, too few or malformed arguments, a name twice | fix the spelling against the ladder |
  | `unknown_name` | rejected, or relaxed when only some names are known | a device, net or pin the deck lacks | use names exactly as the deck has them (read lowercased) |
  | `not_placeable` | rejected | a driver drawn apart (`name` is it; `--decisions` writes no place for one), a card with no pins, a bridge where only a column device stands (`bridge` takes two-pin parts and MOS, not a bipolar transistor); a `face <flat mos>` on any pin but its gate up or down or its drain or source left or right; an `X` block in `column`, `upright`, `face` or `hang` (a block is no column device: `row` and `above` place it by its anchor); a net line its net's role refuses (`route` or `via` on an input, `wire` on a rail, `label` on a rail, `port` on no input or output, `rail` on no rail) or on a net no drawn device touches | name another device or net (`role <net> internal` frees a net); `expand <instance>` to draw a block's devices, or place it with `row`, `above`, `order`, `cell` or `at`; `driver <src> inline` first |
  | `unjoined` | rejected | a group its devices are not joined as: a `mirror` or `bank` whose gates are on two nets, a `stack` member that shares no non-rail channel net with the next | name devices that are so joined, or use relations (`above`, `row`) |
  | `cycle` | dropped | closes an above/left cycle with `blocked_by` | delete or reverse one of the order lines |
  | `conflict` | dropped or relaxed | cannot hold with `blocked_by`; a `weak at` stay that stronger lines moved (no `blocked_by`: the drawing does not say which) | delete the blocker marked `alone: true`; none marked: more than one must go, or this line; a moved stay: take it out, or make it strong |
  | `taken` | dropped or relaxed | its devices already sit in a stronger line's group | `nogroup` them first, or edit that group |
  | `asymmetric` | dropped | no symmetry of the circuit swaps those two, even one that trades a MOS's drain and source | the circuit is not symmetric there: use relations |
  | `no_room` | relaxed | a `wire` had no room and was drawn as names; a `port` found no room at its side and stands where it would with no line; a `face` turned a port's pin where only a name fits; an `order` bridge found no free cell; a `refdes` side had no room | free room (`shelf`, lengths), turn the pin back, or accept the names |
  | `guarantee` | dropped | a strong `at`, a `route` or `via` would put a symbol on another, a wire on another net's point, or a route off its pins | move the coordinates; read pins from `d.json` |
  | `not_drawn` | relaxed | taken by the engine, missing from the drawing | a cktImg bug: report it with the deck |
  | `not_built` | rejected | a verb the engine does not take yet | use the rung below |
  | `title` | rejected | a `*@` line on the file's first line, which SPICE reads as the title | move it below the title line |

  Shelves preserve accepted `row`, `order`, `above` and `column` relations. An
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
- **MOS bodies.** The built-in symbols show a body contact when the fourth
  net differs from that device's source and has a non-rail role. Use
  `*@ class M1 nmos_body` or `pmos_body` to show any B, or the matching
  compact class `nmos` or `pmos` to suppress routing to it. The native
  report lists distinct non-rail bodies a selected class cannot show under
  `unshown_bodies`. A custom symbol file can supply either class on its
  own, or register a visible D/G/S/B variant after its compact class with
  `.body_for = "nmos"` or `"pmos"`. Its first three contacts must match.
- **Polyphase RC cells.** A closed four-phase network with two resistor
  banks and two certified cyclic capacitor banks can show oblique capacitor
  plates and leads. Native stock text/SVG and the editor use an actual
  two-contact `cap_oblique` symbol. With `*@ class C1 cap_oblique` a
  caller can also request this glyph on a single ordinary capacitor. Its
  leads are diagonal in its local frame. Inter-device wires use the
  selected router. An explicit geometry request keeps the other parts on
  ordinary placement.
- **Blocks.** An `X` instance of a `.subckt` is one block. In the body,
  `*@ left|right|top|bottom <ports>` puts ports on a side (in the line's
  order, top down or left to right): a recognised glyph (amplifier
  triangle, centre tap) turned or mirrored when one of its turns fits,
  else the generated box, and `*@ expand` draws the devices instead. With no such line:
  supplies on top, grounds and bias lines (`vb`, `vb1`, ...) below, an
  output (`out*`, `vout*`, `vo`, `vop`, `von`, `o`) right, the rest left.
  A circuit of only amplifier blocks and two-pin parts is drawn along its
  signal (inverting input on top, feedback over the block, input part level
  with its pin), not on the lattice. The amplifier is known by its port
  names: `inp`/`vip`/`in+`/`vp`, `inn`/`in-`/`vn`, a single `in`/`vin`/`a`,
  `out`/`vout`/`y`/`o`, the rest rails (`vdd*`, `vcc*`, `vss*`, `gnd*`,
  `vee*`); any other port name keeps the lattice. On the lattice a block
  takes `row`, `above` and `order` like a part: `*@ above rf x1 rg` draws
  the feedback part over the block and `rg` under it. One placing line
  (`upright`, `bridge`, `row`, `above`, `order`, `face`, `cell`, a strong
  `at`) turns that placement off for the whole deck, so fix such a drawing
  from `--decisions 4`: it gives every device as a strong `*@ at` line,
  paste all and edit the ones to move. `--from` places such a deck afresh.
- **Style** (`lint.zon`, passed as `--config`, or the `zon` text of the
  library call). `.layout` keys, lengths in units of the symbol set's
  two-pin length. They space the drawing and move nothing to another row
  or column:

  | key | default | what it sets | turn it when |
  |---|---|---|---|
  | `stack` | 0.5 | between neighbouring rows | stacked devices crowd: 1 |
  | `series` | 1.0 | between neighbouring columns | columns crowd or sprawl |
  | `rail` | 0.5 | a pin to its supply or ground symbol, the supply bar over its pins | 1 for a roomier drawing |
  | `terminal` | 0.5 | a pin to its input or output port | ports crowd: 1 |
  | `label` | 0.5 | a pin to its net label | labels crowd |
  | `tap` | 0.5 | pins facing one way to the trunk joining them | 1 for a roomier drawing |
  | `clearance` | 0.25 | the router's room between a wire and another net's | wires hug each other |
  | `bend_cost` | 1.0 | what the router pays for a corner, in wire | too many corners: raise it |
  | `cross_cost` | 2.0 | what the router pays to cross a wire, in wire | wires cross that could detour: raise it |
  | `compact` | true | close the drawing up to these lengths | `false` keeps every row and column a full pitch apart |
  | `cross_max` | 3 | the most wires one internal net may cross before it is joined by name (near pins stay wired) | too many crossings: 2; too many names: 6; one net: `*@ wire <net>` |
  | `rail_past` | true | a supply bar is a named rail past its outer pins, no symbol | `false`: the bar carries its symbol, ending on its outer pins |
  | `shelf` | 8 | device columns per row before the drawing wraps | wider page: raise; one row: 0; one deck: `*@ shelf` |

  `.render` (TikZ only): `wire` (hex colour, `"1565c0"`), `sym_w` (1.2 pt),
  `wire_w` (1.5 pt). `.rules`, each `.off`, `.warn` or `.err`:
  `floating_pin`, `single_pin_net`, `duplicate_refdes`, `unmapped_master`,
  `no_ground`, `symbol_geometry`, `label_fallback`. These rules report
  problems and never move anything.
- **Front ends.** `cktimg-json` and `cktimg-tex` read the same lines from
  the deck text, so a hinted deck draws the same in both (the Schemify
  import too, but for the subckt-only case under Lines). Iterate with
  `cktimg-json`: it is the only front end whose `--report` and
  `--decisions` show what became of your lines. `cktimg-tex [--standalone]
  [--config lint.zon] deck.sp out.tex` gives the TikZ figure. In C, the
  hinted deck is the `src` of `cktimg_parse_place(lib, src, zon, &report)`,
  where `report` holds only the settings' complaints. From Zig,
  `place(gpa, &cfg, &lib, &.{deck}, null)`, then `report.write` (with the
  parsed netlist and its roles) gives the `r.json` above. From Python,
  `cktimg.place(deck, symbols=, target=, start=, config=)` returns the
  placement and that report, and `cktimg.draw(...)` returns the SVG and the
  report. `deck` is text or a `sprack.Circuit` (docs/PYTHON.md).
- **Schemify:** `schemify cmd --trust <project> netlist.import n2s/deck.sp`
  imports a deck as editable cells, laid out the same way. `cktimg.import`
  is still accepted but no longer declared, so the palette never lists it.

For an editable scalar drawing with an optional grouped control-bus view, pass `--bundles` to `cktimg-json`. Its `port_bundles` lists each display contact and every original terminal slot, net and coordinate. The optional SVG uses that grouping. [Example and limits](../../docs/research/production-patterns/control-bus/README.md)
