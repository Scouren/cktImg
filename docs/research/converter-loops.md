# Flying-capacitor converter loops

The engine now recognizes a bounded local group around the existing
PMOS–inductor–PMOS path. Its oracle is actual transformed SVG lead and
conductor ink, followed by the source's observed terminal relations. The
committed inventory retains the frozen iteration 9 baseline; measured
iteration 12 results and remaining differences are reported separately below.
Iteration13's [input-bus study](converter-bus.md) measures the preferred left
spine and physical auxiliary-switch connections. Its
[output-branch study](converter-branches.md) measures the common divider–cap–cap
order and preserves all 31 minority source arrangements as exceptions.

## Electrical certificate

[converter_loops.py](figures/converter_loops.py) first uses the existing
`power_paths` topology predicate. Exactly one selected PMOS at each coil end
forms the main path, with no alternate qualifying coil sharing either main
switch. Its input end belongs to the gate-only-controlled PMOS input bus; its
output end has a capacitor to ground. Then the following loop must be unique:

```text
 bus -- input PMOS -- a -- L -- b -- output PMOS -- out
  |                  |                              |
 lower PMOS        flying C                      floating C
  |                  |                              |
  +--------------- bottom -- K diode A -------- negative
```

The six named path nets are distinct and nonrail. The lower PMOS is a selected
input-bus branch. Exactly one grounded capacitor on `out`, and exactly one
two-resistor `out → feedback → ground` divider, complete the certificate.
Feedback is another distinct nonrail net. The diode's anode is on `negative`;
the reversed case is unobserved and is excluded, not declared an invalid
circuit. Ambiguous members, repeated loops, shared complete candidates, and
ambiguous output branches abstain before diode-polarity scope filtering.
Reversing a competing loop's diode cannot hide its shared output branches.
Gates and bodies never substitute for
channel endpoints, including when a body shares a channel net.

No instance name, net spelling beyond the established rail vocabulary, value,
figure number, cached rotation, or coordinate selects a group. In particular,
AG1287's floating output capacitor is **COP**, while many other drawings call
it CO. Examples use M2, M3, M5, M23, M25, M30, M32, or MS2 for the lower switch.

The selector finds **145 cells in 145 AnalogGenie drawings**, among all 2,202
paired drawings. It finds none among all 734 AMSNet drawings. Another 107
certified AG main paths have no unique input-bus-to-reservoir direction and
are excluded by name in the inventory. These are related converter variants,
not 145 independent observations. The numerical modulo-five split has 27
selected holdouts; it does not establish independence.

## Actual source evidence

[converter_loops_cases.json](figures/converter_loops_cases.json) retains every
selected device/net, all 107 excluded main paths, all source exceptions,
source and native hashes, and actual SVG endpoints. The audit verifies
**3,335 lead endpoints**: 23 per circuit for three PMOS, the coil, diode,
three capacitors, and two resistors. MOS D/G/S are checked, not body artwork.
Inductor paths and resistor zigzag paths are read from their actual outer
endpoints; other builtins use transformed line/polyline endpoints. A one-unit
corruption of a cached flying-cap lead fails this oracle.

The all-source relations and frozen native agreement are:

| Terminal relation | Source | Native 9 |
|---|---:|---:|
| Flying capacitor upright, input-side net above bottom net | 145 | 13 |
| Flying capacitor within input-main/coil terminal x interval | 145 | 25 |
| Flying capacitor body below main, ending above/at lower MOS | 145 | 56 |
| Lower MOS horizontal and wholly below main path | 145 | 38 |
| Diode horizontal and below main path | 145 | 0 |
| Diode center between cap columns and at/below both lower cap pins | 145 | 41 |
| Diode anode faces toward output side | 145 | 42 |
| Floating output cap upright, output above negative | 145 | 0 |
| Floating output cap outside output main, at/below main | 145 | 124 |
| Divider two upright resistors, one downward column | 145 | 139 |
| Divider beyond output main, ground end above/at diode row | 145 | 0 |

Conjunctions in this table require every listed condition. The inventory
also retains each condition separately. The native axes alone are misleading:
all 145 lower MOS already lie flat, 144 diodes already lie flat, and all 145
main paths already share a row. Forty flying caps and six floating output
caps stand upright, but their direction is often reversed.

