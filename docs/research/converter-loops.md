# Flying-capacitor converter loops

Research only. This study proposes a complete local group around the existing
PMOS–inductor–PMOS path. No engine change, hint experiment, or Zig build was made.
The oracle is actual transformed SVG lead and conductor ink, followed by the
source's observed terminal relations. Native geometry is frozen iteration 9.

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
circuit. Ambiguous members, repeated loops, shared admitted members, and
ambiguous output branches abstain. Gates and bodies never substitute for
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

## Existing failure and bounded production ownership

The existing `power_paths.classify` selects the lower input-bus PMOS and
the main path, but it does not select the two floating caps as a group.
`forms.classify` starts offrail caps flat; `forms.crooked` may stand them up
from incidental upright neighbors. `forms.ends` then uses rail distance to
choose their upper net. That does not encode either capacitor's loop role.
The six upright native floating output caps all have the opposite vertical
polarity to the source. A cap-axis change alone cannot establish the loop.

`bridges.place` owns only the three-part main chain, selected grounded
shunts, and controller placement; lower PMOS/diode/caps remain independently
placed. `wrap.cutCost` and `power_compact.squeeze` protect the main path,
selected controls, and grounded reservoirs. They have no floating-loop
certificate. `sketch.drawValid` cuts internal nets crossing shelves, and
`thin.name` may cut expensive wires later. `wires` also splits a distant
input/bias into ports: protecting the input bus is not equivalent to setting
an internal net's style to `wire`. Native continuity results are consistent
with these mechanisms; no instrumented per-circuit attribution was run.

A proposed implementation should submit one bounded request through these
owners, rather than add unrelated exceptions:

1. A topology owner, for example `power_loops`, queries existing netlist,
   role, drawn, and form rows and returns only the selected member handles
   and semantic ends. It establishes uniqueness before any coordinate
   write. Keep the three-part path's existing owner and avoid persistent
   per-incidence state or a second netlist representation.
2. `forms` admits both floating caps upright and gives their semantic upper
   ends: input coil node for flying cap, output for output cap. Lower MOS
   and diode remain flat. `relations.forms` and `relations.ends` already
   run afterward, so explicit form/face instructions retain precedence.
3. `bridges` places the whole loop around its main chain before ordinary
   bridge placement can consume its members. Reserve actual-size room for
   the lower channel and diode, cap columns, and an output divider column.
   Use the inequalities above; same-row/column preferences remain soft.
   Gate direction stays with its existing semantic owner. Later cell,
   row/order, mate, face, and origin instructions retain precedence; an
   incompatible admitted relation disables the affected group certificate.
4. `wrap` protects the accepted local group's span, not every device on its
   nets. `power_compact` submits only already-true actual-terminal orders:
   flying-cap interval and vertical bounds, lower row below main, diode
   below cap ends, output cap/divider beyond output main. It preserves
   equal tracks without inventing strict order, and abstains for conflicting
   caller origins or turned/offset symbol frames.
5. A local wiring request seeds the selected terminal subsets through
   reserved Manhattan channels: input bus at the left, main path at top,
   cap drops, diode return below, output/divider at right. Validate actual
   pins, bodies, rail stubs and existing caller routes through `Canvas`.
   Use its checkpoint/restore to commit the whole local plan or none, then
   attach other pins through existing routing. The bus remains an input
   with a port; do not relax `netlines`' public input-style contract. Honor
   explicit label/route/via/first/port requests. A local group can protect
   its successful seed from automatic shelf cuts and thinning without
   exempting unrelated branches or raising a global crossing budget.

The source geometry is compatible with the existing Manhattan C ABI and
canvas representation. No diagonal extension is needed here. A failure to
reserve or safely route the whole request must remain visible, not be counted
as source equivalence because the four axes happen to match.

## Reproduction and acceptance evidence

```sh
python3 -B docs/research/figures/converter_loops.py external/examples/analoggenie /tmp/loops-ag.json --native /tmp/cktimg-human-rules/all-ag-iteration9
python3 -B docs/research/figures/converter_loops.py external/examples/amsnet /tmp/loops-ams.json
python3 -B docs/research/figures/converter_loops_checks.py
```

Compare the first two outputs with the `analoggenie` and `amsnet` inventory
fields. `paired_sha256` hashes sorted human/deck pairs, each byte string
prefixed by its eight-byte little-endian length. Per-file SVG/native hashes
cover the actual evidence. The executable and both versions' report hashes
are retained under `baseline_metrics`.

The research checks pass 21 named cases: an independent six-net fixture,
capacitor/channel pin reversal and card-order invariance; duplicate loop
members, coil/main/output/divider ambiguity, reversed diode, rail or shorted
loop nets, wrong switch polarity, and conducting control exclusions; a real
T-junction, disconnected wire pieces, an off-ink target, and corrupted source
lead rejection. Channel reversal checks selector symmetry, not electrical
equivalence of asymmetric MOS models.

For baseline context, these same 145 circuits have crossings **510 → 562**
and bends **3,425 → 3,534** from frozen iteration 8 to 9. Crossings worsen in
48 and improve in 34 circuits. These are prior engine snapshots, not a loop
experiment or attribution of changes to one rule. No axis-only patch or
`cell`/`at` probe was run: such hints change global placement admission and
wrapping, so they would not isolate the proposed group algorithm.

A future implementation needs red/green end-to-end geometry and continuity
checks against the exact 145-member inventory, the 107 AG exclusions and
zero AMS admissions, caller override cases, real shifted/large symbol frames,
and crossing/bend results. Preserve the named source exceptions above. The
hand-drawn oracle must check continuous local wires, not labels that preserve
only electrical net identity.
