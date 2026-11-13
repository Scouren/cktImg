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
| That output's x equal to the driven gate's x | 75 / 75 |
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
horizontal alignment remains 0/75. Source drawings separate control and
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
shunts remain below them. Block-output horizontal alignment remains 0/75.
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
