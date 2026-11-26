# Center-tapped inductor: exact symbol contract and box baseline

The exact `ct_inductor` family has 19 outer instances in 13 Analog-Genie
circuits. Every actual source glyph has two collinear coil halves, a short
central bridge, a perpendicular midpoint lead and a filled junction dot.
Frozen iteration 12 draws all 19 as boxes. This supports a bounded symbol
contract; it does not establish an orientation or placement rule.

[center_tap_symbols.py](figures/center_tap_symbols.py) scans all 2,202 AG and
734 AMSNet decks and source terminal tables. The [inventory](figures/center_tap_symbols_cases.json)
compares exact selected names, records each source triple's hash and every
actual SVG primitive, and verifies the native drawing against frozen corpus
JSON. Identical cubic path data is stored once by content hash. Its unknown
family census excludes recognized families; it is not a census of incomplete
contracts that still produce boxes within recognized families. No selected
or unknown outer family in this census occurs in AMSNet.

## Contract and pin identity

Proposed recognition: the whole, case-insensitive name `ct_inductor`, with
exactly the three unique declared ports `N1`, `N2`, `N3`. A reordered
declaration retains its order and binds geometry by port name. Extra,
missing, duplicate or unfamiliar ports remain outside this contract.
This is an appearance contract for an electrical subcircuit, not a new
primitive or an inference from arbitrary internal circuitry.

Every observed declaration and body is:

```spice
.subckt ct_inductor n1 n2 n3 params: l1=1n l2=1n k=0
L1 n1 n3 {l1}
L2 n3 n2 {l2}
K12 L1 L2 {k}
.ends ct_inductor
```

**N1 and N2 are the outer ends; N3 is the midpoint tap.** The source asset
names these pins `1`, `2`, `3`. Its actual canonical SVG outer leads end at
(-50,0) and (50,0); the tap ends at (0,20). AG1190 extends the actual outer
lead strokes to ±60; its cache is correct. The central bridge spans
(-5.5,0) to (5.5,0), joining two open cubic coil paths ending at ±5. The tap
stroke begins at (0,-0.5), overlapping that bridge at the filled dot.
These half-unit overlaps are real source ink, not routing tolerances.

The audit locates the named device's own transformed SVG asset, then derives
the three endpoints from those actual primitives. **All 57 endpoints match
the cached terminal coordinates**, and all 57 source pin/net bindings match
the declared call order. The body above independently places the electrical
midpoint at N3. `tools/site/convert.py` obtains generated-body pin bindings
from the source electrical `pinOrder`; the SVG itself does not label nets.
All 19 observed calls use `l1=1n l2=1n k=0`. Shape evidence does not imply
measured inductance, nonzero coupling or a winding polarity-dot convention.

## Exact source orientations

The source coil axis is horizontal in 11 instances and vertical in eight.
The following lists cover every selected name; the detailed coordinates and
SVG object IDs are retained in the inventory.

| Tap direction | Instances |
|---|---|
| Up | ag-1114:x1, ag-1131:x1, ag-1147:x1, ag-1149:xlp, ag-1151:xl, ag-1152:xl1, ag-1152:xl2, ag-1153:xl2 |
| Down | ag-1146:x1, ag-1153:xl1, ag-1187:xtb |
| Right | ag-1103:xl1, ag-1168:x1, ag-1180:xle1, ag-1180:xlo1, ag-1190:x1 |
| Left | ag-1168:x2, ag-1180:xle2, ag-1180:xlo2 |

AG1114 shows a horizontal coil whose tap reaches the bias divider. AG1168
shows two vertical coils with taps facing inward toward their resistors.
AG1180 uses four vertical coils, including both tap directions. No universal
horizontal axis, tap-to-supply rule or source-ID placement exception follows.

## Boundaries and native evidence

AG1181's `tcoil` also declares N1/N2/N3, but its actual glyph contains an
additional capacitor bridge, two extra branch polylines and five circles,
including winding polarity marks. It must not be recognized as a plain
center-tapped inductor solely from its port count or port names.

The four `xfmr` instances (AG591:x1, AG592:x1, AG1182:x1/x2) declare
P_MINUS/P_PLUS/S_MINUS/S_PLUS and draw separate parallel windings with
polarity dots. They require a separate contract. The two `crystal` cases
also warn against broad name assumptions: AG645:x1 with A/B is an actual
source box; AG646:x1 with N1/N2 has a crystal glyph. Their full primitive
inventories are retained as comparisons, not admitted cases.

The frozen executable SHA-256 is
`8e4dcdd30bfa92280db56c117789ceebe851f5413ee56ac11926d9a449e3a03f`.
Re-rendering all 13 full DUTs produces JSON exactly equal to the frozen
iteration-12 wrap corpus. Ordered wire vertices establish the SVG display
transform. Each selected device owns a 60×120-unit rectangular outline, and
all 57 ordered native terminals/net bindings have their own visible box
leads. Native class names alone are not used to classify the body as a box.
This audit does not prove routing equivalence or label-overlap freedom.

