# Current worktree versus the frozen gallery rulebook

Read this together with ../current-human-rules.md. The frozen gallery is the same experimental bf7b0749 binary as round 1; some experimental files are absent from the current worktree. Code differences without header differences remain in the manifest.

## src/block_input_place.zig

### Frozen experimental header

(Absent)

### Current worktree header

Actual paired block input frame -> one five-passive proposal and orders.

Human Rules:
- block_input_place.1 (bounded observation) Source X2/X3 capacitors
  align with their own INP/INN tips; transverse bias resistors share
  two rows beyond that input span. R(INP) lies farther outward than
  R(INN), both between input and cap planes. The actual block never
  turns; its named input frame defines both axes. Its unique bias choke
  sits outward of R(INP), beyond the R-bias row, parallel to the input
  leads; the far tip points outward. docs/research/block-input-chokes.md.
  `propose`
- block_input_place.2 (choice) One nearest full-body-spaced candidate,
  using the observed semantic INN side. All five actual passive frames
  must support it; no larger search or routing exception. Caller owns
  all geometry changes and restores rows on rejection. `propose`
- block_input_place.3 (invariant) Reanchored passive tracks preserve
  actual input rows and paired bias rows through compaction. Ten
  strict coordinate pairs per group retain the source order. `orders`

Data: borrowed cold groups and actual classes in; fixed five-point
proposal or immediate order slices out. No allocation or retained state.
Coordinates use i64 intermediates and checked i32 narrowing. This is
cold scalar geometry, with no speed or hot-loop abstraction claim.

Contents: rooms, propose, orders; private actual-frame helpers.

## src/block_input_rc.zig

### Frozen experimental header

(Absent)

### Current worktree header

Closed paired RC inputs -> cold five-passive placement candidates.

Human Rules:
- block_input_rc.1 (bounded observation) AG1103 X2/X3 have one C and R
  per named INP/INN, one common bias choke, and a unique upstream
  OUTP/OUTN block. Its choke far net is outside the five signal/bias
  nets. Count every raw pin before role/frame filtering.
  X1 lacks that upstream block and its caps do not share input rows.
  Actual source: docs/research/block-input-rc.md. `find`
- block_input_rc.2 (invariant) Caller geometry, sides, shelves, mates,
  grouping and local style/port/route requests defeat the whole inferred
  group. Invalid/dropped hints do not. Only five passives may move; the
  actual block and its declared input frame stay read-only. `collect`

Data: borrowed graph/admission tables in; at most subckt-count cold
28-byte records out. Six typed u32 handles and two u8 class pin indexes
are consumed together. Input nets/endpoint identity remain in CSR.
Twenty i32 order pairs and one Room per group are caller-owned until
the draw completes. All allocations precede geometry writes; no hot
table, retained state, ABI, parallel-commit or speed claim.

Contents: Group, order_pair_capacity, Batch, Batch.deinit, collect, members, nearPin;
private raw-incidence selector and tests.

## src/block_rooms.zig

### Frozen experimental header

(Absent)

### Current worktree header

Output-tank and input-RC requests -> one fresh-lattice transaction.

Human Rules:
- block_rooms.1 (invariant) Empty or declined RC work preserves the old
  output-tank transaction exactly, including its successful owners and
  generic fallback pairs. No rejected RC envelope expands the scene.
- block_rooms.2 (choice) Reserve all actual composite envelopes together.
  Check every future passive body against every future body, including
  other candidates. One failure restores every temporary row before the
  old output-only path runs; no farther search or routing exception.

Data: borrowed cold owner batches and graph/lattice tables in; coordinates
and full passive rows commit together. Scratch has one group copy per
candidate, one Room per group, and two/five u32 handles plus full rows per
output/input group. Handles and rows are separate arrays, accessed together
only during rollback. Coordinate scratch spans the existing device table.
All allocation precedes temporary row writes. Scratch dies before routing;
scene checks and commit are serial, with no hot-loop or speed claim.

Contents: lattice; private prior path, ownership and scene checks.

## src/block_tanks.zig

### Frozen experimental header

Actual paired block outputs -> one unique center-tapped tank frame.

Human Rules:
- block_tanks.1 (habit, bounded) One actual AG1103 rectangle has unique
  OUTP/OUTN bindings across a unique CT/cap pair, with capacitor-only
  outer fanout. Its actual output/cap/coil midpoints align; the capacitor
  lies between the outputs and coil, named ends match, tap faces away.
  Count all competitors before visibility/role/frame filtering. This
  single source case is not a universal block-load rule. `find`
- block_tanks.2 (choice) Keep the block fixed. Reanchor both passive
  midpoints to its actual output midpoint and try a body-spaced position,
  then quarter-unit steps through one extra unit. Caller geometry,
  sides, mates, groups, shelves and styles/ports/routes win. Failure restores
  both complete device rows and all coordinates. A first-net request
  still owns routing order; it does not prohibit placement. `collect`, `place`
- block_tanks.3 (invariant) Only a successful specific owner removes
  its pair from generic coil_tanks. Equal transverse grid tracks retain
  midpoint equality, including shifted class frames; strict actual
  output/cap/coil/tap orders enter the existing compactor. `orders`

Data: CSR, declared binds, actual classes and admitted requests in;
cold 20-byte group records and two passive poses out. Each record is
read together once per draw; u32 typed handles and u8 block pins match
existing table bounds. At most one group per subckt; six i32 order pairs
per group. Caller owns both buffers, allocated before mutation. Two old
rows/coordinates live on the stack. No retained state or speed claim.

Contents: Group, Batch, Batch.deinit, collect, lattice, rooms, fits, commit,
place, orders; private proofs/tests.

### Current worktree header

Actual paired block outputs -> one unique center-tapped tank frame.

Human Rules:
- block_tanks.1 (habit, bounded) One actual AG1103 rectangle has unique
  OUTP/OUTN bindings across a unique CT/cap pair, with capacitor-only
  outer fanout. Its actual output/cap/coil midpoints align; the capacitor
  lies between the outputs and coil, named ends match, tap faces away.
  Count all competitors before visibility/role/frame filtering. This
  single source case is not a universal block-load rule. `find`
- block_tanks.2 (choice) Preserve the block frame and cell. Reanchor both passive
  midpoints to its actual output midpoint and try a body-spaced position,
  then quarter-unit steps through one extra unit. Caller geometry,
  sides, mates, groups, shelves and styles/ports/routes win. Failure restores
  both complete device rows and all coordinates. A first-net request
  still owns routing order; it does not prohibit placement. `collect`, `place`
- block_tanks.3 (invariant) Only a successful specific owner removes
  its pair from generic coil_tanks. Equal transverse grid tracks retain
  midpoint equality, including shifted class frames; strict actual
  output/cap/coil/tap orders enter the existing compactor. `orders`
- block_tanks.4 (choice) A fresh lattice reserves the actual nearest
  composite envelope at the anchor cell before ordinary column spacing.
  Whole-scene preflight uses all future passive boxes. A rejection
  restores ordinary coordinates; fixed/relay/direct placement bypasses
  reservation. No extra slots or farther search are introduced. `lattice`

Data: CSR, declared binds, actual classes and admitted requests in;
cold 20-byte group records and two passive poses out. Each record is
read together once per draw; u32 typed handles and u8 block pins match
existing table bounds. At most one group per subckt; six i32 order pairs
per group, plus one 20-byte numeric room request. Caller owns all three
buffers, allocated before mutation. Two old rows/coordinates live on
the stack. No retained state or speed claim.

Contents: Group, Batch, Batch.deinit, collect, lattice, rooms, propose, fits, commit,
place, orders; private proofs/tests.

## src/common_source_bars.zig

### Frozen experimental header

A reciprocal MOS pair's common sources may meet its tail directly.

Human Rules:
- common_source_bars.1 (bounded observation) An exact S/S/D junction,
  reciprocal D/G pair, same known MOS polarity and shared body/rail
  return occurs 31 times in the 2,936-deck source census. All 31 connect;
  only four actual horizontal rows have a middle tail D and opposite
  vertical lead directions. All four, in one figure, are straight bars.
  This is a bounded frame case, not a universal source/drain rule.
  Evidence: docs/research/common-source-bars.md and
  figures/common_source_bars_cases.json, with 20 topology controls.
- common_source_bars.2 (choice) On an automatic internal net, draw that
  exact three-point bar only when it meets no foreign ink and ordinary
  Canvas body/contact checks pass. No placement or generic trunk corner
  rule changes. Its mirror mate must qualify independently. `draw`