Seven local nets are studied: bus, input coil node, output coil node, output,
lower flying-cap node, floating-cap negative, and divider feedback. **All
seven connect their selected terminals through verified source ink in every
one of the 145 drawings.** Each source spanning tree is Manhattan. There are
zero proper crossings between these seven local trees in all 145 drawings.
This is not a claim about crossings against remote control/bias wiring.

The selected input-bus tree has exactly one vertical column in every source.
It lies strictly left of both selected switch terminals in **141/145**;
AG1267, AG1280, AG1312 and AG1345 put it directly on their shared terminal
column. The `source_bus_spine` field retains the actual two terminal x values,
verified local tree column and clearance for each drawing, with exact names
in the summary. This follows the verified spanning ink after cache-only
segments are removed; it does not infer a bus from device centers or labels.
A leftward gap is a common preference with a known fallback, not a universal
constraint or an established topology selector for the four exceptions.

Each selected loop also has one grounded NMOS shunt whose ground channel
terminal lies **strictly above the diode return row in all 145 drawings**.
The `source_shunt_return` field retains its exact card, ground pin/net,
coordinates, diode row, and actual SVG glyph endpoints. These are **435
additional verified D/G/S leads**, separate from the original 3,335 loop
leads. Selection reuses the existing qualified grounded-shunt predicate;
the measurement uses actual transformed shunt and diode ink. The method
check fixes AG1191:M4.S at `(320,420)` and the diode at y=530, and rejects a
one-unit corruption of that cached ground lead. This proves terminal order;
it does not measure the ground-symbol extent or guarantee space for an
arbitrary configured native rail stub.

Native 9 continuity, without treating labels or ports as physical wires:

| Local net | Continuous source | Continuous native |
|---|---:|---:|
| Input bus: main and lower switch | 145 | 4 |
| Input coil node: main, coil, flying cap | 145 | 105 |
| Output coil node: coil and output main | 145 | 113 |
| Output: main, both caps, divider | 145 | 145 |
| Bottom: lower switch, flying cap, diode | 145 | 50 |
| Negative: floating cap and diode | 145 | 140 |
| Divider feedback | 145 | 144 |

Only **AG1210** preserves all seven local connections in native 9.

The cache contains **62 segments without matching SVG conductor ink**, in
55 circuit/net pairs across 38 selected drawings. All are explicitly retained
under `cache_segments_without_ink`, and together in
`named_cache_ink_disagreements`; none contributes to connectivity. For example,
AG1192's cached VX1 segment `(590,170)–(590,180)` has no conductor stroke.
The selected VX1 terminals still connect using verified ink elsewhere.
Every selected local connection remains continuous after these mismatches are
excluded. Thus neither continuity nor the Manhattan/crossing claim relies on
those cached fragments. This does not certify the cache's remote connections.

## Conditions that must remain separate

AG1191, AG1214, and AG1309 show the common loop clearly. Actual source images
AG1270, AG1268, AG1215, and AG1346 were also inspected to interpret these
exceptions; the inventory audits all selected actual leads.

- The main three parts share a row in 136/145. Offsets occur in AG1215,
  1235, 1284, 1303, 1305, 1317, 1323, 1332, and 1352, as recorded by the
  existing main-path study. Main-row equality remains a preference.
- The lower switch shares the input main's channel-center x in 140/145.
  AG1215, 1221, 1235, 1346, and 1352 move it sideways. All preserve the
  flying-cap interval, lower-switch-before-cap order, and loop closure.
- The diode shares the lower switch's channel row in 144/145. AG1270 puts
  the diode lower, leaving a short vertical bottom-net jog. Both are below
  the main path. Equality must not become a mandatory grouping condition.
- Only 120/145 lower gates face up. The 25 downward controls are named in
  the inventory. The known variation in main gate directions also remains.
- The divider stands between the output main and floating cap in 114/145.
  Seventeen put it between the two caps, and fourteen beyond both caps.
  All place it beyond the output main in one downward column, with the
  ground end above/at the diode row. Do not hardcode `R1/R2 < CO < COP`.
- The grounded output cap stands beyond the floating cap in 144/145.
  **AG1268 reverses their order**. This cannot override the existing
  grounded-reservoir rule or establish a universal capacitor ordering.

These minority arrangements have no proven topology selector yet. Record
their geometric invariants and leave equality, gate direction, and output
branch ordering as choices until a broader group supplies their condition.

## Production ownership and safety

