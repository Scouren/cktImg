# Full freedom inside Schemify

Companion to [steering.md](steering.md): how agents and people steer cktImg
on cells already imported into Schemify, edit them in the editor, and keep
them clean. Read from Schemify's specs and source (`S/` =
`~/Documents/Projects/EDA-Tools/Schematic/Schemify`, `docs/spec/<name>.md`
cited as "plugin-abi §4") and the plugin (`tools/schemify/`), not run.

## What a plugin can do today

- **Read a cell.** The snapshot tables need no grant and cover the active
  document (plugin-abi §4): `Instances` (id, x, y, orient, cell, name),
  `Wires` (x1, y1, x2, y2, net), `Labels`, `Nets`, `Selection`.
  - Coordinates are milli-units (`S/crates/model/doc/src/schematic.rs:27-30`).
  - `orient` is quarter turns plus 4 for a mirror, the same index as the
    plugin's `orient_words` (`S/crates/protocol/format/src/scalar.rs:25-40`;
    `tools/schemify/layout.zig:53-54`).
  - Ports, noconns and constraints are not in the snapshot; `fs_read` of the
    cell file has them (needs `read_project`).
  - The active document's path is not exposed (`Docs.path` is empty,
    `S/crates/model/editor/src/plugins/snapshot.rs:181-182`), so a command
    is told which cell it works on.
- **Map a cell back to the engine.** An instance's `name` is the deck's
  (`tools/schemify/recognize.zig:347-354`), and the engine's grid is xschem
  units with every instance at the engine's position
  (`tools/schemify/layout.zig:6-8, 450-453`): the cell's placement reads
  back exactly, orientation through the family's turn.
- **Write a cell back.** In the editor, `edit <doc> stage <label>` lands as
  one transaction in the visual diff, `commit` as one undo step (edits §1,
  §2); headless, `fs_write` (`write_project`). Writing an open cell with
  `fs_write` leaves the editor stale (no file watcher calls
  `external_change`, `S/crates/model/editor/src/editor/files.rs:155-180`),
  so inside the editor only `edit` writes.
- **Notice edits.** `doc_changed`, `saved` and `selection_changed` say that
  something changed, not what (plugin-abi §6; the op list goes only to
  Schemify's own table owners, edits §1). A plugin diffs instead, against
  the positions it last laid out.

## Where steering lives

| what | where | written by |
|---|---|---|
| intent: rungs 1 and 2, and any lower line an agent writes | the deck's `*@` lines | the agent or designer; never rewritten by the plugin |
| edits: what was moved, rotated or rerouted in the editor | a sidecar `<deck>.layout` of `*@` lines, scoped per cell by `.subckt <cell>` … `.ends` | `cktimg.keep` |
| the drawing | the cell file | the import |

The sidecar is the engine's own language, the way tscircuit keeps drags in
`manual-edits.json` ([docs](https://docs.tscircuit.com/guides/tscircuit-essentials/manual-edits)).
The engine reads it as a later source, appended (`src/root.zig`, `place`'s
`sources`), so an edit wins over an older deck line of the same strength.
The cell file holds no hints: a `constraint` naming an instance blocks its
delete (E042, `S/crates/model/doc/src/edit.rs:233-243`), an unknown
instance attribute reads as a parameter (W007, netlist §6), and every layout
rewrites the cell anyway.

An edit becomes the highest rung that reproduces it:

| the cell shows | line in the sidecar |
|---|---|
| a device mirrored, nothing else | `*@ face M3 g left` |
| a device on another lattice cell | `*@ cell M5 2 4` |
| any other move or rotation | `*@ at M5 2.1667 5.667 R90` |
| a net's wires redrawn | `*@ route n3 ...`, from `Wires` by net |
| wires replaced by names, or back | `*@ label n3`, `*@ wire n3` |
| untouched | the same, `weak` (a stay) |

The editor snaps to 10 xschem units and a symbol unit is 60 in the plugin
(`tools/schemify/layout.zig:51`), so a moved device often lands off the
engine's lattice: `at` must take any position, not only lattice points
(steering.md §2, off-lattice placement).

## Commands

- `cktimg.import <deck> [update]`: as today; with `update`, re-lays out the
  cells whose `provenance` names this deck (`tools/schemify/emit.zig:212-213`),
  from the deck, the sidecar, and the cell's positions as stays. Other
  clashes stay refused (`tools/schemify/plugin.zig:246-255`).
- `cktimg.keep`: diffs the active cell against the sidecar, writes moved
  devices as strong lines on the highest rung that fits and refreshes the
  rest as stays. On every save with
  `schemify.on("saved", function(ev) schemify.cmd("cktimg.keep") end)` in
  `init.lua` (config §3).
- `cktimg.reroute [write]`: keeps every device where it is (a strong `at`
  each, so the placement stages search nothing, steering.md §4) and redraws
  wires, labels, ports and no-connects in one transaction; refuses when the
  cell's devices are not the deck's.

Every run writes the report to `.schemify/cktimg/<stem>.report.json` and its
text form to the log.

## Limits

- **Fuel.** Each cell is one event; the default 10^8 fuel is about 1 ms of
  native layout (`S/docs/dev/backlog.md:71`). More fuel moves the plugin to
  a worker thread, not on the web (backlog.md:66).
- **Headless runs do not save.** `schemify cmd` runs one command and exits
  (`S/crates/view/app/src/headless.rs:61-130`): headless writes use
  `fs_write`.
- **Ids.** Records written with `-` take random ids; the plugin supplies its
  own (as the importer does, `tools/schemify/emit.zig:80-98`) and avoids ids
  the snapshot does not show.
- **Agents over MCP.** `schemify rpc` and `schemify mcp` expose `check`,
  `diff`, `edit`, `fmt`, `netlist` and `run` (rpc §3.1, §7), not `cmd`: an
  MCP-only agent can edit cells but cannot import or render.

## Proving it keeps the circuit

Connectivity is the round trip's (`tests/roundtrip.py`): `spicecmp`
compares by colour refinement, so an exact check by instance name sits
beside it.

1. Import a fixture, move and rotate random instances through
   `schemify rpc edit`, reroute, netlist: `spicecmp` says the same circuit.
2. `schemify diff` before and after the reroute shows no instance moved.
3. A router that drops one segment turns test 1 red.
4. Import, `keep`, re-lay out with the deck unchanged: no difference, and a
   second run gives the same bytes.
5. Delete an instance and reroute: refused, the file untouched.

## What Schemify would add

Nothing blocks. Useful: the active document's path in `Docs.path`; `cmd`
among the RPC and MCP methods (an agent's whole loop over MCP); drawing
plugin annotations on the canvas, so findings show where they are. The rest
is cktImg's: rungs 3 to 5, `weak`, the report (steering.md §8), and the
designer's device names in the engine deck (§10).