- common_source_bars.3 (boundary) Full raw incidence precedes visibility;
  explicit styles, ports, first order, original routes/ats, unsupported
  actual frames and any existing own-net ink decline. Later cut/label
  rounds and ordinary fallback retain their existing behavior. `draw`

Data: borrowed graph/current Canvas/request tables; three typed EdgeIds
in a 12-byte cold stack certificate, used together once per eligible net.
Fixed D/S indices and three actual points need no retained field/table.
No allocation outside Canvas.commit, no node/label mutation. Raw scans
are bounded by three incidences and four pins/card; all wide-coordinate
checks precede narrowing. This is a cold owner, not a speed/residue claim.
The caller owns flow and allocator; commit grows before appending ink.

Contents: draw; private topology, actual frame and bounded coordinate checks.

### Current worktree header

(Absent)

## src/ct_four_wires.zig

### Frozen experimental header

Successful complete four-side CT owner -> its observed physical parts.

Human Rules:
- ct_four_wires.1 (bounded observation) One complete 26-device source
  scene has four local five-pin outputs with an isolated outer gate,
  two lower CT/L parts separated from their remote three-pin branches,
  and one shared opposed-tap supply. The unchanged 148-pair certificate
  includes every separation: docs/research/ct-four-sides.md. No figure,
  device name, distance threshold or generic net rule selects these parts.
- ct_four_wires.2 (boundary) Borrow only successful placement Groups.
  Recheck every actual visible lead and complete net membership. Original
  routes/ats, first-net requests, explicit styles/ports and admitted rail
  representation win, including a normalized default-equivalent rail.
- ct_four_wires.3 (choice) Use ordinary trunk competition for each part,
  in the measured larger-part-first order. Commit a complete two-part
  net or restore all appended ink and symbol rows. Inclusive same-net
  contact joins parts, including proper X crossings; reject it explicitly.
  Every part must retain its own correctly bound name/port. `parts`
- ct_four_wires.4 (boundary) Current auto/cut rounds can retain these
  parts; label rounds use ordinary labels. No crossing-budget exemption,
  route fallback or Canvas behavior changes. Previously successful nets
  remain when a later independent net declines or returns an error.
- ct_four_wires.5 (bounded observation) This scene's four passive-circle
  markers stand outside their own five-pin branches: left of the left
  shunt drain and right of the right drain. The actual opposed CT axis
  selects the side, never a name. A directed trunk endpoint must emit a
  real outward terminal; fallback labels decline atomically. Circle ink
  is a passive marker, not evidence of electrical output direction.

Data: borrowed 104-byte Group and existing per-net/request tables; at most
six original pin handles and points per request. Static member/role pairs
use u5/u2. Cold stack checkpoint lengths use usize and live for one net;
Canvas owns all output allocation. No retained flags, graph or allocator
replacement. Six bounded requests run outside trunk candidate loops. No
hot-path, residue or speed claim. Six data answers are in the source study.

Contents: qualify, rail, parts; private mapping, frame and transaction.

### Current worktree header

Successful complete four-side CT owner -> its observed physical parts.

Human Rules:
- ct_four_wires.1 (bounded observation) One complete 26-device source
  scene has four local five-pin outputs with an isolated outer gate,
  two lower CT/L parts separated from their remote three-pin branches,
  and one shared opposed-tap supply. The unchanged 148-pair certificate
  includes every separation: docs/research/ct-four-sides.md. No figure,
  device name, distance threshold or generic net rule selects these parts.
- ct_four_wires.2 (boundary) Borrow only successful placement Groups.
  Recheck every actual visible lead and complete net membership. Original
  routes/ats, first-net requests, explicit styles/ports and admitted rail
  representation win, including a normalized default-equivalent rail.
- ct_four_wires.3 (choice) Use ordinary trunk competition for each part,
  in the measured larger-part-first order. Commit a complete two-part
  net or restore all appended ink and symbol rows. Inclusive same-net
  contact joins parts, including proper X crossings; reject it explicitly.
  Every part must retain its own correctly bound name/port. `parts`
- ct_four_wires.4 (boundary) Current auto/cut rounds can retain these
  parts; label rounds use ordinary labels. No crossing-budget exemption,
  route fallback or Canvas behavior changes. Previously successful nets
  remain when a later independent net declines or returns an error.

Data: borrowed 104-byte Group and existing per-net/request tables; at most
six original pin handles and points per request. Static member/role pairs
use u5/u2. Cold stack checkpoint lengths use usize and live for one net;
Canvas owns all output allocation. No retained flags, graph or allocator
replacement. Six bounded requests run outside trunk candidate loops. No
hot-path, residue or speed claim. Six data answers are in the source study.

Contents: qualify, rail, parts; private mapping, frame and transaction.

## src/ct_series_tanks.zig

### Frozen experimental header

(Absent)

### Current worktree header

Unique CT / L-C-L paths -> three-passive relative placement requests.

Human Rules:
- ct_series_tanks.1 (bounded observation) Two correlated AG1153 groups
  have perpendicular outer series inductors and a centered parallel C
  beyond them, opposite the actual tap. Count raw competitors and shared
  owners before eligibility. No source ID, value or world direction is
  selected. Source: docs/research/ct-series-tanks.md. `raw`, `find`
- ct_series_tanks.2 (choice) Keep the centered actual coil fixed. One
  complete-body-spaced proposal moves only L/L/C; all failed poses,
  signed reaches or collisions restore three full rows and coordinates.
  Caller requests/mates/groups win. No search or wire bypass. `place`
- ct_series_tanks.3 (bounded habit) Protect the complete four-member
  column span from a shelf cut, without reserving empty rows. Explicit
  wrap precedence wins. Semantic spans remain even when later actual
  frames abstain; only the three-row geometry transaction rolls back. `spans`
- ct_series_tanks.4 (invariant) Real midpoint/near-tip tracks retain
  equalities. Initially true actual-tip orders enter the existing single
  compaction pass; physical conductor paths remain independent. `orders`

Data: borrowed CSR/roles/classes/admitted requests in; cold four-EdgeId
records (16 bytes) and three passive rows out. At most complete-CT count
records, all handles consumed together once per phase. Twelve i32 order
pairs per success cover either world axis. Caller owns both buffers for
one draw; allocation precedes mutation. Canonical order serializes body
collisions. Three old rows and candidate points are fixed stack scratch.
Recognition is outside cut-cost/routing loops; no speed claim is made.

Contents: Group, Batch, Batch.deinit, spans, collect, place, orders; private.

## src/lattice_geometry.zig

### Frozen experimental header

Lattice rows/columns and actual symbol reaches → physical coordinates.

Human Rules:
- lattice_geometry.1 (invariant) Each used row/column clears its actual
  body, pin reaches and existing rail/port stubs. Reflection mates use
  equal column widths. This is the original sketch coordinate pass,
  extracted unchanged so local owners do not exceed the file budget.

Data: borrowed schematic/skeleton tables in; caller-owned x/y arrays
out. Temporary room is one pair per row/column, released before return.
Every fallible allocation precedes exposing the completed arrays.

Contents:
- `pub const Geo`, `Room`
- `pub fn coordinates(gpa: Allocator, s: *const Schematic, nl: *const Netlist, sk: *const Skeleton, len: Lengths, extra: []const Room) !Geo`

### Current worktree header

Lattice rows/columns and actual symbol reaches → physical coordinates.

Human Rules:
- lattice_geometry.1 (invariant) Each used row/column clears its actual
  body, pin reaches and existing rail/port stubs. Reflection mates use
  equal column widths. This is the original sketch coordinate pass,
  extracted unchanged so local owners do not exceed the file budget.
- lattice_geometry.2 (choice) Cold attached-group envelopes enlarge the
  existing cell's numeric room before symmetry equalization. Empty
  requests preserve the original coordinate loops. Callers validate the
  complete proposed scene and discard room after a rejected placement.

Data: borrowed schematic/skeleton tables in; caller-owned x/y arrays
out. Temporary room is one pair per row/column, released before return.
Every fallible allocation precedes exposing the completed arrays.

Contents:
- `pub const Geo`, `Room`
- `pub fn coordinates(gpa: Allocator, s: *const Schematic, nl: *const Netlist, sk: *const Skeleton, len: Lengths, extra: []const Room) !Geo`

## src/part_rows.zig

### Frozen experimental header

Declined named parallel pair -> bounded rows around actual obstacles.

