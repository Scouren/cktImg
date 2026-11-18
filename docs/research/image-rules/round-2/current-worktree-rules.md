# Human Rules in the current worktree at round 2 start

These headers do not identify the frozen gallery binary. Compare worktree-rule-delta.md.

## src/abi.zig

The C ABI (`include/cktimg.h`): a view over `Placed`, not a copy. Names
and wire points are handed out as pointers into the result's own arrays.

Human Rules: none of its own; it hands out `Placed` (placed.zig) and
the name anchors of geom.zig.

What changed from cktImg's, and why (docs/API.md): classes are added to
a library the caller owns, in one call per class, instead of through a
process-global begin/pin/register builder; placement is told which
library and settings to use; roles gave way to terminal flags.

A null handle or an out-of-range index is safe everywhere: null, 0 or
false, never a trap — this is a trust boundary.

## src/actual_anchor.zig

Actual symbol anchors for cold local placement owners.

Human Rules:
- actual_anchor.1 (invariant) Reanchoring changes the device grid and
  recomputes visible outward reach from every actual terminal. It does
  not rewrite the caller's class or electrical pins. Shared CT banks
  anchor midpoints/drains; their private chains anchor path ends/midpoints.

Contents:
- `pub fn move(s: *sch.Schematic, nl: *const netlist.Netlist, d: u32, offset: library.Pt) void`
- `pub fn representable(s: *const sch.Schematic, nl: *const netlist.Netlist, d: u32) bool`

## src/actual_lead.zig

Actual attached block leads -> a verified outward world side.

Human Rules:
- actual_lead.1 (invariant) A visible cardinal terminal must attach to
  its own single closed body at the first boundary reached. Every body
  point/disk lies behind the tip; actual direction agrees with metadata.
  Bias peers and paired-output tanks share this cold frame certificate.
  No family, label or bounding-box proximity substitutes for attachment.

Data: borrowed class strokes and one u8 pin index (device pin-count
width) in; optional Side out. No allocation, retained state or hot-path
dispatch. This is the exact second-use extraction of bias leadSide.

Contents: `leadSide`, private projection.

## src/analysis.zig

Every analysis ngspice accepts as a dot-command, with the parameters it
needs besides the devices themselves.

Human Rules: none of its own; it holds what a deck asks a simulator,
which no drawing shows.

Source of truth: ngspice `src/spicelib/parser/inp2dot.c` (master, 2026)
and the ngspice manual, chapter "Analyses". Syntax in each doc comment
uses `<...>` for optional fields.

Node and device references are already resolved to ids, so a simulator
never looks a name up again. Names that don't exist are rejected by the
parser, not discovered halfway through a simulation.

Not included, on purpose:
  * `.hb` (harmonic balance): compile-time experimental (`WITH_HB`),
    undocumented. The parser reports `error.UnsupportedAnalysis`.
  * Transient noise: not a command; it is enabled by `trnoise`/`trrandom`
    source functions and runs inside `.tran`.
  * `.four`, `.meas`, `.print`, `.save`: post-processing/output requests
    on another analysis's results, not analyses.

## src/antiparallel.zig

Unique antiparallel diode-connected MOS/BJT channels.

Human Rules:
- antiparallel.1 (habit, bounded) Same-kind, same-known-polarity channels
  on reversed distinct nonrail ends, each control tied to its own first
  end, form a local pair only when no third same-kind channel spans those
  ends. All eight selected source devices in AG739/1048/1052/1149 lie
  flat, on separate rows, controls outward, with matched spatial net
  order. AG1149 staggers their columns; one common column is a placement
  choice, not a universal source relation. `find`
- antiparallel.2 (invariant) An existing valid gate/base face left/right
  request retains upright classification, so this inferred habit cannot
  invalidate a formerly honoured caller request. The relations owner
  still admits and applies it; malformed requests give no exemption.
  Other caller constraints retain their ordinary owners. `directed`, `held`

Data: existing CSR, model/role rows and hints in; one optional typed
device handle or a cold precedence predicate out. No arrays, allocation,
retained state or new hot structure. A query reads at most one endpoint's
incidence slice; callers use their existing canonical device passes and
joint chain/slot scratch. Placement remains serial because slots collide.

Contents: `find`, `directed`, `held`, `frame`, `placedMate`, then tests.

## src/bias_neighbors.zig

Private amplifier bias peers, placed from their actual symbol frames.

Human Rules:
- bias_neighbors.1 (habit, bounded) Seven source reference amplifiers
  place an isolated BIAS/BIAS_CIRCUIT peer beyond the bias lead, with
  opposing collinear leads and its whole body outward. AG2444 permits
  touching tips. AG2440's extra VC drives local controls and excludes
  it; a valid circuit need not follow this case. See
  docs/research/bias-block-neighbors.md. `find`
- bias_neighbors.2 (invariant) Count every declared pin incidence before
  drawn state or geometry. The peer has VDD/VSS, one NB/VBN, optional
  VB1/VB2, and no other ports. Rails match the amplifier. Other peer
  bias ports have one incidence and an external terminal role. Source
  evidence uses literal DUT ports; flattened engine decks retain only
  Role.isPort, so this is the explicit engine projection. `find`
- bias_neighbors.3 (choice) Keep the amplifier fixed; turn the whole
  peer and try outward positions beyond occupied symbol/terminal room.
  Actual class origins, tips and strokes determine the relation, never
  a guessed below-row or a rewritten library class. This does not copy
  source upward amplifier biases or every other peer port side. `place`
  Hollow circles and solid disks both belong wholly behind the tip.
- bias_neighbors.4 (invariant) Admitted cells, relations, faces, fixed
  origins including weak stays, definition sides and mates take
  precedence, including admitted members of a relaxed caller group.
  Different shelves abstain. Failed frames/placements
  restore all peer fields. Existing cells remain untouched. `collect`
- bias_neighbors.5 (invariant) The single generic compaction pass keeps
  successful actual-tip order; equal tips already share a track. Each
  class remains rigid, so its outward body stays outward. `orders`

Data: existing netlist/CSR, roles, hints and settled classes in; one
cold 12-byte certificate per possible amplifier out, then existing
peer orientation/grid-position writes. Handles are u32, port indices
u3 (complete contracts have at most eight ports). Collection reserves
once from the block count; the caller frees it. No per-device role
cache, callbacks or retained state. Attempts follow canonical rank.
This is bounded block-layout work, outside routing/cost inner loops;
no speed or no-residue claim is made.

Contents:
- `pub const Pair = struct`, `Batch`, `Batch.deinit`
- `pub fn collect(gpa: Allocator, nl: *const Netlist, s: *const Schematic, sk: *const Skeleton, st: *const Structure, ats: []const ?pinned.At) Allocator.Error!Batch`
- `pub fn place(s: *Schematic, nl: *const Netlist, sk: *const Skeleton, ats: []const ?pinned.At, len: Lengths, at: [][2]f32, pairs: *std.ArrayList(Pair)) void`
- `pub fn orders(s: *const Schematic, pairs: []const Pair, storage: [][2]i32) [2][]const [2]i32`

## src/block_input_place.zig

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

## src/block_symbols.zig

Recognized subcircuit glyphs shared by native drawings and Schemify.

Human Rules:
- block_symbols.1 (choice) A known amplifier or logic gate uses its
  conventional glyph when every named port has an unambiguous role.
  AG807/750/806 show amplifier/comparator triangles; AG1044/438/1070/1076
  show inversion bubbles and logic gates. An unfamiliar name or extra
  control stays a box: AG1070's charge pumps and AG1677's VA port.
  `identify`
- block_symbols.2 (invariant) A glyph preserves every SPICE port, in
  order, including supply pins. Inputs enter left, output exits right,
  supply above and ground below. A caller symbol or explicit side hint
  takes precedence in the caller. `draw`
- block_symbols.3 (choice) A fully differential amplifier retains two
  signed outputs (AG479/782). The default places positive output above
  negative: seven of twelve source glyphs cross input/output signs.
  Port order and electrical identity never change. `identify`, `draw`
- block_symbols.4 (habit) An otherwise complete amplifier with named
  VB1/VB2/VB3 bias pins retains its triangle (85 of 85 source instances,
  including AG1561/1661/1700/2223). Bias pins remain separate below the
  body; an unknown control such as AG1677's VA still keeps a box.
  `identify`, `draw`
- block_symbols.5 (choice) Known opamp/comparator families, including
  `comp`, may declare one input: 47/47 source glyphs retain a triangle
  with the matching minus, plus or unsigned input (AG1401/1432/1422).
  A complete single-input contract creates no missing second pin.
  Unknown controls, duplicate roles and mixed input contracts stay boxes.
  `identify`, `draw`
- block_symbols.6 (choice) Exact AMP/AMP1/CMP/EA family names with the
  same complete port contract use triangles: all 24 selected source
  glyphs agree (AG2553/2550/1367/1237). AMP1 is a whole name, not a
  prefix. ZCD remains a source box.
  Shape/sign evidence does not certify cached source pin coordinates.
  docs/research/block-aliases.md; `identify`
- block_symbols.7 (choice) Generic comp/comparator/CMP triangles are
  plain: 15/48/6 source instances have no interior step. The explicit
  ICM_IDEAL_COMPARATOR_VDD retains its step (AG806/809). AG1390's source
  box and AG1398's missing plus mark remain named disagreements; neither
  creates an instance-specific rendering exception. Appearance does not
  infer electrical function. figures/comparator_strokes.py; `identify`
- block_symbols.8 (choice) Exact A1/EA1/AEA names use triangles only
  with the same complete contract: all 39 selected source glyphs agree.
  Named polarity survives declaration order; AG2423 has only a negative
  input. Unknown controls remain boxed, including AG1752's extra Z.
  Every declared port remains present despite omitted source VSS ink.
  docs/research/remaining-amplifiers.md; `identify`, `draw`
- block_symbols.9 (choice) Exact AEA/ERRORAMP/ERROR_AMPLIFIER/ERROR_AMP
  reference contracts use unsigned triangles: all 15 source glyphs
  agree. VREF enters left; OUT/VEA leaves the apex. Optional VDD/VSS
  and one VB1/VBN/NB bias keep distinct leads. Unknown controls and
  ERRAMP remain boxes; AEA without VREF retains its signed contract.
  Declared VSS survives absent source ink; supply/bias side exceptions
  do not change the canonical glyph. docs/research/reference-amplifiers.md;
  `identify`, `draw`

- block_symbols.10 (order: signal) Complete amplifier and reference
  contracts expose their unique output to placement. The 21 selected
  source banks face that output; contextual VEA belongs only to the
  complete reference shape. Digital, differential and opaque contracts
  supply no such certificate. docs/research/driven-banks.md; `analogOutput`
- block_symbols.11 (choice) Exact CT_INDUCTOR with N1/N2/N3 retains
  two open windings, a filled midpoint and the N3 tap: 19 source glyphs
  and 57 bindings. All three pins are passive; rule 2's input/output
  sides concern active glyphs. Unknown, duplicate or extra ports remain
  boxed. Canonical orientation does not predict source world facing.
  docs/research/center-tap-symbols.md; `identify`, `draw`

Cold, bounded work: at most eight ports, once per registered symbol
or participating placement candidate.
The caller owns the arena and the existing terminal/DrawOp tables.

Contents:
- `pub const Shape = enum(u8)`
- `pub const Drawing = struct`
- `pub fn identify(name: []const u8, ports: []const []const u8) Shape`
- `pub inline fn analogOutput(name: []const u8, ports: []const []const u8) ?u3`
- `pub fn draw(arena: Allocator, shape: Shape, ports: []const []const u8, pitch: i32) Allocator.Error!Drawing`

## src/block_tanks.zig

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

## src/bridges.zig

