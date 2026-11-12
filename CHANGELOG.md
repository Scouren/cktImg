# Changelog

One line per change, citing its issue or pull request. Numbers are measured.

## Unreleased

Added:

- The drawing is closed up (`.layout` key `compact`, on by default; `src/compact.zig`): its empty room taken out by constraint-graph compaction toward the mirror axis and the top, the wires then drawn again on the closed places. The five-transistor OTA's pair columns stand 140 apart instead of 320 and it is 360 tall instead of 440; no device changes row, column or order. `compact = false` keeps the lattice.
- A deck is relaid from its last drawing: `cktimg-json --from last.json` (and `*@ weak at` stays in a deck) anchor the lattice's columns and rows on that drawing's places, and only the radius of change is laid again (`src/relay.zig`): devices new to the deck, devices its structure now puts on another line, and lines pushed along for room. Half an OTA completed to the five-transistor OTA keeps M1 and M3 where they stood and moves only the tail, onto the new axis; an unchanged deck relays to the same bytes. A relaid drawing is wired once, not twice: on the fully differential two-stage golden the layout takes 10 ms instead of 14.5 (debug build, 40 runs, the 27 ms process start taken off).
- A net whose wire crosses too many others is drawn as names (`.layout` key `cross_max`, 6 by default; `src/thin.zig`): the internal net crossing the most wires of other nets, rails aside, is named and the drawing wired again, until none is over. Over the 5,263 Analog Canvas reference circuits: wire crossings 26,670 to 17,388 (the human drawings have 3,412), corners 61,890 to 58,097, wire length 389,281 to 360,910 units; nets named where the human wired them 1,115 to 1,553, nets wired where the human named them 3,934 to 3,466. At `cross_max = 2`: 8,963 crossings, 2,952 and 2,860 such nets.
- A net over the crossing budget is cut, not named at every pin (`src/thin.zig`, `src/wires.zig`): the pins standing near each other (within 3 units gate to gate, 5.5 gate to other, 7.5 otherwise) stay on one wire with one name, as in 75% of the nets people name; a cut net whose parts still cross more than two wires is named at every pin. Over the 5,263 reference circuits: names 16,150 to 15,543 (the human drawings have 11,371), crossings 16,693 to 16,555, corners 54,937 to 55,292.
- A drawing keeps one mirror axis: of the pairs and mirrors a circuit does not wire half to half, only the cluster holding a differential or cross-coupled pair is mirrored about it, and every other mirror's two transistors stand side by side on one side of it (`src/mates.zig`, `src/columns.zig`); they were nested about the one axis, either side of the whole core. A pair takes its loads as mates before a mirror does. Over the 5,263 Analog Canvas reference circuits the engine draws: wire crossings 34,334 to 25,439 (555 circuits with fewer, 68 with more; the human drawings have 3,412), wire length 407,375 to 377,623 units, circuits whose every mirror pair stands side by side 90.5% to 96.1% of 1,260.
- A circuit with no mirrored core has its columns ordered by the signal's way before span: stages left to right in the order the signal passes them, each load after its stage, inputs left and outputs right (`src/columns.zig`). Longer rows are improved by moving one column at a time, not only by swapping neighbours. Over the 5,263 Analog Canvas reference circuits the engine draws (scored against the human drawings): wire crossings 35,372 to 34,334; drawings standing left to right exactly as the human's 20.7% to 22.5%; ports all on the human's side 40.1% to 42.9%.
- The default lengths are a person's pitch (`.layout` keys `stack`, `tap`, `rail`, `terminal`: 0.5 unit each, 1 before; `src/config.zig`): two devices in series half a unit apart, a wire half a unit from a pin to its trunk, a rail symbol or port half a unit from its pin, as measured in 5,274 hand-drawn schematics. Over 5,263 reference circuits: height against the hand drawing 1.30 to 1.04 (mean ratio; median 1.25 to 1.00), area 1.64 to 1.22, wire length 352,101 to 270,793 units (the hand drawings: 179,956), crossings 17,399 to 16,693, corners 55,329 to 54,937. `.layout = .{ .stack = 1, .tap = 1, .rail = 1, .terminal = 1 }` draws as before.
- A lone drain comes straight down to the row of the gate it drives: a net's trunk takes the row of a pin facing sideways whenever every pin facing down stands over it and every pin facing up under it, not only between two of them (`src/trunk.zig`). Over 5,259 reference circuits: corners in wires 56,680 to 55,282, crossings 17,508 to 17,382.
- An input's pins standing near each other share one wire and one port, as people draw 87% of their inputs of two pins or more (`src/wires.zig`, `src/trunk.zig`): the box around the pins no more than 6 units around half, the port out from the wire's left end or its right, where no pin stands beyond; else a port at each pin, as before. Of 1,345 such inputs in 5,263 reference circuits 245 are wired to one port (30 before); crossings 17,264 to 17,355, corners 56,289 to 56,741.
- A tall block stands beside the stack it joins (`src/compact.zig`): closing up along y, two symbols a column apart keep only their order, and a supply pin's wire up to the bar from a lower row is a wire, not a stub. Over 5,259 reference circuits: height against the hand drawing 1.36 to 1.31 (mean ratio), wire length 360,357 to 352,063 units, crossings 17,343 to 17,508.
- A net's trunk runs along the row of a pin that faces sideways level with the junction of its column, joining that pin straight (`src/trunk.zig`, split from `wires.zig`): over 5,263 reference circuits, corners in wires 58,097 to 56,289 and crossings 17,388 to 17,264 (fewer in 110 circuits, more in 21).
- A mirror's facing gates are joined by one straight gate line with the diode tap at its middle, and `cktimg-json` draws a top cell's ports that no name gives a role as inputs and outputs.
- The Schemify import reads the manifest header's `place` attributes and its `lib` rows (Schemify format spec §4, OpenFAT/Schemify#66): a bench the host places apart from its subckt cells refers to them as `<lib>:<cell>` instead of `./<cell>`, and a cell no library reaches from its referrer is a log line naming it.
- The Schemify import calls a project library's cell for an `X` of a subckt the deck does not define: it reads `<lib dir>/<name>.shprim|.shcomp` for each `lib … path` row and places `<lib>:<name>`, pins in node order and matching `k=v` as overrides (a lone parameter name as `{k}`), instead of a generated verbatim leaf. A vendor-kit kit's `vnfet` from PDK-Manager now netlists in every dialect.
- The bench is named after the deck's `.title` when it has one (`tb_nmos_switch.shbench`, not `nmos_switch_2.shbench`).

