# Conventional digital symbols: remaining-box audit

The paired corpus contains no additional conventional digital family awaiting
an alias. [digital_symbols.py](figures/digital_symbols.py) scans every outer
subcircuit instance in 2,202 Analog-Genie and 734 AMSNet drawings. It selects
known digital assets even if their family name is unknown, records the full
outer family/asset census, and checks an
[exact instance inventory](figures/digital_symbols_cases.json). Unused library
definitions do not count as drawn instances. All 56 conventional digital
instances are in Analog-Genie; AMSNet has none.

| Exact family | Instances | Source body | Inversion bubbles | Extra XOR paths |
|---|---:|---|---:|---:|
| inverter | 46 | Triangle | 46 | 0 |
| buffer | 2 | Triangle | 0 | 0 |
| and_gate | 3 | Curved | 0 | 0 |
| nand_gate | 2 | Curved | 2 | 0 |
| xor_gate | 2 | Curved | 0 | 2 |
| xnor_gate | 1 | Curved | 1 | 1 |

Each has the complete declared `VDD VSS A Y` or `VDD VSS A B Y` contract.
The source audit assigns actual path commands/control points, circles and
lead strokes to each named symbol's transformed SVG group. All 120 cached
signal endpoints meet a unique actual signal lead. None of these groups
draws supply leads; VDD/VSS are also absent from their cached terminal maps.
This statement is based on the inspected ink, not inferred from the cache.

Frozen iteration nine, executable SHA-256
`bb6cd0cb906daaf1145d949f88f1fc8c6ca5557c541ccc1bc585e80f01746c99`,
draws **zero boxes** for this cohort: 48 triangles and eight polygonal gate
bodies. All 49 inversion bubbles and three extra XOR/XNOR input paths agree
in count with the source. Native SVG bodies are assigned to the named JSON
placement after verifying its display transform against every wire vertex.
All **232 ordered electrical pins and net bindings** have unique actual SVG
lead strokes, with the expected signal/rail sides and A-above-B input order.
That includes 112 native supply leads absent from the source drawings.

This is bounded agreement, not glyph equivalence. Native bodies are all
80×80 units; source inverter/buffer triangles are approximately
23.751×28.749 units in their untransformed asset frame. Source cubic curves
become native polyline approximations. Native VDD/VSS tips on the XOR/XNOR
instances `ag-438:x1`, `ag-545:x1` and `ag-1076:x5` extend slightly inside
their body outlines: each tip is 0.250943 native units from the nearest
outline segment. These six small overlaps are recorded separately from
the preserved electrical ports; they are not missing connections.

Named exclusions also have positive source evidence: `PFD` in
`ag-439:xpfd`/`ag-440:xpfd` has A/B and QA/QB ports; `DAC` in
`ag-515:x1`/`ag-516:x1` has two output ports; `CP` in `ag-1070:x4`/`x5`
has multiple charge-pump controls. All six have actual source polygons and
remain native boxes. Their names do not justify substituting a simple gate.

Reproduce the audit without a Zig build:

```sh
python3 -B docs/research/figures/digital_symbols.py \
  external/examples/analoggenie /tmp/digital-symbols.json \
  --native-dir /tmp/digital-symbols-native --bin /path/to/cktimg-json
python3 -B docs/research/figures/digital_symbols.py \
  external/examples/amsnet /tmp/digital-symbols-amsnet.json
```

Omit both native options for a source-only report. Reports retain every
source triple's hash, the paired corpus digest, audit dependencies,
renderer/output hashes, exact instance names and observed strokes. Literal
checks reject unknown path commands and a signal/rail coordinate swap;
nearby unrelated triangles cannot satisfy the target placement.