Bridges (issue #8, stage 3): where each horizontal device stands, in
the channels between the columns. In: the netlist, its roles and
structure, and the vertical devices' cells and rows. Out: each bridge's
cell.

Human Rules:
- bridges.1 (book) Flat two-pin parts and MOS channels in series,
  joined by nets that hold just the two current paths (gates and bodies
  aside), lie in one row as a chain, in their order along the nets.
  AnalogGenie ag-738 and ag-995 put the MOS and its compensation
  capacitor together between stages. `chainOf`
- bridges.2 (unmeasured) Any other flat device except a transistor
  (an op-amp, a part with
  a side pin) is a chain of one whose ends are its first and its last
  net that is no rail: its input and its output, as a subcircuit lists
  its ports, not the supply its first port is often on. `chainOf`
- bridges.3 (unmeasured) A chain lies evenly between two columns, its
  first member nearest the first column, each half the other's mirror
  image; what varies is the two columns and the row (bridges.4 to
  bridges.12). `chainSlots`
- bridges.4 (unmeasured) The two columns are the nearest pair of
  distinct columns, one on each end net (ties: the leftmost), when the
  gap holds the chain and no column stands between them, or no column
  is on both end nets. `chainSlots`
- bridges.5: retired; the case of bridges.15 where the driven gates
  stood in one column and no column was on the block's first net.
- bridges.6 (unmeasured) Else the chain stands beside the column on both
  end nets (or on either), one slot past its own, toward the axis when
  an end net lies on the axis. `chainSlots`
- bridges.7 (order: signal) Else, with an end on an input, left of that
  column: what drives stands left of what reads. `chainSlots`
- bridges.8 (unmeasured) Else away from the axis: right of the column
  with no axis, or for a column on the axis. `chainSlots`
- bridges.9 (unmeasured) Beside one column, the member whose end is on
  the column stands next to it. `chainSlots`
- bridges.10 (unmeasured) The chain's row is the tap row of its first
  end that has one: the channel just below the lowest device ending on
  the net from above, else just above the highest below. `chainSlots`
- bridges.11 (habit) With no channel ending on either end net, the
  chain takes the row of the one gate an end is on, its wire straight
  into the gate (else a chain of one takes any pin's tap row). People:
  597 of 1,198 such nets of 5,263 hand-drawn schematics have the flat
  part level with the gate it joins. `chainSlots`
- bridges.12 (book) A chain between two columns whose row a column
  between them runs through lies under the drawing, a row past the
  lowest devices, as the book draws a second stage's CMFB resistors
  under the circuit; the code names no figure. `outside`
- bridges.13 (unmeasured) A chain whose every member's mate stands
  already is that chain's mirror image about the axis. `place`
- bridges.14 (choice) Where a slot is taken, the whole chain moves out,
  away from the axis (right with none), one lattice column at a time:
  a cell holds one device. Chains are placed in rank order. `place`
- bridges.15 (order: signal) A block with a port named as an input or
  an output stands in the signal's order, as a column does: left of
  the leftmost column with a gate its output drives, level with that
  gate, and right of the rightmost column on an input's net left of it
  when none stands between the two; with no gate to drive, right of
  the rightmost column on an input's net. Before bridges.4 to .8.
  People: 266 of 320 blocks whose output drives a gate stand left of
  every such gate, and 522 of the 590 that drive none stand right of
  every upright device on their inputs' nets, in 5,263 hand-drawn
  schematics. Complete reference-amplifier contracts also resolve VEA
  as an output (AG2427); generic port roles stay unchanged. `passage`
- bridges.16 (order: signal) A flat transistor bridges its channel's
  two nets. Its gate and body do not select its columns: the signal
  crosses the channel, as in AnalogGenie ag-385 and ag-386. `chainOf`
- bridges.17 (habit) A flat complementary transmission pair shares one
  column, NMOS above PMOS, rather than becoming a series chain. Both
  source pairs selected by forms.19 (ag-386, ag-751) do so. Spatial
  instructions applied afterward take precedence. `place`
- bridges.18 (habit) A converter's inductor and its unique main PMOS
  at each end share one row in channel order, despite shunts on the
  intermediate nets. All 252 selected source coils lie between those
  switches; 243 share their exact row. Nine have a small offset on one
  switch (named in the power-path study). Ambiguous branches and an
  upright instruction keep the ordinary placement. `power_paths.series`
- bridges.19 (habit, bounded) A certified converter path stands above
  its grounded external-gate shunts and active gate drivers, before
  the generic outside-column fallback. A block whose named output
  drives one main switch stands below that switch in its column:
  all 75 source outputs are below the path. Actual SVG output leads
  align with the driven gate in 67 cases (all 75 cached terminals do),
  but this pass aligns lattice columns; exact output-pin
  alignment needs the later symbol geometry. An occupied cell moves
  the block downward.
  No order is imposed on unrelated bias devices; explicit deck
  instructions run afterward. `power_paths.controlBounds`, `power_paths.blockTarget`
- bridges.20 (habit, bounded) A unique externally controlled ground
  shunt uses a free column between its certified main MOS and coil.
  All 353 source shunts fit that terminal interval; the 101 paired
  source rows already agree with the existing row placement. Keep
  that row and an already interior column. The placement choice is
  the midpoint rounded toward the main switch, then the nearest free
  interior column to that integer, toward the coil on a tie.
  No free column, an existing mate or an admitted order edge
  leaves the ordinary placement. Vertical row/above/order hints have
  already run here; cell instructions still run afterward. `place`
- bridges.21 (habit, bounded) The main path stands above its unique
  outer reservoirs' existing rows. All 359 source signal pins are at
  or below the main channel. Keep capacitor coordinates and raise the
  three-part path together; symbol spacing later reserves actual lead
  reaches. Mixed rows and final cells/at retain their later precedence.
  Multiple grounded caps or an explicitly flat cap give no row bound.
  `power_paths.reservoir`
- bridges.22 (habit, bounded) A certified antiparallel clamp pair takes
  two nearby rows with joint collision search, like a transmission pair.
  Source channels are flat on separate rows in all four selected circuits;
  one common column is a layout choice (AG1149's source is staggered).
  `antiparallel.find`

Contents:
- `pub fn place(gpa: Allocator, nl: *const Netlist, roles: []const Role, st: *const Structure, order: []const u32, drawn: []const bool, form: []const Form, upper: []const u32, lower: []const u32, rank: []const u32, mate: []const u32, order_pairs: []const [2]u32, axis2: ?i32, x: []i32, y: []i32) Allocator.Error!void`

## src/canvas.zig

What is drawn so far (issue #8, stage 4): every net's wires and points
over the placed devices, and the one way to add to them. In: a
`Schematic` whose devices are placed and pinned, and the devices'
boxes. Out: its routes, and terminal and label nodes.

Human Rules:
- canvas.1 (invariant) Every length is a whole number of target units,
  at least 1, rounded up from `config.Layout`: the drawing stays on
  integers and mirrors exactly. `Lengths.of`
- canvas.2 (invariant) A wire runs through no device's body, along no
  other net's wire, onto no other net's point (a pin from the start, a
  wire's end or bend, a symbol or a name), and ends on no other net's
  wire; it may cross one. `Canvas.fits`
- canvas.3 (habit) No other net's wire crosses the stub between a rail
  pin and its symbol: a person's symbol sits on its pin. People: 3 of
  16,030 such stubs in 5,263 hand-drawn schematics are crossed.
  `Canvas.wall`
- canvas.4 (unmeasured) A port, a rail symbol or a name stands at the
  end of a stub out from its pin, toward the first side asked whose stub
  fits (a name: the way its pin faces); where none fits, a name on the
  pin itself. `Canvas.markAt`
- canvas.5 (unmeasured) An input's or output's port goes out toward the
  side a `port` line asks, else the side given, else up, else down: the
  first whose stub neither runs along the net's own wire nor ends on it
  (the node between two parts in series has its port off the line).
  `Canvas.port`
- canvas.6 (invariant) A port whose stub does not fit is a name at its
  point, or at the net's top-left pin where another net's wire crosses
  that point: a name never joins two nets. `Canvas.port`
- canvas.7 (choice) A net's name, where it has no better place, goes on
  its topmost, then leftmost, pin: a place, so the order of the cards
  chooses nothing. `topLeft`
- canvas.8 (invariant) A polyline is committed whole: reserve its route,
  segment and point rows before changing any length. Allocation failure
  leaves the existing drawing intact. `Canvas.commit`

Contents:
- `pub const Lengths = struct`, `Lengths.of(layout: config.Layout, unit: i32) Lengths`
- `pub const Canvas = struct`, `Canvas.Checkpoint`
- `Canvas.init(gpa: Allocator, s: *Schematic, xy: *std.ArrayList([2]f32), len: Lengths, boxes: []const Rect, hidden: []const maze.Mark) Allocator.Error!Canvas`, `Canvas.deinit(c: *Canvas) void`
- `Canvas.commit(c: *Canvas, net: u32, pts: []const Pt) Allocator.Error!bool`, `Canvas.fits(c: *const Canvas, net: u32, a: Pt, b: Pt) bool`
- `Canvas.wall(c: *Canvas) void`
- `Canvas.leaf(c: *Canvas, kind: sch.NodeKind, net: u32, at: Pt, faces: Side) Allocator.Error!void`
- `Canvas.stub(c: *Canvas, kind: sch.NodeKind, net: u32, from: Pt, side: Side, d: i32) Allocator.Error!bool`, `Canvas.markAt(c: *Canvas, kind: sch.NodeKind, p: u32, toward: []const Side, d: i32) Allocator.Error!bool`
- `Canvas.labelAt(c: *Canvas, p: u32) Allocator.Error!void`, `Canvas.port(c: *Canvas, net: u32, from: Pt, side: Side) Allocator.Error!void`, `Canvas.onNet(c: *const Canvas, net: u32, at: Pt) bool`
- `Canvas.middle2(c: *const Canvas) i32`
- `Canvas.save(c: *const Canvas) Checkpoint`, `Canvas.restore(c: *Canvas, cp: Checkpoint) void`
- `pub const Line = struct`, `Line.of(pts: []const Pt) Line`, `Line.push(l: *Line, p: Pt) void`, `Line.slice(l: *const Line) []const Pt`
- `pub fn pinAt(s: *const Schematic, p: u32) Pt`, `pub fn topLeft(s: *const Schematic, pins: []const u32) usize`
- `pub fn stepPt(p: Pt, side: Side, d: i32) Pt`
- `pub fn linesFit(c: *const Canvas, net: u32, lines: []const Line) bool`
- `pub fn ways(s: *const Schematic, pins: []const u32, lines: []const Line, at: Pt) u4`

## src/cells.zig

The deck's `cell` lines (steering rung 3): a device's lattice cell, in the
skeleton's own frame (before it shifts the drawing to start at 0, so
moving one device renumbers nothing). In: the skeleton's cells as the
rest of placement leaves them. Out: the named devices on their cells, the
devices they displaced on the nearest free cell of their row, the mates
no longer mirrored dropped, and a verdict per line.

Human Rules:
- cells.1 (invariant) `cell <dev> <col> <row>` puts the device on that
  lattice cell; the engine's own cells give way. `apply`
- cells.2 (choice) Of `cell` lines on one cell or one device, the
  strongest stands and the rest are dropped, blocked by it: the deck's
  own ranking of its lines. `apply`
- cells.3 (choice) A device a line displaces moves to the nearest free
  cell of its row, right before left: moving as little as possible.
  `put`
- cells.4 (unmeasured) A `cell` line on one of a mated pair puts the
  unnamed mate on the mirror cell (the core stands about x = 0 here),
  unless a stronger line holds that cell. `apply`
- cells.5 (invariant) Mates a line moved off each other's mirror cell
  are drawn as mates no more. `apply`

Contents:
- `pub fn apply(gpa: Allocator, arena: Allocator, nl: *const Netlist, drawn: []const bool, mate: []u32, x: []i32, y: []i32, verdicts: []?Verdict) Allocator.Error!void`

## src/center_tap.zig

Bounded source-derived center-tapped winding, built once per class.

Human Rules:
- center_tap.1 (invariant) N1/N2 are the outer ends; N3 leaves their
  connected midpoint. All 19 source glyphs retain two open, looped
  winding paths and one filled dot. No ordinary inductor or transformer
  is inferred from the subcircuit name. `draw`
- center_tap.2 (choice) At pitch 20 the integer winding is within
  0.702219516315 source units of the measured cubic point-set in both
  directions. This bound covers winding ink only; radius 4 approximates
  the source 3.77907 dot, and AG1190 has longer outer leads. Other pitches
  add integer rescaling error. figures/center_tap_curves.py; `draw`

Data: the cold caller supplies three port names, terminal storage and
its arena/list. This owner fills the ordered terminals and appends seven
operations; two 61-point slices live in the same arena. Coordinates use
one immutable signed-byte table, not per-instance retained metadata.
The table count is bounded by the renderer's 64-point capacity. Likely
curve, lead and dot changes stay here; recognition stays in block_symbols.
No placement scan, dispatch abstraction or runtime speed claim is added.

Contents:
- `pub fn draw(arena: Allocator, ports: []const []const u8, pitch: i32, terminals: []lib.Terminal, ops: *std.ArrayList(lib.DrawOp)) Allocator.Error!void`

## src/checks.zig

The drawing's guarantees, checked on a finished `Placed` alone, however it
was drawn (docs/research/steering.md §6), and what each `*@` line means
read off a drawing. In: a `Placed` and its library (or its netlist and
one line). Out: findings, each naming its rule, its net, a point, and
what else it involves; the drawing code never produces one, so a finding
is a bug in it, or in a caller's edit between the stages. And for a
line: whether the drawing shows it, or null when no drawing can.

Human Rules:
- checks.1 (invariant) Every net with two or more shown pins is one
  piece as a netlister reads it: wires join where their points meet, a
  name written on a wire names it, and a net's names, ports, rails and
  ground-reference pins join by name. `connected`
- checks.2 (invariant) No wire runs through or onto another net's point
  (a pin, a label, a wire's end or bend); crossing another net's wire
  between its points is allowed. `shorts`
- checks.3 (invariant) A dot stands exactly where a net leaves a point
  in three or more directions (a pin's lead toward its device one way),
  nowhere else, and never two at one point. `dots`
- checks.4 (invariant) No net crosses its own wire without a dot there.
  `dots`
- checks.5 (choice) `row`, `above` and `order` read off device origins:
  a `row` on one y, `above` y growing down the list, `order` x growing
  along it: the meaning the report holds each honoured line to.
  `drawnAs`
- checks.6 (choice) `face` reads off the pin: left or right of its
  device's origin, or above or below the other end of its path: the
  meaning the report holds each honoured line to. `drawnAs`
- checks.7 (choice) `label` holds when the net has a name written or no
  wire, `wire` when the named devices' pins on the net are one piece by
  wires alone, `port` when a port symbol on the net stands past all its
  devices' pins on that side: the meaning the report holds each honoured
  line to. `drawnAs`
- checks.8 (choice) `at` holds when the device's origin (and turn) is
  the one asked, `route` and `via` when every point asked (and for
  `route`, every point between them) lies on the net's wires: the
  meaning the report holds each honoured line to. `drawnAs`

Not a guarantee, and not looked for: a wire through a symbol. In 129 of
the engine's drawings of the 5,263 reference schematics, 242 pieces of
another net's wire run through a symbol's box, 236 of them through a
ground symbol.

Contents:
- `pub const Rule = enum`, `pub const Finding = struct`
- `pub fn find(gpa: Allocator, out: *std.ArrayList(Finding), p: *const Placed, lib: *const Library) Allocator.Error!void`
- `pub fn connected(…)`, `pub fn shorts(…)`, `pub fn dots(…)`: each rule group alone
- `pub fn ways(p: *const Placed, n: usize, at: Pt) u4`, `pub fn crossing(a: Pt, b: Pt, c: Pt, d: Pt) ?Pt`
- `pub fn drawnAs(p: *const Placed, nl: *const Netlist, h: hints.Hint, unit: i32) ?bool`
- `pub fn deviceIn(p: *const Placed, name: []const u8) ?usize`

## src/clamp_anchors.zig

Actual channel-ended anchor frames -> one local antiparallel placement.

Human Rules:
- clamp_anchors.1 (habit, bounded) A unique MOS clamp between two
  complementary drain-ended stacks lies strictly inside their four drain
  tips. AG739/1048/1052 supply three actual source examples; AG1149 has
  only one external channel per end and is excluded. Count channel-end
  competitors before polarity, visibility or geometry. `find`
- clamp_anchors.2 (choice) Try one midpoint candidate, with separate
  channel rows spaced by the actual boxes and configured stack distance.
  No lattice rows or other devices move. Unsupported frames, admitted
  caller constraints, external mates, styles or collisions abstain for
  the whole pair. An inferred mirror's diode reference can move here;
  inferred reciprocal mates can move together. Honoured caller mirror
  and symmetry lines still own placement. Only the two positions
  commit. `collect`, `place`
- clamp_anchors.3 (invariant) Preserve initially strict actual terminal
  inequalities through the existing compactor. No wire or label rule
  changes, and no source-distance or shared-column claim follows. `orders`

Data: CSR/model rows, settled symbols, admitted hints and positions in;
two coordinate writes and cold order requests out. Each 24-byte group
has six typed u32 handles, read together once per draw. At most half the
device count are candidates; sixteen i32 coordinate pairs per success.
Caller-owned buffers live only through drawValid; allocation precedes
mutation. Placement is serial because proposals share collision space.

Contents: Group, Batch, Batch.deinit, collect, place, orders;
private queries and tests.

## src/coil_bank_place.zig

Actual frames and atomic placement of the two linked CT banks.

Human Rules:
- coil_bank_place.1 (habit, bounded) The two winding axes and capacitor
  share an actual midpoint; capacitor and ground-return NMOS devices
  lie successively outside the winding columns, opposite the taps.
  Drains bracket the winding ends, gates point inward and sources out.
  AG1180's two banks share exact reflection. `turn`, `proposal`
- coil_bank_place.2 (choice) Keep the existing actual reflection axis
  and bank side. Try one compact paired frame at the old winding row,
  outside the occupied central devices. This single declared candidate
  has body-derived spacing, not measured source distances. A collision
  or unsupported actual frame restores all ten device rows; coordinates
  commit only after all checks. Caller-owned classes never change.
  `place`, `attempt`
- coil_bank_place.3 (invariant) Anchor winding/cap coordinates at their
  actual midpoint and MOS coordinates at the actual drain. Equality
  then shares a compaction track. Preserve initially strict terminal
  inequalities and the verified actual reflection axis through the
  existing generic compactor. `orders`, `axis`

Data: cold 56-byte certificates and settled device rows in; ten poses
and bounded coordinate orders out. Stack scratch holds ten old rows and
ten candidate points. No allocation or retained state during placement;
every fallible collection precedes this transaction. One candidate per
owner, eight orientations per member; this is not a routing hot loop.

Contents:
- `pub fn place(s: *sch.Schematic, nl: *const netlist.Netlist, sk: *const skeleton.Skeleton, ats: []const ?pinned.At, len: Lengths, at: [][2]f32, pairs: *std.ArrayList(Pair)) void`
- `pub fn orders(s: *const sch.Schematic, pairs: []const Pair, storage: [][2]i32) [2][]const [2]i32`
- `pub fn axis(s: *const sch.Schematic, pairs: []const Pair) ?i32`

## src/coil_banks.zig

Paired reciprocal-MOS tanks with two center-tapped windings per bank.

Human Rules:
- coil_banks.1 (habit, bounded) AG1180 contains two mirrored banks, each
  with two parallel CT contracts, one capacitor and two reciprocal
  ground-return NMOS devices. This is one figure, not two independent
  samples. Count all candidates before visibility or frame filtering;
  third windings, extra capacitors and ambiguous active pairs abstain.
  coil_network.findBank; docs/research/center-tap-chains.md
- coil_banks.2 (invariant) Own both banks together only when their exact
  structural mates close over all ten members and corresponding nets.
  Contained automatic cross groups are compatible; admitted caller
  groups, global grouping off, poses, relations, sides and outer-net
  styles win for the whole owner. No private mate is cleared. `collect`

Data: CSR/contracts, roles, structural mates and admitted requests in;
cold 56-byte paired certificates out. Five typed device handles, two
u2 port maps and one u1 end index make each 28-byte bank. All fields are
consumed together by once-per-draw placement, outside routing loops.
At most CT-count/4 owners; caller-owned buffers are reserved before any
geometry write and freed after drawing. Canonical ranks order collision
decisions. No retained flags or copied net table; no speed claim.

Contents:
- `pub const Bank`, `Pair`, `Batch`, `Batch.deinit`
- `pub fn collect(gpa: Allocator, nl: *const Netlist, s: *const sch.Schematic, sk: *const skeleton.Skeleton, st: *const structure.Structure, ats: []const ?pinned.At, lines: *const netlines.NetLines) Allocator.Error!Batch`

## src/coil_bridges.zig

Four direct/cross switches between already placed paired CT banks.

Human Rules:
- coil_bridges.1 (habit, bounded) AG1180 puts corresponding-end switches
  on the two drain rows and the crossed pair vertically in the upper
  half, at distinct mirrored columns. This is one correlated figure;
  topology alone does not choose the upper half. The complete two-chain
  context is required. docs/research/center-tap-chains.md; `collect`
- coil_bridges.2 (invariant) Own only four switch poses, after the bank
  owner succeeds. All four card pins and the whole caller class remain
  intact. The source certifies path contacts, not control positions.
  Any held member or colliding candidate restores all four. `attempt`
- coil_bridges.3 (choice) Two reflected direct-switch poses keep the
  same path endpoints; full-body collision chooses the control side.
  Body-derived crossed columns clear the direct switches. Tips stay within
  the inner winding interval and the crossed lower tips above its
  midpoint. No routing or crossing-budget exemption follows. `orders`

Data: existing CSR, exact mates, frames and successful bank key in;
cold 24-byte four-device owners out. One per parent bounds collection;
each stores five typed handles and four u1 end choices. Caller reserves
24 order slots per owner before writes. Four stack rows provide rollback.
Two candidates/eight poses per member each; outside routing hot loops.

Contents:
- `pub const Owner`, `Batch`, `Batch.deinit`
- `pub fn collect(gpa: Allocator, nl: *const Netlist, s: *const sch.Schematic, sk: *const skeleton.Skeleton, st: *const structure.Structure, ats: []const ?pinned.At, parents: []const banks.Pair) Allocator.Error!Batch`
- `pub fn place(s: *sch.Schematic, nl: *const Netlist, sk: *const skeleton.Skeleton, ats: []const ?pinned.At, len: Lengths, at: [][2]f32, parents: []const banks.Pair, owners: *std.ArrayList(Owner)) void`
- `pub fn orders(s: *const sch.Schematic, parents: []const banks.Pair, owners: []const Owner, storage: [][2]i32) [2][]const [2]i32`

## src/coil_chain_place.zig

Actual-frame placement of the two private CT coupling chains.

Human Rules:
- coil_chain_place.1 (habit, bounded) In AG1180, each C-S-C path is
  straight and ordered between the inner winding columns, outside its
  corresponding drain row. Both chains reflect about the banks' actual
  axis. All four switch card pins remain electrical pins; the source
  exposes only two path contacts. `attempt`, `turn`
- coil_chain_place.2 (choice) Try one body-derived row outside each
  complete bank envelope. Banks and other devices stay fixed. Actual
  cap outer tips and switch path midpoints anchor the grid; caller
  classes are unchanged. Any incompatible frame or body collision
  restores all six rows before coordinates commit. `attempt`
- coil_chain_place.3 (invariant) Preserve only initially strict actual
  tip orders in the existing compactor. Shared path rows/outer columns
  already use identical grid tracks; the bank owner retains reflection.
  No wiring, style or crossing-budget exemption is added. `orders`

Data: cold 36-byte owners and surviving bank keys in; six poses and at
most ten x/two y orders out. Stack scratch holds six old rows/points.
One candidate and eight orientations/member bound placement; caller
allocated all capacity before mutation. This is not a routing hot loop.

Contents:
- `pub fn place(s: *sch.Schematic, nl: *const netlist.Netlist, sk: *const skeleton.Skeleton, ats: []const ?pinned.At, len: Lengths, at: [][2]f32, parents: []const banks.Pair, owners: *std.ArrayList(Owner)) void`
- `pub fn orders(s: *const sch.Schematic, parents: []const banks.Pair, owners: []const Owner, storage: [][2]i32) [2][]const [2]i32`

## src/coil_chains.zig

Private capacitor-switch-capacitor paths between paired CT banks.

Human Rules:
- coil_chains.1 (habit, bounded) AG1180 has two private C-S-C paths
  between corresponding outer ends of its two mirrored CT banks.
  Exactly one path per end and all four direct/cross switch contexts
  qualify. Count every private incidence, including hidden/control
  loads, before visibility. This is one figure, not a general switch
  rule. docs/research/center-tap-chains.md; `topology`
- coil_chains.2 (invariant) Own only six chain devices; the banks are
  read-only anchors. Exact capacitor mates and self-mated switches,
  whole-owner caller precedence and unique membership are required.
  A successful bank list may compact, so retain its typed first-coil
  handle rather than a transient list index. `collect`

Data: complete netlist, existing bank certificates, exact mates and
admitted requests in; cold 36-byte six-device owners out. One per bank
pair bounds both allocations. Six u1 choices identify actual path ends;
no copied net table or active flags. All fields are read together once
per draw outside routing. Canonical parent order determines attempts.
Caller frees both buffers; all allocation precedes geometry mutation.

Contents:
- `pub const Owner`, `Batch`, `Batch.deinit`
- `pub fn topology(nl: *const Netlist, roles: []const sch.Role, pair: banks.Pair) ?Owner`
- `pub fn held(nl: *const Netlist, sk: *const skeleton.Skeleton, st: *const structure.Structure, d: u32) bool`
- `pub fn collect(gpa: Allocator, nl: *const Netlist, s: *const sch.Schematic, sk: *const skeleton.Skeleton, st: *const structure.Structure, ats: []const ?pinned.At, lines: *const netlines.NetLines, parents: []const banks.Pair) Allocator.Error!Batch`

## src/coil_network.zig

Cold contracts for the paired center-tapped resonator network.

Human Rules:
- coil_network.1 (habit, bounded) AG1180 has two reciprocal NMOS tanks,
  each with two parallel CT windings and one capacitor; two private
  C-S-C chains and four direct/cross switches join them. Count every
  candidate before choosing. This is one source figure, not a general
  LC network rule. docs/research/center-tap-chains.md; `findBank`, `chains`
- coil_network.2 (choice) When exactly one complete two-bank context
  exists, request its whole-network reflection before the generic
  maximum-moved-device choice. The graph search must prove all original
  pin bindings and admitted caller constraints; failed requests fall
  back to ordinary search. No terminal-equivalence rule changes.
  `preferred`; structure.mates

Data: netlist incidence/contracts, roles and canonical ranks in; cold
immediate typed-handle certificates out. Existing bank/chain/bridge
placement and structure analysis share these pure bounded scans. Twelve
device-pair requests cover twenty distinct members in 96 stack bytes.
There is no allocation, class geometry, retained state or hot dispatch.
Multiple complete bank contexts abstain from this preference; source
selection does not license moving a held member downstream.

Contents:
- `pub const Bank`, `Pair`, `Chain`, `Bridges`, `Reflection`
- `pub fn ports(nl: *const Netlist, edge: EdgeId) ?[3]u2`
- `pub fn findBank(nl: *const Netlist, roles: []const sch.Role, rank: []const u32, coil: EdgeId) ?Bank`
- `pub fn chains(nl: *const Netlist, roles: []const sch.Role, pair: Pair) ?Chain`
- `pub fn bridges(nl: *const Netlist, roles: []const sch.Role, pair: Pair) ?Bridges`
- `pub fn preferred(nl: *const Netlist, roles: []const sch.Role, rank: []const u32) ?Reflection`

## src/coil_tanks.zig

Unique center-tapped coils and their parallel tank capacitors.

Human Rules:
- coil_tanks.1 (habit, bounded) A capacitor directly across N1/N2 is
  parallel to the winding, centered along it, opposite N3, with matched
  net ends. Nine actual source pairs have these relations and eighteen
  continuous conductor legs. Five have a unique coil owner; AG1180's
  two capacitors each serve two coils and remain outside this rule.
  See docs/research/center-tap-tanks.md. `find`
- coil_tanks.2 (choice) Keep the coil's world pose. Try one nearby
  capacitor position from actual class bounds and the existing spacing,
  then nearest-first quarter-unit steps through one additional symbol
  unit. This bounded room search is a placement choice, not a source
  distance rule. Failure restores every capacitor field. Only center-aligned,
  opposing two-ended frames qualify; no cached class is rewritten.
  Caller placement, groups, mates, sides and net styles win. `collect`,
  `place`
- coil_tanks.3 (habit, bounded) A unique semantic tank stays on one
  shelf, including when its custom frame declines geometric placement.
  Existing cell/strong-at and relation precedence is unchanged. This
  does not reserve a shelf's empty rows or exempt a wire from thinning.
  `spans`
- coil_tanks.4 (invariant) Actual midpoint anchors share one compaction
  track; an initially strict perpendicular order keeps the capacitor
  opposite the tap. Submit to the existing single compaction pass.
  `orders`

Data: netlist/CSR, classes and admitted hints in; typed 12-byte pairs
and capacitor poses out. All pair fields are read together. At most one
per drawn block; indices are u2/u1, coordinates i32. Two caller-owned
buffers last through this drawing only. Canonical order serializes
collision decisions; recognition is a cold once-per-block collection,
outside cut-cost and routing loops. No performance claim is made.

Contents:
- `pub const Pair`, `Batch`, `Batch.deinit`
- `pub fn find(nl: *const Netlist, coil: EdgeId) ?Pair`
- `pub fn spans(gpa: Allocator, nl: *const Netlist, drawn: []const bool, x: []const i32, previous: []const [2]i32) Allocator.Error!std.ArrayList([2]i32)`
- `pub fn collect(gpa: Allocator, nl: *const Netlist, s: *const Schematic, sk: *const Skeleton, st: *const Structure, ats: []const ?pinned.At, lines: *const netlines.NetLines) Allocator.Error!Batch`
- `pub fn place(s: *Schematic, nl: *const Netlist, sk: *const Skeleton, ats: []const ?pinned.At, len: Lengths, at: [][2]f32, pairs: *std.ArrayList(Pair)) void`
- `pub fn orders(s: *const Schematic, pairs: []const Pair, storage: [][2]i32) [2][]const [2]i32`

## src/columns.zig

Column order (issue #8, stage 3): where each column of devices stands.
In: the columns (devices top to bottom), each device's mate, the
netlist and roles. Out: each column's x, device columns at least two
apart so a channel lies between neighbours.

Human Rules:
- columns.1 (habit) A net pulls its columns together when a column's
  current path ends on it, whatever its role (an internal net or an
  output always); a bias or an input only gates read, or a rail, pulls
  none. People: of the nets on exactly two columns, the two stand next
  to each other for 1,719 of 2,316 with a path's end on both (74.2%;
  bias or input 103 of 137), 304 of 733 of gates alone (41.5%, a random
  order 35%), 232 of 950 rails (24.4%), in 5,263 hand-drawn schematics.
  `wiredNets`
- columns.2 (unmeasured) Mated columns are the core: one of each pair
  on the left, its mate its mirror image on the right. `order`
- columns.3 (choice) Of two mated columns, the one nearer, along current
  paths, the lowest-ranked mated device stands in one half and its mate
  in the other: one reference keeps each half whole. Which half stands
  left is the row's to say (columns.13). `assignSides`
- columns.4 (habit) A column whose current path meets a path of each
  half stands on the axis (a pair's tail, a start-up device between
  the halves); one that meets them through gates alone (a reference
  that biases both, a stage that reads both), or that the symmetry
  merely maps to itself, is a free column of the row. People: 1,297 of
  1,630 devices whose path meets both of a mated pair's stand between
  the two (183 of 204 tails; a tendency for the rest, 830 of 1,117);
  of 418 that meet the halves through gates, through mated parts or
  not at all, 311 stand off the axis (148 of the 180 through gates
  outside the pair), in 5,263 hand-drawn schematics. `joinsBoth`
- columns.5 (habit) Of two columns that would share the axis on one
  row, a pair's tail keeps it. People: 91.9% of 347 such devices in
  5,263 hand-drawn schematics stand between the pair's two. `order`
- columns.6 (invariant) At most one column stands on the axis at any
  row; the others, by rank, go free. `order`
- columns.7, .8, .9, .11: retired; columns.13 is the rule they were
  cases of (a free column on the side of the half it shares more nets
  with: people 1,172 of 1,716; one on an output right, 577 of 760, any
  other left, 1,403 of 2,618; a circuit with no core in one row).
- columns.10 (invariant) No free column stands between the core's mated
  columns: the core is one item of the row. People: 6,003 of 6,781 free
  columns stand clear of the core (5,198 beside it, 805 over or under
  it) in 5,263 hand-drawn schematics. `lay`
- columns.12 (choice) Each half of the core, then the row, tries every
  order up to `exhaustive_max` (6) columns, else moves one column at a
  time up to `move_reach` (12) places for `move_rounds` (16) passes; of
  equal orders the one nearer rank order stands: a bound on the work.
  `best`
- columns.13 (order: signal) The columns stand in one row, the core as
  one of them, in the order span.2 then span.1 give: the fewest pins
  left of what drives them, then the narrowest wired nets. A second
  stage stands right of the pair that drives it, a bias generator left
  of what it biases, and of the core and its mirror image the one with
  fewer such pins stands. People: 1,036 of the 1,200 hand drawings with
  a core that differ from their mirror image in those pins face the way
  with fewer; a free column the core drives stands right of it in 599
  of 843, one that drives the core left in 303 of 418; two free columns
  a wired net joins stand on one side in 5,238 of 6,102. `order`

Contents:
- `pub const Columns = struct { start: []const u32, devices: []const u32 }`, `Columns.count(c: Columns) u32`, `Columns.of(c: Columns, k: usize) []const u32`
- `pub const Ctx = struct`
- `pub fn order(gpa: Allocator, nl: *const Netlist, roles: []const Role, cols: Columns, column_of: []const u32, mate: []const u32, partner: []const u32, rank: []const u32, row: []const u32) Allocator.Error![]i32`

## src/compact.zig

Compaction (stage 4, after the wires): the empty room of a wired drawing
taken out, along x toward the mirror axis (the left edge when there is
none), then along y toward the top. In: a wired `Schematic`. Out: the
same drawing closer together: nothing reordered, nothing on one line
taken off it, every symbol rigid, every stub its length.

Human Rules:
- compact.1 (book) The drawing is as close together as its lengths
  allow, along x toward the mirror axis (the left edge when there is
  none), then along y toward the top: one-dimensional constraint-graph
  compaction, each coordinate a **track** brought as near the anchor as
  its constraints allow (a longest path, by relaxation). Lengauer,
  "Combinatorial Algorithms for Integrated Circuit Layout", 1990,
  ch. 10. `squeeze`
- compact.2 (invariant) Nothing changes row, column or order: what is
  on one track stays on it, and two things that would touch sliding
  past each other keep their order. `pass`
- compact.3 (invariant) Every symbol is rigid, and every stub keeps its
  length: a wire ending on a port, a symbol or a name, and a rail's wire
  to its bar or symbol no longer than `rail` (a longer one, up from a
  lower row, is a wire like any other). `read`
- compact.4 (choice) Two things that would touch keep the smaller of
  the gap they have and `clearance`, and a wire between two symbols,
  bends or junctions keeps `tap`: the lengths are `config.Layout`'s.
  `pass`
- compact.5 (habit) Two devices keep their order, and `series` (along
  x) or `stack` (along y) between their symbols only where they stand
  less than `stack` (`series`) apart across the axis: a pair's halves
  close over its tail, a tall block stands beside the stack it joins.
  People: neighbouring columns 1.98 units apart at the mean in 5,263
  hand-drawn schematics; with `series` between every two, 2.95. `pass`
- compact.6 (invariant) A mirrored drawing stays mirrored: the two
  coordinates equally far from the axis are one track, and a pair
  across the axis halves the room between them. `Graph.keep`
- compact.7 (choice) Everything moves by whole quarter units: what was
  on the quarter-unit grid stays on it. `Graph.raise`
- compact.8 (invariant) Nothing moves away from the anchor: the drawing
  as it stands satisfies every constraint. `Graph.solve`
- compact.9 (invariant) Caller-supplied coordinate inequalities keep
  the smaller of a quarter unit and their existing positive gap. They name
  terminal orders across distant rows or columns without teaching the
  compactor circuit topology. Equal coordinates already share a track.
  `pass`

Contents:
- `pub fn squeeze(gpa: Allocator, s: *Schematic, len: Lengths, axis2: ?i32, orders: [2][]const [2]i32) Allocator.Error!void`

## src/config.zig

The `lint.zon` settings file, three tables:

- `.layout`: the drawing's lengths and the router's costs
  (docs/ALGORITHM.md §4);
- `.rules`: one severity per lint rule (`lint.zig`);
- `.render`: colours and line widths for the TikZ emitter.

Lengths are in units, one unit being a two-pin symbol from pin end to pin
end. Every key is optional; an absent key keeps its default, and an
unrecognized key or a malformed value is reported, never fatal — failing
to draw a schematic over a typo in a style file is the wrong trade. Keys
of the wire-first layout whose rules went with it (`min_pitch`,
`junction`, `bend`) are reported as unknown.

```zon
.{ .layout = .{ .stack = 1.5 }, .rules = .{ .no_ground = .err }, .render = .{ .wire = "000000" } }
```

Human Rules:
- config.1 (habit) By default, two devices in series in one column
  stand half a unit apart or more, and the trunk that pins facing one
  way meet on half a unit from its pin. People: 18,863 of the 20,127
  pairs in series in one column of 5,263 hand-drawn schematics stand
  half a unit apart or more, half a unit the commonest gap (30.2%); a
  pin's first piece of wire to a corner or a T is half a unit at the
  median, and the commonest (38.5% of 90,607). `Layout.stack`,
  `Layout.tap`
- config.2 (habit) Neighbouring columns stand one unit apart or more.
  People: 30,907 of 35,678 neighbouring columns (86.6%), 1.75 units at
  the median. `Layout.series`
- config.3 (habit) A supply bar is one of the two forms people draw:
  by default a named rail running past its outer pins, its ends T's and
  not corners, no symbol on it (people 1,255 of 1,370 named bars); off,
  a bar carrying its symbol and ending on its outer pins (1,083 of 1,140
  bars with a symbol). `Layout.rail_past`
- config.4 (habit) An input or output port, and a net label, stands
  half a unit from its pin. People: 15,113 of 16,816 ports stand half a
  unit or more from the pin or wire they join (three quarters at the
  median); their net labels name no net, so a label's distance is not
  in the hand drawings. `Layout.terminal`, `Layout.label`
- config.5 (choice) A wire keeps a quarter unit from another net's wire
  or point: the router's room, so two nets never read as one.
  `Layout.clearance`
- config.6 (choice) A bend costs the router one unit of wire, a
  crossing of another net's wire two: weights that trade length for
  fewer bends and crossings. `Layout.bend_cost`, `Layout.cross_cost`
- config.7 (habit) A drawing is closed up: its empty room taken out
  toward the mirror axis and the top, down to the lengths above.
  People: nine in ten of their neighbouring columns stand 4.0 units
  apart or less, and of their devices one under the other 3.5 (35,678
  and 27,035 pairs); the engine's own stand 5.25 and 5.25.
  `Layout.compact`
- config.8 (habit) One internal net's wire crosses at most three wires
  of other nets (rails aside); a net crossing more is joined by name,
  its near pins still wired. People: of the 4,567 wires that cross
  another net's, 4,417 cross at most three (4,232 at most two); three
  writes about as many names as they do (10,492 against their 11,371
  over 5,263 hand-drawn schematics; two writes 12,241).
  `Layout.cross_max`
- config.9 (habit) A row of the drawing holds eight device columns
  before it wraps into rows of columns, one under the other, unless a
  `*@ shelf` line says otherwise. People: 4,444 of 5,274 hand drawings
  are at most eight columns wide; drawn so, 5,263 reference circuits
  are as wide as their hand drawings at the median. `Layout.shelf`
- config.10 (choice) Wires are drawn blue (`1565c0`) 1.5 pt wide,
  symbols 1.2 pt: the TikZ emitter's own style. `Render`
- config.11 (choice) A rail symbol stands half a unit from its pin.
  People: on the pin itself in 10,885 of 18,313 rail symbols (6,883 of
  8,367 on a two-pin part's end, 3,612 of 8,921 on a transistor's), half
  a unit away in a third. `Layout.rail`

Contents:
- `pub const Layout = struct`, `pub const Render = struct`
- `pub const Config = struct`, `Config.default`
- `Config.parse(arena: Allocator, text: []const u8, diags: ?*std.ArrayList(Diagnostic)) Allocator.Error!Config`
- `Config.load(arena: Allocator, io: std.Io, dir: std.Io.Dir, path: []const u8, diags: ?*std.ArrayList(Diagnostic)) Allocator.Error!Config`
- `pub const Diagnostic = struct`, `Diagnostic.Kind`

## src/csr.zig

Data-oriented bipartite hypergraph.

Human Rules: none of its own; a container of nets and devices that
serves every stage's rules.

A hypergraph H = (V, E) is stored as its bipartite incidence graph:
one side holds vertices, the other holds hyperedges, and an incidence
(e, v) says "vertex v is a member of hyperedge e".

For circuits: vertices are nets, hyperedges are devices, and an edge's
member list is its *pin list*. Order is meaningful (position = terminal
role, e.g. d/g/s/b) and repeats are allowed (bulk tied to source), so
member lists are stored exactly as given, never sorted or de-duplicated.

Layout decisions (see the notes at the bottom of the file):
  * Topology and payload are split. Topology is two CSR arrays (hot);
    user payload lives in `MultiArrayList`s (SoA, touched only on demand).
  * Every reference is a typed `u32` index, never a pointer.
  * Both directions are materialised (edge -> vertices, vertex -> edges),
    so every bulk operation is a *pull*/gather: linear reads, no scatter,
    no write conflicts, trivially parallelisable.
  * Two-phase lifecycle: an append-only `Builder`, then an immutable
    `Graph`. The frozen graph has no dirty flags or branches for
    "not yet built" state (existence-based processing).

Tested with Zig 0.16 (`zig test csr.zig`).

## src/ct_controls.zig

A center-tapped common-base bias stage's local control connection.

Human Rules:
- ct_controls.1 (habit, bounded) AG1114's two NPNs share C/B; their
  emitters meet one CT's outer ends. Exactly two resistors complete B's
  incidence, one to the tap and one to supply. Its actual B leads share
  straight ink. This is ONE figure: common-collector pairs alone have
  55 connected and 295 separated source examples. Count raw candidates
  and all incidences before visibility/polarity/frame eligibility. `find`
- ct_controls.2 (choice) Only for an automatic cut, keep this pair in
  one local part when their actual visible bases face along a clear row.
  A projected pin, intervening own pin, obstacle, or explicit net route
  or first request abstains. Ordinary partitioning, trunk competition,
  whole-part fallback and subsequent crossing cuts remain unchanged.
  Deferred routes/vias still exclude scaffold grouping.
  No device moves and no caller class or pose is rewritten. `adjacent`

Data: immutable full CSR/contracts/roles and current Canvas in; zero or
one pair of indices into its existing net-pin slice out. A cold 20-byte
certificate holds all five member handles, read together.
It lives on the stack during one cut-net query, outside pair/DSU loops;
counts are bounded by four base incidences and one emitter's adjacency.
No new allocation, retained table, distance option or performance claim.
Source proof: docs/research/ct-common-controls.md.

Contents:
- `pub fn adjacent(c: *const Canvas, nl: *const Netlist, net: u32, pins: []const u32, lines: *const NetLines, requests: Requests) ?[2]u32`

## src/ct_feedback_stage.zig

One complete CT/NPN feedback stage -> an actual source-oriented frame.

Human Rules:
- ct_feedback_stage.1 (bounded observation) AG1149 alone supplies the
  nine-member NPN/antiparallel/reciprocal-C/private-L stage in the full
  source census. Count complete incidences and raw alternatives before
  roles, visibility or frames. Source: docs/research/ct-feedback-stage.md.
- ct_feedback_stage.2 (choice) Keep the old actual coil center x. Make
  one body-spaced horizontal-tap-up / emitter-down proposal above the
  foreign body band. No foreign row, class or routing policy changes.
  Eight actual poses per member; unsupported frames or collisions undo
  all nine rows. No search, lattice insertion or source distance rule.
  The actual base, feedback-inner and bias-control columns progress
  inward in that order; the bias body fits before the center track.
- ct_feedback_stage.3 (boundary) Admitted member requests and every
  touched net's style/port/route/first win, including tap and substrate.
  Exact mates and scenes with automatic blocks abstain; the latter
  protects unexposed propagated column mates. The source has neither.
- ct_feedback_stage.4 (invariant) Actual anchors share real coordinate
  tracks. Initially strict lead orders enter the existing one-pass
  compactor. Five source wire trees remain independent requirements.

Data: borrowed CSR/classes/requests in; cold nine-EdgeId records out,
36 bytes read together once per draw. At most one per complete CT;
thirty i32 order pairs per success. Caller-owned two-buffer lifetime
ends after drawing; allocations precede mutation. Nine old rows and
candidate points are bounded stack scratch. No hot-loop/speed claim.
Candidates run in canonical order: earlier commits change the foreign
obstacle table, so this placement pass is deliberately sequential.

Contents: Group, Batch, Batch.deinit, collect, place, orders; private.

## src/ct_four_place.zig

One whole26 source world frame -> atomic actual placement and orders.

Human Rules:
- ct_four_place.1 (bounded observation) The one source scene has inward
  CT taps, upper sources up/lower sources down, and two upright outer
  reciprocal pairs with horizontal bypasses above. Center-tail controls
  both face left; electrical reflection is not full pin reflection.
  The immutable oracle is tests/ct_four_sides.zig, all72 visible leads.
- ct_four_place.2 (choice) One body-bounded proposal and eight actual
  rigid poses per member. Shared spans/offsets must agree; unsupported
  frames abstain. Keep the old upper midpoint x; translate once above
  foreign bodies. No search or routing change. All26 rows roll back;
  coordinates commit only after all325 pairs and foreign bodies clear.
- ct_four_place.3 (invariant) Midpoints and D/near anchors are actual
  existing tracks. Append only initially strict actual-pin inequalities
  from fixed semantic lists into the single compactor. No ghost tracks.

Data: the cold104-byte group is borrowed. Fixed26-row/point/box scratch
lasts one attempt. Order capacity is the sum of adjacent pairs in the
two literal pin-list tables; caller allocates before any mutation.
No hot abstraction, cache mutation or runtime-residue claim.

Contents: order_capacity, place, axis, orders; private.

## src/ct_four_sides.zig

Complete paired CT/LCL/four-MOS-bank scene -> one cold placement owner.

Human Rules:
- ct_four_sides.1 (bounded observation) The full 2936-deck census has one
  complete 26-member case. Directed bypass channels distinguish upper
  and lower tanks. Count all raw candidates and all90 pin incidences
  before known-NMOS, rail, visibility or caller eligibility. No name,
  value or figure ID selects it. Source: docs/research/ct-four-sides.md;
  source geometry and all148 physical partitions are independent tests.
- ct_four_sides.2 (boundary) Exact mates, admitted member requests,
  external block members and touched-net styles/ports/routes abstain.
  Fully contained automatic blocks remain; ordinary first-net ordering
  and rail representation retain their existing owners. `collect`
- ct_four_sides.3 (choice) Protect the whole semantic column span from
  a shelf cut only. A later unsupported actual frame still declines;
  there is no unsafe partial LCL fallback or row-gap reservation. `spans`

Data: borrowed CSR/roles/admitted requests in; one cold [26]EdgeId
certificate out (104 bytes, all handles consumed together per phase).
The one-scene source scope admits exactly one raw candidate; no flags,
nets or frames are retained. Caller owns two buffers for one draw;
allocation precedes mutation. Recognition is outside cut-cost/routing
loops. No hot-path, runtime-residue or performance claim is made.

Contents: Group, Batch, Batch.deinit, collect, spans, ports, binding; private.

## src/ct_four_wires.zig

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

## src/ct_mirror_controls.zig

One complementary-mirror CT oscillator stage supplies an actual interval.

Human Rules:
- ct_mirror_controls.1 (bounded observation) AG1146's complete seven
  members have two straight actual mirror-gate intervals. Select the
  output mirror only: two opposite-polarity two-MOS diode mirrors,
  exact bridge/load incidences, two reciprocal load MOS and one CT.
  This is one figure; broad mirror or control preferences are unsafe.
  Source: docs/research/ct-mirror-controls.md.
- ct_mirror_controls.2 (choice) Nominate its complete actual opposing
  gate interval only for automatic internal-net routing. Explicit
  styles/ports/routes/first, hidden/projected or nonopposing frames
  abstain, including routes deferred until after compaction.
  This supplies a tie witness, never a cost credit or wire.

Data: borrowed immutable netlist/current canvas in; optional two actual
points out. The cold stack Stage holds seven typed EdgeIds (28 bytes),
all read for visibility once outside candidate loops. No allocation,
retained flags, distance option or performance claim. Local CSR scans
count all incidences before polarity/frame filters; no source-ID rule.

Contents:
- `pub fn interval(c: *const Canvas, nl: *const Netlist, net: u32, pins: []const u32, lines: *const NetLines, requests: Requests) ?[2]Pt`

## src/ct_series_tanks.zig

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

## src/device.zig

The device model every stage reads (issue #8): what a device of a kind
is to its card and to a drawing. In: a device kind, a card's letter, a
model type. Out: which of its pins do what.

Human Rules:
- device.1 (invariant) A device's pins are its SPICE card's, in card
  order: the two its current passes through (its **path**), a gate or
  base, a body, a **control** pair (ngspice manual, ch. 2 to 11).
  `of`
- device.2 (invariant) A gate, a body and a control pair pass no
  current: no current path of the drawing runs through them. `carries`
- device.3 (order: potential) A device with a path stands upright with
  its two ends on two rows, or lies flat between two columns. `of`
- device.4 (habit) A transistor's gate (a base) leaves its path
  sideways: on an upright one it points left or right. People: 28,715
  of the 30,349 transistors of 5,263 hand-drawn schematics stand
  upright, each with its gate left or right. `of`
- device.5 (order: signal) A device whose path its gate, its control
  pair or a named source's current sets stands right of what drives
  that control. `reads`
  Narrowing: a source a named source sets (F, H) is left out, as a
  part is; the general form admits it. The hand drawings cannot tell:
  of their 50 such sources 2 stand in a drawing with the source they
  name (one right of it, one left).
- device.6 (order: potential) A source that feeds a load stands with
  its low end down: a voltage source's minus, the pin a current source
  draws from. `lowEnd`
- device.7 (order: potential) An upright transistor has the end of its
  path nearer the supply on top: a p-type's source (its emitter), an
  n-type's drain (its collector). `sourceUp`
- device.8 (choice) A transistor whose `.model` card gives no type is
  p-type when its model's name holds `pmos`, `pfet`, `pnp`, `pjf` or
  `pch` or starts with `p`, n-type likewise: the name is all the deck
  says. `polarity`
- device.9 (choice) A block, a transmission line (T, O, U), a B source
  and a coupling (K) have no path, so none stands between two rows:
  the table gives them none, and a block's ports go by their names
  (`library.portRole`). No hand drawing holds a `B` source to compare.
  `of`

Contents:
- `pub const DeviceKind = enum(u8)`, `pub const Pins = struct`, `pub const max_nodes`
- `pub const Source = enum(u8) { none, independent, controlled }`
- `pub const Control = enum(u8) { none, pair, named }`, `pub const Polarity = enum(u8) { n, p, other }`
- `pub fn of(kind: DeviceKind) Pins`, `pub fn ofLetter(letter: u8) ?DeviceKind`
- `pub fn isTransistor(kind: DeviceKind) bool`, `pub fn isPart(kind: DeviceKind) bool`
- `pub fn carries(kind: DeviceKind, pin: usize) bool`, `pub fn reads(kind: DeviceKind) bool`
- `pub fn lowEnd(kind: DeviceKind) u8`, `pub fn sourceUp(pol: Polarity) bool`
- `pub fn polarity(model: ?[]const u8) Polarity`

## src/dots.zig

Junction dots: where a drawing marks that wires meet. In: a laid-out
`Schematic`'s routes and pins. Out: the points, each once, rounded to the
target's units.

Human Rules:
- dots.1 (habit) A dot stands wherever one net's wires leave a point in
  three or more directions, a device's lead counting as one: a four-way
  meeting as much as a T; never where two nets' wires only cross.
  People: a dot at 41,668 of 43,009 points where three wires of a net
  meet and at all 1,330 where four meet (3% of their dots), in 5,263
  hand-drawn schematics. A pin two wires leave is not in that count:
  the drawings hold dots only between wires, and people run two wires
  from 3,194 of 127,232 pins. `find`
- dots.2 (choice) Where a net's level wire crosses one of its own upright
  wires, the two join there with a dot: an undotted crossing reads as two
  nets crossing. People draw six such crossings in 5,263 schematics.
  `find`

Contents:
- `pub fn find(gpa: Allocator, out: Allocator, s: *const Schematic) Allocator.Error![]Pt`

## src/forms.zig

Forms and ends (issue #8, stage 3): which devices are drawn, which stand
upright in a column and which lie flat between columns, and each upright
device's upper and lower end. In: the netlist, its roles and structure;
for `crooked`, a laid skeleton. Out: `drawn`, `form`, `upper`, `lower`;
the flat parts to stand upright after all.

Human Rules:
- forms.1 (choice) A card with no pins is not drawn: it has nothing to
  draw. A driver (`sch.isDriver`) is not drawn either, by that file's
  rule, unless a `driver` line says so. `classify`
- forms.2 (book) The book's ideal amplifier, an `E` with its low output
  on a ground and a gain of a thousand or more (`E1 out 0 inp inn 1e5`),
  is drawn as a box, the op-amp's triangle with its inputs wired, not as
  a part current passes. The code names no figure. `isAmplifier`
- forms.3 (habit) A dependent source (every `G`, and an `E` that is no
  ideal amplifier) is drawn with two terminals, its control pair no part
  of where it stands. People: 414 of 414 in 5,263 hand-drawn
  schematics. `isDependent`
- forms.4 (unmeasured) A transistor stands upright, except a shorted
  channel (forms.12), a capacitor-coupled MOS channel (forms.19), or a
  source-degeneration bridge (forms.20). Converter paths are forms.21.
  `classify`
- forms.5 (unmeasured) A part with an end on a rail stands upright, a
  capacitor too. `classify`
- forms.6 (unmeasured) A part in series, each of its nets holding just
  one other channel element, stands upright; not a capacitor.
  `classify`
- forms.7 (habit) A part on the way down (one end nearer the supply,
  the other nearer the ground, counted through channel elements, never
  through a gate or another rail) stands upright; not a capacitor.
  People: 262 of 305 such resistors and 18 of 24 diodes in 5,263
  hand-drawn schematics. `classify`
- forms.8 (habit) A current source stands upright wherever it is.
  People: 76 of 83 current sources wherever they are, in those
  drawings. `classify`
- forms.9 (habit) A dependent source stands upright wherever it is.
  People: 398 of 414 in those drawings. `classify`
- forms.10 (unmeasured) A capacitor stands upright only with an end on
  a rail: in series or on the way down it lies flat. `classify`
- forms.11 (unmeasured) A part between two nets the symmetry swaps
  lies flat across the axis, whatever forms.5 to forms.9 say; a
  transistor does not. `classify`
- forms.12 (unmeasured) A device whose current path is shorted (a MOS
  dummy, both ends on one net) lies flat, a transistor too. `classify`
- forms.13 (order: potential) A transistor's upper end is set by its
  type: an n-type's drain is its upper end, a p-type's source.
  `ends`
- forms.14 (order: potential) An upright part's upper end is its end on
  the supply, else the end away from its end on ground, else the end
  fewer channel elements from the supply (ties: its first pin). `ends`
- forms.15 (habit) A flat part between two nets that both hold an
  upright device's pin stands upright, and the drawing is laid again,
  when not both nets have such a pin level with the part within a device
  column: flat, its wire would turn a corner. People: the wire leaves
  both pins of a flat part straight for 44.9% of 4,443 in 5,263
  hand-drawn schematics (12.6% of the 6,171 laid flat here), and people
  stand 55% to 62% of the parts between two such nets upright. `crooked`
  Narrowing: only a part whose card names its two path pins alone
  (`isTwoEnded`); one with a side pin (a control pair, a diode's third
  pin) lies as a block does.
- forms.16 (unmeasured) A flat part with a net no upright device is on
  (an input's, an output's, a block's) stays flat. `crooked`
- forms.17 (book) Two mated parts that meet (a pair of sense resistors
  on the axis) lie across it, as the book draws them; the code names no
  figure. `crooked`
- forms.18 (unmeasured) In a circuit of parts, no transistor and no
  block, no flat part is stood up: its series parts lie along its top
  wire. `crooked`
  Narrowing: a line (`T`, `O`, `U`), a `B` source and a coupling are no
  block here (`isPartsOnly`).
- forms.19 (habit) A MOS channel with distinct drain, source and gate,
  neither channel end on a rail, lies flat when an end meets a capacitor
  and either the channel cannot reach a rail through DC paths, or no
  other DC path ends at that capacitor node and the opposite channel
  end drives another gate/base or a block's named input. A capacitor
  across the channel, from gate to channel, or shorted gives no evidence.
  A gate and body give no path to a rail.
  This includes samplers (ag-385, ag-386) and series compensation
  (ag-738, ag-995), including named block inputs (ag-782), but not an
  ordinary loaded cascode. People: 315 of 319 selected MOS in 2,202
  AnalogGenie drawings lie flat; 20 of 23 in the 734 AMSNet drawings.
  Upright reset and clamp devices are exceptions
  (ag-1039, ag-1054); an `upright` line wins. Evidence and named exceptions:
  docs/research/analoggenie.md. `classify`
- forms.20 (habit) A MOS joining two other MOS source nodes lies flat
  when all three have the same polarity and body rail, both channel
  ends have a direct DC path to that rail, and its gate has no incident
  DC path. Drain, gate and source are distinct on each device. The two
  gain devices have distinct drains and gates, with neither drain on
  the bridge. People: all six selected MOS in ag-769, ag-770, ag-771 and
  ag-954 lie flat; AMSNet has no qualifying examples. The gate condition
  excludes nine upright clamps (ag-2460 through ag-2468). Neither bridge
  end is a rail; an `upright` line wins. Evidence and scope:
  docs/research/analoggenie.md. `isDegeneration`
- forms.21 (habit) A recognized converter path lies horizontally
  through its switches and inductor. `power_paths` owns the conditional
  topology and evidence; its inductor keeps that form in `crooked`.
- forms.22 (habit, bounded) A complete flying-capacitor converter loop
  has two upright floating capacitors: input coil node above the lower
  node, and output above negative. Its divider stands downward and its
  return diode stays flat through `crooked`. All 145 selected source
  drawings agree. `power_loops` owns the topology, ambiguities and
  evidence; caller form/end instructions still run afterward.
- forms.23 (habit, bounded) A resistor from a private grounded voltage
  source to a distinct MOS gate stays flat through `crooked`. The whole
  source branch belongs at one driven gate's row; `input_resistors`
  owns the all-pin certificate and 22-case actual-source evidence.
  Placement chooses the anchor; caller forms and ends still win.
- forms.24 (habit, bounded) A unique antiparallel diode-connected MOS
  or BJT pair lies flat. All eight source devices agree; antiparallel
  owns the exact topology. A valid upright gate/base face request keeps
  the previous upright form; explicit forms still run afterward.

Contents:
- `pub fn classify(gpa: Allocator, nl: *const Netlist, roles: []const Role, st: *const Structure, drawn: []bool, form: []Form, verdicts: []?hints.Verdict) !void`
- `pub fn ends(gpa: Allocator, nl: *const Netlist, roles: []const Role, drawn: []const bool, form: []const Form, upper: []u32, lower: []u32) !void`
- `pub fn crooked(nl: *const Netlist, roles: []const Role, st: *const Structure, sk: *const Skeleton, column: i32, stood: []bool) bool`
- `pub fn isTwoEnded(nl: *const Netlist, d: u32) bool`, `pub fn isPartsOnly(nl: *const Netlist) bool`
- `pub fn isDependent(nl: *const Netlist, roles: []const Role, d: u32) bool`

## src/geom.zig

Answers every renderer of a `Placed` needs and must not work out on its
own: where a symbol's stroke lands, and where a device's name fits. Two
renderers that each placed their own names would disagree, so both the
C accessors and the TikZ emitter ask here (as in cktImg).

Human Rules:
- geom.1 (habit) A device's name stands on a side of its symbol no pin
  of it stands on, right before left, above before below: away from the
  gate of an upright transistor, right of an upright two-pin part, above
  one lying flat. Beside the symbol it is level with its origin, else a
  line above or below that; over or under it, centred. The sides with
  pins come after the others; the first spot clear of symbols, wires and
  the names placed before it, or the first spot tried when none is
  clear. People: 40,958 of 45,982 named devices in 5,263 hand-drawn
  schematics (89.1%); 25,038 of 27,139 upright transistors carry the
  name on the side away from the gate. `refdesAnchors`
- geom.2 (choice) A `*@ refdes` line's side is tried before the rest.
  `refdesAnchors`
- geom.3 (choice) Names are placed device by device, each clear of the
  ones before: one pass, so a renderer and the C accessors agree.
  `refdesAnchors`
- geom.4 (habit) A port's net name stands on the side away from the
  wire that meets it (a port whose wire leaves right is named on its
  left); right when no wire meets it. People: 13,814 of 15,521 port
  symbols one wire leaves, in 5,263 hand-drawn schematics; the side
  with no wire is the engine's own (people: left 784, right 348 of
  1,398). `nameSide`
- geom.5 (habit) A ground rail carries no name: the symbol says ground.
  Its name is written only to tell two grounds apart: in a drawing whose
  ground rails stand on two nets or more, and then not on net "0".
  People: 0 of 16,717 ground symbols in 5,263 hand-drawn schematics
  carry a name; of 436 drawings with two ground nets, 433 keep one as
  plain symbols and name the other. `namesRail`
- geom.6 (habit) A rail's net name stands on the first side of its
  symbol, right, left, above, below, that no wire of its net leaves:
  beside the bar of a rail on the end of a wire, above one standing on a
  bar's run. People: 4,531 of 6,169 supply names in 5,263 hand-drawn
  schematics stand beside the symbol's bar (73.4%, a tendency), 1,511
  above it. `railSide`

## src/hints.zig

A deck's `*@` lines (issue #7, docs/research/vocabulary.md): what the
circuit means and how it is drawn, stated by name, one line each:

    *@ [weak] <verb> <arguments>
    *@ group pair m1 m2        (also mirror, bank, stack, cross)
    *@ above m9 iss m7         m9 above iss above m7
    *@ face m3 g left          m3's gate on its left

Each stage applies the lines it owns and says what became of each;
`report` gathers the verdicts. What each verb draws is the rule of the
stage that owns it.

Human Rules:
- hints.1 (invariant) A `*@` line is drawn as it says, or the report
  says it was relaxed, dropped or rejected and why; none is dropped in
  silence. `Verdict`
- hints.2 (choice) A strong line outranks a stay (`weak`), and a later
  line an earlier one of the same strength: a deck is edited by adding
  a line. `admitOrder`, `applyOrder`
- hints.3 (invariant) Lines that set an order (one thing above or left
  of another) are drawn only while they close no cycle; the line that
  would is dropped, naming the stronger lines it conflicts with.
  `acyclic`, `conflict`

Contents:
- `Verb`, `Verb.grouping(v: Verb) bool`, `Verb.rung(v: Verb) u8`, `Verb.head(v: Verb, strength: enum { strong, weak }) []const u8`, `Verb.side(v: Verb, comptime T: type, word: []const u8) ?T`
- `Hint`, `Read`, `State`, `Code`, `Verdict`, `Verdict.of(code: Code) Verdict`, `Verdict.blocked(arena: Allocator, state: State, code: Code, by: []const u32) Allocator.Error!Verdict`
- `pub fn read(line: []const u8) ?Read`
- `pub fn collect(arena: Allocator, text: []const u8) Allocator.Error![]const Hint`
- `pub fn nesting(depth: u32, head: []const u8, open: []const u8, close: []const u8) u32`
- `pub fn admitOrder(arena: Allocator, list: []const Hint) Allocator.Error![]const u32`
- `pub fn applyOrder(gpa: Allocator, list: []const Hint) Allocator.Error![]const u32`
- `pub fn conflict(gpa: Allocator, arena: Allocator, check: anytype, admitted: []const u32, new: u32, code: Code) Allocator.Error!Verdict`
- `pub fn acyclic(gpa: Allocator, n: usize, edges: []const [2]u32) Allocator.Error!bool`
- `pub fn int(word: []const u8) ?i32`

## src/input_place.zig

Private voltage-source/resistor branches → a horizontal gate approach.

Human Rules:
- input_place.1 (habit, bounded) The resistor lies between its private
  grounded voltage source and one MOS gate, on that gate's row. The
  source stands outside it, signal above ground and at/below the gate
  row. All 22 source branches have these relations and continuous
  source legs; the same gate witnesses the straight resistor approach.
  Other gates and channel incidences on that net need not share its row.
  See docs/research/input-resistors.md and input_resistor_legs.py.
- input_place.2 (choice) Keep the MOS fixed and use two free adjacent
  cells on its gate side, the source two rows below. Canonical device
  order decides competing branches and breaks ties between available
  gates. Only a clear local rectangle qualifies; its span stays on one
  shelf. Actual terminal lines and
  extents are supplied by schematic.settleDevice and sketch.coordinates:
  their grid anchors align collinear R ends with the MOS gate, including
  shifted caller frames, without treating symbol origins as terminals.
- input_place.3 (invariant) Branch mates and honoured row/above/order/
  cell/face requests keep their placement. Incompatible forms/ends
  abstain. Explicit origins remain owned by sketch.keepAts.

Data: existing per-device cells, forms, ends, rank and admitted hints
in; only R/source cells and the R's semantic left end change. The cold
three-handle certificate is queried per resistor, with no retained
state. One protected interval per drawn resistor is the maximum; the
caller owns and frees that array. Capacity is reserved before writes.

Contents:
- `pub fn place(gpa: Allocator, nl: *const Netlist, roles: []const Role, order: []const u32, rank: []const u32, drawn: []const bool, form: []const Form, upper: []const u32, mate: []const u32, gate_right: []const bool, left_end: []End, x: []i32, y: []i32, verdicts: []const ?hints.Verdict, spans: *std.ArrayList([2]i32)) Allocator.Error!void`

## src/input_resistors.zig

Grounded input branches: existing graph, roles and drawn rows -> a
private voltage-source junction and the resistor's driven gate net.

Human Rules:
- input_resistors.1 (habit, bounded) A resistor between a private
  grounded voltage source and a distinct MOS gate lies flat at one
  driven gate's row. The upright source stands outside it, ground
  below and signal at or below that row. All 22 selected AG/AMS source
  drawings agree; 160 actual SVG leads and both local conductor legs
  are verified in docs/research/input-resistors.md.
- input_resistors.2 (scope) Count every pin on the private junction,
  including hidden devices, gates and bodies. Only the resistor and
  one independent voltage source may meet there. Both resistor ends
  are distinct and nonrail. A driven MOS has distinct D/G/S and known
  polarity. A BJT base or MOS source alone supplies no certificate:
  AG637:R1 and AMS114:RS are upright source counterexamples.
- input_resistors.3 (scope) Other pins may meet the gate net, and more
  than one gate may qualify. AG1082 has a channel load; AG477 has three
  driven gates but only one same-row straight local anchor. Placement
  chooses one gate for every geometric condition; this query chooses
  none. Explicit driver, form, face and placement requests keep their
  existing owners and precedence.

Data: at most one stack result per resistor; its three u32 handles are
existing graph indices consumed together. No new table or allocation.
Each query scans existing pin/incident rows; resistor queries share
read-only graph data, while callers own form and placement writes.

Contents:
- `pub const Branch = struct`
- `pub fn find(nl: *const Netlist, roles: []const Role, drawn: []const bool, resistor: u32) ?Branch`
- `pub fn isGate(nl: *const Netlist, drawn: []const bool, net: u32, d: u32) bool`

## src/json.zig

`Placed` as one JSON document — what the C ABI's `cktimg_json` streams for
a consumer that would rather parse one document than walk the accessors.
Same shape as cktImg's:

```json
{ "devices": [ { "name": "m1", "class": "nmos", "value": "nch", "rot": 3, "mirror": false,
                 "pos": [x, y], "pins": [ { "term": "d", "net": "out", "xy": [x, y] } ],
                 "bulk": "0" } ],
  "nets": [ "out", … ],
  "wires": [ { "net": "out", "segments": [ [ [x, y], [x, y] ] ] } ],
  "junctions": [ [x, y] ], "labels": [ { "net": "vb", "at": [x, y], "side": "left" } ],
  "no_connects": [ [x, y] ] }
```

Human Rules: none of its own; it writes `Placed`, whose rules are
placed.zig's and dots.zig's.

`pins` holds one entry per class terminal the card has. `bulk` is there
only when the card has one node past them (a MOS body on a three-terminal
symbol): its net, with no point, since the symbol draws no pin for it.
With two or more nodes past them (a dependent source's control pair on a
two-terminal symbol) the device has `"hidden": ["b", "0"]` instead, the
nets in card order.

Integers only; streamed, nothing allocated.

## src/latex.zig

CircuiTikZ emitter: a `Placed` as a `circuitikz` picture that `pdflatex`
draws. Compiled only with `-Dlatex_renderer=true` (`root.latex` is `void`
otherwise, so a stale reference names the missing option). Needs
`\usepackage[american]{circuitikz}`.

Human Rules:
- latex.1 (choice) A device whose class CircuiTikZ has a component for
  is drawn as that component: two-pin parts as `to[R]`, `to[C]`, …
  between their pins; rails, ports and dots as `vdd`, `ground`, `ocirc`
  and `circ`; any other class (a generated box, a subcircuit block) from
  its strokes: a paper figure in CircuiTikZ's standard symbols.
  `writeComponent`
- latex.2 (choice) A transistor or op-amp node takes the turn and mirror
  that best points each anchor at its pin, with a lead from the anchor
  out, then across onto the pin: the component is not the library
  symbol's size, and the wires still end on the pins. `writeComponent`
- latex.3 (choice) An op-amp is drawn as CircuiTikZ's only when nothing
  is wired to its reference pin, which that symbol lacks; else from its
  strokes. `writeComponent`
- latex.4 (habit) A rail's net name and a port's stand where `geom`
  puts them (geom.6, geom.4): a rail's beside its bar, or above it on a
  bar's run; a port's on the side away from its wire. People: 4,531 of
  6,169 supply names in 5,263 hand-drawn schematics stand beside the bar
  (a tendency), and 13,814 of 15,521 port names away from the wire.
  `write`

The one emitter inside the library, as in cktImg: a paper figure is a
user-facing feature, so it comes from the library a user links, not a
sample they vendor. Everything it needs to agree with other renderers —
placed strokes, name anchors — comes from `geom`.

Coordinates: one target unit is one point, and y is negated at the one
place points are written (`writePoint`), since TikZ's y grows upwards.
Streamed: nothing but the name anchors is allocated.

## src/lattice_geometry.zig

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

## src/levels.zig

Rows (issue #8, stage 3): each vertical device's level, top 0. In: the
netlist, its structure, each device's mate, form and ends. Out: one level
per device (unspecified for a device not drawn or not vertical).

Human Rules:
- levels.1 (order: potential) A device stands above another when its
  lower end is the other's upper end, and each device's row is the
  longest path down from the top; nothing stands on another through a
  rail. `rows`
- levels.2 (habit) A transistor whose gate is the only gate on the
  junction of two devices of one column takes a row between them, its
  gate level with the junction. People: 69% of 1,443 such gates in 5,263
  hand-drawn schematics. `rows`
- levels.3 (habit) Not when the lower device is a transistor of its type
  on the same rail: it keeps its row. People: 65% of 184. `rows`
- levels.4 (book) Nor when it is mated and the upper device is a
  transistor of its type on the same rail, as the book draws a fully
  differential second stage; the code names no figure. `rows`
- levels.5 (choice) A deck's `row` line holds devices level and its
  `above` line one over another, whatever else moves: the deck's word
  wins. `rows`
- levels.6 (choice) Where devices stand above each other in a loop (a
  transmission gate's two), only their column's links count: a loop has
  no longest path. `rows`
- levels.7 (unmeasured) Mates stand level, where that sets no device
  above itself. `rows`
- levels.8 (unmeasured) The upright members of a block other than a
  stack stand level, where that sets no device above itself. `rows`
- levels.9 (book) Each type's transistors on ground drop to that type's
  lowest row among them, as the book draws a second stage's current
  source beside the first stage's mirror; the code names no figure. A
  set held level drops only when every member stands on ground, and a
  drop that breaks a `row` or `above` line is undone. `rows`
- levels.10 (habit) A two-pin part on ground with nothing over it hangs
  under its net: a row below the lowest transistor whose gate the net
  drives, level with a device the net is the upper end of; mates hang
  level; a hang that breaks a line is undone. People: 72% of 1,642 such
  pins in 5,263 hand-drawn schematics are under the net; 27% here by
  longest path alone. `rows`
  Narrowing: a part with two pins on its card or a dependent source
  (`isFoot`); a switch and a three-pin diode keep their row.

Contents:
- `pub fn rows(gpa: Allocator, nl: *const Netlist, roles: []const Role, st: *const Structure, rel: *const Relations, mate: []const u32, below: []const u32, drawn: []const bool, form: []const Form, upper: []const u32, lower: []const u32) ![]u32`

## src/library.zig

Device classes: what each device looks like, supplied by the application.

A target (an SVG renderer, a TikZ figure, a Schemify plugin) registers one
class per primitive device kind it draws — terminal
anchor points and body strokes — and the layout reads pin sides and pin
reach from those anchors. Nothing about a symbol's size or shape is assumed
anywhere else. Recognized subcircuits have conventional fallback glyphs;
every other unsupported kind or block has a generated box.

## The canonical frame

Integer coordinates, origin at the device centre, y down. The principal
terminals sit on the x axis (a two-pin symbol at x = -20 and x = +20: one
`unit`, pin end to pin end); an auxiliary terminal (a gate, a base) sits off
it. A pin faces the side its anchor lies on — the larger of |x| and |y|
decides. The layout's horizontal form of a device is this frame as drawn;
its vertical form is the frame turned a quarter to the left (`Orient.left`,
schematic.14).

## Append-only

A `ClassId` never changes meaning: registration appends, a same-name
registration with the same terminals returns the existing id, and one with
different terminals is refused. Placed schematics hold ids, so an id that
moved would silently redraw old output.

Human Rules:
- library.1 (choice) A device whose kind has no registered symbol is
  drawn as a labelled box, its pins alternating left and right down
  it: something must draw it, and lint reports it. `classFor`
- library.2 (invariant) A transistor is drawn as the symbol of its type:
  `pmos` or `nmos`, `pnp` or `npn`, `pjfet` or `njfet` (device.8).
  `className`
- library.3 (choice) A block uses the caller's registered symbol first,
  else a recognized glyph with a complete named-port contract,
  else a generated box. Explicit side directives keep the box geometry.
  `blockFor`
- library.4 (order: potential) A generated block's supply port
  (`vdd…`, `vcc…`, `avdd…`, `dvdd…`, `vpp…`) stands on top, its ground
  (`gnd…`, `vss…`, `vee…`, `agnd…`, `dgnd…`, `0`) at the bottom, where
  no `*@` line of its definition places it (netlist.6): the names a
  net is a rail by (schematic.1, .2), read the same way. People: a
  supply port on top in 833 of 1,003 ports of the blocks of 5,263
  hand-drawn schematics, a ground below in 328 of 328, in the symbol's
  own frame (740 and 235 as drawn: the rest stand on blocks the person
  flipped). `defaultSide`, `spellings`
- library.5 (habit) A generated block's bias line `vb`, `vb1`, `vb2`…
  comes in from below; a `vbn` or `vbias` port stays left. People: a
  tendency, 413 of 674 such ports of 5,263 hand-drawn schematics (right
  114, top 74, left 73), and the type of the gates the line drives
  inside does not split them (298 of 421 below for p-type, 132 of 313
  for n-type); of the 64 other `vb…` ports 17 stand below, 32 right, 9
  left. `defaultSide`
- library.6 (habit) A generated block's output (`out…`, `vout…`, `vo`,
  `o`, `vop`, `von`, `vo+`, `vo-`) leaves on the right; every other
  port enters on the left. People: an output on the right in 960 of
  the 1,110 such ports of the blocks of 5,263 hand-drawn schematics and
  an input on the left in 1,741 of 1,887, in the symbol's own frame
  (905 and 1,665 as drawn); `vo` on the right in 12 of 17.
  `defaultSide`
- library.7 (habit) An amplifier block's inverting input stands above
  its non-inverting one, where no `*@` line of its definition places
  either. People: a tendency, 448 of the 678 blocks of 5,263
  hand-drawn schematics with both inputs on one upright side as drawn
  (152 of 179 where the output is fed back to the inverting input
  alone, 287 of 489 otherwise); a block's symbol cannot tell, the
  feedback is the circuit's. `blockFor`
  Narrowing: only between two left ports named as `portRole` reads
  them; `vin` is the inverting input only beside a non-inverting one;
  only a port's role reads a name in any case (`named`).
- library.8 (habit) A generated block's ports on a side stand one unit
  apart, centred on its middle: an even count stands half a unit either
  side of it. People: neighbouring ports stand a unit apart or less in
  1,535 of 1,670 gaps of the blocks of 5,263 hand-drawn schematics, the
  two ports of a two-port side in 1,137 of 1,261 (two units, a row left
  empty between them, in 13). `blockFor`

Contents (the geometry and `Class`; what follows them is not listed yet):
- `pub const Pt = extern struct`, `Pt.zero`, `Pt.add(a: Pt, b: Pt) Pt`, `Pt.sub(a: Pt, b: Pt) Pt`, `Pt.eql(a: Pt, b: Pt) bool`, `Pt.above(a: Pt, b: Pt) bool`, `Pt.transposed(p: Pt) Pt`, `Pt.round(p: [2]f32) Pt`, `Pt.toF(p: Pt) [2]f32`
- `pub const Rect = struct`, `Rect.intersects(a: Rect, b: Rect) bool`, `Rect.contains(r: Rect, p: Pt) bool`, `Rect.merge(a: Rect, b: Rect) Rect`, `Rect.point(p: Pt) Rect`, `Rect.fromCorners(a: Pt, b: Pt) Rect`, `Rect.translate(r: Rect, by: Pt) Rect`, `Rect.grow(r: Rect, d: i32) Rect`
- `pub const Orient = packed struct(u8)`, `Orient.r0`, `Orient.left`, `Orient.apply(o: Orient, p: Pt) Pt`, `Orient.applyRect(o: Orient, r: Rect) Rect`, `Orient.flipped(base: Orient, flip_x: bool, flip_y: bool) Orient`
- `pub const Side = enum(u2)`, `Side.opposite(s: Side) Side`, `Side.isHorizontal(s: Side) bool`, `Side.perpendicular(a: Side, b: Side) bool`, `Side.flipX(s: Side) Side`, `Side.flipY(s: Side) Side`, `Side.transposed(s: Side) Side`, `Side.unit(s: Side) Pt`, `Side.vec(s: Side) [2]f32`, `Side.of(p: Pt) ?Side`
- `pub const Class = struct`, `Class.shows(c: Class, i: usize) bool`, `Class.side(c: Class, i: usize, o: Orient) ?Side`, `Class.box(c: Class, o: Orient, origin: Pt) Rect`, `Class.bbox(c: Class) Rect`

## src/lint.zig

Schematic review rules: what a team considers wrong with a drawing, and
how badly. The `.rules` table of `lint.zon`.

Human Rules: none of its own; it reports where a drawing breaks the
review rules a team sets in `lint.zon`, and draws nothing.

Immediate mode, as in cktImg: `check` takes the data and a rule table (a
value — one severity per rule) and returns findings; there is nothing to
construct or keep in sync. It reads only `Placed` and the library, so a
host can lint a drawing it built itself.

Findings come out in rule order, then device or net order: two runs over
one input give identical reports.

## src/loop_place.zig

Certified converter loops and admitted cells → one local power region.

Human Rules:
- loop_place.1 (habit, bounded) A unique flying-capacitor converter
  keeps its main path above the flying/output capacitor drops and the
  lower MOS/diode return. All 145 source groups put the flying cap
  between input main and coil, output branches beyond the output main,
  and the downward divider above the diode. See converter-loops.md.
- loop_place.2 (choice) Use one main row and one lower return row.
  Default to divider, floating cap, grounded cap after the main path:
  114/145 source drawings use this order; the 31 named exceptions have
  no proven topology selector (converter-branches.md). This preference
  applies only after the caller/mate guards below. Exact row equality
  also has source exceptions. Start at the existing main row and reserve
  its whole horizontal band with one clear row above and below.
  Outside devices in that band
  can send supply bars across the loop even from distant columns.
  On collision, try the next disjoint band above. This fallback and
  its one-row margin are default-placement choices, not a guarantee
  for arbitrary rail/stack lengths. Actual wire fits still certify
  the entire tree or abstain; they never bypass a body or rail.
- loop_place.3 (invariant) Mates and honoured row/above/order/cell/face
  requests retain their placement. Incompatible forms or capacitor
  ends abstain. Rejected/dropped requests impose no restriction.
  Existing ground shunts move with the group. Separated controls may
  remain above or below. Actual body/pin reach is reserved by coordinates.

Data: existing per-device cells/forms/ends and cold topology handles
in; changed cells/flat ends and protected x spans out. At most one
span per drawn coil, allocated once; the caller frees it after wrapping.
Handles are u32, signed lattice coordinates i32; a 12-member stack
holds ten selected devices and at most two shunts. Each candidate reads
these fields together. Placement is serial because earlier rectangles
occupy cells for later groups; no state survives the skeleton pass.

Contents:
- `pub fn place(gpa: Allocator, nl: *const Netlist, roles: []const Role, drawn: []const bool, form: []const Form, upper: []const u32, mate: []const u32, left_end: []End, x: []i32, y: []i32, verdicts: []const ?hints.Verdict) Allocator.Error!std.ArrayList([2]i32)`

## src/mates.zig

Mates (issue #8, stage 3): which column devices mirror each other. In:
the structure, each device's column and its neighbours in it. Out: each
column device's mate (itself on the axis), or `none`.

Human Rules:
- mates.1 (unmeasured) In a circuit with a symmetry, each upright device
  stands opposite its image; a flat part is not mirrored. `find`
- mates.2 (habit) In a circuit with none, the two of each differential
  pair, cross-coupled pair and two-member mirror stand mirrored, with
  the devices of one type (kind, polarity and pin count, as a
  symmetry's two) above and below them in their two columns. People,
  drawn level: 946 of 1,057 differential pairs, 76 of 81 cross-coupled,
  2,637 of 3,006 mirrors of two; 1,433 of 1,644 pairs of one type up
  and down the two columns, and 17 of 170 of two types. `pairMates`
- mates.3 (unmeasured) A bank's two are not mirrored: a tail and a
  second stage's source share a bias line. `pairMates`
- mates.4 (unmeasured) A pair's loads mirror with the pair before they
  mirror as some mirror's other half. `pairMates`
- mates.5 (invariant) Columns mirror whole: a column's devices stand
  mirrored only when all their images stand in one column whose images
  stand in it. `mirrorable`
- mates.7 (habit) Two mated pairs of columns stand side by side, each
  about its own axis, whatever joins them. People: 1,768 of 2,407 twos
  of mated pairs of columns in circuits with no symmetry, 228 about one
  axis; of the 643 that nets join half to half (a pair and its folded
  branches, a chain of mirrors), 406 and 174. `oneAxis`
  Narrowing: one pair of columns keeps its mirror, the largest holding
  a differential or cross-coupled pair (the lowest rank on a tie; none
  when none holds such a pair); the rest stand free, level by their
  rows, not mirrored about axes of their own: the skeleton, the wires
  and the closing up carry one axis.

Contents:
- `pub fn find(gpa: Allocator, nl: *const Netlist, _: []const Role, st: *const Structure, drawn: []const bool, form: []const Form, column_of: []const u32, above: []const u32, below: []const u32, n_columns: usize) Allocator.Error![]u32`

## src/maze.zig

A maze router for one connection (issue #8, stage 4): the cheapest
orthogonal path from a pin to its net's wires so far. In: the devices'
boxes, everything drawn so far, the pin and its side, the net. Out: the
path's corners, pin first, or null.

Human Rules:
- maze.1 (choice) A routed wire runs on a lattice of `step` (a quarter
  unit, at least 1) or on a line a pin, a box edge or another wire
  already has, so it meets any of them exactly. `route`
- maze.2 (book) A routed wire is the cheapest orthogonal path: its
  length, plus `bend` a bend, plus `cross` each crossing of another
  net's wire. After M. Wybrow, K. Marriott and P. J. Stuckey,
  "Orthogonal Connector Routing", Graph Drawing 2009. `route`
- maze.3 (book) Crossing a rail's wire costs a quarter of `cross`: the
  book crosses supply stubs freely. `route`
- maze.4 (invariant) A routed wire never runs inside a device's box,
  along or within `clear` of another net's wire, within `clear` of
  another net's point, across a wall (a rail's short stub, its bar), or
  through a point of its own net that is not where it ends. `route`
- maze.5 (invariant) A routed wire crosses another net's wire straight,
  never bends on it and never ends on it. `route`
- maze.6 (invariant) A routed wire leaves its pin the way the pin faces,
  never turns straight back, and enters the pin it runs to from that
  pin's side. `route`
- maze.9 (habit) A routed wire ends on its net's wire, never on another
  pin of the net: a pin is an end of its wire, which branches off it.
  People: 87,922 of 93,770 pins of wired nets that are no rail have one
  wire, leaving the way the pin faces (5,263 hand-drawn schematics).
  `route`
- maze.7 (choice) The cheapest path is sought round the pin and its
  nearest target first, then round the whole net, then over the whole
  drawing: most connections are local. `route`
- maze.8 (choice) A grid of more than 65,536 points is not searched,
  and the pin is named instead: it bounds the work. `route`

Contents:
- `pub const Wire = struct`
- `pub const Mark = struct { at: Pt, net: u32 }`
- `pub const Pin = struct { at: Pt, side: Side }`
- `pub const Query = struct`
- `pub fn route(gpa: Allocator, q: Query) Allocator.Error!?[]Pt`

## src/netlines.zig

The deck's net lines (steering rung 2): how each net is drawn. In: the
netlist and its roles. Out: per net its style, port side and rail style,
the nets to wire first, and a verdict per line. A pure function of the
deck, so the drawing (`wires`) and the report read the same.

    *@ label vb1
    *@ wire vb1 [ladder|trunk|route]
    *@ port out right
    *@ rail 0 bar|each|plain
    *@ first n1 n2
    *@ route n1 2,0 2,3 5,3
    *@ via n1 4,1 4,6

Human Rules:
- netlines.1 (invariant) `label`: the net is a name at each of its pins
  and has no wire. `read`
- netlines.2 (invariant) `wire`: the net is a wire, by the pattern
  named or any that fits; one the canvas cannot draw falls back to
  names, and the report says so. `read`
- netlines.3 (invariant) `port`: an input's or an output's port leaves
  on the side named, where its stub fits. `read`
- netlines.4 (invariant) `rail`: the rail is one bar past its pins with
  a symbol on each unbroken run (`bar`), a symbol at each pin (`each`),
  or one bar and no symbol (`plain`). `read`
- netlines.5 (invariant) `first`: the nets named are wired before every
  other, in the order of the lines in the file. `read`
- netlines.6 (invariant) `route`: the net's wire has this polyline (in
  symbol units, as a `via`'s points are), each piece level or upright
  and one end on a pin of the net, drawn whole or not at all, before
  every net no such line pins. `read`
- netlines.7 (invariant) `via`: the net's wire passes these points, in
  order. `read`
- netlines.8 (choice) Of two lines setting one net's style, port or
  rail, the preferred one (`hints.admitOrder`) stands: one answer
  whatever the order of the lines. `read`
- netlines.9 (unmeasured) A rail is its symbols: no line names it or
  wires it, and only `rail` styles it; an input is a port at its pins,
  never wired by a line; only an input or an output takes `port`.
  `admits`
- netlines.10 (unmeasured) Unless a line says, a supply is one bar over
  its pins. `read`
- netlines.11 (book) Unless a line says, a ground is a symbol at each
  pin, one per branch, as the book draws it. `read`
- netlines.12 (unmeasured) Unless a line says, the reference the engine
  gave a circuit with no ground is its bottom wire, as people draw it:
  one bar and no symbol. `read`

Contents:
- `pub const Style`, `pub const Rail`, `pub const NetLines = struct`
- `pub const Route = struct`
- `pub fn read(arena: Allocator, nl: *const Netlist, roles: []const Role, unit: i32, verdicts: []?Verdict) Allocator.Error!NetLines`

## src/netlist.zig

ngspice netlist → bipartite hypergraph of devices + list of analyses.

Human Rules:
- netlist.1 (choice) An `X` of a subcircuit the deck defines is drawn
  as one block, its pins the instance's nets and what is inside hidden:
  the definition is its author's unit. `addInstance`
- netlist.2 (choice) A block whose definition says `*@ expand`, or that
  a top-level `*@ expand <instance>` line names, is drawn as its
  devices instead; an instance inside it expands or stays a block by its
  own definition. `addInstance`
- netlist.3 (invariant) An expanded instance's devices and nets carry
  the names ngspice gives them: device `r1` of `x1` is `r.x1.r1`, its
  net `a` is `x1.a`, its ports are the instance's nets, and ground
  (`0`, `gnd`) stays the deck's. `Frame`
- netlist.4 (choice) An `X` whose master the deck never defines and
  whose name holds the word `nfet`, `pfet`, `nmos` or `pmos` (four
  nodes), `res` or `cap` (two or three) is drawn as that device, not as
  a block: the deck has no definition, and the PDK's name is all it
  says. `pdkPrimitive`
- netlist.5 (choice) An `X` of any other master the deck never defines
  is drawn as a block with ports `p1`..`pN`: nothing says more.
  `defineOpaque`
- netlist.6 (choice) A definition's `*@ left`, `right`, `top` or
  `bottom` line puts the ports it names on that side of the block, in
  the lines' order (top to bottom, left to right); the rest follow in
  port order, on the side `library.defaultSide` gives them.
  `directive`
- netlist.7 (choice) A `*@ kind <dev> nmos|pmos|npn|pnp|res|cap|block`
  line draws a device as that kind when its pin count fits the kind's
  card, the preferred line last. `kindLine`

No tokenizer/parser split. A SPICE netlist is line-oriented and flat:
every card is one logical line, its kind is known from the first byte,
and the output is appended to arrays, never built into a tree. So:

    bytes ─lowercase─▶ logical lines ─split─▶ fields ─switch(first byte)─▶ arrays

Fields are slices into one lowercased copy of the source; nothing else is
copied. The file is walked three times, once per concern, because each
pass needs everything the previous one found:

  1. `.model` names          (to count Q/M/D pins, which can vary)
  2. devices → nets, pins    (the hypergraph)
  3. analyses                (reference nets and devices by name)

Re-scanning bytes is far cheaper than storing an intermediate token
stream that only exists to be read back.

Supported cards: R C L K V I E G F H B D Q J Z M S W T O U X, and every
analysis in `analysis.zig`. Rejected with an error rather than silently
mis-parsed: A/N/P/Y devices, E/G/F/H `poly(n)`, `.include`/`.lib`, `.hb`.
`.control` blocks are skipped; other dot-commands (`.options`, `.ic`,
`.param`, ...) are ignored.

Which letter is which kind, and how many nodes its card names, is the
device table's (`device.zig`, which owns `DeviceKind`); `Netlist.path`
reads a card's current path from it.

## Subcircuits

A definition's `*@` lines, read by `directive`:

    .subckt opamp inp inn out vdd vss
    *@ expand
    *@ left inp inn
    *@ right out
    *@ top vdd
    *@ bottom vss
    ...
    .ends

## src/opamp.zig

Op-amp circuits (issue #8, stage 3): where the devices of a circuit of
amplifier blocks and two-pin parts stand, as people draw one. In: the
netlist, its roles, each device's class. Out: a place and a turn for
every drawn device, or nothing when the circuit is of another kind. The
steps of the procedure are `opamp_grow.zig`'s. Lengths are hundredths
of a unit on a quarter-unit grid, y down.

Human Rules:
- opamp.1 (invariant) A deck with a line that places or turns a device
  (`upright`, `bridge`, `row`, `above`, `order`, `face`, `cell`, a
  strong `at`) is laid by its lines, not along the signal; a stay
  (`weak at`) is no such line. `steered`
- opamp.2 (habit) A circuit whose every drawn device is a two-pin part
  or an amplifier block (one or two inputs and one output by their port
  names, the rest rails), with at least one block, is drawn along its
  signal, not on the lattice: its blocks and parts all bridge. People:
  199 of 5,263 hand-drawn schematics are of this kind; laid so, 170
  such circuits cross 14 wires where the lattice crossed 306 and their
  hand drawings 6. `applies`, `place`
  Narrowing: a block whose symbol has an input right of its output, or
  a pin count other than its class's, leaves the circuit on the
  lattice (`place`).
- opamp.3 (unmeasured) The groups the procedure begins stand one under
  the other in the order begun, 1.5 units apart; a group a part joins to
  a node of an earlier one stands with that part's end at the node's x.
  `place`
- opamp.4 (habit, bounded) A capacitor circuit of amplifier blocks,
  resistors, voltage sources and externally controlled MOS switches
  follows the signal too: AG759/762/799. A control net may touch only
  MOS gates and a voltage source to a rail; a channel cannot touch a
  supply. Driven stages (AG807/2209), diode/current steering (AG1042)
  and complementary parallel pairs (AG751) stay on the lattice.
  These are admission limits, not a universal definition of a switch.
  Only D/S enter the path; flat gates face up. Local return loops may
  turn a channel upright (AG800/801). `applies`, `externalGate`, `place`
  A MOS class must have a flat, one-unit channel and its gate above it;
  its whole symbol must fit the reserved switch frame. Other caller
  frames retain lattice placement (`place`, `channelFits`).

Data: reads the netlist's existing pin rows and roles. `place` owns one
optional channel midpoint per device until export (library coordinates,
`Pt` is two i32s); null means no MOS. D/S alone append path incidences.
The phase arena owns the table; no electrical pins or classes change.

Contents:
- `pub fn applies(nl: *const Netlist, roles: []const Role, drawn: []const bool) bool`
- `pub fn steered(nl: *const Netlist) bool`
- `pub fn place(arena: Allocator, nl: *const Netlist, roles: []const Role, drawn: []const bool, lib: *const Library, classes: []const ClassId) Allocator.Error!?[]?At`
- for `opamp_grow.zig`: `pub const none`, `unit`, `quarter`, `tries`; `pub const P`, `R`, `Kind`, `Link`, `Pin`, `Block`, `Two`, `Canvas`, `Put`
- `pub const Placer = struct`, `Placer.canvas`, `Placer.free`, `Placer.wire`, `Placer.add`, `Placer.anchor`, `Placer.aOn`, `Placer.put`
- `pub fn partRect(kind: Kind, cx: i32, cy: i32, tall: bool) R`, `pub fn ceilQuarter(v: i32) i32`, `pub fn roundEven(num: i64, den: i64) i32`

## src/opamp_grow.zig

The op-amp placement's procedure (`opamp.zig` holds its tables and its
door): blocks in signal order, each with its feedback rows, its inputs'
trees grown leftward and its load rightward. In: a `Placer` with the
netlist's shape. Out: every device placed on a canvas. The shares below
are people's, in the hand drawings (5,263 schematics, 199 of this
kind).

Human Rules:
- opamp_grow.1 (habit) The block farthest from the inputs is placed
  first, its output pin at the origin; a block that drives it is placed
  when its output net is reached, left of it. People: 85% of driven
  blocks stand right of their driver. `rootOrder`, `grow`
- opamp_grow.2 (habit) The inverting input is on top: the block's
  symbol is drawn so (`library.blockFor`), and its feedback then stands
  over the block. People: 76%. `block`
- opamp_grow.3 (habit) A part from the output to an input lies flat
  over the block for the upper pin, under it for the lower; two or three
  parts in series back to the output lie in one such row. People: 82%
  straight over or under, 96% on their pin's side. `block`, `fbPath`
- opamp_grow.4 (unmeasured) A part to a rail from a node of a feedback
  row hangs upright under that node, over the block as under it.
  `block`
- opamp_grow.5 (habit) From a pin's node leftward: parts to a rail
  stand upright beside it, the first series part lies level with the
  node, the rest stack away from the block; from the output rightward
  the same. People: 45% (the first series part level with the node).
  `grow`
- opamp_grow.6 (unmeasured) On the upper input's net, when the lower
  input carries a signal, a part to ground lies flat in the input's row
  instead of hanging upright. `grow`
- opamp_grow.7 (choice) Of a node's series parts, the one nearest a
  block still to be placed goes first, then the larger tree, then the
  earlier canonical device name: card permutation changes no tie. `grow`
- opamp_grow.8 (unmeasured) A part between two nodes that both stand
  lies in the first row past every body between them, or upright beside
  them when one is over the other. `close`
- opamp_grow.9 (unmeasured) What no block's tree reaches is drawn in a
  group of its own, grown from its first net that is no rail; a part
  with both ends on rails, or both on one net, hangs upright. `run`
- opamp_grow.10 (choice) A body keeps 0.28 unit from every other (the
  first level part at a pin only clears a real overlap); a taken place
  moves by half a unit: the procedure's clearance and its step.
  `Placer.put`
- opamp_grow.11 (habit, bounded) A two-part C/MOS feedback path whose
  junction has only one ground MOS forms a rectangle: capacitor and
  ground switch share a row, signal switch returns upright outside the
  amplifier. Parallel cells share capacitor columns (AG800/801). A
  direct feedback capacitor instead takes the outer row, leaving the
  switched branch flat (AG803). Eight source cells satisfy 55/55 local
  geometry checks; four in AG805/813 remain outside admission. Longer
  paths retain their own axes (AG799). `cellShunt`, `feedbackCell`
  All seven rectangular source cells face the return gate away from
  the amplifier; reflecting across its vertical channel preserves D/S.

Contents:
- `pub fn run(p: *Placer) Allocator.Error!void`

## src/pinned.zig

The deck's geometry lines (steering rung 4): exact coordinates and
orientation, and where a device's name goes.

    *@ at M5 6 4.5 R90        the class origin at (6, 4.5) symbol units
    *@ refdes M5 left         its name left of it

Human Rules:
- pinned.1 (invariant) A device with an `at` line has its class origin
  at the line's coordinates, in units of the symbol set's `unit`
  (rounded to the nearest whole drawing unit, the frame `Placed` uses),
  turned as its word says when it names one: the user's word. `read`
- pinned.2 (invariant) Of two lines on one device, the preferred stands
  (`hints.applyOrder`). `read`, `sides`
- pinned.3 (invariant) A `refdes` line puts the device's name on the
  side it names. `sides`
- pinned.4 (invariant) A line that cannot hold is refused with its
  verdict, and the device is laid as without it: a name the deck lacks,
  a device not drawn, a coordinate not finite or past 1e6 units, a word
  that is no turn or side. An `at` whose symbol would overlap another's
  is dropped (sketch.13). `read`, `sides`

Contents:
- `pub const At = struct`
- `pub fn read(arena: Allocator, nl: *const Netlist, unit: i32, drawn: []const bool, verdicts: []?Verdict) Allocator.Error![]?At`
- `pub fn sides(arena: Allocator, nl: *const Netlist, verdicts: []?Verdict) Allocator.Error![]?Side`
- `pub fn orientWord(word: []const u8) ?Orient`

## src/placed.zig

The result, as plain data: where every device, pin, wire, dot and name
went, in the target's integer coordinates (y down). No accessor is needed
to read it — every column is a slice — and it points at nothing but its
own arena, so it outlives the netlist and the schematic it came from.
In: a laid-out `Schematic` and its netlist. Out: `Placed`, its devices in
this order: the netlist's devices that are drawn (a pinless `K` card is
not), then one rail or port device per terminal symbol the layout drew
(unnamed: `dev_name` is empty, the net is on its one pin), then the
driver islands' sources and their terminal symbols.

Human Rules:
- placed.1 (invariant) Every wire ends exactly on its pin: a pin off the
  row or column line the layout routed to (an op-amp's second input)
  gets a short lead, along the pin's side first, then onto it. `run`
- placed.2 (habit) A terminal net is drawn as the symbol of its role: a
  supply as a power rail, the sink as a ground rail, an input or a bias
  net as an input port, an output as an output port. People: 24,748 of
  24,843 nets that are ports of their cell, in 5,263 hand-drawn
  schematics, carry the symbol of the role the engine gives them (supply
  3,954 of 3,973, ground 5,439 of 5,450, input 5,906 of 5,916, bias
  2,770 of 2,790, output 6,679 of 6,714). `roleClass`
- placed.3 (choice) Where the library has no symbol for a net's role,
  the net's name is written there instead: something must stand for the
  net. `terminal`
- placed.4 (habit) A terminal symbol's or a label's name runs away from
  the wire that meets it; left when no wire does. People: 13,814 of
  15,521 port symbols one wire leaves carry their name on the side away
  from it. Which way a written name's text runs is not in the hand
  drawings, and the side with no wire is the engine's own (people: left
  784, right 348 of 1,398 ports). `leafSide`
- placed.5 (choice) A driver (R3: a source from a supply, input or bias
  net to ground) is not wired into the circuit but drawn apart, left of
  it, between its own net's symbol above and a ground symbol below.
  People: none of the 982 such sources in the cells of 5,263 hand-drawn
  schematics stands apart; all 982 are wired where they stand, 683 of
  them left of every other device. The corpus holds cells only, and 963
  of the 982 drive a net with no terminal name: what people do with a
  bench's supply source it cannot say (19 instances). `islands`
- placed.6 (order: potential) A driver apart stands upright with the end
  of its path off the ground up. People: 951 of those 982 sources stand
  with the driven end up. `islands`
- placed.7 (choice) Drivers apart stand in name order, two units apart,
  the nearest a unit and a half clear of the circuit: the order of the
  cards changes nothing. `islands`
- placed.8 (invariant) A wire that runs through a junction dot is split
  there, so every wire that meets a dot ends on it and a netlister that
  joins wires only at their ends (xschem) reads one net.
  `splitAtJunctions`
- placed.9 (habit) A sink named `vee…` is drawn with the supply's
  glyph, below its pin, not the ground's. People: 470 of 477 `vee` rail
  symbols in 5,263 hand-drawn schematics. `roleClass`

## src/power_compact.zig

Certified converter paths and their actual terminals → coordinate orders
supplied to the generic compactor. No circuit state survives this pass.

Human Rules:
- power_compact.1 (habit, bounded) The whole channel of each upright
  grounded shunt or active gate driver stays below its flat main path.
  All 365 selected shunts and 92 drivers have both D/S below that path
  in the AnalogGenie source drawings (power_paths.5). Device centers
  alone let AG1356:M12.S rise to the main row. Preserve the actual upper
  D/S terminal's order, including caller-supplied shifted/tall symbols.
- power_compact.2 (habit, bounded) A unique grounded shunt's signal
  terminal stays between its connected main and coil terminals. All
  353 unique source channels lie in that inclusive interval; AG1418:MN2
  is level with the coil's terminal. Each initially strict half keeps
  its order; equality already shares one compaction track.
- power_compact.3 (invariant) Only relations true before compaction
  enter the graph. A turned/offset main path without one horizontal
  channel row, an explicit `at` participant, or an already external
  shunt does not acquire these orders. Caller geometry has precedence.
- power_compact.4 (habit, bounded) A unique upright outer reservoir's
  signal stays beyond the main switch away from the coil, and at or
  below its channel. Preserve each initially true actual-terminal
  relation; equality already shares a track. All 359 source reservoirs
  agree, including two level signals. Shifted caller symbol frames
  require the transformed signal pin, not the device center.
- power_compact.5 (habit, bounded) A selected flying-capacitor loop
  retains its actual cap interval, downward drops, lower return and
  divider orders. All 145 source groups obey these inequalities.
  Preserve only initially true relations; explicit origins and turned
  or hidden channel leads abstain. When both diode ends already fit
  between the cap columns, retaining those orders also keeps its center
  inside. No exact lower-row equality or output-branch order is added.
- power_compact.6 (invariant) Other geometry owners may append initially
  true actual-coordinate orders to the same pass. Bias peers and coil
  tanks use this
  seam; this owner does not discover or place those groups. Empty
  extra slices preserve the converter-only requests.

Data: existing netlist/CSR, skeleton and schematic rows in; temporary
x/y pairs of i32 coordinates out. Both pair fields are read together.
A group table has one slot per drawn coil; x has thirteen slots per group,
y twelve per group plus each coil-end/main-gate incident candidate. Each is
sized once, freed on return, and collected serially in graph order.
The compactor owns coordinate writes; this pass only submits orders.

Contents:
- `pub fn deviceBoxes(gpa: Allocator, s: *const Schematic, nl: *const Netlist, sk: *const Skeleton) Allocator.Error![]library.Rect`
- `pub fn clear(gpa: Allocator, s: *const Schematic, nl: *const Netlist, sk: *const Skeleton) Allocator.Error!bool`
- `pub fn drawnAxis2(gpa: Allocator, s: *const Schematic, sk: *const Skeleton) !?i32`
- `pub fn squeeze(gpa: Allocator, s: *Schematic, nl: *const Netlist, sk: *const Skeleton, ats: []const ?pinned.At, len: Lengths, axis2: ?i32, extra: []const [2][]const [2]i32) Allocator.Error!void`

## src/power_loop_wires.zig

Certified flying-capacitor loops → local wire trees on actual pins.

Human Rules:
- power_loop_wires.1 (habit, bounded) Keep the seven local connections
  of a certified loop continuous. All 145 selected AnalogGenie source
  drawings connect these terminals through actual Manhattan conductor
  ink, with no proper crossing between the seven local trees. Gates,
  bodies and remote controls do not belong to these trees. Provenance:
  docs/research/converter-loops.md and its exact source inventory.
- power_loop_wires.2 (choice) The main path is the top wire, the lower
  switch and diode the bottom wire, with vertical capacitor drops and
  a downward divider. Actual pins must support this ordering. Commit
  the whole group or leave it to the ordinary wire patterns; no partial
  loop survives a body, pin or prior-wire collision.
  A projected routing point must equal its transformed class terminal;
  off-line connectors added later cannot certify this local tree.
- power_loop_wires.3 (invariant) Explicit net styles, routes, vias and
  a requested first-net order take precedence. After a successful local
  tree, the ordinary wiring sees its outside pins plus one tree anchor:
  a remote connection may still be named, and an input still has a port.
  Automatic thinning never erases the local tree. Record the successful
  anchor so a later router attaches every outside pin to that tree.
  A later group sharing a seeded net keeps all its terminals for the
  ordinary patterns; one anchor never represents two disconnected trees.
- power_loop_wires.4 (choice) Retain an output's outermost selected pin
  toward its requested port side, so outside-pin wiring still sees the
  whole local output extent. A local output with no outside pins gets
  its port at the whole tree's boundary, toward the requested side or
  the loop's output direction. An input's seeded component also gets
  its port at this boundary before nearby outside pins attach to it;
  distant pins keep their ordinary ports.
  The retained anchor is a routing handle, not a new physical boundary
  inside the loop. Default inputs follow their actual anchor pin side,
  outputs point right, and projection ties choose the top-left point.
  Requested sides and collision-safe port fallback retain precedence.
  `port`
- power_loop_wires.5 (habit, bounded) The input spine stands strictly
  left of both selected switch terminals in 141/145 source drawings;
  four put it on their shared terminal column. Try the existing `tap`
  gap first, then that terminal column if a body or prior wire blocks
  the gap. This is a bounded default preference, not a topology rule
  selecting the four exceptions. Both candidates use actual pins and
  roll back failed fragments before trying the next. `bus`

Data: existing netlist/roles/drawn rows select temporary 68-byte groups,
one capacity slot per drawn coil. Each wiring pass maps a group to 18
existing u32 pin handles in seven fixed rows, at most four per net.
No persistent state, new nodes, callbacks or per-pin allocation; the
canvas owns routes, and the caller owns/frees the group request slice.
A temporary u32 anchor per net is `none` until a tree is committed.

Contents:
- `pub fn collect(gpa: Allocator, nl: *const Netlist, roles: []const sch.Role, drawn: []const bool, lines: *const NetLines) Allocator.Error![]Group`
- `pub fn seed(c: *Canvas, groups: []const Group, pins_of: []std.ArrayList(u32), mates: []u32, anchors: []u32) Allocator.Error!void`
- `pub fn port(c: *Canvas, net: u32, pins: []const u32, anchor: u32) Allocator.Error!bool`

## src/power_loops.zig

Flying-capacitor loops: existing graph, roles and drawn rows -> one
optional group of ten device handles and seven semantic net handles.

Human Rules:
- power_loops.1 (habit, bounded) A unique PMOS/coil/PMOS path from an
  externally controlled PMOS input bus to a grounded output reservoir
  closes a lower loop through another bus PMOS, a flying capacitor,
  a diode and a floating output capacitor. A unique two-resistor
  output-to-ground divider completes the group. All seven local nets
  are distinct and nonrail. Channel endpoints alone select the group.
- power_loops.2 (habit, bounded) Both floating caps stand upright,
  input-side coil net above the flying cap's lower node and output
  above the other cap's negative net. The divider runs downward and
  the lower MOS and diode lie flat. All 145 selected AnalogGenie
  drawings agree; the 734 AMSNet drawings select none. These are
  related converter variants, not independent examples. `forms`
- power_loops.3 (scope) The observed diode has its anode on the
  floating output's negative net. Reversal is unobserved and excluded,
  not an invalid circuit. Count every complete loop before this test.
  Duplicate members, competing paths/branches and shared groups
  abstain before forms or coordinates can hide an alternative.
- power_loops.4 (scope) Gate direction, lower-row equality and output
  branch order vary in the source. This topology result imposes none
  of them. Explicit forms, ends and placement instructions retain
  precedence in their owners. Evidence: docs/research/converter-loops.md,
  3,335 verified actual SVG lead endpoints and seven continuous local
  source wire trees per selected circuit. Geometry alone is no wire.
- power_loops.5 (scope) None of the 145 source groups has a grounded
  capacitor on either main gate or either coil endpoint. Such an
  extension needs its own branch-placement evidence, so the whole
  promoted pattern abstains after raw shared-member checks. This is
  an unobserved extension, not an invalid circuit.

Data: at most one result per existing coil; all handles fit the graph's
u32 indices. Callers read the whole fixed group, on their stack only.
Queries allocate nothing and retain nothing. Every scan is bounded by
an existing edge/CSR row; independent coil queries read shared rows.
Owners apply forms, placement and wiring after the query. This free
function is their shared topology seam, not another netlist table.

Contents:
- `pub const Member = enum(u4)`, `pub const Net = enum(u3)`
- `pub const Group = struct`
- `pub fn find(nl: *const Netlist, roles: []const Role, drawn: []const bool, coil: u32) ?Group`

## src/power_paths.zig

Inductive converter paths, separate from their bias and control columns.

Human Rules:
- power_paths.1 (habit, bounded) An inductor off the named rails with a
  grounded NMOS channel at either end identifies a switching node. A
  PMOS with distinct D/S/G and neither channel end on a rail lies flat
  between that node and a capacitor-to-ground reservoir: AG1363/1383.
  A gate/body does not make the grounded channel. `classify`
- power_paths.2 (habit, bounded) Independently controlled PMOS channels
  sharing an input bus lie flat when their other ends meet that inductor
  or a capacitor: AG1250's main/flying-capacitor branches. Every path
  incident on the bus must be such a PMOS; its control touches MOS gates
  only. A capacitor to its own gate/opposite end is no evidence. The
  auxiliary supply branch alone remains unresolved (AG1199:M1 and
  AG1202:M5 stand upright); an inductor's bias mirror stays upright too.
- power_paths.3 (habit) The selected path's inductor lies flat and is not
  stood up by forms.crooked. All 252 selected AnalogGenie inductors and
  649 selected PMOS lie flat in the source drawings. This is two related
  converter families, not 649 independent examples. The 734 AMSNet
  drawings select none. LC oscillators and inductive LNAs give counter-
  examples to using inductor adjacency alone: AG1109, AG1111, AG491.
  Explicit deck hints retain precedence. `classify`, `inductor`
- power_paths.4 (habit) The main path is the unique selected PMOS at
  each coil endpoint, even when shunts or bias columns tap it. The coil stands
  between the two selected main PMOS in all 252 source circuits; all
  three share a row in 243. The nine source offsets and the full named
  inventory are recorded by docs/research/figures/power_paths.py.
  More than one selected switch at an end, an ambiguous choice of coil,
  or an explicitly upright member gives no three-part group. `series`
- power_paths.5 (habit, bounded) The main path stands above its
  externally controlled grounded NMOS shunts and active MOS gate
  drivers. Both D/S pins lie below the path for all 365 such shunts
  and 92 such drivers in the selected source drawings. A bias channel
  merely touching the coil has no such order: 110 of 140 nonselected
  PMOS there stand level with or above the path. `controlBounds`
- power_paths.6 (habit, bounded) A main switch with gate-only external
  control faces down when both outer ends of its unique series path
  have capacitors to ground. All 107 such controls face down in the
  source drawings, including AG1363:MP3. The input-bus family has 159
  downward and 131 upward main gates, so one reservoir or an external
  gate alone does not decide. `externalReservoirGate`
- power_paths.7 (habit, bounded) A block driving one certified main
  switch stands below that switch. Its actual SVG output lead faces up
  on the gate's x line in 67 of 75 source drawings; AG1354, 1358, 1366,
  1369, 1372, 1377, 1393 and 1396 face right with bent connections.
  Cached terminal pairs align in all 75, but differ from 43 actual
  output-lead endpoints: they do not establish glyph orientation.
  The declared output identifies the terminal when an input shares its net.
  Multiple qualifying outputs or targets leave the ordinary layout;
  caller geometry and the actual symbol frame qualify the later pin
  alignment. The eight source exceptions remain mismatches, with no
  circuit-name guard. `blockTarget`, controller_glyphs.py, sketch.zig
- power_paths.8 (habit, bounded) One externally controlled grounded
  NMOS at a certified coil endpoint stands below the connection from
  the main MOS to that coil. All 353 uniquely selected source shunts
  lie within that terminal interval. Two eligible channels are
  ambiguous: AG1383:M7 is an amplifier tail beside power shunt MN1.
  Gate/body incidences and duplicates do not add channels. `groundShunt`
- power_paths.9 (habit, bounded) One grounded capacitor on a main
  switch's outer channel net stands upright, beyond that switch away
  from the coil. All 359 source reservoirs have ground below signal;
  357 signals are below the main channel and two are level (AG1309,
  AG1329). Gate/coil branches, non-ground rails and multiple reservoirs
  do not establish this group. Caller forms retain precedence. `reservoir`

Data: reads existing netlist paths/CSR, model types, drawn and rail rows;
writes only the caller's forms. The placement queries read existing
coordinate slices and return scalar bounds, with no retained state.
Three boolean arrays, each vertexCount,
hold gate-only controls, switching-coil endpoints and shared input buses.
The allocator owns this scratch only for classify; no retained state,
new handles, device objects or per-incidence allocations. CSR bounds
every local scan. `inductor` rechecks only a coil's immediate neighbors
when forms.crooked needs the same certificate without retaining scratch.

Contents:
- `pub fn classify(gpa: Allocator, nl: *const Netlist, roles: []const Role, drawn: []const bool, form: []Form) Allocator.Error!void`
- `pub fn inductor(nl: *const Netlist, roles: []const Role, drawn: []const bool, d: u32) bool`
- `pub fn seriesTopology(nl: *const Netlist, roles: []const Role, drawn: []const bool, d: u32) ?[3]u32`
- `pub fn inputBus(nl: *const Netlist, roles: []const Role, drawn: []const bool, net: u32) bool`
- `pub fn series(nl: *const Netlist, roles: []const Role, drawn: []const bool, form: []const Form, d: u32) ?[3]u32`
- `pub fn controlBounds(nl: *const Netlist, roles: []const Role, drawn: []const bool, form: []const Form, members: [3]u32, coordinates: []const i32) ?[2]i32`
- `pub fn control(nl: *const Netlist, roles: []const Role, drawn: []const bool, form: []const Form, members: [3]u32, d: u32) bool`
- `pub fn externalReservoirGate(nl: *const Netlist, roles: []const Role, drawn: []const bool, form: []const Form, d: u32) bool`
- `pub fn blockTarget(nl: *const Netlist, roles: []const Role, drawn: []const bool, form: []const Form, d: u32) ?[2]u32`
- `pub fn groundShunt(nl: *const Netlist, roles: []const Role, drawn: []const bool, form: []const Form, net: u32) ?u32`
- `pub fn reservoir(nl: *const Netlist, roles: []const Role, drawn: []const bool, form: []const Form, main: u32, inner: u32) ?u32`

## src/relations.zig

The deck's placement lines (steering rung 2): `upright`, `bridge`,
`face`, `row` and `above`, applied by the skeleton. In: the netlist, its
structure, and the skeleton's tables as each stage leaves them. Out: the
tables changed as the lines say, the rows' constraints for `levels`, and
a verdict per line.

Rows and their order are difference constraints: `row a b` an equality,
`above a b` an edge.

Human Rules:
- relations.1 (invariant) `driver <dev> apart` draws a two-pin
  independent source apart, left of the circuit, upright between its
  net's symbol and ground; `driver <dev> inline` draws a device in the
  circuit. `drivers`
- relations.2 (invariant) A device an `upright` line names stands in a
  column, one a `bridge` line names lies flat between columns; a
  transistor only stands. `forms`
  Narrowing: no controlled source (E, G, F, H) is taken, which the
  general form admits (`twoPin`).
- relations.3 (choice) Of lines setting one value (a device's form, an
  end, a driver), the preferred stands, applied last: the deck's own
  ranking of its lines. `forms`
- relations.4 (invariant) `face <dev> <end> up|down` puts that end of
  an upright device up or down. `ends`
- relations.5 (invariant) The upright devices a `row` line names stand
  on one row; a bridge it names takes the row of its first upright
  device. `rows`
- relations.6 (invariant) Each upright device an `above` line names
  stands on a row above the next one's. `rows`
- relations.7 (choice) Of `row` and `above` lines that close a cycle,
  the strongest stand and the rest are dropped with their preferred
  conflict: the deck's own ranking of its lines. `rows`
- relations.8 (unmeasured) A `row` or `above` line on mated devices also
  holds for their mirror images, where those are drawn upright and the
  image contradicts no line; a bridge's mate takes the image row. `rows`
- relations.9 (choice) The engine's own column links, mates, blocks and
  ground drop give way to the `row` and `above` lines: the deck is the
  user's word. `Relations.refuses`
- relations.10 (invariant) `face <dev> g left|right` puts a transistor's
  gate (or base) on that side; on a flat part, the named end stands on
  that side. `faces`
  Narrowing: a flat part by its pin count, as `sketch.fits` turns it;
  the device model's flat part also takes a four-pin switch and leaves
  out a two-port box.
- relations.11 (unmeasured) A `face` line on one of a mated pair turns
  the unnamed mate's gate the other way; a flat part's mate is not
  turned with it. `faces`
- relations.12 (invariant) A drawing whose mated pair's gates a line
  turned to face the same way is not drawn mirrored. `faces`

Contents:
- `pub const Relations = struct`, `Relations.find(r: *const Relations, d: u32) u32`, `Relations.refuses(r: *const Relations, gpa: Allocator, below: []const u32, u: u32, l: u32) Allocator.Error!bool`
- `Check.holds(ck: Check, lines: []const u32) Allocator.Error!bool`: the admission test `hints.conflict` calls
- `pub fn drivers(gpa: Allocator, nl: *const Netlist, drawn: []bool, verdicts: []?Verdict) Allocator.Error!void`
- `pub fn forms(arena: Allocator, nl: *const Netlist, drawn: []const bool, form: []Form, verdicts: []?Verdict) Allocator.Error!void`
- `pub fn ends(arena: Allocator, nl: *const Netlist, drawn: []const bool, form: []const Form, upper: []u32, lower: []u32, verdicts: []?Verdict) Allocator.Error!void`
- `pub fn rows(gpa: Allocator, arena: Allocator, nl: *const Netlist, st: *const Structure, drawn: []const bool, form: []const Form, verdicts: []?Verdict) Allocator.Error!Relations`
- `pub fn faces(arena: Allocator, nl: *const Netlist, drawn: []const bool, form: []const Form, mate: []const u32, gate_right: []bool, left_end: []skeleton.End, verdicts: []?Verdict) Allocator.Error!bool`
- `pub fn pinIndex(nl: *const Netlist, d: u32, word: []const u8) ?u32`
- `pub fn twoPin(kind: DeviceKind) bool`
- `pub fn pinName(arena: Allocator, kind: DeviceKind, k: u32) Allocator.Error![]const u8`

## src/relay.zig

A drawing relaid (stage 4): the previous drawing's places (the deck's
`*@ weak at` stays) set against the lattice the engine reads from the
deck as it is now. In: the skeleton's cells, the lattice's own
coordinates, the stays. Out: every drawn device's point, and no second
wiring: the drawing is not closed up again.

Human Rules:
- relay.1 (invariant) A column or row of the lattice keeps the place
  its devices' stays agree on: what the deck did not change stands
  where it stood. `axis`
- relay.2 (choice) Where the stays' places disagree with the
  skeleton's order of the lines, the heaviest set of lines by devices
  keeps them (a longest increasing subsequence), each line at the place
  most of its stays agree on, the lesser on a tie: the fewest devices
  move. `axis`
- relay.3 (invariant) Every other device is inside the radius of change
  and is laid again: one new to the deck, one the structure now puts on
  another line (a pair it mirrors, a row it joins); one it only turns
  is turned where it stands. `place`
- relay.4 (choice) A line with no place of its own stands the lattice's
  pitch after the line before it (before the first kept line, the pitch
  before it), and where that leaves no room the lines after it move
  along as one, so what stood mirrored stays mirrored. `axis`
- relay.5 (invariant) A relaid drawing has no symbol on another: where
  two would overlap, the stays are let go and the deck is laid afresh.
  `place`

Contents:
- `pub fn place(gpa: Allocator, s: *const Schematic, sk: *const Skeleton, xs: []const i32, ys: []const i32, ats: []?pinned.At, at: [][2]f32) Allocator.Error!bool`

## src/report.zig

The decision report (docs/research/steering.md §5), as one JSON document:
what a caller, an agent above all, reads to judge a drawing and steer the
next one.

- `gates`: every finding of `checks.find`; none is the guarantee.
- `requests`: each `*@` line of the deck, by line number: honoured,
  relaxed, dropped or rejected, why, and the lines that blocked it. An
  honoured line the finished drawing does not show (`checks.drawnAs`) is
  reported relaxed, `not_drawn`: a bug.
- `metrics`: crossings between nets, bends, the nets drawn as names.
- `decisions`: the engine's decisions as the `*@` lines that state them,
  rungs 1 to 4 (cells and places as `weak` stays); a deck plus these
  lines, under `*@ grouping off`, draws the same picture.
- `grid`: the skeleton's rows, each device at its lattice column.

Human Rules:
- report.1 (choice) A crossing is a level wire of one net and an upright
  wire of another meeting strictly inside both; a touch at an end, a T or
  a bend is none: it is the measure the drawings are compared by.
  `crossings`
- report.2 (choice) A corner is a point with no pin on it that a net's
  wire leaves exactly two ways at a right angle; a T, a net's crossing of
  its own and a straight joint are none, and a trunk drawn in pieces has
  its corners where two pieces end: it is the measure the drawings are
  compared by. `bends`
  Both agree with the scorer the 5,263 hand-drawn reference schematics
  are compared by: on 200 of its drawings, 305 crossings and 1,178
  corners either way, none differing.

Contents:
- `pub fn verdicts(arena: Allocator, nl: *const Netlist, roles: []const Role, st: *const Structure, sk: *const Skeleton, p: ?*const Placed, lib: ?*const Library) Allocator.Error![]const Verdict`
- `pub fn decisions(arena: Allocator, nl: *const Netlist, st: *const Structure, sk: *const Skeleton, p: ?*const Placed, unit: i32, rung: u8) Allocator.Error![]const []const u8`
- `pub fn write(gpa: Allocator, w: *Writer, p: *const Placed, lib: *const Library, nl: *const Netlist, roles: []const Role, layout: config.Layout) !void`

## src/resistor_downstream.zig

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

## src/resistor_load_place.zig

Complete six/twelve-device load owners -> actual frames and strict orders.

Human Rules:
- resistor_load_place.1 (bounded observation) A diode PMOS stands over
  two upright resistors, each aligned with its outward-gated input
  drain. The common grounded tail is below both sources. Three source
  groups certify these relations, nine straight corridors and clear
  nominal group envelopes. The tail tree may bend. `attempt`
- resistor_load_place.2 (bounded priority) The linked two-stage case
  has separate local axes, matching semantic rows and both tail gates
  left. This refines the automatic tail bank, retaining graph mates
  and caller classes. It never requests a wire between the bias gates.
- resistor_load_place.3 (choice) One body-spaced candidate per owner,
  centered at the old input-pair midpoint and above all foreign bodies.
  Eight rigid poses per member; unsupported frames/collisions restore
  all six/twelve rows before any position write. No source distances.
- resistor_load_place.4 (invariant) Actual lead anchors share tracks;
  preserve initially strict source orders and the foreign-body boundary
  through the existing one-pass compactor. No wire policy changes.
- resistor_load_place.5 (choice) Only the linked twelve-member owner
  leaves at least two tap lengths plus clearance between each resistor
  output and its input drain. The source has two distinct branch rows;
  this configured spacing is a bounded candidate, not a universal routing
  guarantee. Strict compact orders do not retain a numeric distance.

Data: cold 24/48-byte owners, actual classes and coordinates in; at most
twelve poses/positions out. Fixed stack scratch, no allocation. Forty
caller-owned i32 pairs per stage bound requests (twenty per axis).
Placement is canonical/sequential because owners share collision room.
No routing-loop abstraction, retained state or speed claim.

Contents: place, orders; private actual-frame transaction helpers.

## src/resistor_load_wires.zig

Successful closed load stages -> checked actual four-terminal trees.

Human Rules:
- resistor_load_wires.1 (bounded observation) All three certified source
  stages put the horizontal load bar through both resistor tips, with
  a drain branch and outward gate branch. This specific tip turn differs
  from generic trunk.13. Source: docs/research/resistor-load-stages.md.
- resistor_load_wires.2 (invariant) Consume successful six-device owners,
  never infer ownership from four points. Require every declared pin to
  equal its transformed actual lead; hidden, projected or extra pins
  abstain. Keep all ordinary Canvas body/contact/crossing rules.
- resistor_load_wires.3 (boundary) Explicit sequencing, styles and ports
  win. Only a current automatic internal net is seeded after rails.
  Later thinning remains ordinary: cut/label rounds do not seed it.
  Commit the entire tree or restore every earlier route/point/segment;
  mark drawn only after success. No terminal-list or mate-table edits.
- resistor_load_wires.4 (bounded observation) The linked twelve-member
  source has two complete three-terminal output trees. Keep each local
  resistor-to-drain interval whole; branch on distinct interior rows.
  Approach the inward gate directly and the outward gate below both
  complete bodies. Both trees commit together under normal Canvas rules.
  This one candidate requires the observed actual frame; no wire budget
  exemption or universal spacing claim follows from it.
- resistor_load_wires.5 (choice) Keep the outer branch's column strictly
  before the inward branch. Move its lower row past every actual body
  intersecting that row, scanning all bodies before each update so their
  enumeration order changes nothing. At most one increase per body is
  possible. Foreign wires, points and vertical obstructions still decline
  the whole pair; the ordinary crossing budget remains unchanged.

Data: borrowed successful 24/48-byte owners and per-net tables, consumed
once per wiring pass. At most six u32 pin handles, six points, two owner
rectangles and four Lines are bounded stack scratch. Canvas owns all
output allocations; no retained graph,
new hot struct, per-net scan, allocation table or speed claim.

Contents: seed; private exact-pin mapping and one candidate transaction.

## src/resistor_loads.zig

Closed resistor-loaded differential stages -> cold placement owners.

Human Rules:
- resistor_loads.1 (bounded observation) Three source stages have one
  diode PMOS, two resistors, one NMOS input pair and one grounded NMOS
  tail. Count complete load/tail incidence and raw drain competitors
  before model, visibility or caller-frame checks. No name/value test.
  Source: docs/research/resistor-load-stages.md; `find`.
- resistor_loads.2 (bounded priority) Two stages whose outputs drive
  the other's input gates and whose tails form one complete automatic
  bank own twelve devices together. Their separate local axes and left
  tail gates refine the generic bank/global-axis arrangement. Keep all
  mate identities; actual drawing symmetry validation remains in force.
- resistor_loads.3 (boundary) Admitted caller geometry, grouping and
  symmetry requests win for the whole owner. Only its own input pairs
  and, for a linked owner, its complete tail bank may touch it. External
  or incompatible mates and other crossing blocks abstain. `collect`

Data: borrowed CSR/model/role/admission tables in; cold six-handle and
two-stage records out (24/48 bytes). At most PMOS-count raw candidates; disjoint survivors use six devices. Each
record is consumed together once per placement phase; no hot table or
ABI changes. Caller-owned lists/order storage live through one draw;
every allocation precedes geometry mutation. Canonical stage ordering
fixes sequential collision decisions. No hot-loop or speed claim.

Contents: Group, Pair, Batch, Batch.deinit, collect; private topology/admission queries.

## src/root.zig

SPICE netlist in, placed schematic out. See docs/API.md for the usage code
this surface was written from, and docs/ALGORITHM.md for the layout.

Human Rules: none of its own; it runs the stages, whose files list the
rules.

Tiers, coarse to fine — each is the one below it with the choices made:

| call | gives you |
|------|-----------|
| `place(gpa, cfg, lib, sources, diag)` | an owned `Placed` |
| `Pipeline.run` | a borrowed `Placed`, pages reused across documents |
| `netlist.parse` → `guessRoles` → `layout` → `Placed.init` | every stage, each usable alone |

The caller's `Library` supplies primitive symbols and may override every
subcircuit glyph; recognized blocks have conventional generated symbols.

Contents (the new shared glyph entry; the existing exports follow below):
- `pub const device = @import("device.zig")`
- `pub const library = @import("library.zig")`
- `pub const block_symbols = @import("block_symbols.zig")`

## src/routes.zig

Routes (issue #8, stage 4): the nets no pattern of `wires.zig` drew, by
the maze router (`maze.zig`). In: the canvas, the waiting nets and every
net's pins, and the drawing's mirror if it has one. Out: their wires,
ports and labels.

Human Rules:
- routes.1 (unmeasured) A net the mirror maps to itself is drawn
  mirrored: its left pins joined to each other or to the axis, the
  axis between the points reached (and the net's pins on it) as a
  spine, and the left half's mirror image. `halves`
  Narrowing: only when the axis falls on the grid, every pin off it has
  its mirror image, and every pin on it faces along the spine from its
  end; else the net is routed as any other.
- routes.2 (habit) A net's mirror mate is drawn as the mirror image
  of the net's wires (the cross-coupled pair's X: each output runs to
  the opposite gates), whatever drew the net: a pattern of `wires.zig`
  or the router. People: 1,070 of 1,112 pairs of nets whose pins are
  each other's mirror image (5,263 hand-drawn schematics). `mirrored`
  Narrowing: only when every pin of the net was joined and the mate's
  pins are its pins' images; else the mate is drawn on its own.
- routes.3 (choice) A routed net grows from its topmost (then leftmost)
  pin, the unjoined pin nearest a joined one next (the upper on a tie),
  each by the cheapest path to the net's wires so far: one fixed order,
  so card order chooses nothing. A prewired local tree instead receives
  every outside pin; no unconnected pin starts a second tree. `join`
- routes.4 (invariant) A net stays one net: a pin no path reaches
  carries the net's name, and then so does its first pin. `finish`
- routes.5 (unmeasured) An output's port leaves from the topmost of
  its wires' outermost points, on the drawing's nearer side: the right
  when the wires' middle is at or right of the drawing's. `port`

Contents:
- `pub const Mirror = struct { axis2: i32, net_mate: []const u32 }`
- `pub fn draw(c: *Canvas, waiting: []const u32, pins_of: []const std.ArrayList(u32), mirror: ?Mirror, anchors: []const u32) Allocator.Error!void`
- `pub fn attach(c: *Canvas, net: u32, pins: []const u32, anchor: u32) Allocator.Error!void`
- `pub fn port(c: *Canvas, net: u32) !void`
- `pub fn mirrored(c: *Canvas, net: u32, mate: u32, pins: []const u32, mate_pins: []const u32, from: usize, axis2: i32) !bool`

## src/schematic.zig

The schematic a layout fills (docs/ALGORITHM.md): each device as its
library class, the drawing's nodes (devices, terminal symbols, labels)
and pins, and its wires. Stage 1, the nets' roles (R1–R3), is here; the
stages that place and wire are `structure.zig`, `skeleton.zig` and
`sketch.zig`, and `placed.zig` exports the result.

Human Rules:
- schematic.1 (habit) A net named `vdd…`, `vcc…`, `avdd…`, `dvdd…`,
  `vpp…` or `v+` is a supply, drawn with a supply symbol (R1). People:
  rail symbols and no port on 4,010 of the 4,157 nets so named in 5,263
  hand-drawn schematics, a numbered one (`vdd1`, `vcc2`) in 22 of 22.
  `roleFromName`
- schematic.2 (habit) Net 0, and a net named `gnd…`, `vss…`, `vee…`,
  `agnd…`, `dgnd…` or `v-`, is a ground, drawn with a ground symbol
  (R1). People: rail symbols and no port on 5,467 of the 5,535 nets so
  named, a numbered one (`vss1`, `vee2`) in 10 of 10. `guessRoles`
- schematic.3 (habit) A net named `vb…` or `bias…` is a bias line,
  drawn as a port with its name (R1). People: a port on 2,926 of the
  3,241 such nets with no transistor's drain or collector on them, in
  5,263 hand-drawn schematics. `roleFromName`
  Wider than people draw: a bias line a drain or collector makes is a
  port here too, where of 1,138 such nets 834 carry no symbol (642 are
  drawn in pieces joined by the written name, 192 as one wire) and 59
  an input port. Read as inner nets and wired, they draw 557 crossings
  and 1,966 corners more over 5,263 circuits: the pattern is the
  written name, which is the wiring's to draw (wires.13).
- schematic.4 (habit) A net named `vin…`, `in…` or `vref…` is an
  input port; one named `vout…`, `out…` or `vo` an output port (R1).
  People: a port and no output on 2,650 of the 2,677 nets named
  `vin…` or `in…` and on 580 of the 627 named `vref…` with no drain on
  them; a port and no input on 3,894 of the 3,935 named as an output.
  `roleFromName`
- schematic.5 (habit) A `vref…` net a transistor's drain or collector
  makes is an output port, not an input. People: none of the 11 such
  nets carries an input port (4 an output port, 6 a plain one): too
  few to be a rule of its own, kept for the reference a circuit makes.
  `guessRoles`
- schematic.6 (unmeasured) An unnamed net a voltage source drives from
  ground is an input port when the source carries a signal (`ac`,
  `sin`, `pulse`, `pwl`, `exp`, `sffm`, `am`, `trnoise`, `trrandom`),
  else a bias port, unless a `*@ driver <src> inline` line keeps the
  source in the circuit (R2). The hand drawings hold no bench to test
  it on: each is a cell (schematic.9). `guessRoles`, `isSignalSource`
- schematic.7 (habit) A circuit of parts (no transistor) with no pin on
  a ground stands on one bottom wire drawn with no ground symbol: the
  internal net of two pins or more that most two-pin cards end on
  (second pins less first pins; a voltage source's minus and the pin a
  current source draws from count double, a controlled source's ends
  as a part's), then the one with the most pins, then by name; unless
  a `*@ role <net> ground` line names the ground. People: 172 of 191
  connected pieces in 5,263 hand-drawn schematics, and that score
  names the wire in 77.9%; counting a controlled source's low end
  double as well names it in 47 of the 63 circuits that hold one,
  against 50. `reference`, `isReference`
- schematic.8 (choice) A `*@ role <net> <role>` line sets that net's
  role over every guess, the preferred line last: the deck's author
  knows what the net is. `guessRoles`
- schematic.9 (unmeasured) A voltage source from ground to a supply,
  input or bias net is not drawn in the circuit: the net's terminal
  symbols stand for it there, and it is drawn apart (R3). The hand
  drawings hold no bench to test it on; in a cell people wire such a
  source where it stands (1,017 of 1,018), which a `*@ driver <src>
  inline` line asks for. `isDriver`
- schematic.10 (habit) An `E` that is a dependent source, not an
  amplifier, is drawn as the library's two-pin `vcvs` symbol, where it
  has one. People: a two-pin source symbol for 37 of 37 `E` cards (464
  of 464 with `G`, `F` and `H`) in 5,263 hand-drawn schematics, none of
  which draws an `E` as an amplifier. `initDevices`
- schematic.11 (choice) A `*@ class <dev> <class>` line draws a device
  as that class only when the class has as many terminals as the one
  it replaces: every pin drawn before stays drawn. `initDevices`
- schematic.12 (habit) A device's row line passes through the middle
  of its left and right pins, its column line through the middle of
  its upper and lower pins: with several on a side, the middle one's
  line, pin or not. So two pins facing each other stand on one line.
  People: 6,581 of the 6,694 nets of two pins facing each other along
  a row or a column in 5,263 hand-drawn schematics. `settleDevices`
- schematic.13 (unmeasured) An amplifier symbol's reference terminal
  on ground (the class marks it: a controlled source's minus output),
  like a MOS body, is part of the symbol and gets no wire. The hand
  drawings draw no `E` as an amplifier to test it on; a two-pin
  source's minus on ground is a pin with its wire there, in 164 of
  164, and here. `referencePin`
- schematic.14 (choice) An upright device is its symbol turned a
  quarter left, then flipped as the layout asks: unflipped, a MOSFET's
  drain is up, its gate left, its source down. People: the gate left
  of 17,977 of 28,715 upright transistors, right of the rest: a side
  the layout chooses, not this form. `form`
- schematic.15 (invariant) A pinless card has no drawable class. A
  coupling (`K`) stays in the netlist without creating a symbol, as in
  ag-1101 and ag-1157; class hints cannot give it pins. `initDevices`
- schematic.16 (choice) A selected controller's output supplies its
  column line: 67 of 75 source SVG outputs face up on their main gate's
  x; eight face right. Cached terminals claim 75 aligned columns and
  do not establish artwork direction. The chosen line must remain
  between the visible perpendicular pins;
  moving it past one would reverse its required reach. Hidden/reference
  pins do not constrain the line or contribute reach. `alignPin`

Contents:
- `pub const structure`, `pub const skeleton`, `pub const sketch`
- `pub const Circuit`, `pub const DeviceKind`, `pub const Side`, `pub const Library`, `pub const ClassId`, `pub const Orient`, `pub const Pt`
- `pub const none: u32`, `pub const max_pins`
- `pub const Role = enum(u8)`, `Role.isRail(r: Role) bool`, `Role.isPort(r: Role) bool`, `pub const Orientation = enum(u1)`
- `pub const DeviceInfo = struct`, `pub const NodeKind = enum(u8)`, `pub const Node = struct`, `pub const Pin = struct`, `pub const Route = struct`
- `pub const Schematic = struct`, `Schematic.deinit`, `Schematic.pinSide`, `Schematic.reach`, `Schematic.pinPoint`, `Schematic.deviceNode`, `Schematic.boxAt`, `Schematic.addNode`, `Schematic.addPin`
- `pub fn guessRoles(gpa: Allocator, nl: *const netlist.Netlist) Allocator.Error![]Role`
- `pub fn isReference(nl: *const netlist.Netlist, roles: []const Role, net: u32) bool`
- `pub fn roleWord(word: []const u8) ?Role`
- `pub fn initDevices(gpa: Allocator, nl: *const netlist.Netlist, roles: []const Role, lib: *Library) !Schematic`
- `pub fn settleDevices(s: *Schematic, circuit: *const Circuit.Graph) void`
- `pub fn settleDevice(s: *Schematic, circuit: *const Circuit.Graph, d: u32) void`
- `pub fn alignPin(s: *Schematic, circuit: *const Circuit.Graph, d: u32, pin: usize) bool`
- `pub fn isDriver(circuit: *const Circuit.Graph, roles: []const Role, d: u32) bool`
- `pub fn referencePin(s: *const Schematic, d: u32, pin: usize, net: u32) bool`
- `pub fn form(o: Orientation) Orient`

## src/sequence.zig

The deck's `order` lines (steering rung 2): devices left to right. In:
the netlist, its structure, and the skeleton's tables as each stage
leaves them. Out: the column links that would break an order refused,
the columns reordered, bridges set between their neighbours (and on the
rows `row` lines give them), and a verdict per line.

Human Rules:
- sequence.1 (invariant) The devices an `order` line names stand left to
  right in that order, each left of the next. `read`
- sequence.2 (choice) Of `order` lines that close a cycle, the strongest
  stand and the rest are dropped with their preferred conflict: the
  deck's own ranking of its lines. `read`
- sequence.3 (unmeasured) An `order` line on mated devices also holds
  for their mirror images, reversed, where every device it names has a
  mate of its form and the image closes no cycle with any line. `read`
- sequence.4 (invariant) Upright devices that a chain of "left of" pairs
  joins through bridges alone stand in that order: `order a b` and
  `order b c` with b a bridge put a's column left of c's. `read`
- sequence.5 (invariant) Two upright devices one line orders stand in
  different columns: the engine makes no link between them.
  `Sequence.refuses`
- sequence.6 (choice) The columns move as little as the lines allow: a
  stable order by present x, and columns that shared an x and that no
  line separates keep sharing it. `columns`
- sequence.7 (invariant) A bridge an `order` line names stands right of
  every device before it in a line and left of every one after it; with
  no free cell there it stays, its line relaxed. `bridges`
- sequence.8 (choice) A bridge a line places takes the free cell nearest
  its own (on the row a `row` line gives it), bridges a line puts first
  placed first, then in canonical order: moving as little as possible.
  `bridges`

Contents:
- `pub const Sequence = struct`, `Sequence.refuses(s: *const Sequence, gpa: Allocator, above: []const u32, u: u32, l: u32) Allocator.Error!bool`
- `Check.holds(ck: Check, lines: []const u32) Allocator.Error!bool`: the admission test `hints.conflict` calls
- `pub fn read(gpa: Allocator, arena: Allocator, nl: *const Netlist, st: *const Structure, drawn: []const bool, form: []const Form, verdicts: []?Verdict) Allocator.Error!Sequence`
- `pub fn columns(gpa: Allocator, s: *const Sequence, column_of: []const u32, col_x: []i32) Allocator.Error!void`
- `pub fn bridges(gpa: Allocator, s: *const Sequence, bridge_row: []const u32, by_rank: []const u32, drawn: []const bool, form: []const Form, x: []i32, y: []i32, verdicts: []?Verdict) Allocator.Error!void`

## src/skeleton.zig

Stage 3 of issue #8: where each drawn device stands, as a cell of a
lattice. In: the netlist, its roles and its structure. Out, per device:
drawn or not; its form (vertical: current enters at its top and leaves
at its bottom; horizontal: a bridge between columns); which side its
gate faces; its x and y. Neighbouring device columns stand eight
lattice columns apart and device rows two apart, so a channel lies
between any two: taps, bridges and wires go there. Forms are
`forms.zig`'s, mates `mates.zig`'s, rows `levels.zig`'s, column order
`columns.zig`'s, flat parts `bridges.zig`'s, shelves `wrap.zig`'s.

Human Rules:
- skeleton.1 (order: potential) Upright devices stand in one column
  when one's lower end and the other's upper end are one net, never
  through a rail; a column is a chain current flows down. `link`
- skeleton.2 (unmeasured) Where several devices meet on a net, a stack
  block's two (hinted or recognized) share a column first. `choose`
- skeleton.3 (unmeasured) No column runs through a pair: where the
  devices above or below a net are two mates or a differential or
  cross-coupled pair, nothing links across it, and the pair's tail
  stands in a column of its own. `choose`
- skeleton.4 (habit) Else the link follows the current: the device
  below is of the upper one's type first; then, on either side, a
  transistor before a part and a part direct current passes before a
  capacitor, which hangs beside the column. People, on the nets where
  one device meets several that differ on it, in 5,263 hand-drawn
  schematics: the same type 278 of 291, a transistor 369 of 401, direct
  current 749 of 778. Then one whose column reaches a rail, the engine's
  tie-break (people: 261 of 465), then rank. `choose`
- skeleton.5 (invariant) The net the symmetry pairs with a net gets
  the mirror image of its link. `link`
- skeleton.6 (choice) Device columns stand 8 lattice columns apart and
  device rows 2 apart: a channel between any two holds taps, wires and
  seven bridge slots. `lay`
- skeleton.7 (invariant) Mated upright devices stand mirror images
  about one axis; a pair a line moves apart, or a device its own mate
  whose column left the axis, is mated no more. `lay`
- skeleton.8 (invariant) No two drawn devices share a cell.
  `expectDistinctCells`
- skeleton.9 (habit) A transistor's gate faces the mean of the rest of
  its gate net, what drives it and what it drives with it. People:
  4,558 of 5,685 transistors of no block in 5,263 hand-drawn schematics
  (3,982 of 4,374 where a current path drives the net). `gates`
- skeleton.14 (order: signal) A gate with nothing in the drawing to face
  (alone on its net, or on a rail) faces left, the side its signal
  enters by; one with a mate elsewhere faces away from its mate, the
  mirror image (skeleton.7). People: 2,684 of 3,317 left, 283 of 367
  away from the mate; away from the drawing's middle, the rule this
  replaces, 1,914 of 3,043. `gates`
- skeleton.10 (habit) A differential pair's gates face out. People:
  1,396 of 1,579 pairs in 5,263 hand-drawn schematics. `gates`
- skeleton.11 (habit) The two of a mirror or cross-coupled pair face
  each other. People: 2,685 of 3,130 mirrors of two and 214 of 239
  cross-coupled pairs. A bank's two do too here, a choice: people 962
  of 1,968 (600 face out). A mirror or bank of three or more has no
  rule of its own: skeleton.9 turns each gate (people turn all of one
  left, the rule retired as skeleton.12, in 12 of 1,103 such mirrors
  and 88 of 380 banks). `gates`
- skeleton.15 (habit, bounded) A two-MOS bank with one complete analog
  block output and otherwise only capacitors on its gate net faces an
  exterior driver. All 42 actual source gates in 21 selected banks do
  so. Keep existing mates, ambiguous incidences and an interior driver;
  explicit faces still run last. No source row or universal wire-tree
  policy follows: 17 banks occupy unequal rows and two have a detached
  remote gate. docs/research/driven-banks.md; `bankDriver`, `gates`
- skeleton.13 (choice) A flat part `forms.crooked` stands upright
  (forms.15) is placed by laying the whole drawing again, not moved
  alone: it then follows every rule an upright part does. `place`

Contents:
- `pub const Form = enum(u8) { vertical, horizontal }`
- `pub const End = enum(u8) { auto, first, second }`
- `pub const Skeleton = struct`
- `pub const Options = struct { shelf: u32 = (config.Layout{}).shelf }`
- `pub fn place(gpa: Allocator, arena: Allocator, nl: *const Netlist, roles: []const Role, st: *const Structure, opts: Options) Allocator.Error!Skeleton`
- `pub const Invalid = error{...}`, `pub fn validate(sk: *const Skeleton, nl: *const Netlist) Invalid!void`

## src/sketch.zig

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

## src/span.zig

What an order of the columns costs (issue #8, stage 3): the span of its
wired nets, and how far it runs against the signal's way. In: the
columns' context (`columns.Ctx`) and each column's x. Out: a cost,
lower the better; and whether the signal enters on the left.

Human Rules:
- span.1 (unmeasured) Columns stand in the order that makes the wired
  nets narrowest: each from its leftmost column to its rightmost, plus
  the gap a flat two-pin device between two wired nets crosses. `span`
- span.2 (order: signal) A pin stands right of the device that drives
  its net, on every net but a rail: a gate after its driver, a load
  after its stage. Counted before any width, with a mirrored core or
  without. People: 5,614 of 7,584 gates in circuits with a core stand
  right of or level with the leftmost device driving their net, 1,863
  of 2,507 in circuits without (74% both), in 5,263 hand-drawn
  schematics: a tendency pin by pin (where the signal comes back round
  a loop one pin must stand left), a rule of the whole drawing
  (columns.13). `against`
- span.3 (order: signal) The columns that read an input stand, on
  average, no further right than those that drive an output; else the
  whole row is turned end for end. People: 893 of the 931 hand drawings
  with a named input and output that run either way run left to right.
  `flowsRight`
- span.4 (habit) In a circuit of parts the signal enters at its
  source, on the left. People: the part farther from the source stands
  right of the nearer in 90.1% of 1,676 pairs in 5,263 hand-drawn
  schematics. `flowsRight`
- span.5 (choice) With no output named, a circuit of parts ends at
  the middle of its columns: something must stand for the far end.
  `flowsRight`

Contents:
- `pub fn span(ctx: Ctx, x: []const i32) !i64`
- `pub fn flowsRight(ctx: Ctx, x: []const i32) bool`
- `pub fn isChannelPin(ctx: Ctx, d: u32, pin: usize) bool`

## src/structure.zig

Stage 2a of issue #8: the circuit's structure, from its connectivity
alone. In: the netlist and its nets' roles. Out, per device and net in
card order:

- a canonical order of devices and of nets;
- blocks, the groups a designer draws as one unit;
- the left-right symmetry (`symmetry.zig`), under the deck's lines.

Data: one row per device and per net (u32 handles, `none` = no mate);
blocks as kind + start offsets + members (each device in at most one row
block and one stack, so members ≤ 2 × devices). Everything is computed
once per schematic; temporaries are freed before `analyze` returns.

Cites: T. Massier, H. Graeb, U. Schlichtmann, "The Sizing Rules Method
for CMOS and Bipolar Analog Integrated Circuit Synthesis", IEEE TCAD
27(12), 2008 (blocks as groups of transistor pairs); symmetry.zig's.

Human Rules:
- structure.1 (invariant) The drawing does not depend on the order of
  the cards: every tie is broken by the canonical order of device and
  net names. `rankByName`
- structure.2 (choice) The canonical order is natural: a run of digits
  reads as a number (`m2` before `m10`), the rest bytewise: a tie needs
  a breaker that the cards' order cannot be. `nameLess`
- structure.3 (invariant) A `symmetric a b` line draws a and b as each
  other's mirror image, an `axis x` line puts x on the mirror axis, and
  `symmetry off` draws no mirror at all, not even a block's. `mates`
- structure.4 (choice) Of `symmetric` and `axis` lines that no one
  symmetry satisfies together, the strongest stand and the rest are
  dropped; `symmetry off` drops them all: the deck's own ranking of
  its lines. `mates`
- structure.5 (invariant) A `group` line's devices are drawn as one
  block of the kind it names, as written (a stack top to bottom); a
  device a `nogroup` line names is in no block; `grouping off` leaves
  only the named groups. `groupLines`
- structure.6 (choice) Of `group` lines that name one device, the
  strongest takes it (a stack line and another kind may share it): the
  deck's own ranking of its lines. `groupLines`
- structure.7 (book) Two transistors of one type, each one's gate on the
  other's drain (neither net a rail), are drawn as one block, a
  cross-coupled pair. Massier, Graeb and Schlichtmann (Cites). `blocks`
- structure.8 (book) The only two transistor sources on a net that is no
  rail and holds no gate, of one type, with distinct gates and distinct
  drains, are drawn as one block, a differential pair. Massier, Graeb
  and Schlichtmann (Cites). `blocks`
- structure.9 (book) Two or more transistors of one kind and polarity
  on one gate net (no rail), one of them diode-connected, are drawn as
  one block, a current mirror. Massier, Graeb and Schlichtmann (Cites).
  `blocks`
- structure.10 (book) The same with none diode-connected (current
  sources on a bias line, cascodes) are drawn as one block, a bank.
  Massier, Graeb and Schlichtmann (Cites). `blocks`
- structure.11 (book) Transistors in series, each one's lower end alone
  with the next one's upper end on a net that is not a rail, are drawn
  as one block, a stack, top to bottom. Massier, Graeb and Schlichtmann
  (Cites). `blocks`
- structure.12 (habit) A transistor is in at most one of a
  cross-coupled pair, a differential pair and a mirror or bank, taken in
  that order; a stack may share it. People: of 93 twos that are both a
  cross-coupled and a differential pair (a latch on a tail), 88 turn
  their gates toward each other, as a cross-coupled pair's; of 190
  transistors of a pair that stand level with the pair's other or with
  another transistor on their gate net, not both, 153 stand with the
  pair's (5,263 hand drawings). `blocks`
- structure.13 (habit, bounded) The complete paired CT-bank network
  of AG1180 reflects whole banks and their two private C-S-C paths.
  Try that graph-proved reflection before maximizing moved devices;
  combine it with admitted caller symmetry, and retain ordinary search
  if the trial fails. Global grouping/symmetry off exclude it. The
  source contains one such context. `mates`; coil_network.preferred

Contents:
- `pub const none: u32`
- `pub const BlockKind = enum(u8) { pair, cross, mirror, bank, stack }`, `BlockKind.ofTwo(k: BlockKind) bool`, `BlockKind.verb(k: BlockKind) hints.Verb`
- `pub const Structure = struct`, `Structure.members(s: *const Structure, b: usize) []const u32`
- `Pins.holds(p: Pins, lines: []const u32) Allocator.Error!bool`: the admission test `hints.conflict` calls
- `pub fn analyze(gpa: Allocator, arena: Allocator, nl: *const Netlist, roles: []const Role) Allocator.Error!Structure`
- `pub fn nameLess(a: []const u8, b: []const u8) bool`
- `pub fn rankByName(arena: Allocator, gpa: Allocator, names: []const []const u8) Allocator.Error![]u32`

## src/symmetry.zig

The left-right symmetry of a circuit (issue #8, stage 2a): an
involution on devices and nets that maps the circuit onto itself. In:
the netlist, its nets' roles and the canonical order. Out: each device's
and net's mate (itself on the axis), or `none` everywhere.

Devices and nets are the vertices of one graph, a pin an edge labelled
with its terminal. Colour refinement (1-dimensional Weisfeiler-Leman)
with individualization: two copies are refined, a vertex individualized
in one and a candidate image in the other, depth first, until both
colourings are discrete; the map is then read off the colours.

Cites: B. McKay, A. Piperno, "Practical graph isomorphism, II", J.
Symbolic Computation 60, 2014.

Human Rules:
- symmetry.1 (unmeasured) A circuit that maps onto itself by swapping
  devices and nets in pairs is drawn as a mirror image about one axis,
  each device opposite one of its own kind, polarity and pin count, each
  net opposite one of its own role; what maps to itself stands on the
  axis. `find`
- symmetry.2 (unmeasured) An input and a bias net count as one role: a
  pair driven with `ac` on one input and dc only on the other is still
  drawn mirrored. `initialColours`
- symmetry.3 (unmeasured) A device's mirror image keeps its terminals:
  gate opposite gate, drain opposite drain; a path's two ends may trade
  places only where the part does not tell them apart (a resistor's or
  a switch's may, a diode's may not). `preservesPins`
  Narrowing: each family keeps the label numbers it had, which order
  the colours and so which of equal symmetries is met first
  (`pinLabel`).
- symmetry.4 (unmeasured) A swap that moves no net but a rail (two
  parallel devices traded) is not drawn as a mirror. `movesSignal`
- symmetry.5 (book) Of the symmetries, the drawing shows the one that
  moves the most devices that are not sources: the Gilbert cell has
  three, and the book draws that one (no book named). `consider`
  Narrowing: only voltage sources are left out of the count; the device
  table's sources also take I, E, G, F and H (`movedDevices`).
- symmetry.6 (choice) Of symmetries that move as many devices, the
  first met in the canonical order is drawn: something must break the
  tie, and the order of the cards may not. `consider`
- symmetry.7 (choice) The search stops after `refines_max` (64)
  refinements or `candidates_max` (16) complete maps: a circuit of many
  identical cells has many symmetries, and the first few are as good as
  any. `complete`

Contents:
- `pub const none: u32`
- `pub const Polarity = device.Polarity`
- `pub const Pin = struct`
- `pub fn find(gpa: Allocator, nl: *const Netlist, roles: []const Role, device_rank: []const u32, net_rank: []const u32, pins: []const Pin, device_mate: []u32, net_mate: []u32) Allocator.Error!bool`
- `pub fn sameType(nl: *const Netlist, a: u32, b: u32) bool`
- `pub const polarity = device.polarity`

## src/thin.zig

Thinning (stage 4): the nets whose wires cross too many others, drawn
in parts joined by name instead. In: the drawing's routes, the nets'
roles and how the deck's lines style each net. Out: the style of each
net it thins set to `cut`, or `label` if it was `cut` already; the
caller wires the drawing again.

Human Rules:
- thin.1 (habit) No internal net's wire crosses more than `max` wires
  of other nets: past that the net is joined by name. People: of 43,282
  wired nets in 5,263 hand-drawn reference schematics (Analog Canvas
  gallery), 423 cross more than two others. `name`
- thin.2 (habit) A net over the budget is first `cut`: each group of
  near pins on one wire, one name a group (`wires.zig`). People: 75% of
  their named nets keep the pins that stand near each other wired.
  `name`
- thin.3 (choice) A `cut` net is named at every pin only when one
  physical part still crosses more than two other wires. Disconnected
  parts do not pool their budgets (AG2309/2318/2319). Route chunks
  meeting at an endpoint, T, overlap or same-net X form one part:
  `dots.2` puts a junction at the X. `name`
- thin.4 (book) A rail's wires are not counted: a gate line crosses the
  stubs up to the supply bar. Razavi Fig. 12.20. `name`
- thin.5 (choice) The net crossing the most wires goes first (on a tie,
  the first in the nets' canonical order), and the crossings are
  counted again without it, until none is over. Total crossings still
  rank eligible nets, including `cut` nets; the order of the cards
  chooses nothing. `name`
- thin.6 (invariant) A rail, a port and a net a deck line styles keep
  their wires: only internal nets the deck's lines leave to the engine
  are thinned. `steps`
- thin.7 (invariant) A thinned net's mirror image goes with it, so a
  mirrored drawing stays mirrored. `name`

Contents:
- `pub fn name(gpa: Allocator, routes: []const Route, roles: []const Role, rank: []const u32, net_mate: ?[]const u32, max: u32, style: []Style) Allocator.Error!bool`

## src/transmission.zig

Complementary parallel MOS channels, shared by placement and turning.

Human Rules:
- transmission.1 (habit) Two complementary MOS channels on the same
  unordered drain/source nets, with distinct gates outside those nets,
  form a parallel transmission pair. Among forms.19's selected AG
  circuits, ag-386 and ag-751 both put NMOS above PMOS in one column,
  clocks outward (2/2). Same-type pairs are excluded: ag-761's lower
  switch points inward. An ambiguous bank of three is not a pair.
  `mate`; bridges and sketch apply the geometry only to flat members.

Data: reads the existing netlist's MOS pin rows and model types, bounded
by one channel net's CSR incidences. Returns one device handle, borrowed
from that table; no storage, allocation, ownership or capacity changes.
The two callers own placement and orientation, respectively.

Contents:
- `pub fn mate(nl: *const Netlist, d: u32) ?u32`

## src/trunk.zig

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

## src/wire_requests.zig

Admitted geometry intent borrowed while scaffolding defers its execution.
Human Rules: absolute route/via and device-at requests still take
precedence over an automatic stage's routing preference before compaction.
Both CT control queries need the original slices; effective scaffold
routes and placements may temporarily be empty.

Data: two read-only slices owned by drawValid, alive through its wiring
phases. No allocation, flags, mutation or per-candidate query. The view
travels once per wiring call, and each cold stage checks its own members.

Contents:
- `pub const Requests = struct`

## src/wires.zig

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

## src/wrap.zig

Shelves (issue #8, stage 3): a row of device columns too wide for a page
is wrapped into rows of columns, one under the other. In: each drawn
device's cell and mate. Out: the cells, wrapped, and each one's shelf.

Human Rules:
- wrap.1 (habit) A row of more device columns than a page holds is cut
  into shelves of equal width, one under the other. People: their
  drawings of over 30 devices are 20 units wide at the median over 5,263
  hand-drawn schematics; one row of columns was 37. The page is the
  layout's (`config.Layout.shelf`, 8 columns, whose rule it is; 0 keeps
  one row); `*@ shelf <columns>` sets it for a deck, `*@ shelf off`
  keeps one row. `cut`
- wrap.2 (unmeasured) Each cut goes between the two columns the fewest
  nets but rails cross, within a third of a shelf of its equal-width
  place (ties: the nearer). `cutCost`
- wrap.3 (invariant) No cut parts a device from its mate: the mirrored
  core stays whole on one shelf and keeps its x. `cutCost`
- wrap.4 (unmeasured) Every shelf starts at the left edge of the core's
  shelf, or of the first shelf when there is no core. `cut`
- wrap.5 (choice) No cut parts an honoured `row` or `order` group,
  or puts an `above` line's upper device on a later shelf than its
  lower device. Left shelves precede right shelves, so an upper-left
  to lower-right pair may cross a cut. Rejected, dropped and unhandled
  instructions impose no cut restriction. Admission and bridge
  placement have already set these verdicts.
  A deck with `cell` or strong `at` lines is not wrapped: those are
  places of the drawing as it stands (relaid from a `weak at` stay,
  a deck wraps as it did). `cut`, `cutCost`
- wrap.6 (choice) Shelves stand `shelf_gap` (6) lattice rows apart, and
  a shelf's rows that only another shelf's columns filled are closed
  up: the shelves are read off the cells, so the engine's own decisions
  pasted back give the shelves they came from. A shelf containing a
  placed converter loop retains its reserved row gaps. `shelves`
- wrap.7 (habit, bounded) A certified converter's main PMOS–coil–PMOS
  path and its required grounded shunts and active gate drivers stay
  on one shelf. A cut must not undo their channel order or put the
  power path below its controls. Source: the 252 groups and 365/92
  shunt/driver relations in the power-path study. Unrelated bias
  columns may still wrap. Cell/at instructions and shelf-off retain
  their existing precedence. `cutCost`, `power_paths.controlBounds`
- wrap.8 (habit, bounded) Each unique upright outer reservoir stays on
  its main path's shelf. All 359 source capacitors stand beyond their
  main switch away from the coil; separate shelves can reverse that x
  order and put the capacitor above the path. Preserve existing cap
  columns and admitted rows/mates. `cutCost`, `power_paths.reservoir`
- wrap.9 (habit, bounded) A successfully placed flying-capacitor loop
  stays on one shelf. All 145 selected source groups keep its seven
  local nets continuous. The placement pass supplies only spans whose
  members accepted the group layout; caller-constrained groups do not
  acquire this protection. Preserve that shelf's existing row gaps:
  sparse cell rows cannot reveal the supply stubs and bars occupying
  reserved room beside the lower return. AG1222 and 16 other selected
  cases lose their local tree when these gaps close before routing.
  Keeping the whole shelf's gaps is a conservative placement choice;
  later compaction measures actual ink and symbol clearance.
  `loop_place.place`, `cut`, `cutCost`
- wrap.10 (habit, bounded) A placed private grounded-source/resistor
  branch stays with its chosen MOS gate on one shelf. All 22 selected
  source branches have continuous source legs and a straight approach
  to that gate. Its two-row source drop is reserved with the protected
  interval, using the same caller-owned span mechanism. `input_place`
- wrap.11 (habit, bounded) A unique center-tapped coil and its parallel
  tank capacitor share a shelf. Cold collection supplies cut-only spans;
  it does not preserve all empty rows. A custom class may decline the
  later relative placement while retaining semantic grouping. `coil_tanks`

Contents:
- `pub fn shelves(gpa: Allocator, nl: *const Netlist, roles: []const Role, drawn: []const bool, form: []const Form, mate: []const u32, columns: u32, x: []i32, y: []i32, shelf: []u32, verdicts: []?hints.Verdict, protected: []const [2]i32) Allocator.Error!void`

## tools/schemify/recognize.zig

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