Fixed:

- Transistors on a ground named `vss` or `gnd` drop to their type's lowest row as those on net 0 always did (`src/levels.zig`): a second stage's current source level with the tail source. Over the 5,263 Analog Canvas reference circuits: drawings whose every top-bottom order is the human's 23.7% to 26.6%, rows the human drew kept whole 32.2% to 35.7%; the longer gate lines cost wire crossings, 25,439 to 26,670.
- A subckt with parameters no longer always gets a `spice_code` instance re-declaring them as `.param k={k}` (ngspice braces, which HSPICE syntax reads as a name). The shim appears only when card text kept verbatim names a parameter, and it is written bare (`.param k=<value>`).
- An `X` override that is an expression over the caller's parameters (`w=w*2`, `l='l+w/2'`) imported as literal ngspice braces (`{{({w})}}*2`). A subckt parameter with a literal default is now a number parameter, unless some call passes it text Schemify cannot evaluate (`w=wn`, a bench `.param`). An expression over number parameters is one hole Schemify evaluates (`{w*2}` renders `w=1.6e-7` in every dialect).
- An import whose every file already existed as a shared leaf re-issued its probes instead of finishing.
- A bench named like a subckt of its netlist (`rcdiv.sp` holding `.subckt rcdiv`) is `tb_rcdiv.shbench`, not `rcdiv_2.shbench`.
- The import summary no longer counts a driver island's net (engine rule R3: the source drawn apart and joined by name) as a net left unwired: the rcdiv bench reads 1/1 nets fully wired, not 1/2.

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