Human Rules:
- part_rows.1 (bounded choice) After ordinary trunk rejection, a named
  pair on one row facing the same horizontal direction may use rows
  just outside actual body, mark and wire boundaries. Current AG1052's
  two correlated output pairs motivate this fallback. No source name,
  role inference, corner rule or crossing budget changes. `draw`
- part_rows.2 (invariant) The existing trunk cost, corners, fit and
  naming checks accept every candidate. The surrounding wire_parts
  transaction owns complete rollback and cross-part separation.

Data: one caller-owned scratch i32 row slice, sized once from checked
2*boxes+2*marks+4*segments. Canvas owns all input/output; no retained
graph or flags. This is cold bounded search, with no speed claim.

Contents: draw; private checked capacity and row boundaries.

### Current worktree header

(Absent)

## src/resistor_downstream.zig

### Frozen experimental header

One successful linked-load owner -> its observed named 2+1 and 2+2 parts.

Human Rules:
- resistor_downstream.1 (bounded observation) Two correlated branches in
  complete AG1052 keep the owned resistor/drain pair physically separate
  from a remote input gate. Each remote drain also has the complete raw
  resistor/NMOS-follower/PMOS-gate interface, with every supply/body bound.
  The source census admits exactly these two nets in 2,936 drawings.
  No name, value, distance or crossing budget selects. `branch`
- resistor_downstream.2 (boundary) Exactly one successful linked Pair and
  both complete interfaces qualify together before routing deferral.
  Multiple owners, raw competitors, unknown models, aliases and admitted
  interface geometry/net requests retain ordinary routing. `qualify`
- resistor_downstream.3 (choice) Each qualified net uses ordinary trunk
  and names for its local pair and remote gate, atomically. Current cut
  rounds may retain the two pieces; label rounds use ordinary labels.
  All actual leads, names, contacts and thinning remain authoritative.
- resistor_downstream.4 (bounded observation) The same complete source
  interfaces keep their supply-resistor/drain pair separate from the
  NMOS/PMOS gate pair. Both earlier 2+1 attempts precede these two 2+2
  attempts. Internal roles require names; spelling never implies a port.
  These are two correlated branches of one source drawing. `parts`

Data: one borrowed 48-byte Pair or empty; two temporary six-handle Branch
arrays (24 bytes each), four temporary expected device/index slots and
four u32 pin handles. No allocation, retained graph or widened request
view. The caller owns all inputs; wire_parts owns cold append rollback.
Raw CSR counts precede filtering. No hot-path or speed claim.

Contents: qualify, parts; private topology, intent and actual-pin checks.

### Current worktree header

One successful linked-load owner -> its observed two named 2+1 outputs.

Human Rules:
- resistor_downstream.1 (bounded observation) Two correlated branches in
  complete AG1052 keep the owned resistor/drain pair physically separate
  from a remote input gate. Each remote drain also has the complete raw
  resistor/NMOS-follower/PMOS-gate interface, with every supply/body bound.
  The source census admits exactly these two nets in 2,936 drawings.
  No name, value, distance or crossing budget selects. `branch`
- resistor_downstream.2 (boundary) Exactly one successful linked Pair and
  both complete interfaces qualify together before routing deferral.
  Multiple owners, raw competitors, unknown models, aliases and admitted
  interface geometry/net requests retain ordinary routing. `qualify`
- resistor_downstream.3 (choice) Each qualified net uses ordinary trunk
  and names for its local pair and remote gate, atomically. Current cut
  rounds may retain the two pieces; label rounds use ordinary labels.
  All actual leads, names, contacts and thinning remain authoritative.

Data: one borrowed 48-byte Pair or empty; two temporary six-handle Branch
arrays (24 bytes each). No allocation, retained graph or widened request
view. The caller owns all inputs; wire_parts owns cold append rollback.
Raw CSR counts precede filtering. No hot-path or speed claim.

Contents: qualify, parts; private topology, intent and actual-pin checks.

## src/sketch.zig

### Frozen experimental header

Stage 4 of issue #8: a drawing from the skeleton. In: the netlist, its
roles and a symbol library. Out: a laid-out `Schematic`, as
`Placed.init` reads one: every drawn device oriented and placed, its
pins, terminal symbols, wires, labels, dots and no-connect crosses. How
each net is wired is `wires.zig`'s.

Human Rules:
- sketch.1 (order: potential) An upright device's end on its upper net
  faces up, and no end of it on that net faces down. `fits`
- sketch.2 (unmeasured) An upright device's gate faces the side the
  skeleton gives it; of its four flips, the first that keeps sketch.1
  and this. `fits`
- sketch.3 (invariant) A `face` line says which end of a flat part is
  its left: the user's word. `firstLeft`
- sketch.4 (habit) A flat device's end on the net of the nearest device
  beside it faces that device: its ends are its path's two pins (a box
  of two ports: its two pins), and of the devices on their two nets
  that stand in another column, the nearest is the one fewest cells
  away, columns plus rows. So two parts in series are one line, and a
  part with one end on a port turns the other toward its net. People:
  4,414 of 4,471 flat two-pin parts (98.7%) and 1,684 of 1,719 other
  flat devices with a path (a pass transistor, a switch: 98.0%) in
  5,263 hand-drawn schematics; turned by a series neighbour, a lone pin
  and then the mean column, 91.5% of the parts. `fits`, `firstLeft`
- sketch.6 (habit) Where no device stands beside it, or two as near
  pull opposite ways, a flat device's first end is its left one when
  the devices on that end's net stand, at their mean column, no further
  right than those on the other's. People: 370 of 460 such parts
  (80.4%). `firstLeft`
- sketch.7 (invariant) No two devices of the lattice touch: each column
  is as wide as its widest device's reach on each side, each row as
  tall as its tallest device's (its body, where that reaches more than
  `stack` past its pins). `coordinates`
- sketch.8 (unmeasured) A pin on a port or rail net has room beyond it
  for its symbol: the symbol's stub (none for a rail symbol on a
  two-pin part, which stands on the pin: wires.10), and a unit more on
  a left or right side; a supply pin facing up takes none (its bar runs
  over the top).
  `coordinates`
- sketch.9 (choice) Neighbouring columns stand `series` apart and rows
  `stack` apart, and a lattice column with no device takes no room: the
  lengths are `config.Layout`'s. `coordinates`
- sketch.10 (invariant) Mirrored columns are as wide as each other, so
  the drawing keeps the skeleton's symmetry exactly. `coordinates`
- sketch.11 (invariant) A deck carrying a previous drawing's stays
  (`*@ weak at`) is relaid from them (`relay.zig`), unless it is an
  op-amp circuit (`opamp.zig`). `drawValid`
  Narrowing: a deck with a `weak at` line, even one rejected or
  overridden, is relaid; the general form asks for an `At.weak`.
- sketch.12 (invariant) A drawing closed up (`compact.zig`) has no
  symbol on another: where the squeeze leaves two overlapping, the
  lattice's places stand; a deck whose every device has its `at` line
  is not closed up. `drawValid`
- sketch.13 (invariant) A device stands where its `at` line puts it,
  turned as the line says, unless its symbol would overlap another
  drawn device's; the least preferred `at` gives way first and stands
  where the lattice has it. `keepAts`
- sketch.14 (unmeasured) An internal net with drawn pins on two shelves
  is joined by name, each shelf's pins wired, unless a deck line styles
  it. `drawValid`
- sketch.15 (choice) After the nets that cross too many wires are named
  (`thin.zig`), the drawing is wired again, at most three times: a wire
  gone may free a path that crosses anew, and the bound ends the work.
  `drawValid`
- sketch.16 (unmeasured) A MOS body, an op-amp's reference pin and a
  card pin its class lacks are drawn on the symbol, with no wire.
  `wiredSide`
- sketch.17 (invariant) No other net's wire touches a pin drawn only on
  its symbol. `hiddenPins`
- sketch.18 (invariant) No two pins of one side of a device meet at one
  point: a pin off its device's line for that side (an op-amp's second
  input) is wired from its own line. `placeDevices`
- sketch.19 (unmeasured) A device pin with no other pin on its net
  carries a no-connect cross. `noConnects`
- sketch.20 (habit) A flat complementary transmission pair's gates face
  outward while its members still share a column on separate rows,
  after cell and row instructions. People: ag-386 and ag-751, both
  source pairs selected by forms.19. An explicit `at` turn takes
  precedence when devices are placed. `fits`
