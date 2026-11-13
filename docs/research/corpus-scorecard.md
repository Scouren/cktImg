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
