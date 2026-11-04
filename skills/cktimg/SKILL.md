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
   change the names, add the line, or set the length; redraw. Done when
   every complaint is gone or is open (no rung here fixes it).

5. **Stop** when the checklist passes, or after three rounds that fixed
   nothing. Hand over the drawing, `r.json`, the deck with its `*@` lines and
   any `lint.zon`, and each open complaint.

## The ladder

| rung | you change | how | for a complaint like |
|---|---|---|---|
| 0 names | net and device names | Roles, below | a net in the wrong role: a label where a port belongs, a bias line wired as a signal |
| 1 meaning | the groups cktImg recognizes | `*@ group pair\|mirror\|bank\|stack\|cross <devices>`, `*@ nogroup <devices>`, `*@ grouping off` | matched devices not side by side; a stack not one column; a device pulled into the wrong group |
| style | lengths for every drawing of the project | a `lint.zon` with `.{ .layout = .{ .stack = 1.5, .terminal = 2 } }`, passed as `--config lint.zon` | crowded or sprawling |

A complaint about rows, left-to-right order, cells, coordinates or routes is
open: those rungs are still to come.

## Reference

- **Reading a drawing.** `r.json` first:
  - `gates`: the checklist's first item.
  - `grid`: each lattice row, top down, each device `name@column`.
  - `decisions`: the groups cktImg chose, as `*@ group` lines (below).
  - `metrics`: crossings, bends, and the nets drawn as names.

  Then `d.json`: each device's `pos` (y grows down; names starting `_` are
  the rail and port symbols cktImg drew), its `pins` and their nets. Then
  the image (`magick -density 110 d.svg d.png` when you read PNG).
- **Decisions.** A `decisions` line pasted into the deck holds that group;
  edit its kind or devices to change it. The deck plus every line and
  `*@ grouping off` draws the same picture, so a rung-1 fix starts from them.
- **Hints** (`*@` lines) sit at the deck's top level; inside a `.subckt`
  they are that subckt's, and the Schemify import carries them into its
  cell. A hinted group stands over recognition; `nogroup` keeps a device out
  of every group; `grouping off` keeps the hinted groups alone.
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
