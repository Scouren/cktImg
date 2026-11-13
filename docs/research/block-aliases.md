# Exact amplifier aliases: source evidence and native baseline

This study supports a bounded glyph-recognition change for the exact family
names `AMP`, `AMP1`, `CMP` and `EA`. Frozen iteration eight still draws every
selected instance as a box. Matching these glyphs would not establish full
schematic equivalence.

[block_aliases.py](figures/block_aliases.py) scans all 2,202 Analog-Genie
drawings. It selects instances from the converted SPICE's last subcircuit,
using the whole, case-insensitive family name and its complete declared port
contract. The [exact inventory](figures/block_aliases_cases.json) checks names,
including exclusions and cached-frame disagreements; equal counts with
different names fail.

| Exact family | All occurrences | Complete contracts | Actual source triangles |
|---|---:|---:|---:|
| AMP | 6 | 1 | 1 |
| AMP1 | 40 | 16 | 16 |
| CMP | 8 | 4 | 4 |
| EA | 43 | 3 | 3 |
| A1, excluded generic name | 63 | 37 | 37 |
| ZCD, excluded box family | 2 | 2 | 0 |

`AMP1` is one exact name; it does not admit `AMP10`. Other prefixes and
suffixes are excluded. A complete contract has two to eight ports, exactly
one output, either one signed/unsigned input or the positive/negative pair,
and only unique recognized supply, ground and VB1/VB2/VB3 bias roles.
Unknown controls, duplicate roles and mixed input contracts remain boxes.
Caller-provided classes and explicit side instructions retain precedence.
Names alone do not infer a subcircuit's electrical function.

The 24 admitted instances have matching source polarity marks: 22 signed
input pairs and two single negative inputs, `ag-1393:x1` and `ag-1456:x1`.
The source SVG supplies transformed triangle vertices, polarity strokes and
external lead endpoints independently of the cached terminal table. Neither
these aliases nor the two excluded families occur in the 734 AMSNet drawings.
The textbook variants are correlated evidence, not independent validation
of every possible circuit using these names.

## Cached source coordinates are a separate observation

Fifteen admitted instances have all cached signal coordinates at the actual
same-role SVG lead. The following nine disagree:

| Instance | Cached signal ports disagreeing with their SVG leads |
|---|---|
| ag-1349:x2 | INN, INP |
| ag-1351:x1 | INN, INP, OUT |
| ag-1367:x1 | INN, INP, OUT |
| ag-1393:x1 | INN, OUT |
| ag-1407:x1 | OUT |
| ag-1456:x1 | INN, OUT |
| ag-2551:x1 | OUT |
| ag-2556:x1 | INN, OUT |
| ag-2605:x1 | INN, INP, OUT |

All 24 contracts declare VSS but omit it from the cached source terminal
map. This is missing cached geometry, not proof that the source SVG lacks a
VSS lead. Triangle/sign agreement therefore cannot certify all-port geometry.

## Native before/after oracle

[block_aliases_native.py](figures/block_aliases_native.py) checks the same
24 names. Native JSON supplies placement, ordered ports and net bindings;
ordered SVG wire paths establish and verify the display transform. A body
must belong to the named placement, every declared pin must reach its own
body's visible lead, signed inputs must meet their marks on the base, and
OUT must leave the apex. A neighboring triangle cannot satisfy the case.
Selected source triples and source-audit dependencies must still match their
recorded hashes before rendering.

The frozen iteration-eight executable, SHA-256
`9c67912a0f95c3bc334db7a981a26b756bf6502cd103d5789f134ec4f3f15874`,
produces **24 boxes, zero triangles**, while preserving **all 130 ordered
ports and net bindings** and their individual SVG leads. Boxes range from
60×40 to 160×80 native units. Every box labels its family and every port;
port text is 9 px and family/reference text is 11 px. The audit records
actual body dimensions, label anchors and font sizes; it does not certify
font bounding boxes or absence of label overlap.

Temporary full-deck controls remapped the families to the existing `opamp`
or `comparator` glyphs without changing the declared electrical bindings.
All 24 controls pass triangle, sign, signal-role and ordered-binding checks.
The four comparator controls additionally draw an interior step absent from
the corresponding source CMP glyphs. Extra native interior polylines remain
visible in the report, separate from the shape/sign gate. The existing-family
audit below supports a general distinction between plain comparator triangles
and the explicitly stepped ICM glyph; it does not support removing every
comparator step or adding a special rule for one CMP source instance.

Repeated frozen-native runs produce identical report bytes. Literal checks
cover a nearby unrelated triangle and reversed port order. An OUT/VDD
coordinate swap originally passed body/sign and electrical-order checks;
the independent signal-role check now rejects it. No source wiring round
trip or complete stroke/placement equivalence is claimed.

## Existing comparator styles

[comparator_strokes.py](figures/comparator_strokes.py) checks all 74 outer
instances of four exact family names, including incomplete port contracts.
It assigns actual outline, polarity and step strokes to each source symbol,
and checks an [exact style inventory](figures/comparator_strokes_cases.json).
No unsupported ink is skipped. These are observations of all occurrences,
not counts of instances the engine can recognize.

