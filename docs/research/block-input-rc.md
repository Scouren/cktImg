# Paired input RC branches anchored to an actual block frame

This is a source certificate and a placement prototype under validation.
The complete 2,936-deck census has three broad matches, all in AG1103:
`ag-1103:x1`, `ag-1103:x2`, and `ag-1103:x3`. The bounded downstream predicate
selects exactly `ag-1103:x2` and `ag-1103:x3`. They are two correlated groups in
one figure, not independent evidence for a universal amplifier-input habit.

Reproduce every field, actual endpoint, local ink tree, corpus name/hash,
dependency hash and named mutation check:

```sh
python3 -B docs/research/figures/block_input_rc.py external/examples \
  /path/to/block-input-rc-replay.json --check
```

The [script](figures/block_input_rc.py) and [inventory](figures/block_input_rc_cases.json)
reuse the frozen actual DA/PA box-port and complete center-tap certificates.
They freshly inspect the SVGs. Cache coordinates alone are insufficient.
The full [public fixture](../../tests/block_input_rc_fixture.sp) is checked
against every original declaration/card, excluding only the outer `dut`
wrapper and retaining the CLI's three weak external-role instructions.

## Predicate and boundary

Each block has unique declared INP/INN bindings on distinct nonrail nets.
Each such net has exactly three raw pin incidences: that block pin, one
nondegenerate two-terminal capacitor, and one nondegenerate two-terminal
resistor. The four passive devices are distinct. The two resistors reach
one common nonrail bias net; the two capacitors reach distinct upstream
nets, separate from both inputs and the bias net.

The narrower case also requires exactly one two-terminal bias inductor
beside the two resistors, and exactly one other nonpassive block touching
both upstream nets, bound uniquely and in order through OUTP/OUTN. Every raw
competitor counts before frame filtering. The one excluded passive block
is a *freshly certified complete center-tapped inductor*, not an X-prefix
or model-name exception. An unknown, malformed or uncertified X device
remains a competitor. Unknown/hidden extra input or bias incidences reject.

All three broad candidates have the bias inductor, but **X1 has no such
upstream output block**. Its cap-near tips are `(250,-10)` and `(250,120)`;
its own input tips are `(340,30)` and `(340,70)`. Thus X1 supplies an actual
row-alignment counterexample to the broad RC-only rule. It remains a named
excluded row with all measured relations and local ink retained.

The DA and PA source symbols are rectangles. Their visible input leads are
independently attached to their own body and bound by declared port name.
VSS is absent in the source; its geometry remains unknown. Neither a
triangle nor an unseen terminal is inferred.

## Actual source relations and local trees

| Group | INP / INN tips | Cap-near tips | Input R tips | Bias R tips |
|---|---|---|---|---|
| X2 | `(90,270)` / `(90,310)` | `(40,270)` / `(40,310)` | `(50,330)` / `(70,330)` | `(50,370)` / `(70,370)` |
| X3 | `(580,270)` / `(580,310)` | `(630,270)` / `(630,310)` | `(620,330)` / `(600,330)` | `(620,370)` / `(600,370)` |

The full inventory retains both ends of every passive and the source object,
own lead primitives, named binds, original `.cir`/`.human.json`/`.svg` hashes,
verified conductor segments and actual junction dots. Ten literal endpoints
per broad group independently check extraction. X3 is the reflected case.

Define the longitudinal axis by the actual outward direction of the two
input leads, and the transverse axis from INP to INN. These are perpendicular
cardinal axes. On those axes, both selected groups have:

- Parallel input capacitors whose near tips are on the corresponding input
  rows, with common near/far planes farther outward than the block.
- Transverse resistors between the block input plane and the capacitor plane.
  Their input tips share one row and their bias tips share another. Both rows
  lie beyond the input span, with the bias tips farther away. INP's resistor
  is farther outward than INN's resistor.
- A continuous local input triple on each branch: block input, cap-near tip,
  and resistor-input tip. The paired resistor-bias tips are also continuous.

Only those **six local trees** are required for the two selected groups.
Whole upstream output nets and the remote bias tree are not required; the
source omits some remote joins. Equal labels do not supply physical ink.
The tree method distinguishes endpoints/T/overlap, dotted crossings and
undotted proper crossings. Removed own-terminal ink and foreign-net bridge
controls must fail. Eight rigid poses retain each actual-frame relation.

## Public RED and current limitation

[tests/block_input_rc.zig](../../tests/block_input_rc.zig) remains unimported.
ROOT ran its four tests against the exact frozen `feedback-native` engine:
**two pass, two fail**. The literal source/eight-pose/mutation test and all
caller-constraint cases pass. The default X2 geometry fails with compaction
off, and its local net14 triple lacks physical ink with compaction off.
These are separate assertions; geometry failure cannot hide the ink RED.
The tests will check both compaction settings once earlier assertions pass.

The direct replay, frozen input hashes and log are in
`.objective/human-schematic-equivalence/runs/iteration21-resume1/block-input-rc-tests/`:

```sh
# Integrity only; ROOT alone runs the command without --check (serial Zig).
python3 -B .objective/human-schematic-equivalence/runs/iteration21-resume1/block-input-rc-tests/run.py --check
```