- sketch.21 (habit) A flat MOS control faces its drawn active drivers
  when every driver stands strictly above it or every driver below it.
  Active terminals are transistor paths and named block outputs; other
  gates, bodies, sources and passive loads do not vote. A same-row or
  opposing driver leaves the class's side unchanged. People: 107/107
  qualifying converter controls face their drivers (75 block outputs,
  18 two-drain and 14 four-drain networks). Source terminal coordinates
  qualify that observation; distinct lattice rows are the placement
  proxy here. External controls use power_paths.6 where qualified;
  others abstain, and sketch.20 takes priority.
  Across all flat MOS, 139/142 qualifying sources agree; ag-809:m10,
  ag-813:m7 and ag-3103:m12 keep upward labelled controls from separate
  drawing groups. This habit does not yet recognize those local groups.
  `controlSide`, `fits`; docs/research/figures/gate_facing.py
- sketch.22 (habit, bounded) A converter controller below its unique
  main switch on the same final column points OUT up at its downward
  gate: 67 of 75 selected source SVGs do so. AG1354/1358/1366/1369/
  1372/1377/1393/1396 face right; their case remains unresolved. Cached
  terminal geometry alone incorrectly suggests 75. The actual OUT pin sets
  the controller's column, including a signed glyph's offset. Explicit
  origins or definition sides, an off-column main gate and an unsafe
  pin envelope abstain. `orientAll`; schematic.16
- sketch.23 (habit, bounded) An isolated amplifier bias peer uses its
  actual class frame after lattice coordinates, before scaffold wiring.
  Only its whole orientation and grid anchor change; admitted cells,
  stays and other caller geometry keep precedence. `bias_neighbors`
- sketch.24 (habit, bounded) A unique parallel tank capacitor uses its
  actual centered frame beside its fixed coil, opposite the actual tap.
  Caller geometry and occupied local room take precedence. `coil_tanks`
- sketch.25 (habit, bounded) A unique antiparallel clamp pair's controls
  face outward and matching nets occupy the same spatial channel end.
  All eight actual source devices agree. Couple the turns only while
  both actual frames support the joint rows, without either member's
  admitted origin/relation override. `antiparallel.placedMate`, `fits`

- sketch.26 (habit, bounded) A complete mirrored pair of shared CT
  banks owns its ten actual frames atomically. Caller requests and
  unsupported geometry abstain as a whole. `coil_banks`, `coil_bank_place`
- sketch.27 (habit, bounded) A unique MOS clamp with four complementary
  channel-ended anchors uses one clear actual-frame position strictly
  between their drain tips. No lattice row or anchor moves. `clamp_anchors`
- sketch.28 (habit, bounded) Two private C-S-C paths use the surviving
  mirrored banks as fixed anchors. Place only their six devices, with
  caller precedence, actual path frames and rollback. `coil_chains`
- sketch.29 (habit, bounded) The paired banks' four direct/cross
  switches use drain rows and the observed upper-half crossing pose.
  Keep full caller frames and exact mates; abstain atomically on a
  collision or request. No wire policy changes. `coil_bridges`
- sketch.30 (habit, bounded) One unique CT/capacitor tank follows a
  verified pair of actual block output leads. The block stays fixed;
  a successful two-row transaction supersedes generic tank placement.
  Explicit requests and occupied room retain precedence. `block_tanks`
- sketch.31 (bounded observation) One complete CT/NPN feedback stage
  uses the observed tap-up, emitter-down frame above the foreign body
  band. All nine members move atomically; actual frames, admitted
  requests, mates and collisions retain precedence. `ct_feedback_stage`

Contents:
- `pub fn lay(gpa: Allocator, nl: *const Netlist, roles: []const Role, lib: *Library, layout: config.Layout) !Schematic`
- `pub fn draw(gpa: Allocator, s: *Schematic, nl: *const Netlist, layout: config.Layout, st: *const Structure, sk: *const Skeleton) !void`

### Current worktree header

Stage 4 of issue #8: a drawing from the skeleton. In: the netlist, its
roles and a symbol library. Out: a laid-out `Schematic`, as
`Placed.init` reads one: every drawn device oriented and placed, its
pins, terminal symbols, wires, labels, dots and no-connect crosses. How
each net is wired is `wires.zig`'s.

Human Rules:
- sketch.1 (order: potential) An upright device's end on its upper net
  faces up, and no end of it on that net faces down. `fits`
- sketch.2 (unmeasured) An upright device's gate faces the side the
  skeleton gives it; of its four flips, the first that keeps sketch.1
  and this. `fits`
- sketch.3 (invariant) A `face` line says which end of a flat part is
  its left: the user's word. `firstLeft`
- sketch.4 (habit) A flat device's end on the net of the nearest device
  beside it faces that device: its ends are its path's two pins (a box
  of two ports: its two pins), and of the devices on their two nets
  that stand in another column, the nearest is the one fewest cells
  away, columns plus rows. So two parts in series are one line, and a
  part with one end on a port turns the other toward its net. People:
  4,414 of 4,471 flat two-pin parts (98.7%) and 1,684 of 1,719 other
  flat devices with a path (a pass transistor, a switch: 98.0%) in
  5,263 hand-drawn schematics; turned by a series neighbour, a lone pin
  and then the mean column, 91.5% of the parts. `fits`, `firstLeft`
- sketch.6 (habit) Where no device stands beside it, or two as near
  pull opposite ways, a flat device's first end is its left one when
  the devices on that end's net stand, at their mean column, no further
  right than those on the other's. People: 370 of 460 such parts
  (80.4%). `firstLeft`
- sketch.7 (invariant) No two devices of the lattice touch: each column
  is as wide as its widest device's reach on each side, each row as
  tall as its tallest device's (its body, where that reaches more than
  `stack` past its pins). `coordinates`
- sketch.8 (unmeasured) A pin on a port or rail net has room beyond it
  for its symbol: the symbol's stub (none for a rail symbol on a
  two-pin part, which stands on the pin: wires.10), and a unit more on
  a left or right side; a supply pin facing up takes none (its bar runs
  over the top).
  `coordinates`
- sketch.9 (choice) Neighbouring columns stand `series` apart and rows
  `stack` apart, and a lattice column with no device takes no room: the
  lengths are `config.Layout`'s. `coordinates`
- sketch.10 (invariant) Mirrored columns are as wide as each other, so
  the drawing keeps the skeleton's symmetry exactly. `coordinates`
- sketch.11 (invariant) A deck carrying a previous drawing's stays
  (`*@ weak at`) is relaid from them (`relay.zig`), unless it is an
  op-amp circuit (`opamp.zig`). `drawValid`
  Narrowing: a deck with a `weak at` line, even one rejected or
  overridden, is relaid; the general form asks for an `At.weak`.
- sketch.12 (invariant) A drawing closed up (`compact.zig`) has no
  symbol on another: where the squeeze leaves two overlapping, the
  lattice's places stand; a deck whose every device has its `at` line
  is not closed up. `drawValid`
- sketch.13 (invariant) A device stands where its `at` line puts it,
  turned as the line says, unless its symbol would overlap another
  drawn device's; the least preferred `at` gives way first and stands
  where the lattice has it. `keepAts`
- sketch.14 (unmeasured) An internal net with drawn pins on two shelves
  is joined by name, each shelf's pins wired, unless a deck line styles
  it. `drawValid`
- sketch.15 (choice) After the nets that cross too many wires are named
  (`thin.zig`), the drawing is wired again, at most three times: a wire
  gone may free a path that crosses anew, and the bound ends the work.
  `drawValid`
- sketch.16 (unmeasured) A MOS body, an op-amp's reference pin and a
  card pin its class lacks are drawn on the symbol, with no wire.
  `wiredSide`
- sketch.17 (invariant) No other net's wire touches a pin drawn only on
  its symbol. `hiddenPins`
- sketch.18 (invariant) No two pins of one side of a device meet at one
  point: a pin off its device's line for that side (an op-amp's second
  input) is wired from its own line. `placeDevices`
- sketch.19 (unmeasured) A device pin with no other pin on its net
  carries a no-connect cross. `noConnects`
- sketch.20 (habit) A flat complementary transmission pair's gates face
  outward while its members still share a column on separate rows,
  after cell and row instructions. People: ag-386 and ag-751, both
  source pairs selected by forms.19. An explicit `at` turn takes
  precedence when devices are placed. `fits`
