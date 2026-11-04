# Changelog

One line per change, citing its issue or pull request. Numbers are measured.

## Unreleased

Added:

- The Schemify import reads the project's `place` and `lib` rows (Schemify format spec §4, OpenFAT/Schemify#66): a bench the host places apart from its subckt cells refers to them as `<lib>:<cell>` instead of `./<cell>`, and a cell no library reaches from its referrer is a log line naming it.

## 2.1.0 (2026-11-04)

Changed (Zig API; the C ABI is unchanged):

- `report.decisions` takes the skeleton, the drawing, its unit and a rung (1 to 4) (#15, #17).
- `hints.Hint.devices` is `args` (a line's arguments are not all devices), and `hints.Verb` holds every verb (#15).

Added:

- Steering rungs 1 and 2: every verb of docs/research/vocabulary.md on those rungs (`symmetric`, `axis`, `symmetry off`, `role`, `driver`, `class`, `kind`, `expand`; `above`, `row`, `order`, `face`, `upright`, `bridge`, `label`, `wire`, `port`, `rail`, `first`) and the `weak` prefix. Lines are admitted strongest first, a conflicting one dropped with its preferred conflict (#15).
- The report's `requests`: each line's verdict, every honoured one checked against the drawing; `cktimg-json --decisions 1|2` prints the engine's decisions as lines, and a deck plus them draws the same picture (#15).
- A ground bar (`*@ rail 0 bar`) (#15).
- Every golden figure drawn in full with 21 rung 1 and 2 lines (#15).
- Steering rungs 3 to 5: `cell` (in the skeleton's own frame, a displaced device moving aside, a mate to the mirror cell), `at` and `refdes`, `route` and `via` (committed whole, the router joining the rest of the net to them); `--decisions 3|4` with its fixed point (#17).
- The Schemify import carries every `*@` line of a subckt into its cell, hands the engine the designer's device names (so a cell no longer depends on the order of its instances), and logs each line the engine does not honour with the designer's line numbers (#16).

Fixed:

- The report's `wire` check mis-grouped a net's wire pieces and called a one-pin net unwired, so a wired net could read `no_room` (#17).
- An output port whose stub does not fit is named at the net's top-left pin, not its first in card order, so the cards' order no longer moves it (found by the line fuzz) (#15).

Measured:

- `cktimg.wasm` is 485,783 bytes (cap 550 KB).

## 2.0.0 (2026-11-04)

Breaking:

- The layout draws the structure first, then the wires. `layout_engine` is gone, and `layout` takes `(gpa, nl, roles, lib, config.Layout)` (#8, #9).
- `lint.zon`'s `.layout` keys are now `stack`, `series`, `rail`, `terminal`, `label`, `tap`, `clearance`, `bend_cost` and `cross_cost`. The old `min_pitch`, `junction` and `bend` are reported as unknown keys (#9).
- The xschem target and the `cktimg-xschem` binary are removed. The Schemify plugin replaces them (#6).
- The repository root is the Zig engine, and the Schemify plugin is Zig in `tools/schemify/` (#10).

Added:

- Grouping hints in the deck: `*@ group pair|mirror|bank|stack|cross <devices>`, `*@ nogroup`, `*@ grouping off`. The Schemify import carries them into its cells (#7, #9, #13).
- Left-right symmetry: every symmetric golden figure is drawn exactly symmetric (#9).
- Dots on every point where three or more of a net's wires meet, and where a net crosses itself (#9).
- `structure.analyze`, `skeleton.place`, `skeleton.validate` and `sketch.draw` are public, so a caller can edit the placement between stages (#12).
- `checks.find`: a drawing's guarantees (one piece per net, no shorts, dots right) as findings on any `Placed` (#13).
- `report.write` and `cktimg-json --report`: findings, crossings, bends, the engine's groups as `*@ group` lines, and the lattice rows (#13).
- `skills/cktimg/`, a skill for agents drawing with cktImg, and `docs/research/` on steering the layout (#9, #11).

Measured:

- The 107 plugin fixture cells lay out in 205 ms total (`zig build bench`, ReleaseFast); the wire-first layout took 2245 ms (#9).
- `cktimg.wasm` is 424,118 bytes (cap 550 KB).

Unchanged: the C ABI (`include/cktimg.h`).