`power_loops.find` returns ten device handles and seven semantic net handles
in a temporary 68-byte value. It shares the existing series-path and input-bus
predicates. Local alternatives and complete groups sharing any member are
counted before diode-polarity or grounded-extension scope filters. No source
ID or drawing coordinate participates in recognition. A grounded capacitor
on either main gate or coil-end net is unobserved in all 145 selected source
groups, so that extension abstains before forms change; it remains a valid
circuit for the ordinary layout path.

`forms` puts the two floating capacitors and divider upright, with their
semantic upper ends, and keeps the selected diode flat. Caller form and end
relations run afterward. `loop_place` runs after placement relations, cells,
and faces have been admitted. Compatible groups reserve the main row, cap
drops, lower return, divider, and existing grounded shunts. Honoured
row/above/order/cell/face requests, mates, or incompatible forms/ends prevent
that group placement. Existing output-branch order is retained as a choice;
it is not claimed to reproduce the source's three ordering families.

Placement searches disjoint horizontal row bands, with one clear row above
and below, because supply bars can reach the loop from distant columns.
Separated controls can remain above or below. `wrap` protects only spans
returned by successful group placement, and retains existing row gaps on the
shelf containing such a span. Sparse device cells cannot describe occupied
rail-stub space: closing those gaps placed control supply stubs directly on
the proposed return in AG1222 and 16 other selected cases. The two complete
DUT clearance regressions, AG1222 and AG1349, require local continuity and
no shorts in both compaction modes without prescribing a control side.
The band margin and whole-shelf gap retention are conservative default
placement choices, not guarantees for arbitrary configured rail lengths.

`power_compact` submits only already-true actual-terminal inequalities for
the capacitor intervals and drops, lower return, and output divider. Shifted
or tall caller symbols use transformed pins. Equal coordinates already share
a compaction track; explicit origins and incompatible frames abstain. The
compactor measures the actual scaffold's bodies and wires, including rail
stubs, before reducing their spacing.

`power_loop_wires` maps the seven selected terminal subsets onto existing
pins and seeds their Manhattan trees after rails. Each projected routing
point must equal its actual transformed terminal. `Canvas` checks pins,
bodies, rail stubs, and prior wires; checkpoint/restore commits the whole
local plan or none. Explicit wiring styles, routes, vias, and first-net order
retain precedence. A successful local tree survives automatic thinning, while
outside pins continue through the ordinary router using its recorded anchor.
An outside branch may still use a named connection, and an input retains its
port. An output keeps its whole tree's outer boundary for port placement.
A later group sharing a seeded net retains all its terminals for ordinary
routing; one anchor cannot stand for two disconnected local trees.

The native C ABI and existing Manhattan representation are unchanged.
A failure to reserve or safely route a complete tree remains visible and
cannot count as equivalence because the symbol axes happen to match.

## Measured iteration 12 checkpoint

The frozen wrap snapshot (`cktimg-json` SHA-256
`8e4dcdd30bfa92280db56c117789ceebe851f5413ee56ac11926d9a449e3a03f`)
retains the exact 145 selected and 107 excluded source groups. All **22
universal terminal relations now hold in all 145**, and every circuit has
**all seven local connections continuous**. Reconstructed spanning trees
have **zero proper crossings between these seven local trees**. This does
not certify remote control wiring or source-equivalent branch ordering.
All 17 remaining pre-wrap-fix failures also pass with compaction both off
and on after preserving the reserved shelf gaps.
Its WASM artifact is **559,658 bytes**, SHA-256
`def3d992a8eb6909712453b6cc8c76c4c08077e189406df9e8337008e37de570`.

The same snapshot preserves the previous exact cohorts: 252 main chains,
365 shunts below the main path, 353 unique shunts inside their terminal
interval, 359 grounded reservoirs upright/outside/at-or-below with ground
below, 92 active drivers below, and all 75 block-output relations. Both
107-device reservoir gate-direction cohorts retain source agreement.

For these same 145 circuits, whole-circuit metrics change from frozen
iteration 9 to this snapshot: crossings **562 → 464**, bends **3,534 → 2,696**.
Crossings improve in 71 circuits and worsen in 52; bends improve in 115 and
worsen in 18. These totals include remote wiring. A lower total is not a
claim that every source arrangement improved.

