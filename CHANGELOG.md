# Changelog

One line per change, citing its issue or pull request. Numbers are measured.

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
