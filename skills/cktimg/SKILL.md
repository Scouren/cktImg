---
name: cktimg
description: Draw a SPICE netlist as a schematic with cktImg (SVG, TikZ, JSON, Schemify cells), or fix a cktImg drawing.
---

cktImg lays a netlist out the way a textbook draws it and keeps the drawing
clean. You steer it on a **ladder** of rungs, from the names in the deck down
to lines that override what it recognizes. Work from the top and **descend**
one rung only for a **complaint** the rung above cannot fix.

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
   `cktimg-json --decisions 2 deck.sp`), or set the length; redraw. Done
   when every complaint is gone or is open (no rung here fixes it), and
   every line you wrote is `honoured` in `r.json`'s `requests` (Lines,
   below).

5. **Stop** when the checklist passes, or after three rounds that fixed
   nothing. Hand over the drawing, `r.json`, the deck with its `*@` lines and
   any `lint.zon`, and each open complaint.

## The ladder

| rung | you change | how | for a complaint like |
|---|---|---|---|
| 0 names | net and device names | Roles, below | a net in the wrong role: a label where a port belongs, a bias line wired as a signal |
| 1 meaning | what the circuit is | `*@ group pair\|mirror\|bank\|stack\|cross <devs>`, `nogroup <devs>`, `grouping off`; `symmetric <a> <b>`, `axis <dev>`, `symmetry off`; `role <net> supply\|ground\|input\|output\|bias\|internal`; `driver <src> apart\|inline`; `class <dev> <symbol>`; `kind <dev> nmos\|pmos\|npn\|pnp\|res\|cap\|block`; `expand <instance>` | matched devices not side by side; the wrong mirror image; a net or device misread |
| 2 relations | where things stand to each other | `*@ above <devs>` (top down), `row <devs>` (level; a bridge takes the row), `order <devs>` (left to right; a bridge goes between); `face <dev> g left\|right`, `face <dev> <pin> up`; `upright\|bridge <dev>`; `label <net>`, `wire <net> [ladder\|trunk\|route]`, `port <net> left\|right\|top\|bottom`, `rail <net> bar\|each`, `first <nets>` | the parts are right, their arrangement is not |
| style | lengths for every drawing of the project | a `lint.zon` with `.{ .layout = .{ .stack = 1.5, .terminal = 2 } }`, passed as `--config lint.zon` | crowded or sprawling |

A complaint about cells, coordinates or routes is open: those rungs are
still to come.

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
- **Decisions.** `--decisions 2` (and the report's `decisions`) states the
  engine's choices as lines; a pasted line holds that choice, an edited one
  changes it. The deck plus every line and `*@ grouping off` draws the same
  picture.
- **Lines** (`*@ [weak] <verb> <args>`) sit at the deck's top level. A
  line beats the engine; a later line beats an earlier one, a strong one a
  `weak` one (a stay). `requests` gives each line a state: `honoured`;
  `relaxed` (a `wire` or `port` with no room, drawn as names); `dropped`,
  `blocked_by` the lines it cannot hold with (`alone`: deleting that one
  admits it), so delete or change a blocker; `rejected` (malformed, or a
  name the deck lacks). `relaxed not_drawn` is a cktImg bug: report it. The
  Schemify import carries only `group` lines into its cells.
- **Roles.** A net's name decides its role: supply `vdd*`, ground `0`, `gnd`
  or `vss`, inputs `in*`/`vin*`, outputs `out*`/`vout*`, bias `vb*`/`bias*`.
  A V source from ground makes its net an input when it carries a signal
  (`ac`, `sin`, `pulse`, `pwl`, ...), else a bias; a V source from a supply,
  input or bias net to ground is a driver, drawn apart at the left.
- **Blocks.** An `X` instance of a `.subckt` is one block. In the body,
  `*@ left|right|top|bottom <ports>` puts ports on a side of the generated
  box, and `*@ expand` draws the devices instead.
- **Lengths** (`.layout`, in units of the symbol set's two-pin length) space
  the drawing and keep every row and column; `src/config.zig` lists each
  with its default.
- **Schemify:** `schemify cmd --trust <project> cktimg.import n2s/deck.sp`
  imports a deck as editable cells, laid out the same way.
