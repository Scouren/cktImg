# Keep the local input bias choke with its RC branches

The four-passive RC prototype repairs its six local source trees, but the
complete native audit finds four new source-connected losses in AG1103:
`net15:lbw5.1--r3.1`, `net15:lbw5.1--r4.1`,
`net17:lbw6.0--r5.1`, and `net17:lbw6.0--r6.1`.
The chokes remain far from the newly placed resistor pairs. The prototype
is unaccepted; passing the narrower RC tests does not preserve these trees.

The measured binary is `block-input-native-install/bin/cktimg-json`, SHA256
`6425a66e9d1fd1ec35af67b5e5635ff8aa9af9c84352e08e81620e303b0ec42d`.
The complete result is `block-input-connectivity.json` under
`.objective/human-schematic-equivalence/runs/iteration21-resume1/`.
The sibling `block-input-views/manifest.json` certifies the inspected actual
SVG against its scored JSON/report. This is a placement regression, not
evidence for a new proximity exception in routing.

## Actual source certificate

[block_input_chokes.py](figures/block_input_chokes.py) replays the entire
2,936-deck [original RC audit](figures/block_input_rc.py), compares every
field against its frozen inventory, then independently inspects the three
actual inductor paths. It retains the original exact selected names
`ag-1103:x2` and `ag-1103:x3`, plus the excluded `ag-1103:x1`.

```sh
python3 -B docs/research/figures/block_input_chokes.py external/examples \
  /path/to/block-input-chokes-replay.json --check
```

The [new inventory](figures/block_input_chokes_cases.json) records actual
primitive object IDs, declared card-index mappings, source hashes, all
corpus names/hashes, local import closure and named method checks. The
original RC inventory and its dependencies are unchanged.

| Group | R(INP) / R(INN) bias tips | Choke bias tip | Choke far tip |
|---|---|---|---|
| X2 / LBW5 | `(50,370)` / `(70,370)` | `(30,380)`, card pin 1 | `(-10,380)`, card pin 0 |
| X3 / LBW6 | `(620,370)` / `(600,370)` | `(640,380)`, card pin 0 | `(680,380)`, card pin 1 |

On the block's actual outward input axis, each choke is parallel to the
input leads and farther outward than INP's resistor; its far terminal is
farther outward still. On the actual INP-to-INN axis, its two terminals
are beyond the shared resistor-bias row. **The choke and resistor tips
do not share a row:** source y380 versus y370. Each resistor has a short
stem to the choke row, followed by a bar joining the three bias terminals.
The exact four source conductor intervals and actual junction dot are
retained for each local tree. The oracle does not require the source's
particular 10- or 20-unit gaps.

X1 is a concrete boundary: LBW3's bias/far tips are `(310,-70)` and
`(350,-70)`, while its resistor-bias tips are `(270,-60)` and `(300,-60)`.
It violates the two outward-order relations and the downstream transverse
relation. Its lack of a unique upstream named-output block already excludes
it from the production candidate. The two selected groups are correlated
examples in one figure, not a universal amplifier-input convention.

All three choke far terminals are bound to `V_bias`, but every pair is
physically separate in the actual source. The companion checks both
verified named-net ink and all conductor ink before recording these three
negative relations. Equal labels never join them. The extension requires
only each local resistor/resistor/choke tree; it must not force a global
V_bias wire.

## Proposed bounded extension and tests

The topology already proves exactly one nondegenerate two-terminal bias
inductor beside the two resistors, counting all raw incidences. The extended
case also requires the choke far net to differ from both inputs, both
upstream nets and the common resistor bias. Source V_bias satisfies this.
The original degree checks already exclude input/bias aliases; two upstream
aliases previously survived and now have a ROOT-confirmed selector RED.
The companion retains exact named mutations for all five aliases. Retain that
handle and its semantic bias endpoint, and include it in the existing
group's placement ownership and overlap/constraint admission. No broader
selector, model-name exception, or additional schematic family is needed.

Use the unchanged actual block input frame. Turn the complete choke class
parallel to the outward input axis, with its bias tip toward the resistors
and its far tip outward. Place one body-derived candidate beyond the R-bias
row and beyond INP's resistor. Include its complete body and visible leads
in the numeric room request and the simultaneous future-scene preflight.
Retain all five full passive rows on rollback. Unsupported actual choke
frames, admitted choke geometry/net constraints, shared ownership and
collisions decline the complete RC group. A declined combined reservation
still follows the exact prior output-tank-only lattice path.

Successful groups request strict actual-terminal orders in both axes,
including `R(INP) < choke-bias < choke-far` along the outward axis and
`R-bias < choke` along INP-to-INN. Neither a zero-gap alias nor a fixed source
distance is acceptable. Ordinary routing must connect the three actual
bias tips. There is no routing-budget, label, distance, or crossing exemption.

[tests/block_input_chokes.zig](../../tests/block_input_chokes.zig) is
unimported. ROOT confirmed the four-passive RED: source frame and local
three-tip ink fail; literal/caller controls pass. The five-passive candidate
passes all five original RC tests and the four new positive/control tests,
but the separately added remote V_bias separation test still fails with
compaction off. The candidate remains unaccepted pending the complete
source/native transition audit. The suite separates source geometry
from physical ink, checks both compaction modes, verifies actual transformed
class tips, and includes eight rigid poses, wrong-row/skew/reversed-terminal
mutations, reversed/renamed choke cards and explicit choke position/form.
Existing input-RC and output-tank tests must remain unchanged and green.
Before accepting production, extend the private combined-room oracle to
the fifth envelope, malformed choke frames, five-row collision rollback,
exact output-only fallback and every allocation failure.

## Six data answers

1. The transformation remains borrowed CSR, actual classes and admitted
   constraints to cold groups, numeric room/order requests and passive
   poses. The block and all electrical bindings remain unchanged.
2. Each candidate owns exactly five distinct passives. Capacity comes from
   the named group count, never the observed two cases. Combined transaction
   scratch is `2 * output_groups + 5 * input_groups` full rows.
3. Keep typed u32 handles, u8 named block-pin indices and 0/1 passive
   endpoint identity. One additional handle makes the cold group six
   handles plus two pin indices, expected 28 bytes; assert the real size.
   Keep existing i32 coordinates and checked widened intermediate arithmetic.
4. Each cold candidate is read as a whole. Preserve placement SoA tables
   and the current concrete shared coordinate owner; no hot pin/route field,
   dispatch, generic callback, or retained dynamic table is needed.
5. The caller owns phase-local groups and bounded scratch. Allocate before
   mutating rows, restore complete temporary state before fallback, and
   free scratch before routing. OOM must leave the prior scene unchanged.
6. The simultaneous scene transaction stays deterministic and serial.
   There is no SIMD, performance, or no-residue claim. Measure native/WASM
   size, complete corpus transitions and one/N-job byte equality separately.