The public geometry oracle derives its axes from actual native named input
tips and sides. It does **not** force source world orientation or swap the
native INP/INN order. Explicit passive origin/form and explicit block origin/
rotation remain authoritative. No imported-suite green claim includes these
currently failing prospective tests.

## Bounded four-passive owner under validation

The prototype owns only the two capacitors and two resistors; the block's complete
class, origin frame, control pins and orientation are read-only. The upstream
block and bias inductor certify the topology but are not moved by this owner.

1. Collect exact raw-incidence candidates before relay or local mutations.
   Reject any ambiguity, undrawn competitor, unsupported actual input frame,
   shared passive ownership, incompatible mate/shelf/group, admitted member
   or block geometry/side request, or explicit local style/port/route. Invalid
   or dropped hints do not silently suppress a group. First-net ordering
   remains a routing-order instruction.
2. Use the actual own attached input leads to establish the two axes. Turn
   each full passive class without altering its terminals, preserve semantic
   input/remote or input/bias binding under reversed cards, and require
   `actual_anchor.representable`. Derive one nearest candidate from full
   class body/lead bounds and ordinary clearances. Align caps to the actual
   corresponding input tips; place the two bias branches outside the input
   span. The observed semantic INN side is the first bounded candidate;
   do not invent an untested farther search or change the block frame.
3. Existing row space is a real obstacle. In the compact room-before-feedback
   drawing X2's input plane is x1913 and the CT tap is x1863; X3's input plane
   is x2053 beside the preceding PA body. Simply moving source-sized passives
   there would overlap existing neighbors. Reuse `lattice_geometry.Room`
   to reserve each actual four-passive envelope at its block cell *before*
   physical column spacing. No new slots, source coordinates or fixed gap
   are required. This is the second concrete room-producing owner after
   `block_tanks`, so a concrete shared coordinate-transaction spine is
   justified if necessary; callbacks or retained generic layout state are not.
4. Reserve the existing output-tank and new input-RC envelopes together.
   Preflight the complete proposed scene with all future passive rows/poses,
   including candidate-versus-candidate collisions. Temporary full device
   rows are restored on every failure. Allocate coordinate scratch and
   reserved geometry before exposing mutations. If the combined proposal
   fails, restore every temporary row and leave incoming coordinates intact,
   then run the original output-tank-only transaction exactly. Its successful
   output owners and generic fallback remain authoritative. Direct/along
   placement or admitted fixed/relay coordinates
   bypass reservation. An empty request set preserves the old path.
5. Commit all four passive rows only after the whole proposal passes actual
   frame and collision checks. Successful groups contribute bounded existing
   compaction relations and shelf protection: actual cap rows remain tied
   to the unchanged block input offsets, resistor bias/input rows remain
   shared, and longitudinal block→resistors→capacitors orders stay strict.
   A compaction relation must preserve actual tips, not only origins.
   Rejected groups contribute neither room nor orders. Ordinary routing
   must then satisfy the existing physical-ink tests; no forced wire or
   crossing-budget exemption is proposed.

The next implementation tests must separately prove simultaneous room bounds,
four-row rollback, rejected reservation equality, malformed/shifted/inward
actual frames, raw hidden incidence, local style/route precedence and OOM.
A geometry pass alone would not complete this change.

## Six data answers for the implementation

1. **Transformation:** borrowed CSR/bindings, roles, actual classes, admitted
   constraints and existing lattice coordinates become a cold candidate
   batch, bounded room/order requests, and successful four-passive poses.
   No public ABI, symbol metadata or netlist binding changes.
2. **Cardinality:** at most one candidate per subcircuit device and four owned
   devices per candidate. Reject overlaps before placement. Allocate once
   from the graph's subcircuit count; one numeric room per accepted anchor.
   The observed list has exactly two groups, but capacity is not hardcoded.
3. **Widths:** existing typed u32 device/net handles; u8 named block terminal
   indices under the existing class terminal bound; passive endpoint identity
   is 0/1. Re-read the two input nets from CSR rather than retaining names,
   upstream/choke proof rows or redundant booleans. A five-handle plus two-pin
   cold group would be 24 bytes with the existing layout; assert its actual
   size. Coordinates remain existing i32 with widened checked arithmetic.
4. **Access:** selection scans CSR once per candidate; each small cold group
   is read as a whole during prepare/preflight/commit. Preserve the engine's
   SoA placement rows; do not add flags or fields to hot pin/route structs.
   Immediate room/order arrays retain their current packed representations.
5. **Lifetime:** the caller owns a draw-phase batch and bounded scratch.
   Four prior full rows and proposed tips live only through each transaction;
   simultaneous preflight may require a caller-owned dense list of the
   selected members' temporary rows. Free it before routing. All fallible
   allocations precede exposing mutations, with OOM cleanup and equality
   tests. No process-retained state.
6. **Parallelism:** candidate topology inspections are read-only, but commit
   and shared numeric spacing are deterministic serial scene operations.
   Do not parallelize conflicting placement. This is cold scalar work;
   there is no speed, SIMD, or no-residue claim. Measure native/WASM size and
   complete-corpus deterministic output before accepting the owner.