- sketch.21 (habit) A flat MOS control faces its drawn active drivers
  when every driver stands strictly above it or every driver below it.
  Active terminals are transistor paths and named block outputs; other
  gates, bodies, sources and passive loads do not vote. A same-row or
  opposing driver leaves the class's side unchanged. People: 107/107
  qualifying converter controls face their drivers (75 block outputs,
  18 two-drain and 14 four-drain networks). Source terminal coordinates
  qualify that observation; distinct lattice rows are the placement
  proxy here. External controls use power_paths.6 where qualified;
  others abstain, and sketch.20 takes priority.
  Across all flat MOS, 139/142 qualifying sources agree; ag-809:m10,
  ag-813:m7 and ag-3103:m12 keep upward labelled controls from separate
  drawing groups. This habit does not yet recognize those local groups.
  `controlSide`, `fits`; docs/research/figures/gate_facing.py
- sketch.22 (habit, bounded) A converter controller below its unique
  main switch on the same final column points OUT up at its downward
  gate: 67 of 75 selected source SVGs do so. AG1354/1358/1366/1369/
  1372/1377/1393/1396 face right; their case remains unresolved. Cached
  terminal geometry alone incorrectly suggests 75. The actual OUT pin sets
  the controller's column, including a signed glyph's offset. Explicit
  origins or definition sides, an off-column main gate and an unsafe
  pin envelope abstain. `orientAll`; schematic.16
- sketch.23 (habit, bounded) An isolated amplifier bias peer uses its
  actual class frame after lattice coordinates, before scaffold wiring.
  Only its whole orientation and grid anchor change; admitted cells,
  stays and other caller geometry keep precedence. `bias_neighbors`
- sketch.24 (habit, bounded) A unique parallel tank capacitor uses its
  actual centered frame beside its fixed coil, opposite the actual tap.
  Caller geometry and occupied local room take precedence. `coil_tanks`
- sketch.25 (habit, bounded) A unique antiparallel clamp pair's controls
  face outward and matching nets occupy the same spatial channel end.
  All eight actual source devices agree. Couple the turns only while
  both actual frames support the joint rows, without either member's
  admitted origin/relation override. `antiparallel.placedMate`, `fits`

- sketch.26 (habit, bounded) A complete mirrored pair of shared CT
  banks owns its ten actual frames atomically. Caller requests and
  unsupported geometry abstain as a whole. `coil_banks`, `coil_bank_place`
- sketch.27 (habit, bounded) A unique MOS clamp with four complementary
  channel-ended anchors uses one clear actual-frame position strictly
  between their drain tips. No lattice row or anchor moves. `clamp_anchors`
- sketch.28 (habit, bounded) Two private C-S-C paths use the surviving
  mirrored banks as fixed anchors. Place only their six devices, with
  caller precedence, actual path frames and rollback. `coil_chains`
- sketch.29 (habit, bounded) The paired banks' four direct/cross
  switches use drain rows and the observed upper-half crossing pose.
  Keep full caller frames and exact mates; abstain atomically on a
  collision or request. No wire policy changes. `coil_bridges`
- sketch.30 (habit, bounded) One unique CT/capacitor tank follows a
  verified pair of actual block output leads. The block stays fixed;
  a successful two-row transaction supersedes generic tank placement.
  Explicit requests and occupied room retain precedence. `block_tanks`
- sketch.31 (bounded observation) One complete CT/NPN feedback stage
  uses the observed tap-up, emitter-down frame above the foreign body
  band. All nine members move atomically; actual frames, admitted
  requests, mates and collisions retain precedence. `ct_feedback_stage`

- sketch.32 (bounded observation) A closed resistor-loaded differential
  stage owns its six actual frames; two feed-forward stages sharing a
  complete tail bank own twelve. Separate local axes refine automatic
  bank arrangement while preserving caller requests and mate identities.
  `resistor_loads`, `resistor_load_place`
- sketch.33 (bounded observation) Two complete downstream RC input
  branches and bias chokes follow their actual block input frame. Five passive rows
  share a fresh-lattice room transaction with output tanks; rejected
  work restores the prior output-only path. `block_input_rc`, `block_rooms`

Contents:
- `pub fn lay(gpa: Allocator, nl: *const Netlist, roles: []const Role, lib: *Library, layout: config.Layout) !Schematic`
- `pub fn draw(gpa: Allocator, s: *Schematic, nl: *const Netlist, layout: config.Layout, st: *const Structure, sk: *const Skeleton) !void`

## src/trunk.zig

### Frozen experimental header