## Proposed ownership and validation

`block_symbols` can own the exact recognition and canonical three-terminal
glyph. `Library.blockFor` and Schemify already share that owner and preserve
caller-defined symbols and explicit port-side directives. Keep the device
as a subcircuit; do not give it an ordinary two-terminal inductor's path or
reuse converter placement rules. Preserve every declared terminal and its
binding in both front ends.

Two existing representation limits need an explicit decision before claiming
full glyph parity. `DrawOp.circle` is white-filled by native SVG and LaTeX,
so it cannot currently represent the source's filled tap dot. Coil curves
can be approximated by existing polylines, but `tests/svg.zig` emits at most
64 vertices per operation; a copied dense source curve could be truncated.
Neither limit justifies quietly dropping source ink. Schemify's
`recognize.boxPins` currently derives input/output directions from left/right
glyph sides; passive coil ports need an intentional bidirectional treatment
that still respects explicit caller pin metadata.

The source audit compares the exact executed method-check names with this
expected list; its count is derived: `reject_tcoil`, `reject_xfmr`,
`reject_family_suffix`, `reject_duplicate_port`, `reject_extra_supply`,
`reject_unknown_ports`, `accept_case_and_port_permutation`,
`reject_missing_dot`, `reject_missing_coils`, `reject_hollow_dot`,
`reject_displaced_tap`. The [engine tests](../../tests/center_tap_symbols.zig) check
bilateral winding silhouettes, a connected midpoint branch assigned to N3,
ordered ports under permutations, an N2/N3 swap mutation, caller precedence
and source-bound negative families. The initial proposal kept these tests
unimported; checkpoint 21 has now exercised their missing-behavior failures.
This silhouette oracle alone does not certify placed electrical binding or exact curve/dot ink. Actual native SVG and Schemify export must
be checked as well; drawing-operation counts alone cannot establish parity.

Reproduce the baseline without a build:

```sh
python3 -B docs/research/figures/center_tap_symbols.py external/examples /tmp/center-tap-replay.json \
  --native-dir /tmp/center-tap-native \
  --baseline-dir /tmp/cktimg-human-rules/all-ag-iteration12-wrap \
  --bin /tmp/cktimg-human-rules/iteration12-wrap/cktimg-json
```

The source inventory remains the frozen iteration-12 baseline. The active
checkpoint-21 implementation and its curve certificate are described below.

## Proposed implementation boundary

The smallest complete extension needs a filled-circle drawing operation;
substituting a hollow circle, font bullet or several thin strokes would
not preserve the source dot across renderers. Append a `filled_circle` tag
after the existing line/polyline/circle/text tags. The existing circle tag
keeps its meaning and numeric value. The C header would add kind 4 while
retaining kinds 0 through 3, the `CktimgOp` record and all function
signatures. The existing circle accessor can return center/radius for
either circle kind, with the kind query distinguishing fill. This is an
additive C interface extension: existing records remain valid, but a
renderer using the old header must handle the new kind to display it.
Public Zig consumers with exhaustive drawing-operation or shape switches
must add the new cases.

`block_symbols` would append a `center_tap` shape and dispatch its verified
three-name contract to a private drawing helper. Passive terminals should
not borrow amplifier input/output roles. A finite integer table can
approximate each source winding as a separate open polyline, with exact
shared endpoints at the outer leads and central bridge. Each winding must
remain within the SVG writer's current 64-point limit; a compile-time
bound and complete-path rendering check are needed. This is an integer
approximation to cubic ink, not a claim of pixel-identical curves. Its
deviation must be measured against the source path before acceptance.

The necessary owners are:

- `src/block_symbols.zig`: exact recognition and canonical geometry.
- `src/library.zig`: the drawing tag, copying and body bounds.
- `src/abi.zig` and `include/cktimg.h`: registration, kind and circle access.
- `src/latex.zig`, `tests/svg.zig` and `tools/schemify/emit.zig`: filled
  disk output. `tests/svg.zig` is also the native command-line SVG writer.
- `tools/schemify/recognize.zig`: all three recognized passive pins are
  bidirectional. Existing explicit PININFO and side directives retain
  precedence; left/right geometry must not imply signal direction.

Schemify's format already supports rank-2 `circle` with `fill true`, and
its current symbol renderer reads that attribute. No new Schemify record
form is needed. Its standard outline stroke still applies, so source
stroke thickness and subpixel dot radius are not identical rendering
contracts. Native SVG and LaTeX can emit the filled disk directly. Symbol
ink does not create external electrical connections: N1, N2 and N3 retain
three distinct declared subcircuit terminals.

