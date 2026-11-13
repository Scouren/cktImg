# Corpus scorecard

[corpus_score.py](figures/corpus_score.py) retains a native drawing and
decision report for every indexed source circuit. It compares those drawings
with the cached human geometry. This measures specific structural relations;
it does not certify visual or electrical equivalence.

## Run a checkpoint

Build `cktimg-json` with the repository's pinned toolchain, then run:

```sh
python3 -B -I docs/research/figures/corpus_score.py \
  --examples external/examples/analoggenie \
  --bin zig-out/bin/cktimg-json \
  --out /tmp/cktimg-ag-checkpoint \
  --label symbols-and-couplings \
  --expect-issues docs/research/figures/corpus_issues.json
```

The output directory must be new or empty. The runner copies the executable
there before starting workers. It retains every native JSON and report,
including a named error when a circuit fails. `scorecard.json` records the
binary, runner, both existing scorers, index, source SVG, source geometry,
deck and output hashes. Its sorted ID list must equal the source index;
missing inputs cannot reduce the denominator silently.

To rescore the same geometry without replacing its original scorecard:

```sh
python3 -B -I docs/research/figures/corpus_score.py \
  --examples external/examples/analoggenie \
  --out /tmp/cktimg-ag-checkpoint --reuse \
  --result-name reviewed-scorecard.json --label reviewed-checkpoint \
  --expect-issues docs/research/figures/corpus_issues.json
```

Reuse verifies the recorded executable, inputs and available output hashes.
It also accepts the earlier exploratory inventories, which did not record
output or preview hashes; the resulting scorecard records them. `--jobs 1`
and `--jobs 4` must produce identical scorecards for the same retained inputs,
label and runner. Runtime and worker count are not part of the scorecard.

## Independent oracles

Wire crossings, bends and normalized lengths reuse
[tools/site/build.py](../../tools/site/build.py). Its geometric measurement of
the native drawing must agree with the native report's crossings and bends.
The same function measures the human wires. A discrepancy fails the run.

Pair order, shared rows, shared columns and source symmetry reuse
[figures/score.py](figures/score.py), the checked transcription of
[tests/golden.zig](../../tests/golden.zig). The existing fourteen recorded
examples remain its oracle. The adapter adds explicit checks for channel
orientation, four gate directions and known amplifier/gate signal direction.
It does not infer the expected orientation from connectivity or an engine rule.

Both drawings use the same electrical anchor: a MOS drain/source midpoint,
a BJT collector/emitter midpoint, a two-ended part's endpoint midpoint, or
the mean of the same corresponding block terminals. A source inverter's
omitted power pins therefore cannot shift its anchor in the native drawing.
Block correspondence uses exact names, documented signal-port aliases, then
an unambiguous net match. Ambiguity remains a named unsupported device.

Coordinates are normalized to the default symbol length of 40. The row and
column tolerance is two units, matching the existing native drawing scorer;
the value is recorded. This allows small coordinate differences, not a row
of visibly displaced devices. A global horizontal reflection is accepted,
as in the golden scorer. Individual subcircuits are not independently
reflected to improve their scores.

Every run exercises independent coordinate examples and deliberate mutations:
translation and reflection preserve relations; moving a row, turning a
channel, reversing a gate and removing a device create named disagreements.
An amplifier example checks input aliases and omitted supply pins. Source
SVG inspection also covered AG385, 386, 738, 995, 807, 750, 806, 1044, 438,
1070, 1076, 479, 861, 782, 377 and 1182 during adapter review.

## Named limitations

[corpus_issues.json](figures/corpus_issues.json) records two source-geometry
limitations: AG1146:X2 has no net for `b<3:0>`, and AG3495:X2 has no net for
`φ3`. Their drawings are retained, their devices are named as unsupported,
and neither circuit can satisfy all scored relations. An unexpected issue
or an unexpected resolution of a recorded issue fails until the marker is
reviewed. Without `--expect-issues`, any such issue fails.

The scorecard lists each disagreement by device or device pair. A zero
error count means the runner and declared oracles completed; it does not
mean the drawings agree. `equivalent_relations` means only the listed
orientation, direction, ordering and row/column predicates all agree.
The separate symmetry measure is descriptive: its source-wide axis
heuristic is not a complete block detector.

Glyph strokes, block membership, exact wire topology and label placement
remain unscored. Native JSON exposes a class name and terminal geometry,
but no glyph strokes. A `block:` class can contain a triangle or logic gate;
`generated_classes` is provenance, never a count of incorrect boxes.
Connectivity, shorts and SPICE round trips retain their separate tests.

## 2026-11-13 checkpoint

The executable with capacitor-coupled MOS forms, series bridges, conventional
amplifier/gate glyphs and pinless-coupling handling had SHA256
`223b5079c5695088e29ed622b07bdc5abf8224b8c68f10658e02ba9fe79f8828`.
All 2,202 AnalogGenie circuits rendered, including the eight earlier
`NoTerminals` failures: AG1101, 1103, 1122, 1128, 1157, 1163, 1171 and 1190.
No device-name mismatches, native findings or wire-metric disagreements
occurred. The two source limitations above remained.

| Measure | Native / agreement | Human / eligible |
|---|---:|---:|
| Wire crossings | 4,910 | 2,691 |
| Wire bends | 24,087 | 20,590 |
| Channel/part orientation agreement | 29,384 | 32,000 |
| Gate-direction agreement | 13,121 | 23,252 |
| Known block signal-direction agreement | 83 | 143 |
| Left/right pair-order agreement | 203,875 | 338,266 |
| Above/below pair-order agreement | 208,195 | 320,423 |
| Circuits matching all scored relations | 253 | 2,202 |

For the same 2,194 circuits that rendered before the glyph/coupling changes,
crossings changed from 4,863 to 4,850 and bends from 23,963 to 23,917.
Eight newly renderable circuits are counted separately in that comparison.
Aggregate improvement does not erase per-circuit regressions: crossing counts
rose in AG1067, 1070, 759, 438, 1074, 755, 764 and 888.

