---
name: cktimg
description: Schematics from SPICE netlists with cktImg. Use when the user wants a circuit or netlist drawn as a schematic (SVG, TikZ, JSON, Schemify cells), or a cktImg drawing changed.
---

cktImg lays a netlist out the way a textbook draws it and keeps the drawing
clean: every net one piece, no wire on another net's pin. You steer it on a
**ladder** of rungs, from the names in the deck down to lines that override
what it recognizes. Work from the top and **descend** one rung only for a
**complaint** the rung above cannot fix.

## Steps

1. **Write the deck so its names carry its meaning.** Supply `vdd*`, ground
   `0`, `gnd` or `vss`, inputs `in*`/`vin*`, outputs `out*`/`vout*`, bias
   `vb*`/`bias*`; matched devices numbered side by side (`M1`/`M2`); one
   `.subckt` per block. Done when `cktimg-json deck.sp d.json` exits 0.

2. **Draw at rung 0**, no hints:
   `cktimg-json --svg d.svg --report r.json deck.sp d.json`. Done when you
   hold `d.svg`, `d.json` and `r.json`.

3. **Review against [CHECKLIST.md](CHECKLIST.md).** Read `r.json` first:
   `gates` must be empty (a finding is a cktImg bug: report it with the
   deck); `grid` lists each lattice row top down, each device `name@column`;
   `decisions` the groups cktImg chose, as `*@ group` lines; `metrics` the
   crossings, bends and nets drawn as names. Then `d.json`: each device's
   `pos` (y grows down; names starting `_` are the rail and port symbols
   cktImg drew), its `pins` and their nets. Then look at the image
   (`magick -density 110 d.svg d.png` when you read PNG).
   Done when every checklist item is *ok* or carries a complaint naming its
   devices or nets ("`m3` and `m4` in different rows").

4. **Fix each complaint on the highest rung that fixes it** (the ladder
   below): change the names, add the line, or set the length; redraw. Done
   when every complaint is gone or no rung here fixes it.

5. **Stop** when the checklist passes, or after three rounds that fixed
   nothing. Hand over the drawing, the deck with its `*@` lines and any
   `lint.zon`, and each complaint still open.

## The ladder

| rung | you change | how | for a complaint like |
|---|---|---|---|
| 0 names | net and device names | the names in step 1 | a net in the wrong role: a label where a port belongs, a bias line wired as a signal |
| 1 meaning | the groups cktImg recognizes | `*@ group pair\|mirror\|bank\|stack\|cross <devices>`, `*@ nogroup <devices>`, `*@ grouping off` | matched devices not side by side; a stack not one column; a device pulled into the wrong group |
| style | lengths for every drawing of the project | a `lint.zon` with `.{ .layout = .{ .stack = 1.5, .terminal = 2 } }`, passed as `--config lint.zon` | crowded or sprawling |

Rows, left-to-right order, cells, coordinates and routes cannot be pinned
yet: hand a complaint only they would fix to the user as open.

## Reference

- **Decisions.** Each `decisions` line, pasted into the deck, holds that
  group; edit one (its kind, its devices) to change it. The deck plus all of
  them and `*@ grouping off` draws the same picture, so start a rung-1 fix
  from them.

- **Hints** (`*@` lines) sit at the deck's top level. Inside a `.subckt`
  they are that subckt's: the Schemify import carries them into its cell
  and logs a name the cell does not have. A hinted group stands over
  recognition; `nogroup` keeps a device out of every group; `grouping off`
  keeps only hinted groups.
- **Blocks.** An `X` instance of a `.subckt` is one block. In the body,
  `*@ left|right|top|bottom <ports>` puts ports on a side of the generated
  box, and `*@ expand` draws the devices instead.
- **Roles.** A net's name decides its role. A V source from ground makes its
  net an input when it carries a signal (`ac`, `sin`, `pulse`, `pwl`, ...),
  else a bias; a V source from a supply, input or bias net to ground is a
  driver, drawn apart at the left.
- **Lengths** (`.layout`, in units of the symbol set's two-pin length):
  `stack`, `series`, `rail`, `terminal`, `label`, `tap`, `clearance`,
  `bend_cost`, `cross_cost`. They move nothing to another row or column.
  `src/config.zig` has each with its default.
- **Schemify:** `schemify cmd --trust <project> cktimg.import n2s/deck.sp`
  imports a deck as editable cells, laid out the same way.