The six data answers are:

1. An exact family name and three ordered port names become a verified
   shape and the existing terminal/drawing-operation arrays.
2. Each registration has exactly three terminals, two bounded winding
   paths and a fixed set of lead, bridge, tap and disk operations. There
   are 19 selected source instances, but no source-instance lookup is
   needed at runtime.
3. Shape remains `enum(u8)`. Existing operation values must remain fixed;
   adding the fifth operation may widen Zig's inferred tag bit count and
   requires measured union-size checks, not an assumed layout guarantee.
   Canonical integer coordinates fit a signed byte table; transformed
   coordinates and radius use the existing `i32` geometry range.
4. Registration reads port names sequentially; rendering walks existing
   contiguous operation and point slices. There is no new placement scan,
   graph, flag array or retained topology state.
5. The caller-owned arena holds the generated terminals and points. The
   existing registration copy and error-cleanup contract remains in force.
6. Registrations are independent and preserve declaration order. There is
   no shared mutable state, new parallel scheduling or performance claim.

## Required tests before activation

The original prospective engine tests established the named midpoint and
winding silhouette. Before checkpoint 21, their oracle was strengthened
with own-winding attachment and literal missing/hollow/displaced-dot and
disconnected-coil mutations.
Case and all declaration permutations must retain named geometry. Full
placed fixtures should exercise horizontal and vertical source examples
without demanding their source world orientation.

Separate renderer tests must distinguish the new disk from the existing
hollow circle in SVG, LaTeX and emitted Schemify records. An ABI fixture
must register both kinds, verify old numeric tags, query the transformed
center/radius and show that the new operation contributes to bounds.
Schemify tests must check all three emitted directions as bidirectional,
literal terminal-to-net bindings, compatible and conflicting PININFO,
explicit sides and caller-library precedence. A checked no-metadata
fixture may request names with `.save` so otherwise unused singleton nets
are observable without changing their electrical binding.

These tests must fail on the missing behavior before implementation. Then
the 19 actual source bodies and 57 ordered bindings need independent
native/export checks, followed by whole-corpus change-name comparison,
electrical round trips, renderer gates and the existing WASM size cap.
This proposed symbol work does not select source-facing orientations or
make converter placement claims.

## Checkpoint 21 curve certificate

The active implementation appends the `center_tap` shape and delegates its
bounded drawing to `src/center_tap.zig`. Two runtime polylines share one
61-point signed-byte table; the second is translated by (50,0). The helper
fills three terminals in declared order and appends seven operations.
It adds no placement rule or retained topology metadata. The separate
filled-circle, renderer, ABI and passive-direction changes are being
validated with it; this section records no completed native-corpus result.

[center_tap_curves.py](figures/center_tap_curves.py) and its
[exact certificate](figures/center_tap_curves_cases.json) derive that table
from the two common source paths, each containing 23 cubic segments and two
straight segments. They verify the exact 19 names and source path/inventory
hashes, and compare the generated table with the current runtime table.
At standard library unit 40 (pitch 20), the winding point-sets have a
**two-sided Hausdorff distance at most 0.702219516315 source units**.

The generator subdivides cubics using exact rational arithmetic. A separate
verifier reconstructs each restriction from Bernstein endpoint values and
derivatives and checks a contiguous partition. Every control lies within
0.1 units of its chord. The chord's capsule is convex, and the curve's
continuous projection reaches both endpoints, giving the bound in both
directions. Rounding corresponding vertices contributes at most
0.602219516315 units. An independent monotone-collinear trace check proves
that reducing 95 chord vertices to 61 retained integer points preserves
the rounded polyline point-set, including its backtracking.

The exact method list contains 19 checks, including altered control,
missing leaf, overlapping interval, moved integer vertex, deleted turn,
wrong endpoint, capacity overflow, hidden backtracking, changed winding
translation, source hash and runtime table mutations. The emitted native
curves still require a separate renderer audit. The bound excludes stroke
thickness, dot radius, leads and world placement. Ideal uniform scaling
multiplies it; integer rescaling at other pitches adds error and is outside
this standard-scale certificate. Radius 4 differs from the source radius
3.77907 by 0.22093 units. Integer leads use shared endpoints instead of the
source half-unit overlaps, and AG1190's longer outer leads remain a named
canonical-length mismatch.

```sh
python3 -B docs/research/figures/center_tap_curves.py /tmp/center-tap-curves.json --check
```

Before implementation, the glyph suite failed the actual winding/midpoint
and filled-dot assertions, while contract and caller-precedence controls
passed. The boundary suite separately failed the numeric kind-4 C
registration and filled renderer/body-bound assertions. These meaningful
failures are recorded in `iteration21-glyph-red.log` and
`iteration21-boundaries-red.log`; completed checkpoint validation is pending.
