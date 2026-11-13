# Converter output branches: a default with named exceptions

The 145 topology-certified converter loops in [converter-loops.md](converter-loops.md)
have three vertical branches beyond the output main switch: the resistor
divider (`R`), floating output capacitor (`CO`), and grounded output capacitor
(`CG`). Their actual source lead columns give four orders:

| Order, left to right | Source drawings | Exact native 12 matches | Exact final native 13 matches |
|---|---:|---:|---:|
| R–CO–CG | 114 | 26 | 114 |
| CO–R–CG | 17 | 12 | 0 |
| CO–CG–R | 13 | 1 | 0 |
| CG–CO–R | 1, AG1268 | 0 | 0 |

The final iteration-12 wrap snapshot matches the complete three-branch order
in **39/145** drawings. Its **55/145** agreement on “divider between main and
floating cap” is a weaker boolean measure. These are distinct measurements.
Every case name, both orders, source columns, and native JSON hash is in
[converter_branches_cases.json](figures/converter_branches_cases.json).
That inventory retains the iteration12 baseline. Final iteration13 uses
R–CO–CG in all 145 drawings and matches **114/145** source orders: **88 gains
and 13 losses** against the baseline. The 31 minority source arrangements
remain named exceptions; the common default does not explain their cases.

The three branch glyphs per drawing are already included in the existing
3,335-endpoint loop audit. This study references those **435 glyph certificates
(870 endpoints)**, checks their source `.cir`, `.svg`, and `.human.json` hashes,
and requires their actual terminal coordinates to match the studied devices.
It does not duplicate the loop selector or substitute cached orientation for
ink. No AMS circuit qualifies under the existing loop certificate. The source
variants are correlated; 145 drawings are not 145 independent design choices.

## Tested explanations and their limits

All drawings attach feedback to a remote controller: 139 have one remote
terminal and six have three. Another actual-SVG audit verifies those terminals
in **116 drawings**. **29 remain unknown**: 25 cached coordinates fail the lead
endpoint match; four have an unsupported primitive container (AG1210, AG1289,
AG1342, AG1352). The latter failures do not prove that a lead is absent.
The inventory retains every coordinate, object reference, and exact failure.

Among the common 114 drawings, 28 have one verified feedback terminal left of
the divider and 59 have one to its right; five have three left and one has
three right. The other 21 are unknown. In 52 of the 59 one-right cases, CG is
closer in x to that terminal than R. Placing R nearest the controller would
therefore contradict many common sources. CO–R–CG has left/right/unknown
counts 5/6/6; CO–CG–R has 9/3/1. Controller side is no clean exception selector.

Only **AG1237 and AG1260** physically wire the verified remote feedback
terminal to the divider. The other 114 verified drawings have separate ink
components. Named connections are visible in inspected examples, but label
semantics were not independently audited here. Names never join components
in the continuity measurement.

MOS body ties, controller pin kind, and opaque-block count also overlap across
orders. For example, tying all three selected MOS bodies to their sources
occurs in 9 common, 2 CO–R–CG, and 10 CO–CG–R drawings. Tying all three to the
supply occurs in 101/15/3/1 across the four orders. Eight drawings with extra
negative-output control attachments all use the common order (AG1191–1194,
AG1196–1199); that explains no minority choice. Exact feature/name groups are
retained, including mixed body ties.

## A reviewable outer-topology counterexample

The name-free outer graphs have 138 equivalence classes. One five-member
class has two source orders: **AG1306 is CO–R–CG**, while **AG1308, AG1318,
AG1325, and AG1341 are CO–CG–R**. The AG1306/1308 source SVGs were also rendered
and inspected: both place controllers above the loop; the branch columns
differ visibly. Their CO/R/CG columns are 450/490/570 and 450/540/490.

Each of the four cross-order pair certificates includes every node mapping
and **45 pin-index mappings across 14 devices**. For AG1306→AG1308, all device
identifiers happen to map to the same spelling, but that is an output of the
search. X1 pin positions 1 and 3 map `net1→net0` and `net0→net1`; its position 4
maps `VB2→VB3`. X2 position 4 maps `net0→net1`. The stored map lists all other
terminals and their nets, including MOS body pins.

Equivalence preserves MOS D/G/S/B roles and polarity, diode A/K roles,
symmetric passive ends, literal passive values and MOS instance parameters,
rail roles, top-level port membership, and selected loop roles. Opaque blocks
preserve declared pin counts and positional connectivity. Instance/net names,
block family names, semantic block-port names, and model parameter bodies do
not select a mapping. Hash refinement only prunes candidates; the final
edge-by-edge certificate and complete pin map must both pass.

Recursively expanding hidden subcircuits produces **145 distinct graphs**.
Thus this is an outer-connectivity counterexample, not a full-circuit one.
No proven condition currently predicts all 31 minority arrangements.

## Placement results and reproduction

`loop_place` uses **divider, floating cap, grounded cap** as its default
inside an otherwise admitted loop group. Explicit caller cells/orders and
independently supported constraints retain precedence: the placement owner
abstains when an admitted caller relation touches a group member. This replaces
its earlier inferred x-sort with a bounded preference, not a universal human
rule. The final native audit matches the complete order in 114/145 drawings;
the weaker divider-between-main-and-floating-cap condition also agrees with
the source in 114/145. These equal totals measure different conditions.
`tests/converter_branches.zig` records the source AG1191 order and opposing
explicit constraints. Its default-order assertion failed before the change;
both explicit-precedence cases passed, and all three pass after the change.
The 13 lost baseline order matches are AG1234, AG1240, AG1263, AG1289,
AG1290, AG1295, AG1298, AG1304, AG1306, AG1311, AG1334, AG1346, and AG1350.
They remain regressions against their actual source order. The separate
[bus study](converter-bus.md) measures local input-spine and auxiliary-branch
continuity, including its remaining source mismatches.

Run from the repository root; the script checks four named audit-method
oracles, including a gate/channel role mutation and a tied-column rejection:

```sh
python3 -B docs/research/figures/converter_branches.py \
  external/examples/analoggenie /tmp/converter-branches-replay.json \
  --native /tmp/cktimg-human-rules/all-ag-iteration12-wrap
cmp docs/research/figures/converter_branches_cases.json /tmp/converter-branches-replay.json

python3 -B docs/research/figures/converter_branches.py \
  external/examples/analoggenie /tmp/converter-branches-final13.json \
  --native /tmp/cktimg-human-rules/all-ag-iteration13-final
```

The `--loops` argument can select a regenerated loop inventory. It must carry
the actual source certificates and matching hashes; its own hash is retained
in this result. Missing native files, stale sources, ambiguous branch columns,
and uncovered pin mappings fail the audit. The script does not execute the
engine, regenerate native results, or infer a runtime rule from circuit IDs.