The full 2,202-drawing comparison against iteration 11 also records physical
gate-direction changes. Of 23,252 source gate facts, matches rise from
14,157 to 14,193: **549 improve and 513 regress**, with one changed direction
matching neither version. Every improvement and regression concerns an
unchanged upright transistor outside the ten loop members and selected
grounded shunts. The 513 regressions span 61 circuits. This compares literal
left/right/up/down directions without normalizing mirrored groups. Promoted
forms affect earlier column ordering and its gate-facing choices; AG1194's
MN1/MN2 pair provides a checked example, not a causal explanation for every
changed device. Symbol-axis matches improve by 245 with no regressions;
measured native flow directions are unchanged.

Known differences remain named by the source inventory. In this snapshot,
all 145 native input buses use the shared terminal column, while 141 source
buses stand strictly to its left. Divider-between-main-and-floating-cap
agreement is **55/145**, down from **77/145** in the baseline; grounded-cap
ordering agreement is **138/145**, up from **128/145**. Source row offsets,
lower-gate directions, and minority output-branch arrangements remain
separate from the universal inequalities. The checkpoint establishes a
bounded improvement, not complete handwritten equivalence.

## Reproduction and acceptance evidence

```sh
python3 -B docs/research/figures/converter_loops.py external/examples/analoggenie /tmp/loops-ag.json --native /tmp/cktimg-human-rules/all-ag-iteration9
python3 -B docs/research/figures/converter_loops.py external/examples/amsnet /tmp/loops-ams.json
python3 -B docs/research/figures/converter_loops_checks.py
python3 -B docs/research/figures/converter_loops.py external/examples/analoggenie /tmp/loops-native12.json --native /tmp/cktimg-human-rules/all-ag-iteration12-wrap --native-crossings
python3 -B docs/research/figures/converter_loops_checks.py --native-crossings
```

Compare the first two outputs with the `analoggenie` and `amsnet` inventory
fields. `paired_sha256` hashes sorted human/deck pairs, each byte string
prefixed by its eight-byte little-endian length. Per-file SVG/native hashes
cover the actual evidence. The executable and both versions' report hashes
are retained under `baseline_metrics`.

`--native-crossings` requires `--native`. It adds each native selected tree
under `native_connections.*.spanning_ink_segments` and all 21 named tree
pairs under `native_local_crossings`. A disconnected group records `null`
for crossings; it cannot count as a zero-crossing success. In the frozen
iteration 9 replay, only AG1210 has a complete result and the other 144
remain unknown. All 145 iteration 12 groups have complete results with
empty proper-intersection lists. Native segments come from the engine's
exported physical wire table; source segments are separately verified
against SVG ink. Remote branches outside the selected spanning trees are
not part of this crossing count. Without the flag, AG/AMS reports and the
30-method output remain byte-identical to the committed baseline evidence.

The research checks pass 30 named cases: an independent six-net fixture,
capacitor/channel pin reversal and card-order invariance; duplicate loop
members, coil/main/output/divider ambiguity, reversed diode, rail or shorted
loop nets, wrong switch polarity, and conducting control exclusions; grounded
main-branch abstention with retained evidence; a real T-junction, disconnected
wire pieces, an off-ink target, and corrupted source lead rejection. Three
literal bus cases distinguish a strictly left column from a shared terminal
column and a column between unequal terminal x values. Channel reversal
checks selector symmetry, not electrical equivalence of asymmetric MOS models.
The added cases retain a reversed-diode shared competitor in ambiguity
counting, verify the literal shunt-ground/return relation, and reject a
corrupted cached shunt ground lead against actual SVG ink.
The optional crossing checks add three literal cases: an interior crossing,
an endpoint contact that is not a proper crossing, and an incomplete tree
whose crossing result remains unknown. All **33** optional method checks pass.

For baseline context, these same 145 circuits have crossings **510 → 562**
and bends **3,425 → 3,534** from frozen iteration 8 to 9. Crossings worsen in
48 and improve in 34 circuits. These are prior engine snapshots, not a loop
experiment or attribution of changes to one rule. No axis-only patch or
`cell`/`at` probe was run: such hints change global placement admission and
wrapping, so they would not isolate the proposed group algorithm.

The implementation's red/green regressions cover complete source DUTs,
actual terminal geometry and seven physical local trees, compaction/shelves,
capacitor pin reversal and PMOS body aliasing, shifted/tall and skewed custom
symbols, caller overrides, shared-net routing, output-port boundaries, and
local rail clearance. Selector tests retain ambiguous and unsupported cases,
including a shared competitor with a reversed diode. The source inventory
still names every selected/excluded case and every minority relation.
The oracle checks continuous local wires independently of labels that preserve
only electrical net identity.