The remaining orientation inventory is concentrated. Of 1,183 source-horizontal
MOS channels still drawn upright, 756 are PMOS switches in 252 related
power-converter drawings. These repeated variants are not independent
evidence. Their power paths and control/bias circuitry need separate layout
roles. Other substantial families are switched-capacitor signal networks
(AG795, 800/801), pass-transistor decoder trees (AG812) and logic paths
(AG1067). A complementary pair sharing channel endpoints is insufficient:
only 16 of 42 such source devices in a preliminary scan were horizontal.

## Inductive converter follow-up

[power_paths.py](figures/power_paths.py) studies two converter arrangements
without using their titles, device names or coordinates to select them.
An inductor away from the named rails, with a grounded NMOS channel at
either end, supplies the switching nodes. PMOS channels with distinct
drain, source and gate, and neither channel endpoint on a rail, lie flat
in these bounded cases:

- A channel connects a switching node to a capacitor-to-ground reservoir
  (AG1363 and AG1383).
- A channel belongs to a shared input bus whose current paths are all
  PMOS with gate-only controls, and its other end reaches that inductor
  or a nonparasitic capacitor (AG1250's main and flying-capacitor branches).

The source geometry puts all 649 selected PMOS and all 252 adjacent
inductors horizontally. These are 252 related converter drawings, with
359 reservoir switches and 290 input-bus branches. The 734 AMSNet drawings
select none; they provide no external positive validation of this rule.
Against the checkpoint above, 613 selected PMOS and 230 selected inductors
were upright. This predicts orientation opportunities, not a measured
improvement of the completed drawings.

The input bus alone is insufficient. Including its auxiliary supply
branches selects 433 horizontal and two upright PMOS: AG1199:M1 and
AG1202:M5. Excluding capacitor/inductor-free auxiliary branches leaves
143 horizontal converter switches unresolved. Likewise, an inductor's
bias mirror remains upright (AG1250:MP10), and inductive amplifiers and
LC oscillators reject broader adjacency rules (AG491, AG1109, AG1111).
These source drawings were inspected as SVGs as well as terminal data.

Run the study independently of the native executable:

```sh
python3 -B -I docs/research/figures/power_paths.py \
  external/examples/analoggenie /tmp/power-paths-ag.json
python3 -B -I docs/research/figures/power_paths.py \
  external/examples/amsnet /tmp/power-paths-amsnet.json
```

The JSON records every selected and unresolved device, named exceptions,
inductors and source/deck hashes. AnalogGenie's paired-input digest was
`d0b46b9c401de5e07816935bc6c3ebaf0c114032c5bde53db12187ca1ae54c33`;
AMSNet's was
`530bf39d99b7b1daa2466904b3bc68ac050181e35da390046168ccc5f69afe17`.
The public-placement regression also checks the whole MP3–LRX–MP2 series
order and row: getting each device's orientation right is insufficient.

The next source constraint concerns the control connection, not an entire
bias column. In all 252 certified main paths the coil lies between the
two main switches; 243 share exactly one row. AG1215, 1235, 1284, 1303,
1305, 1317, 1323, 1332 and 1352 offset one switch by 10–20 source units.
Among devices attached to those paths, the script records:

| Independently selected relation | Source agreement |
|---|---:|
| Grounded NMOS shunt with gate-only external control: both channel pins below the power row | 365 / 365 |
| MOS channel directly driving a main switch's gate: both channel pins below the power row | 92 / 92 |
| Named block output driving a main switch's gate: below the power row | 75 / 75 |
| Cached output terminal's x equal to the driven gate's x | 75 / 75 |
| Actual SVG output lead facing up on the driven gate's x | 67 / 75 |
| Reservoir-only main switch's gate faces down | 214 / 214 |

The 92 active transistor drivers occur in 32 drawings and include
diode-connected devices. The 75 output blocks occur in 75 drawings;
AG1373's output touches the gate directly, while the other 74 lie below
it. A source block's center is not a reliable substitute for its output
terminal: omitted supplies and asymmetric terminals can shift that mean.
These are observed constraints, not a claim that current placement satisfies
them. `gate_drivers`, `ground_shunts`, `block_outputs` and `gate_directions`
retain every named source coordinate in the study output.

Add `--native /tmp/cktimg-ag-checkpoint` to the study command to check
those same named control relations in a retained native checkpoint. This
records each native JSON hash and every disagreement; a missing drawing,
device or terminal fails instead of reducing the denominator. It uses the
actual block output pin for alignment, not the block's lattice column.
Keeping a controller's lattice column under its main switch can improve
ordering without yet aligning the two electrical terminals.

[controller_glyphs.py](figures/controller_glyphs.py) independently checks
the rendered source rather than treating cached terminal positions as glyph
geometry. Of the same 75 controllers, 70 have triangular SVG bodies and
five are opaque. Actual output leads face up on the main gate's x line in
67 cases. AG1354, 1358, 1366, 1369, 1372, 1377, 1393 and 1396 face right,
with a bent connection to the gate. All 75 actual output leads still lie
below the main channel. Only 32 actual lead endpoints equal their cached
OUT/VO coordinates; the other 43 cached coordinates describe a different
terminal frame. Thus 75/75 cached alignment is not a 75/75 drawing rule.
The eight right-facing cases remain named mismatches for an upward habit;
they are not filtered out or selected by circuit name.

The audit selects paths and unique semantic block outputs from the netlist,
then locates the actual triangle apex and outgoing SVG lead. Opaque blocks
require a unique SVG lead at the named output. Literal rotated-triangle and
misplaced-cache examples check the oracle itself; every source is hashed,
and the exact right-facing name inventory is checked. AMSNet's 734 drawings
select no controllers. Run it with:

```sh
python3 -B -I docs/research/figures/controller_glyphs.py \
  external/examples/analoggenie /tmp/controller-glyphs-ag.json
```

The bounds matter. The flying-capacitor family has 159 downward-facing
and 131 upward-facing main-switch gates, so the reservoir direction rule
does not extend to it. Nor can all bias devices touching the coil be moved
below it: 110 of 140 nonselected PMOS channels at those nodes are level
with or above the main path. AG1250:MP10 being below is not a general rule.

The reservoir-only discriminator is structural: both outer ends of the
certified main path have qualifying capacitors to ground. This selects
107 paths. Each has one actively driven main gate and one gate-only external
control; both point down in the source. The fourth checkpoint already faces
all 107 active gates correctly and leaves all 107 external gates facing up.
The `--native` audit records these two populations separately. A direction
fallback for the external control must retain the two-reservoir condition;
all 290 main gates in the flying/input-bus family are externally controlled,
and their source directions differ.

## Second measured pass: forms and groups

The next frozen native executable had SHA256
`2018208cb09b98ef16b505cff93ba707c1df96df76797569cc0d97665236b825`.
It includes transmission pairs, source degeneration, converter series paths,
switched-capacitor amplifier placement and fully differential symbols.
All 2,202 AnalogGenie drawings still render with no new named source issues,
missing devices, native findings or independent wire-metric disagreements.

| Measure | First pass | Second pass | Eligible |
|---|---:|---:|---:|
| Wire crossings | 4,910 | 5,022 | Human: 2,691 |
| Wire bends | 24,087 | 24,353 | Human: 20,590 |
| Orientation agreement | 29,384 | 30,350 | 32,000 |
| Gate-direction agreement | 13,121 | 13,669 | 23,252 |
| Left/right pair order | 203,875 | 205,360 | 338,266 |
| Above/below pair order | 208,195 | 204,879 | 320,423 |
| All scored relations | 253 | 287 | 2,202 |

This is a mixed intermediate result. Converter channel axes and series order
improve, but their control circuitry is often placed above or beside the
power path instead of beneath it. The orientation rule alone is incomplete;
the next placement rule must account for actual gate drivers and grounded
shunts. No previously complete scored match was lost. The native/source SVGs
were inspected for AG1363, 1250, 769, 782, 751, 759, 800 and 803.

The 83 admitted switched-capacitor drawings improve separately: crossings
58→31, bends 783→302, labelled nets 28→15, orientation agreement 323→486
of 519 and gate direction 115→243 of 319. Their remaining crossing increases
are AG3437 (1→5), AG797 (2→5), AG803 (1→4) and AG804 (1→2).
Local feedback rectangles, vertical buffer groups and paired-stage alignment
remain incomplete.

All 734 AMSNet drawings also render without source or native findings. Their
crossings stay at 189, bends change 1,682→1,680 and complete scored matches
stay at 243. Orientation and pair-order agreements are unchanged; gate
agreement changes 1,414→1,416 of 1,851.

The scorer now measures custom source symbols' signal axis from their
authored IN/INP/INN/OUT-style terminal names, even when the asset type is an
opaque `hierarchical-symbol-…` identifier. An independent coordinate example
first failed, then passed; arbitrary terminal names still make no assertion.
Rescoring both frozen executables with this same adapter changes block-flow
coverage from 143 to 683 source instances: agreement is 446→491 of 683.
The table above and the count of complete scored matches are unchanged.

Validation at this intermediate point passed 259 tests without LaTeX and
260 with it, 4,000 generated netlists, the SVG gallery and format checks.
The Schemify module was 561,080 bytes. All 91 named round-trip fixtures were
accounted for: 89 equivalent and the two named capacity refusals. Ten selected
source decks also passed the current Schemify host, including differential
amplifiers, transmission pairs, degeneration, switched-capacitor networks and
both converter families. These electrical checks do not establish visual
equivalence.

## Amplifier bias terminals

[biased_amplifiers.py](figures/biased_amplifiers.py) selects the named `opamp`
family only when the declaration has two distinct signed inputs, one output,
optional rails and unique VB1/VB2/VB3 roles. All 85 selected AnalogGenie
instances have a closed triangular source outline; AMSNet selects none.
AG1401's one-input amplifier is outside this contract and remains unresolved.
An unknown VA/VX control or duplicate bias alias does not qualify.

The independent oracle reads the actual source SVG path, matching its asset
type because exported instance labels may differ from converted card names.
The output records each selected card, declared ports, source asset and hashes
of the SVG, terminal data and netlist. The paired-source digest is
`f193fdb23c88b87ca27329d8c671d7519dda026da20c5945e950d14fdbffee07`.
Native and Schemify tests preserve every ordered pin; bias and ground
terminals have distinct coordinates. The positive triangle check was red
before implementation. Unknown controls and caller geometry retain their
separate regression cases.

```sh
python3 -B -I docs/research/figures/biased_amplifiers.py \
  external/examples/analoggenie /tmp/biased-amplifiers-ag.json
```

## Fourth measured pass: preserve local groups

The frozen native executable is
`9052da1b689bb4a5386b8c11d3e4bfc57af4b470262818ca0c5b146bfc5f2db3`.
All 2,202 AnalogGenie and 734 AMSNet drawings render, with no missing devices,
native findings or wire-metric disagreements. The same two named source
limitations remain. All comparisons below use the same source geometry.

The block-flow adapter now also reads explicit IN/INP/INN/OUT terminals on
custom source symbols, independently of engine recognition. This increases
the eligible block-flow inventory from 143 to 683. Rescoring the frozen
baseline gives 446/683; the current drawing gives 491/683. Historical
143-port totals above must not be compared directly with that denominator.
A custom source with an upward output and a generated rightward output is
an independent failing example in the adapter's self-check.

| Measure | Original complete checkpoint | Fourth pass |
|---|---:|---:|
| Wire crossings | 4,910 | 5,136 |
| Wire bends | 24,087 | 24,545 |
| Part/channel orientation agreement, of 32,000 | 29,384 | 30,357 |
| Gate-direction agreement, of 23,252 | 13,121 | 13,787 |
| Left/right pair agreement, of 338,266 | 203,875 | 206,588 |
| Above/below pair agreement, of 320,423 | 208,195 | 204,991 |
| Circuits matching every scored relation, of 2,202 | 253 | 288 |

The fourth pass changes 90 geometry hashes from the third: only certified
converter circuits and AG800/801. None of the third pass's 287 fully matching
circuits loses that status; AG800 gains it. This also checks that replacing
stable sorting with heap sorting in `rankByName` changes no unrelated
geometry: its name/index comparator already defines a total order. The
literal repeated-name rank oracle and existing card-reversal checks pass.

The converter oracle now passes all 252 main-path row/order checks, all
365 selected ground-shunt and 92 active-driver below-path checks, and all
75 block-output below-path checks. Source row equality itself has nine
small-offset exceptions, recorded in the source study. Before shelf protection,
only 204 native main paths shared a row and 206 kept the coil between their
switches: wrapping had split a correctly placed local group. Exact-source
regressions for AG1250/1383 failed on that interaction before the fix.

Preserving those groups is not a routing improvement by itself. Within the
252 converter circuits, third-to-fourth crossings rise from 814 to 933 and
bends from 4,503 to 4,781. Crossings worsen in 56 circuits and improve in 16;
AG1213 adds eight, and AG1248/1347 add seven each. Exact block output/gate
horizontal alignment against cached terminals remains 0/75; only 67/75
actual SVG output leads use that alignment. Source drawings separate control and
bias groups more effectively; their composition and wiring remain work.

The four admitted local feedback cells pass 30/30 checks, including their
outward return gates, and AG801's paired cells pass 2/2. The complete source
inventory is eight cells and 62/62 checks; native geometry passes 44/62,
with four complete cells. Excluded AG805/813 stay in the inventory. Across
the same 83 switched-amplifier circuits, third-to-fourth crossings remain
30 and bends rise from 299 to 301; only AG800/801 change geometry.

AMSNet remains at 243/734 circuits satisfying all scored relations. Its
crossings change from 189 to 188, bends from 1,682 to 1,677, gate agreement
from 1,414 to 1,417 of 1,851, and orientation/x/y agreement is unchanged.
These source predicates do not select AMSNet converter or feedback cells.

Validation for this checkpoint: 275 tests without the LaTeX renderer and
276 with it; fuzz, formatting and the gallery; 89 fixture decks preserve
their circuits through the real Schemify host, with the same two named
capacity refusals. The rebuilt plugin is 557,714 bytes, below 563,200, with
SHA-256 `1bca2e98eb09f5673744e661860aba38fe5a7470bd8efcd9a37a7db0bb33883f`.
The remaining disagreements and the unscored features above prevent a claim
of equivalence to the human drawings.

## Fifth measured pass: reservoir controls and single-input symbols

The frozen native executable has SHA-256
`81fe3d0b22f52f4e2fc7f0c86a92d1fbc08b51174471e75529add43f272c083e`.
All 2,202 AnalogGenie and 734 AMSNet drawings render with the same exact
source-limit inventory and no native or wire-metric findings. AMSNet
geometry is byte-identical to the fourth pass. AnalogGenie changes 108
geometry hashes and loses no previously complete scored match.

The two-reservoir predicate now faces all 107 external main-switch gates
down, matching their source drawings; all 107 actively driven mates still
agree. The input-bus family remains outside this external-control rule.
All 252 main paths retain their row/order and all 365 selected ground
shunts remain below them. Block-output horizontal alignment against cached
terminals remains 0/75; the actual SVG lead relation applies to 67/75.
One active-driver terminal, AG1356:M12, now stands level with the coil
instead of strictly below it, leaving 91/92 strict driver checks. This
spacing regression remains recorded rather than changing the oracle.

| Measure | Fourth pass | Fifth pass |
|---|---:|---:|
| Crossings | 5,136 | 5,002 |
| Bends | 24,545 | 24,658 |
| Gate direction agreement, of 23,252 | 13,787 | 13,894 |
| Left/right agreement, of 338,266 | 206,588 | 206,587 |
| Above/below agreement, of 320,423 | 204,991 | 205,021 |
| All scored relations, of 2,202 | 288 | 288 |

No circuit gains crossings in this pass. Orientation agreement remains
30,357/32,000 and terminal signal-flow agreement remains 491/683. These
metrics do not measure the newly corrected glyphs: an independent SVG
check verifies all 47 selected single-input triangles and polarity marks,
up from zero; all ordered bindings remain correct. AG1370's paired-input
`comp` is independently checked as well. Their upward orientation in the
source remains a separate placement task.

Validation passes 280 tests without LaTeX and 281 with it, 4,000 fuzz
cases, formatting and the gallery. Exact fixture-name inventories cover
89 equivalent fixture decks and the same two capacity refusals. All 48
selected symbol decks round-trip through the release Schemify host; six
representative decks also pass the current host, whose two import aliases
produce identical cells and equivalent exports. The plugin rebuild is
558,123 bytes, SHA-256
`5b471ad81cdf561002cb188fd44d1df978de0160e69380c8f6674aafa46035b1`.
Source/native views were inspected for AG1363, 1401, 1370, 1432 and 1356.
The remaining local-group, orientation, spacing and routing differences
still prevent a claim of equivalence.

## Sixth measured pass: actual controller pins

The frozen executable is
`9fd18dffd77da9555f06aa82b9cbeb8a930fb911e728b0df89fbf5165d5295e1`.
Exactly the 75 selected converter-controller drawings change geometry;
all other AnalogGenie drawings and every AMSNet drawing are unchanged.
All decks render with the same issue inventory and no new native findings.
Every generated controller output now faces up, shares its main gate's
x coordinate and lies below that gate. Reanchoring uses the electrical
terminal and reserves the oriented symbol's space before coordinates are
assigned. Explicit positions and definition sides remain authoritative;
unsupported custom pin envelopes retain their original geometry.

The earlier 75/75 source-direction claim was based on cached terminal
coordinates and was incorrect. Direct SVG artwork gives **67 upward
outputs and eight rightward outputs**. The rightward drawings are
AG1354, 1358, 1366, 1369, 1372, 1377, 1393 and 1396: their output wires
bend upward to the switch. AG1393's cached OUT is on that routed
connection above its right-facing triangle, not at the glyph's lead tip.
Only 32/75 actual SVG output endpoints equal the cached coordinates.
The rule therefore represents a 67/75 source habit, with eight retained
mismatches, rather than a universal placement fact. No case ID selects
production behavior.

The 47 single-input glyphs retain correct triangles, signs and ordered
bindings. Actual source-apex agreement changes from 3/47 to 45/47:
AG1366/1369 regress from matching rightward glyphs to the upward default;
AG2418 remains correctly rightward outside the converter group. This
independent artwork check is separate from cached terminal signal flow.

| Measure | Fifth pass | Sixth pass |
|---|---:|---:|
| Crossings | 5,002 | 5,006 |
| Bends | 24,658 | 24,526 |
| Left/right agreement, of 338,266 | 206,587 | 206,593 |
| Above/below agreement, of 320,423 | 205,021 | 204,919 |
| Cached terminal signal flow, of 683 | 491 | 526 |
| All scored relations, of 2,202 | 288 | 288 |

Crossing increases remain named: AG1362 +3, AG1358/1418 +2, and
AG1365/1398/1453 +1. Main-path row/order, all 365 grounded-shunt below
relations and both 107 reservoir gate directions remain correct. The
AG1356 compaction exception persists at 91/92 strict driver checks.

Both test configurations pass (288 without LaTeX, 289 with), as do 4,000
fuzz cases, formatting and the gallery. The 91 exact fixture names give
89 circuit-equivalent round trips and the same two capacity refusals.
All 75 controller source decks also round-trip through the release host
(152 named subcircuits), with eight representative decks passing the current
host (16 named subcircuits). Both exact subcircuit inventories match.
The plugin is 560,793 bytes, SHA-256
`00c1df7ad2a5dcc0142808b01ff4b36bbf1c696032db67b072b87f3eba30c8bd`.
The remaining shunt columns, group separation, terminal-side choices,
rightward source exceptions and routing differences remain work.


## Seventh measured pass: grounded converter shunts

The frozen executable is
`1d1a395380d1b7aed441630861190f25b51b7fa1c6c92d4aa4013e1b3a9561b2`.
Exactly 240 of the 252 converter drawings change; every other AnalogGenie
drawing and every AMSNet drawing remains byte-identical. The unique grounded
shunt uses an available column between its certified main switch and coil,
keeping its existing row. Existing mates and admitted ordering constraints
retain precedence; adjacent main/coil columns keep the ordinary placement.
No source IDs select production behavior.

The actual connected terminal lies inside the main-to-coil interval for
**344/353** selected shunts, up from **14/353**. Before compaction all 353
satisfy it. Compaction loses the cross-row terminal order in nine cases:
AG1247:M4, AG1256:M3, AG1278:M3, AG1281:M3, AG1286:M4, AG1287:M4,
AG1290:M4, AG1356:MN1 and AG1455:M4. These remain explicit failures for the
next compaction change; the source interval oracle has not been relaxed.
All 252 main paths retain their shared row and order, all 365 selected
ground shunts remain below them, and both 107 reservoir gate-direction
checks remain correct. Controller output alignment stays 75/75; its eight
actual source-direction exceptions remain. AG1356:M12 still fails strict
vertical clearance, leaving 91/92 active-driver checks.

| Measure | Sixth pass | Seventh pass |
|---|---:|---:|
| Crossings | 5,006 | 4,850 |
| Bends | 24,526 | 24,136 |
| Channel/part orientation, of 32,000 | 30,357 | 30,356 |
| Gate direction, of 23,252 | 13,894 | 13,862 |
| Left/right agreement, of 338,266 | 206,593 | 206,483 |
| Above/below agreement, of 320,423 | 204,919 | 205,236 |
| All scored relations, of 2,202 | 288 | 289 |

AG1384 gains every scored relation; no complete match is lost. The sole
physical orientation regression is AG1217:C1, its flying capacitor becoming
horizontal while the source draws it vertically. Only four actual gate
directions change: AG1217:M9, M10, M18 and M19, each toward the unreflected
source direction. Holding the previous scorer reflection choices fixed
gives 13,898 gate matches (+4); changed reflection choices in 15 drawings
contribute -36, yielding the reported -32. These aggregate scores therefore
need their retained per-device geometry for interpretation.

Crossings increase in 31 named drawings despite the aggregate reduction:
AG1265 +6; AG1411 +4; AG1202/1254/1272/1300/1338/1359 +3;
AG1215/1294/1307/1329/1337/1343/1374/1375/1429 +2;
AG1192/1193/1239/1255/1259/1274/1313/1321/1332/1346/1347/1356/1379/1412 +1.
The exact output inventory retains these regressions alongside the gains.

Grounded reservoir capacitors show a separate placement tradeoff: outside
order changes from 335/359 to 330/359, while at-or-below placement improves
from 238/359 to 243/359. Both results are identical before and after
compaction. With shelving also disabled, all 359 already have the correct
outside order; the remaining shelf grouping needs a separate rule.

Both test configurations pass (296 without LaTeX, 297 with), as do 4,000
fuzz cases, formatting, unchanged legacy style findings and the 31-drawing
gallery. Source/native views were inspected for AG1191, 1363, 1383 and
1401. All 252 converter decks round-trip through the release Schemify host
with an exact inventory of 428 subcircuits. The 91 fixture names give 89
equivalent decks and the same two capacity refusals; seven representative
converter decks also pass the current host (11 exact subcircuits).
The rebuilt plugin is 561,656 bytes, SHA-256
`ff5ae7ad3d440dd433f96fa732eef879ac491ed1f44a5850e90c11e109b242d3`.
The nine compaction losses, capacitor regression, shelf grouping, wire
routing and remaining source mismatches prevent a claim of equivalence.

## Eighth measured pass: preserve terminal order during compaction

The frozen executable is
`9c67912a0f95c3bc334db7a981a26b756bf6502cd103d5789f134ec4f3f15874`.
The generic compactor now accepts increasing coordinate pairs. A separate
converter pass supplies only relations already true between actual settled
terminals: the upper D/S of an upright control stays below the flat power
path, and a unique shunt stays between its connected main and coil pins.
An explicit `at`, missing/hidden channel terminal or nonflat main path
prevents the relevant request. Shifted custom symbols use their transformed
terminals; symbol centers do not substitute for them.

All **353/353** selected shunts now remain within the source-derived interval,
up from 344. All **92/92** active drivers remain strictly below the main path,
up from 91. The other certified checks remain unchanged: 252 main paths,
365 shunts below, both 107 reservoir gate directions, and 75 controller
output alignments. The eight source controller-direction exceptions remain.
Only AG1247, 1256, 1278, 1281, 1286, 1287, 1290, 1356, 1429 and 1455
change geometry; every other AG drawing and all 734 AMSNet drawings retain
identical bytes. The small terminal clearances are below the structural
scorer's tolerance: every aggregate relation score remains unchanged,
including 289/2,202 all-relation matches. Per-drawing wire metrics also
remain unchanged: 4,850 crossings and 24,136 bends in total. These independent
terminal checks catch errors that the aggregate score does not distinguish.

The first plugin build was 564,625 bytes, above its 563,200-byte limit.
Replacing eight bare ascending `i32` sorts with heap sort reduces it to
557,105 bytes, a measured saving of 7,520 bytes. Equal integers have no
separate identity; keyed sorts remain unchanged. All geometry and report
hashes across 2,202 AG and 734 AMSNet drawings are identical before and
after this isolated substitution. This is a size result, not a speed claim.
The resulting plugin SHA-256 is
`8b26c6879b3de883329d2efe3bc973e290aa4fa605dedef95c66b22cab83515a`.

Reservoir capacitors still satisfy outside placement in 330/359 cases and
at-or-below placement in 243/359. Their group must survive shelf wrapping
and compaction; that work remains separate. The
[capacitive cross-coupling study](capacitive-cross-coupling.md) likewise
records a coherent source group and rejected isolated-rotation prototypes.
Neither study establishes full schematic equivalence.

Validation passes 300 tests without LaTeX and 301 with it, 4,000 randomized
connectivity/hint/card-order cases, global Zig formatting, and unchanged
legacy style diagnostics. The 31-drawing gallery and source/native views of
AG1247, 1356 and 1429 were inspected. All 252 converter decks round-trip
through the release Schemify host with the same exact 428 subcircuits.
All 91 fixture names retain 89 equivalent decks, 98 comparisons and the
same two named capacity refusals. Four changed converter decks also pass
the current host with seven exact subcircuits. The repeated plugin build
matches byte for byte.

## Ninth measured pass: keep outer reservoirs with the power path

The frozen executable is
`bb6cd0cb906daaf1145d949f88f1fc8c6ca5557c541ccc1bc585e80f01746c99`.
The unique grounded capacitor on each certified main switch's outer net
now bounds the main path's height and extends its protected shelf span.
Compaction preserves initially true relations between the actual capacitor
signal terminal and main channel. Ambiguous parallel capacitors, other
branches, hidden devices and caller geometry retain their separate cases.

All **359/359** selected capacitors now lie outside the main switch away
from the coil, up from 330, and at or below the main channel, up from 243.
Their upright axes and ground-below directions remain correct. All four
relations hold together in 359 cases, up from 214. The actual source
equality cases AG1309:COP and AG1329:COP still sit 40 native units below
the channel; allowing equality does not infer their exact level placement.
All earlier named checks remain correct: 252 ordered main paths, 353 shunt
intervals, 365 shunts below, 92 drivers below, both 107 reservoir gate
directions, and 75 controller output alignments. The eight actual controller
direction exceptions remain.

Exactly 124 AnalogGenie drawings change, all within the existing converter
inventory. Every other AG drawing and all 734 AMSNet drawings retain
identical geometry and report bytes. All 2,202 AG drawings render with the
same two named source issues. No full relation match is gained or lost:
the partial score remains **289/2,202**, not schematic equivalence.

| Measure | Eighth pass | Ninth pass |
|---|---:|---:|
| Crossings | 4,850 | 4,900 |
| Bends | 24,136 | 24,210 |
| Channel/part orientation, of 32,000 | 30,356 | 30,356 |
| Gate direction, of 23,252 | 13,862 | 13,883 |
| Left/right agreement, of 338,266 | 206,483 | 206,789 |
| Above/below agreement, of 320,423 | 205,236 | 205,378 |

No physical device axis, gate direction or block flow changes. The gate
score increase comes entirely from nine changed whole-drawing reflection
choices. Crossing counts worsen in 51 drawings, including AG1214 by eight,
AG1193 and AG1208 by five each. These regressions remain recorded in the
frozen per-drawing comparison. Visual inspection of AG1191, 1374, 1214 and
1309 confirms the reservoir placement while exposing unfinished flying
capacitor loops, bias groups and routing. A correct local relationship is
not sufficient to reproduce the whole source layout.

The regressions exercise complete source DUTs, reversed cards and capacitor
terminals, explicit geometry, ambiguity, wrong branches and a shifted,
tall custom capacitor. One older controller test now explicitly requests
both rows that imply its strict-above oracle, instead of relying on the
previous default placement. Both renderer suites pass, 312 tests without
LaTeX and 313 with it, together with 4,000 fuzz cases, formatting and
unchanged legacy style findings. All 252 converter decks retain the exact
428 round-trip subcircuits; the 91 fixtures retain 98 comparisons, 89
equivalent decks and the same two named capacity refusals.

The plugin is 558,272 bytes, SHA-256
`ca06d58d945271499e8d326e629940d823ddf681b3ea1756cbf670f7ed58e41a`.
Its repeated build is byte-identical. The 31-drawing gallery passes and
six representative views were inspected. The four source/native examples
above also pass the current Schemify host with six exact subcircuits.
All 124 changed drawings produce identical geometry and report bytes when
rerendered serially against the four-job corpus run.

## Tenth measured pass: preserve admitted relations across shelves

The frozen executable is
`c094dc10d95a3d14e15494faef868cb5fad4b94648692c068f8f489644ac307c`.
Shelf cuts now consult relation admission results. Accepted `row` and
`order` groups stay together; an accepted `above` pair forbids a cut only
when its upper device would move to a later shelf than its lower device.
Forward upper-left to lower-right chains may cross shelves. Rejected,
dropped and unhandled relations impose no cut restriction.

The independent regressions reproduce a reversed accepted relation and
geometry changed by rejected names. A separate mutation test rejects the
overly restrictive rule that keeps every `above` chain on one shelf; the
existing exported-layout fixed-point test catches the same error. Explicit
coordinates retain precedence. Four new tests pass with compaction enabled
and disabled, checking verdicts, strict ordering and electrical connectivity.

All 2,202 AnalogGenie and 734 AMSNet drawings retain identical geometry,
reports, per-drawing scores and source issues. The partial all-relation
score remains **289/2,202**. All 31 gallery SVGs are byte-identical; the
two-stage amplifier and before/after views of the new hint cases were
inspected. This fixes a constraint violation without claiming new source
layout equivalence.

Validation passes 316 tests without LaTeX, 317 with it, 4,000 fuzz cases,
formatting and unchanged legacy style findings. The full fixture inventory
retains its exact 98 comparisons and two capacity refusals. Four explicit
hint decks pass the release Schemify host; two also pass the current host.
Their native geometry and reports are byte-identical between serial and
four-job runs. The repeated plugin build is identical at 558,433 bytes,
SHA-256 `a792fcf766aeaf3c4bfc6bd2054b8ccaa96777465ed65e992df4fc2614460b05`.

## Eleventh measured pass: exact amplifier aliases and comparator strokes

The frozen executable is
`ffb91e897d114cccc22d426535f6d5cf255461808b1b1cc49325bfc7bbd92763`.
Complete contracts for the exact family names AMP, AMP1, CMP and EA now
use the existing signed triangle. All **24/24** selected source instances
match the triangle and input-sign checks, up from zero. Their **130/130**
ordered ports and net bindings remain intact, and every pin has its own
visible lead. Recognition retains the existing complete-contract boundary;
unknown controls, duplicate roles, prefixes, A1 and ZCD remain separate.
See the [alias study](block-aliases.md) for source coordinate disagreements
and the limits of the native ink check.

Generic comp/comparator/CMP triangles have no interior step; the explicit
ICM_IDEAL_COMPARATOR_VDD glyph retains its three-segment step. The actual
native audit checks all 53 complete comparator contracts, preserving 267
ordered pins: 51 plain generic triangles and two stepped ICM triangles.
AG1390's source box and AG1398's missing plus sign remain named differences.
The [digital audit](digital-symbols.md) separately confirms zero boxes among
56 conventional digital instances, while recording supply-lead, curve and
proportion differences. Neither result establishes full symbol equivalence.

Exactly the 24 alias drawings change geometry and reports. Every other AG
drawing and all 734 AMSNet drawings remain byte-identical. All structural
scores remain unchanged, including **289/2,202** all-relation matches; no
physical axis, gate direction or block flow changes. Crossings increase
from 4,900 to 4,901, entirely in AG1349 (five to six), while total bends
decrease from 24,210 to 24,209. The earlier named converter terminal-order
checks remain correct. Source/native views of AG2550, 1367, 1393 and 1237
show the improved glyphs and unfinished layout groups; AG1393 still points
upward where the actual source points right.

Validation passes 320 tests without LaTeX, 321 with it, 4,000 fuzz cases,
formatting and unchanged legacy style findings. All 31 gallery SVGs remain
identical and the non-inverting amplifier was inspected. The 94-deck symbol
cohort round-trips through Schemify with exactly 198 subcircuits, alongside
the fixture suite's unchanged 98 comparisons and two capacity refusals.
Four symbol decks also pass the current host with nine exact subcircuits.
All 24 changed drawings produce identical geometry and report bytes in
serial and four-job runs. The plugin is 558,473 bytes, SHA-256
`446d9d89fb4f131c58e897fafe6e12ee2c5b86d5e39bf24baf4e6a1ed2ac5a21`,
and its repeated build is byte-identical.

## Twelfth measured pass: complete local converter loops

The frozen executable is
`8e4dcdd30bfa92280db56c117789ceebe851f5413ee56ac11926d9a449e3a03f`.
The [converter-loop study](converter-loops.md) supplies actual SVG endpoints
and conductor trees for 145 uniquely recognized flying-capacitor groups.
The engine now places their switches, capacitors, diode and divider together,
reserves room across shelving, and commits seven local wire trees atomically.
Outside terminals attach to a recorded successful tree anchor. Explicit
geometry and wiring instructions retain precedence; incompatible actual
symbol pins or occupied routes make the local wire transaction abstain.

All **145/145** groups satisfy the 22 universal source terminal relations.
All seven selected local nets are physically continuous in **145/145**,
versus one in the frozen baseline. Their reconstructed minimal trees have
zero proper crossings with each other. This excludes remote control wires.
Exact earlier cohorts remain correct: 252 main paths, 365 shunts below,
353 unique shunts within their main-to-coil interval, 359 reservoir capacitor
orders, 92 driver orders, 75 controller alignments, and both 107-case
reservoir gate policies. Source-variable branch order and bus clearance
remain differences, separately retained in the study.

Exactly 145 AnalogGenie drawings change; the other 2,057 and all 734 AMSNet
drawings remain byte-identical. All drawings render with the same two source
issues and no native gate findings. Total AG crossings fall from 4,901 to
4,802 and bends from 24,209 to 23,372. **52 drawings gain crossings**;
these named regressions remain in the frozen comparison. Physical axis
agreement improves for 245 devices with no axis regressions. Physical
vertical gate direction improves for 549 devices and regresses for 513;
one changed gate matches neither source direction. The regressions are
outside the selected loop devices and shunts. Promoted forms affect column
ordering before the existing gate-facing pass; AG1194's reordered
MN1/MN2 pair confirms that mechanism against actual source leads. Physical
block flow is unchanged. The partial all-relation score remains
**289/2,202**, with no gained or lost names. This is not visual equivalence.

Regressions reproduce remote split nets, hidden custom terminals, shared
bus groups and rail collisions before the fixes. Both test configurations
pass: 338 without LaTeX and 339 with it, together with 4,000 fuzz cases,
formatting and unchanged legacy style findings. All 31 gallery SVGs remain
byte-identical; representative gallery views and final AG1191, 1222, 1316
and 1349 layouts were inspected. The full fixture suite retains 98 exact
comparisons and the same two capacity refusals. All 252 converter decks
round-trip through the release host with 428 exact subcircuits; six selected
decks also pass the current host with 12 exact subcircuits.

Seven bare-value sort substitutions reduce the initial over-limit plugin
by 15,302 bytes. Full 2,956-drawing before/after comparisons prove identical
geometry, reports and scores for that isolated change; no speed claim is
made. The final plugin is 559,658 bytes, SHA-256
`def3d992a8eb6909712453b6cc8c76c4c08077e189406df9e8337008e37de570`.
Its repeated build is byte-identical. All 145 changed drawings also reproduce
identical geometry and report bytes in serial and four-job runs.

## Thirteenth measured pass: converter branch order and input buses

The frozen executable is
`eaefa6ee157dd71f4ab2631b2a804dbf51180f24f15ab2334f6af8bef1f7f6cc`.
The default output order is now divider, floating capacitor, grounded
capacitor, following the common case in the
[branch-order study](converter-branches.md). Complete three-branch agreement
improves from **39/145 to 114/145**, with 88 named gains and 13 losses.
The 31 minority arrangements remain unresolved: outer topology and controller
position do not establish a reliable exception rule. Explicit caller geometry
continues to take precedence.

The local input bus now tries a spine one existing tap distance left of both
switch terminals, falling back to their shared terminal column when blocked.
All **145/145** native spines are strictly left; the source uses that relation
in **141/145**. AG1267, AG1280, AG1312 and AG1345 remain named disagreements
because their source spines use the terminal column. All 22 universal local
terminal relations still hold in 145/145 groups. Each group's seven selected
wire trees remains physically continuous, with zero proper crossings in all
21 tree pairs. Exact earlier cohorts also remain correct: 252 main paths,
365 shunts below, 353 unique shunt intervals, all four relations on 359
grounded capacitors, 92 driver orders, 75 controller alignments, and both
107-case reservoir gate policies.

Visual review exposed an oracle gap: the seven local trees excluded the
auxiliary input switch. The first boundary-port trial retained all local
certificates but lost 63 of the 64 previously wired auxiliary branches,
leaving electrical connections through ports. The expanded
[auxiliary-bus audit](converter-bus.md) checks all three actual switch
terminals and another 435 source D/G/S leads. The repaired proximity rule
measures the outside cluster's extent plus its distance to actual existing
tree ink, within the existing input distance limit. A retained routing pin
does not stand in for the whole component. Wrong-net ink, empty ink and
oversized clusters cannot satisfy that test.

The final result physically joins **107/145** auxiliary branches, up from
64, with none of the previous 64 lost. Source continuity agreement improves
from **65/145 to 106/145**: 42 source-supported gains and one regression,
AG1199:M1. Its source puts the auxiliary switch in a separate distant block;
the current native placement puts it close enough to join. All 38 native
branches still disconnected are connected in their sources. Auxiliary
placement remains unfinished, and the distance choice does not reproduce
the source's block separation. The public regressions require physical ink,
electrical connectivity and no shorts. An older uncompact AG1316 known-gap
marker failed on an unexpected improvement and was replaced by the same
positive continuity assertion.

All **2,956** corpus decks render with the same two named source issues and
no native findings. Geometry changes in 145 AnalogGenie drawings and reports
in 144; every other AG result and all 734 AMSNet results remain byte-identical.
No physical device axis, gate direction or block flow changes. The partial
all-relation score stays **289/2,202**, with no gained or lost names. Total
AG crossings increase from **4,802 to 4,864**, and bends from **23,372 to
23,435**. Crossings worsen in 64 named drawings. On the 145 selected loops,
the corresponding totals are 464 to 526 crossings and 2,696 to 2,759 bends;
these whole-circuit regressions are separate from the zero-crossing local
trees. The source branch, bus and auxiliary exceptions prevent a claim of
schematic equivalence.

Validation passes **349 tests without LaTeX and 350 with it**, 4,000 fuzz
cases, global formatting and style checks with the same five legacy API
findings. All 31 gallery SVGs are byte-identical. All 145 selected drawings
produce identical geometry and report bytes in serial and four-job runs.
The full fixture suite retains 98 exact comparisons and the same two named
capacity refusals; all 252 converter decks round-trip through the release
Schemify host with 428 exact subcircuits. The nine-deck current-host check
also passes, with 17 exact subcircuit names matching the corresponding
release-host inventory. Final views of AG1191, 1199, 1249, 1268, 1294, 1316
and 1349 were inspected against the frozen corpus geometry. They show clearer
local loops and restored auxiliary wires, while auxiliary switches remain
upright and below the loop, controller boxes and crossings remain, and
AG1199 joins the block that its source draws separately.

The plugin is **560,234 bytes**, SHA-256
`f27345af840d847ac37f6c9341c4b8112b2c9e76478dfb8051bcd4fa95eb6e16`.
Repeated native and plugin builds are byte-identical.