The trunk pattern (issue #8, stage 4): one net with no symbol of its own
as a trunk along a row, or down a column, with each pin brought to it,
or a column's pins joined in order. In: the canvas, the net and its
pins, placed. Out: the net's wires on the canvas (an output's or an
input's port too), or nothing drawn when no track fits.

Human Rules:
- trunk.1 (unmeasured) Pins all in one column, each facing up or down,
  are joined in order down that column. `draw`
- trunk.2 (habit) Of the tracks that fit, a net takes the one whose
  wire costs least, as the router counts a path (maze.2): its length,
  plus `bend_cost` a corner (a point the wire leaves exactly two ways
  at a right angle; a T, a crossing of its own and a straight joint
  are none), plus `cross_cost` each crossing of another net's wire
  drawn so far, a quarter of it for a rail's. People draw a net at the
  fewest corners its pins allow in 93.8% of the nets, and a net's wire
  crosses no other net's in 33,360 of 37,990 nets that are no rail
  (5,263 hand-drawn schematics). `cost`
- trunk.3 (invariant) No wire of a trunk has a spur: a track on which
  two pins' ways run on together past where they meet is never taken.
  `corners`
- trunk.4 (habit) The rows a trunk tries first, and keeps on a tie, are
  those of its pins facing sideways, nearest the tap row first: such a
  pin joins the trunk straight. People: a level wire runs along the
  row of a gate standing between a pin facing down and a pin facing up
  in 3,898 of 3,955 such nets (5,263 hand-drawn schematics).
  `levelRows`
- trunk.5 (habit) A level trunk stands `tap` (half a unit) out from the
  tips of the pins facing up or down that it joins: under the lowest
  facing down, over the highest facing up (midway where they stand two
  taps apart), and half a `tap` out only where neither row has room.
  People: a level wire past two pins or more facing one way stands
  half a unit out in 729 of 1,404 nets and a quarter in 76; between a
  pin facing down and one facing up it stands off both tips in 9,466
  of 11,252, midway in 5,134 (5,263 hand-drawn schematics). `tapRows`
- trunk.6 (choice) The rows tried after those, in order: `tap` under
  the pins facing down, `tap` over those facing up, half a `tap` each
  way; half a unit past the pins' devices, the side away from the
  drawing's middle first (a gate line over the top row's gates, under
  the bottom's); the first on a tie: a fixed order, so the cards'
  order chooses nothing. `draw`
- trunk.7 (book) Two pins facing each other along a row (a mirror's
  gates) are joined straight first, a gate line, and its middle
  brought to the trunk, as the book draws it. A track on the pins' own
  row needs no separate rung; that does not rule out a rung on the
  remaining bounded tracks. AMS401's source resistor/gate approach
  stays straight while a lower trunk reaches its feedback capacitor.
  Keep a midpoint that passes corner, obstacle and free-end checks;
  otherwise cost both adjacent quarter-unit taps, strictly inside the
  pair, through the same checks. AG981/984/986 have straight source
  gate lines whose native midpoint meets another wire. Alternatives
  keep the first on an exact cost tie; reflection is not universal.
  A displaced full-row tap leaves the original half rows available;
  only an accepted midpoint with any required free end rules them out.
  `trunkLines`, `draw`
- trunk.8 (unmeasured) A pin comes to its trunk straight when it faces
  it; out half a unit and along when it faces sideways; round its own
  device, through the channel on its right, when it faces away.
  Only when every original track fails for a named part, retry its
  sideways-pin rows without artificial half-unit approach vertices.
  AG2365 then keeps a proper foreign-wire crossing. Existing tracks,
  ports, departure checks and forbidden contacts retain precedence.
  `wayTo`
- trunk.9 (choice) A net of at most 12 pins may run its trunk upright,
  where that costs less: down the column of a pin facing up or down,
  midway between two neighbouring pins, or half a unit either side of
  a pin, each kind nearest the pins' middle first, then nearest the
  drawing's middle: the bound keeps the search small. `uprightColumns`
  Narrowing: only for a net with no port or name on its wire.
- trunk.10 (order: signal) A port or a name leaves a trunk from its
  free end, the left (where the signal enters) before the right; an
  end some pin of the net stands beyond is not free. `freeEnd`
- trunk.11 (choice) An input or a bias whose trunk has no free end for
  its port is not drawn as one trunk; a part of a net joined by name
  with none carries its name at its top-left pin, so card order
  chooses nothing. `draw`
- trunk.12 (unmeasured) An output's port leaves from the outer end of
  its trunk, or of its column at its tap, on the drawing's nearer
  side: the right when the trunk's right end reaches the drawing's
  middle; a lone pin's port leaves from the pin. `draw`
- trunk.13 (habit) A pin is an end of its wire, which leaves it the way
  the pin faces: no track runs through the tip of a pin facing across
  it or turns on one, and the wire branches off its pins. People:
  87,922 of 93,770 pins of wired nets that are no rail (5,263
  hand-drawn schematics). `corners`
- trunk.14 (habit) A bias's wire crosses no other net's (a rail's
  aside): a track that would is not taken, and a part no track fits
  ends in ports (wires.13). People: 3,926 of 4,080 wired bias nets
  (5,263 hand-drawn schematics). `cost`

- trunk.15 (choice, bounded) A complete complementary-mirror CT stage
  may nominate one actual opposing gate interval (ct_mirror_controls.1).
  Only an exact tie after full length, corner, crossing, obstacle and
  free-end checks prefers candidate ink covering that interval. Every
  cheaper legal candidate wins; null preserves the original tie order.

- trunk.16 (bounded request) A complete four-side CT scene can request
  an output part's left or right endpoint (ct_four_wires.5). The request
  changes final endpoint selection only, after ordinary candidate cost
  competition. It requires multiple output pins; singleton and ordinary
  port/name behavior stay unchanged. The caller certifies an actual
  outside terminal and atomically rejects a blocked/fallback result.

- trunk.17 (bounded fallback) Only after an ordinary named two-pin
  component declines, two same-facing horizontal pins on one row
  may try actual obstacle boundary rows (part_rows). Full cost,
  corner, contact and name rules remain unchanged; ports never
  use this fallback. Exact full-cost ties choose the smaller row.

Contents:
- `pub fn drawPairRows(c: *Canvas, net: u32, pins: [2]u32, rows: []const i32) Allocator.Error!bool`
- `pub const End = enum { port, name, port_left, port_right }`
- `pub inline fn draw(c: *Canvas, net: u32, pins: []const u32, end: End) Allocator.Error!bool`
- `pub fn drawPreferred(c: *Canvas, net: u32, pins: []const u32, end: End, preferred: ?[2]Pt) Allocator.Error!bool`

### Current worktree header

The trunk pattern (issue #8, stage 4): one net with no symbol of its own
as a trunk along a row, or down a column, with each pin brought to it,
or a column's pins joined in order. In: the canvas, the net and its
pins, placed. Out: the net's wires on the canvas (an output's or an
input's port too), or nothing drawn when no track fits.

Human Rules:
- trunk.1 (unmeasured) Pins all in one column, each facing up or down,
  are joined in order down that column. `draw`
- trunk.2 (habit) Of the tracks that fit, a net takes the one whose
  wire costs least, as the router counts a path (maze.2): its length,
  plus `bend_cost` a corner (a point the wire leaves exactly two ways
  at a right angle; a T, a crossing of its own and a straight joint
  are none), plus `cross_cost` each crossing of another net's wire
  drawn so far, a quarter of it for a rail's. People draw a net at the
  fewest corners its pins allow in 93.8% of the nets, and a net's wire
  crosses no other net's in 33,360 of 37,990 nets that are no rail
  (5,263 hand-drawn schematics). `cost`
- trunk.3 (invariant) No wire of a trunk has a spur: a track on which
  two pins' ways run on together past where they meet is never taken.
  `corners`
- trunk.4 (habit) The rows a trunk tries first, and keeps on a tie, are
  those of its pins facing sideways, nearest the tap row first: such a
  pin joins the trunk straight. People: a level wire runs along the
  row of a gate standing between a pin facing down and a pin facing up
  in 3,898 of 3,955 such nets (5,263 hand-drawn schematics).
  `levelRows`
- trunk.5 (habit) A level trunk stands `tap` (half a unit) out from the
  tips of the pins facing up or down that it joins: under the lowest
  facing down, over the highest facing up (midway where they stand two
  taps apart), and half a `tap` out only where neither row has room.
  People: a level wire past two pins or more facing one way stands
  half a unit out in 729 of 1,404 nets and a quarter in 76; between a
  pin facing down and one facing up it stands off both tips in 9,466
  of 11,252, midway in 5,134 (5,263 hand-drawn schematics). `tapRows`
- trunk.6 (choice) The rows tried after those, in order: `tap` under
  the pins facing down, `tap` over those facing up, half a `tap` each
  way; half a unit past the pins' devices, the side away from the
  drawing's middle first (a gate line over the top row's gates, under
  the bottom's); the first on a tie: a fixed order, so the cards'
  order chooses nothing. `draw`
- trunk.7 (book) Two pins facing each other along a row (a mirror's
  gates) are joined straight first, a gate line, and its middle
  brought to the trunk, as the book draws it. A track on the pins' own
  row needs no separate rung; that does not rule out a rung on the
  remaining bounded tracks. AMS401's source resistor/gate approach
  stays straight while a lower trunk reaches its feedback capacitor.
  Keep a midpoint that passes corner, obstacle and free-end checks;
  otherwise cost both adjacent quarter-unit taps, strictly inside the
  pair, through the same checks. AG981/984/986 have straight source
  gate lines whose native midpoint meets another wire. Alternatives
  keep the first on an exact cost tie; reflection is not universal.
  A displaced full-row tap leaves the original half rows available;
  only an accepted midpoint with any required free end rules them out.
  `trunkLines`, `draw`
- trunk.8 (unmeasured) A pin comes to its trunk straight when it faces
  it; out half a unit and along when it faces sideways; round its own
  device, through the channel on its right, when it faces away.
  Only when every original track fails for a named part, retry its
  sideways-pin rows without artificial half-unit approach vertices.
  AG2365 then keeps a proper foreign-wire crossing. Existing tracks,
  ports, departure checks and forbidden contacts retain precedence.
  `wayTo`
- trunk.9 (choice) A net of at most 12 pins may run its trunk upright,
  where that costs less: down the column of a pin facing up or down,
  midway between two neighbouring pins, or half a unit either side of
  a pin, each kind nearest the pins' middle first, then nearest the
  drawing's middle: the bound keeps the search small. `uprightColumns`
  Narrowing: only for a net with no port or name on its wire.
- trunk.10 (order: signal) A port or a name leaves a trunk from its
  free end, the left (where the signal enters) before the right; an
  end some pin of the net stands beyond is not free. `freeEnd`
- trunk.11 (choice) An input or a bias whose trunk has no free end for
  its port is not drawn as one trunk; a part of a net joined by name
  with none carries its name at its top-left pin, so card order
  chooses nothing. `draw`
- trunk.12 (unmeasured) An output's port leaves from the outer end of
  its trunk, or of its column at its tap, on the drawing's nearer
  side: the right when the trunk's right end reaches the drawing's
  middle; a lone pin's port leaves from the pin. `draw`
- trunk.13 (habit) A pin is an end of its wire, which leaves it the way
  the pin faces: no track runs through the tip of a pin facing across
  it or turns on one, and the wire branches off its pins. People:
  87,922 of 93,770 pins of wired nets that are no rail (5,263
  hand-drawn schematics). `corners`
- trunk.14 (habit) A bias's wire crosses no other net's (a rail's
  aside): a track that would is not taken, and a part no track fits
  ends in ports (wires.13). People: 3,926 of 4,080 wired bias nets
  (5,263 hand-drawn schematics). `cost`

- trunk.15 (choice, bounded) A complete complementary-mirror CT stage
  may nominate one actual opposing gate interval (ct_mirror_controls.1).
  Only an exact tie after full length, corner, crossing, obstacle and
  free-end checks prefers candidate ink covering that interval. Every
  cheaper legal candidate wins; null preserves the original tie order.

Contents:
- `pub const End = enum { port, name }`
- `pub inline fn draw(c: *Canvas, net: u32, pins: []const u32, end: End) Allocator.Error!bool`
- `pub fn drawPreferred(c: *Canvas, net: u32, pins: []const u32, end: End, preferred: ?[2]Pt) Allocator.Error!bool`

## src/wires.zig

### Frozen experimental header

Wires (issue #8, stage 4): every net of a placed drawing, as terminal
symbols, wires and labels, by the book's patterns. In: a `Schematic`
whose devices are placed and pinned, the devices' boxes, and the
drawing's mirror if it has one. Out: its routes, terminal and label
nodes, and the nets drawn as labels.

Human Rules:
- wires.1 (choice) Rails are wired first, then the symbol of an input
  or a bias of one pin, then the internal nets and the outputs, then
  the wires of the inputs and biases, each group in the canonical net
  order: a net wired earlier claims its room first, and the order of
  the cards chooses nothing. A symbol takes little room and has one
  place; an input's or a bias's part can always end in ports
  (wires.13), a wire cannot: drawn last, it takes its track among the
  wires it would cross (trunk.2). Over the 5,263 reference circuits,
  with trunk.2's crossings, against inputs and biases second:
  crossings 7,395 -> 7,279, corners 39,521 -> 39,185. `drawStep`
- wires.2 (choice) A `via` line's wire runs from the net's top-left pin
  to each point in turn by one L, along the row first, and skips a
  point neither L reaches: the line names points, not the path.
  `pinned`
- wires.3 (habit) A rail drawn as a bar takes each of its pins that
  faces the bar (up for a supply, down for ground) and stands no more
  than two units from it; a pin farther off has a symbol of its own.
  People: of 9,149 upright supply runs in 5,263 hand-drawn schematics,
  97% are no longer. `bar`
- wires.4 (unmeasured) A rail pin that does not face its bar, every
  pin when fewer than two reach the bar, and a pin whose stub to it
  does not fit, each have a rail symbol of their own. `bar`
- wires.5 (choice) A rail's bar stands one rail stub (`rail`) past the
  outermost of its pins facing it: the outermost pin meets it on the
  stub its symbol would have had. `bar`
- wires.6 (habit) A rail's bar that ends on its outer pins carries one
  symbol on each unbroken run of it, at the run's middle stub. People:
  1,083 of 1,140 supply bars carrying a symbol end on their outer pins.
  `bar`
- wires.7 (habit) A supply bar's run of two stubs or more is instead a
  named rail, where both ends fit: it goes on `rail` past its outer pins,
  carries no symbol, and its name stands at its right end; never a
  symbol and a run past both. People: 1,255 of 1,370 named bars run past
  both ends, the name at the right end in 1,252 of 1,256; no person
  draws a symbol on a bar that runs past (0 of 730). `rail_past` off,
  every bar is wires.6's (`config.Layout.rail_past`). `bar`
  Narrowing: a supply's bar only; a ground drawn as a bar ends on its
  outer pins.
- wires.8 (unmeasured) No other net's wire crosses a rail's bar or its
  run past its pins. `bar`
- wires.9 (unmeasured) A rail drawn as a plain bar brings every pin
  facing it to the bar however far; where the bar breaks or a pin does
  not reach it, each run and each pin off it carries the net's name,
  and a bar in one piece carries none. `bar`
- wires.10 (habit) A rail symbol on a two-pin part's end stands on the
  pin; on any other pin, and a port at a pin, one stub out from it,
  toward the side a `port` line asks, else the way the pin faces; a
  name on the pin where neither stub fits. People: on the pin 6,883 of
  8,367 rail symbols at a two-pin part's end in 5,263 hand-drawn
  schematics, 3,612 of 8,921 at a transistor's path end. `terminal`
  Narrowing: no name's stub is tried before the pin, as
  `Canvas.labelAt` would.
- wires.11 (habit) A bias net of two gates facing each other on one row
  is one straight gate line between them, a port symbol hanging from
  its middle, never a written name (a name at its first pin only when no
  stub fits at the middle). People: a port symbol on 197 of 264 such
  gate lines in 5,263 hand-drawn schematics. `ported`
- wires.12 (habit) An input's or a bias's pins standing near each other
  (the box round them no more than 6 units around half) are one wire
  with one port at a free end. People wire 87% of their inputs of two
  pins or more to one symbol and cut a connection past 5.5 to 7.5
  units (5,274 drawings). `near`
  Narrowing: one cut for every pin kind; per-edge cuts (gate to gate 3,
  gate to other 5.5, other 7.5) once the pitch is the human one.
- wires.13 (habit) An input or a bias whose pins stand farther apart, or
  whose wire has no free end for its port, has a port on a stub at each
  pin; a bias is never a written name. People: of 4,378 nets named
  `vb*` or `bias*` in 5,263 hand-drawn schematics, 3,228 carry port
  symbols and none a written name. `ported`
- wires.14 (choice) Any other net takes the first pattern that fits: a
  ladder, then a column or a trunk (`trunk.zig`); one no pattern fits
  is routed (`routes.zig`) after every pattern: a pattern is the shape
  a reader knows, the router what is left. `patterned`
- wires.15 (unmeasured) An internal net whose pins face each other in
  pairs along rows, one pair a row on two rows or more, is a ladder: a
  rung between each pair and one upright through them all at the
  mirror axis when it lies within every rung, else at the rungs' shared
  middle, as a CMFB midpoint meets its gate line. `ladder`
- wires.16 (choice) A bias a `wire` line wires, or a `route` or `via`
  line pins, carries its name once, at its top-left pin: the name
  joins it to its sources drawn apart, and card order chooses nothing.
  `wire`
- wires.17 (habit) A net joined by name falls into parts, each pin no
  farther from another of its part (along x plus along y) than 15, 11
  or 6 half units as neither, one or both of the two face sideways.
  People: fitted on the connections people wire and name in 5,274
  hand-drawn schematics (93.6% of nets right on those held out).
  `within`
- wires.18 (unmeasured) Each part of two pins or more of a net joined
  by name is one trunk with one name at a free end; a pin alone, or a
  part no trunk fits, carries the name at each pin. `parts`
- wires.19 (choice) A net joined by name that is all one part is named
  at every pin: it was cut because its one wire crossed too much.
  `parts`
- wires.20 (habit, bounded) After rails claim their room, a certified
  converter loop connects its selected local terminals before ordinary
  nets. Its outside pins retain the normal port/name/wire choice.
  All 145 selected source loops have seven continuous local trees with
  no crossing between them; power_loop_wires.1 names the source audit.
  A seeded input component gets its port at the actual tree boundary;
  nearby outside pins attach under wires.12's distance limit. Measure
  their whole cluster plus its shortest reach to the actual tree ink;
  the retained routing handle is not its boundary. Distant pins retain
  ports. This native proximity choice does not infer source block layout.
  Explicit styles and first-net requests abstain. `power_loop_wires.seed`
- wires.21 (habit, bounded) A complete CT-linked common-base bias stage
  keeps its two actual opposing B leads in one cut part when the direct
  interval fits. The five-member source observation and exclusions are
  ct_controls.1; this changes neither ordinary near grouping nor the
  whole-part fallback and later crossing cuts. `parts`

- wires.24 (bounded observation) A complete reciprocal-MOS source/source/
  tail-drain junction may share a direct horizontal bar through its actual
  tips. Only automatic internal nets with the measured clear opposing
  frame qualify; caller requests, ordinary corner rules and later cuts
  remain. Each mirror mate qualifies itself. `common_source_bars.draw`

Contents:
- `pub fn wire(gpa: Allocator, s: *Schematic, nl: *const Netlist, xy: *std.ArrayList([2]f32), len: Lengths, boxes: []const Rect, hidden: []const maze.Mark, mirror: ?routes.Mirror, net_rank: []const u32, lines: *const NetLines, requests: Requests, loops: []const power_loops.Group, load_singles: []const resistor_loads.Group, load_pairs: []const resistor_loads.Pair, downstream: []const resistor_loads.Pair, four_groups: []const ct_four_sides.Group) Allocator.Error!void`

### Current worktree header

Wires (issue #8, stage 4): every net of a placed drawing, as terminal
symbols, wires and labels, by the book's patterns. In: a `Schematic`
whose devices are placed and pinned, the devices' boxes, and the
drawing's mirror if it has one. Out: its routes, terminal and label
nodes, and the nets drawn as labels.

Human Rules:
- wires.1 (choice) Rails are wired first, then the symbol of an input
  or a bias of one pin, then the internal nets and the outputs, then
  the wires of the inputs and biases, each group in the canonical net
  order: a net wired earlier claims its room first, and the order of
  the cards chooses nothing. A symbol takes little room and has one
  place; an input's or a bias's part can always end in ports
  (wires.13), a wire cannot: drawn last, it takes its track among the
  wires it would cross (trunk.2). Over the 5,263 reference circuits,
  with trunk.2's crossings, against inputs and biases second:
  crossings 7,395 -> 7,279, corners 39,521 -> 39,185. `drawStep`
- wires.2 (choice) A `via` line's wire runs from the net's top-left pin
  to each point in turn by one L, along the row first, and skips a
  point neither L reaches: the line names points, not the path.
  `pinned`
- wires.3 (habit) A rail drawn as a bar takes each of its pins that
  faces the bar (up for a supply, down for ground) and stands no more
  than two units from it; a pin farther off has a symbol of its own.
  People: of 9,149 upright supply runs in 5,263 hand-drawn schematics,
  97% are no longer. `bar`
- wires.4 (unmeasured) A rail pin that does not face its bar, every
  pin when fewer than two reach the bar, and a pin whose stub to it
  does not fit, each have a rail symbol of their own. `bar`
- wires.5 (choice) A rail's bar stands one rail stub (`rail`) past the
  outermost of its pins facing it: the outermost pin meets it on the
  stub its symbol would have had. `bar`
- wires.6 (habit) A rail's bar that ends on its outer pins carries one
  symbol on each unbroken run of it, at the run's middle stub. People:
  1,083 of 1,140 supply bars carrying a symbol end on their outer pins.
  `bar`
- wires.7 (habit) A supply bar's run of two stubs or more is instead a
  named rail, where both ends fit: it goes on `rail` past its outer pins,
  carries no symbol, and its name stands at its right end; never a
  symbol and a run past both. People: 1,255 of 1,370 named bars run past
  both ends, the name at the right end in 1,252 of 1,256; no person
  draws a symbol on a bar that runs past (0 of 730). `rail_past` off,
  every bar is wires.6's (`config.Layout.rail_past`). `bar`
  Narrowing: a supply's bar only; a ground drawn as a bar ends on its
  outer pins.
- wires.8 (unmeasured) No other net's wire crosses a rail's bar or its
  run past its pins. `bar`
- wires.9 (unmeasured) A rail drawn as a plain bar brings every pin
  facing it to the bar however far; where the bar breaks or a pin does
  not reach it, each run and each pin off it carries the net's name,
  and a bar in one piece carries none. `bar`
- wires.10 (habit) A rail symbol on a two-pin part's end stands on the
  pin; on any other pin, and a port at a pin, one stub out from it,
  toward the side a `port` line asks, else the way the pin faces; a
  name on the pin where neither stub fits. People: on the pin 6,883 of
  8,367 rail symbols at a two-pin part's end in 5,263 hand-drawn
  schematics, 3,612 of 8,921 at a transistor's path end. `terminal`
  Narrowing: no name's stub is tried before the pin, as
  `Canvas.labelAt` would.
- wires.11 (habit) A bias net of two gates facing each other on one row
  is one straight gate line between them, a port symbol hanging from
  its middle, never a written name (a name at its first pin only when no
  stub fits at the middle). People: a port symbol on 197 of 264 such
  gate lines in 5,263 hand-drawn schematics. `ported`
- wires.12 (habit) An input's or a bias's pins standing near each other
  (the box round them no more than 6 units around half) are one wire
  with one port at a free end. People wire 87% of their inputs of two
  pins or more to one symbol and cut a connection past 5.5 to 7.5
  units (5,274 drawings). `near`
  Narrowing: one cut for every pin kind; per-edge cuts (gate to gate 3,
  gate to other 5.5, other 7.5) once the pitch is the human one.
- wires.13 (habit) An input or a bias whose pins stand farther apart, or
  whose wire has no free end for its port, has a port on a stub at each
  pin; a bias is never a written name. People: of 4,378 nets named
  `vb*` or `bias*` in 5,263 hand-drawn schematics, 3,228 carry port
  symbols and none a written name. `ported`
- wires.14 (choice) Any other net takes the first pattern that fits: a
  ladder, then a column or a trunk (`trunk.zig`); one no pattern fits
  is routed (`routes.zig`) after every pattern: a pattern is the shape
  a reader knows, the router what is left. `patterned`
- wires.15 (unmeasured) An internal net whose pins face each other in
  pairs along rows, one pair a row on two rows or more, is a ladder: a
  rung between each pair and one upright through them all at the
  mirror axis when it lies within every rung, else at the rungs' shared
  middle, as a CMFB midpoint meets its gate line. `ladder`
- wires.16 (choice) A bias a `wire` line wires, or a `route` or `via`
  line pins, carries its name once, at its top-left pin: the name
  joins it to its sources drawn apart, and card order chooses nothing.
  `wire`
- wires.17 (habit) A net joined by name falls into parts, each pin no
  farther from another of its part (along x plus along y) than 15, 11
  or 6 half units as neither, one or both of the two face sideways.
  People: fitted on the connections people wire and name in 5,274
  hand-drawn schematics (93.6% of nets right on those held out).
  `within`
- wires.18 (unmeasured) Each part of two pins or more of a net joined
  by name is one trunk with one name at a free end; a pin alone, or a
  part no trunk fits, carries the name at each pin. `parts`
- wires.19 (choice) A net joined by name that is all one part is named
  at every pin: it was cut because its one wire crossed too much.
  `parts`
- wires.20 (habit, bounded) After rails claim their room, a certified
  converter loop connects its selected local terminals before ordinary
  nets. Its outside pins retain the normal port/name/wire choice.
  All 145 selected source loops have seven continuous local trees with
  no crossing between them; power_loop_wires.1 names the source audit.
  A seeded input component gets its port at the actual tree boundary;
  nearby outside pins attach under wires.12's distance limit. Measure
  their whole cluster plus its shortest reach to the actual tree ink;
  the retained routing handle is not its boundary. Distant pins retain
  ports. This native proximity choice does not infer source block layout.
  Explicit styles and first-net requests abstain. `power_loop_wires.seed`
- wires.21 (habit, bounded) A complete CT-linked common-base bias stage
  keeps its two actual opposing B leads in one cut part when the direct
  interval fits. The five-member source observation and exclusions are
  ct_controls.1; this changes neither ordinary near grouping nor the
  whole-part fallback and later crossing cuts. `parts`

- wires.22 (bounded observation) Successful complete resistor-load
  stages put their load bar through the actual resistor tips. The cold
  owner consumer runs after rails, uses ordinary contact checks, and
  declines caller styles, sequencing or later cut/label rounds. No net
  gets an exemption from automatic thinning. `resistor_load_wires.seed`
- wires.23 (bounded observation) A successfully placed complete four-side
  CT scene retains its source-separated components and one shared tap
  supply. The cold owner checks actual pins, names and same-net contacts
  atomically; normal trunk costs and later thinning remain. `ct_four_wires`

- wires.24 (bounded observation) One qualified linked-load owner keeps
  its two downstream local resistor/drain pieces separate from remote
  input gates. Original caller intent and complete raw supply/body
  contracts select; ordinary names, contacts and thinning remain.
  `resistor_downstream`

Contents:
- `pub fn wire(gpa: Allocator, s: *Schematic, nl: *const Netlist, xy: *std.ArrayList([2]f32), len: Lengths, boxes: []const Rect, hidden: []const maze.Mark, mirror: ?routes.Mirror, net_rank: []const u32, lines: *const NetLines, requests: Requests, loops: []const power_loops.Group, load_singles: []const resistor_loads.Group, load_pairs: []const resistor_loads.Pair, downstream: []const resistor_loads.Pair, four_groups: []const ct_four_sides.Group) Allocator.Error!void`

## tools/schemify/recognize.zig

### Frozen experimental header

(Absent)

### Current worktree header

Recognize transform: `Deck` devices → symbols (bundled `core` cells, generated subckt
cells, generated leaf cells) and per-instance parameter overrides.

A card maps onto its `core` cell only when the core template re-emits it faithfully:
the core templates always print some parameters (`m=`, a diode's `area=`, a MOSFET's
`w=`/`l=`), so a card that omits them would change meaning. Every other card becomes an
instance of a generated *leaf* (`spice_<kind>.shprim`, template `{name} {pins} {args}`)
that re-emits the card text verbatim. `X` cards call the generated cell of a subckt in
the file, or a generated stub leaf named after an undefined subckt.

Human Rules:
- recognize.1 (symbol contract) A named center-tapped inductor has three
  passive ports. Left/right drawing position never invents an input or
  output direction; explicit PININFO and caller side geometry win.