| Exact family | Plain triangle | Stepped triangle | Box |
|---|---:|---:|---:|
| comp | 15 | 0 | 0 |
| comparator | 48 | 0 | 1 |
| CMP | 6 | 0 | 2 |
| ICM_IDEAL_COMPARATOR_VDD | 0 | 2 | 0 |

The two stepped triangles are `ag-806:x1` and `ag-809:x2`. Both have an actual
three-segment interior step in the `comparator` SVG asset. The generic
`comparator` box is `ag-1390:x1`; its eight-port contract is supported, so it
remains an existing source-body mismatch rather than an excluded contract.
Its IN+ and OUT share a net, which is an electrical fact, not a glyph rule.
`ag-1398:x1` is a plain triangle with only a minus mark despite declaring both
INN and INP; that polarity mismatch also remains explicit. The two CMP boxes,
`ag-1362:x1` and `ag-1418:x1`, contain unknown VX/LX controls and are outside
the complete contracts admitted by this alias proposal. No instance of these
four exact families occurs in AMSNet.

The evidence supports plain appearance for recognized generic
`comparator`/`comp`/`CMP` contracts while retaining the stepped appearance for
the explicit ICM family. Changing appearance does not establish electrical
semantics or fix the two named existing generic-comparator discrepancies.

## Iteration eleven: complete comparator cohort

The implemented alias rule changes all 24 selected boxes into triangles.
The native audit matches every source input sign and retains all 130 ordered
pins, net bindings and own-body SVG leads. All 24 triangles contain no extra
interior polylines. Serial and four-job geometry/report outputs are identical.
Source/native placement and proportions still differ; the wider score and
AG1349 crossing regression are recorded in the [scorecard](corpus-scorecard.md).

[comparator_strokes_native.py](figures/comparator_strokes_native.py) extends
the native check to all **53 complete contracts** in the comparator source
inventory: 51 generic `comp`/`comparator`/`CMP` instances and two explicit ICM
instances. The inventory separately fixes all 53 admitted and 21 excluded
instance names. Selection includes contextual VIN polarity: VIN beside VIP
is negative, while a lone VIN is unsigned. A separate native sign check
prevents that distinction from disappearing in the SVG adapter.

Frozen iteration eleven, executable SHA-256
`ffb91e897d114cccc22d426535f6d5cf255461808b1b1cc49325bfc7bbd92763`,
preserves all **267 ordered ports and net bindings**, each with an actual SVG
lead, and passes every native signal-role check. All 51 generic instances
have no interior step; both ICM instances retain one four-vertex step with
the source's right/up/right segment directions in its untransformed frame.
The step's dimensions are not asserted equal to the source.

The gate retains exactly the observed discrepancies: the source body differs
for `ag-1390:x1`; source/native mark counts differ for `ag-1390:x1` and
`ag-1398:x1`. The first has an unsigned source box, so its mark difference
accompanies its body difference. These named gaps waive neither electrical
binding preservation nor native signal-role/step checks. Against frozen
iteration nine the same audit fails on four CMP boxes and 47 generic
comparator steps, establishing that it detects both changed behaviors.

The audit also attempts source signal-lead assignment using the earlier
triangle/sign projection rule. That rule cannot assign all signal roles in
20 of these broader source cases, including both ICM symbols; the exact
names and reasons remain in the report. Those are limits of this source
geometry check, not evidence of missing electrical pins. No full source
terminal-frame equivalence is claimed for the broader cohort.

Reproduce the source and native audits from the repository root:

```sh
python3 -B docs/research/figures/block_aliases.py \
  external/examples/analoggenie /tmp/block-aliases-source.json
python3 -B docs/research/figures/block_aliases.py \
  external/examples/amsnet /tmp/block-aliases-amsnet.json
python3 -B docs/research/figures/comparator_strokes.py \
  external/examples/analoggenie /tmp/comparator-strokes-source.json
python3 -B docs/research/figures/comparator_strokes.py \
  external/examples/amsnet /tmp/comparator-strokes-amsnet.json
python3 -B docs/research/figures/comparator_strokes_native.py \
  /tmp/comparator-strokes-source.json external/examples/analoggenie \
  /tmp/comparator-strokes-native /tmp/comparator-strokes-native.json \
  --bin /path/to/cktimg-json
python3 -B docs/research/figures/block_aliases_native.py \
  /tmp/block-aliases-source.json external/examples/analoggenie \
  /tmp/block-aliases-native /tmp/block-aliases-native.json \
  --bin /path/to/cktimg-json
```

Add `--require-triangles` for the shape/sign/signal-role gate. It fails on
the exact 24 frozen-native names. The paired source digest is
`f193fdb23c88b87ca27329d8c671d7519dda026da20c5945e950d14fdbffee07`
for Analog-Genie and
`c0d304c90b355b63e2d69655f4a68d51e10b9910f907416dfa4c418c5393c725`
for AMSNet. Reports retain source, executable, audit and output hashes.
