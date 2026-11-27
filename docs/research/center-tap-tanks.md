# Center-tapped coils and parallel tank capacitors

Nine source coil/capacitor relations share four geometric facts: the
capacitor is parallel to the winding, their longitudinal midpoints agree,
their electrically corresponding ends have the same order, and the
capacitor lies opposite the center-tap lead. Both outer-net legs are actual
continuous SVG conductor ink in all nine relations. This is evidence from
seven capacitors in five drawings, not nine independent circuits or a
universal rule for every LC network.

The exact pairs are:

| Source | Coil/capacitor pairs | Ownership |
| --- | --- | --- |
| AG1103 | XL1/C1 | Unique |
| AG1147 | X1/C | Unique |
| AG1151 | XL/C | Unique |
| AG1152 | XL1/C1, XL2/C2 | Unique |
| AG1180 | XLE1/CT1, XLO1/CT1, XLE2/CT2, XLO2/CT2 | Two coils per capacitor; excluded from the unique rule |

[The source reader](figures/center_tap_tanks.py) reselects the complete
center-tap family inventory and checks its exact names and source hashes.
Each measured coil endpoint comes from its own SVG symbol; each capacitor
endpoint comes from its own capacitor strokes. Named-net conductor paths
use only cache segments backed by actual SVG ink. Cache-only segments are
retained as evidence and cannot establish a connection. Actual contact dots
distinguish a joined crossing from a plain crossing. All eighteen paths,
actual terminals, ordered bindings and owner lists are retained in the
[source inventory](figures/center_tap_tanks_cases.json). Its 25 named checks
include wrong half-plane, swapped ends, off-center/skewed frames, all eight
poses, labels, foreign nets, proper crossings and cache-only wire cases.

The engine projection selects one complete `CT_INDUCTOR` contract with
exactly `N1/N2/N3`, distinct outer nets, a distinct tap net, exactly one
two-terminal capacitor across the outer nets, and no second complete coil
on that unordered pair. Counts precede visibility and frame filtering, so
an unseen competitor cannot make an ambiguous topology appear unique.
AG1180 remains a separate whole-bank placement problem; applying the
unique-pair rule twice to one capacitor would assign conflicting owners.

The prototype preserves the coil's existing pose. After ordinary lattice
coordinates it turns only the capacitor, using actual class terminals and
sides. Both symbols must have centered opposing outer terminals; the tap
must be cardinal and perpendicular. The first position uses actual class
bounds and existing spacing. A nearest-first search advances on the
quarter-unit grid through at most one additional symbol unit. That local
search radius is an explicit placement choice, not a measured human
distance. Every candidate clears other visible symbol boxes plus the
configured clearance. If no candidate fits, the capacitor's complete
original state is restored.

Caller cells, faces, forms, relations, groups, mates, fixed origins or weak
stays take precedence. Explicit styles, port sides, rail outer nets and
route/via requests also exclude automatic geometric placement. A semantic
unique pair stays on one shelf even if a custom frame declines the later
placement; this uses cut-only spans and does not reserve every empty row.
The existing wrap rules retain cell/strong-origin and admitted relation
precedence. A successful pair contributes only initially true coordinate
orders to the existing single compaction pass. Its equal longitudinal
midpoint already shares a real coordinate track; no synthetic track is
introduced.

The first single-position prototype failed on AG1151 and the first AG1152
tank because ordinary I3 and D2 occupied the target. The bounded local
search resolves those tested collisions. All nine focused public tests now
pass, including all five source pairs in both compaction modes, AG1152's
formerly split physical leg, reversed capacitor cards, reordered declared
ports, caller precedence, topology exclusions, a broad fixed obstacle,
literal oracle mutations and an allocation-failure sweep. The declaration
permutation uses a fresh Library because registered classes persist by
family name. The allocation sweep disables backing resize/remap so every
growth reaches the allocator's failure sequence. These focused results do
not establish whole-corpus physical parity; checkpoint21 remains under
broader validation.

[The native companion](figures/center_tap_tanks_native.py) checks all 25
ordered electrical bindings before measuring actual public terminal
coordinates and ten physical wire legs. It verifies each selected drawing,
report, executable and source hash against the corpus scorecard. Native
labels cannot bridge a gap. Its eight literal checks reject binding changes,
duplicate device names, gaps bridged by labels or foreign wires, and shifted
midpoints; a reordered declaration preserves the named contract. The
separate center-tap glyph audit checks actual rendered symbol ink; this
companion measures placement and native wire geometry.

The initial center-tap glyph candidate has zero of five complete relative
relations and only two pairs with both physical legs joined. Its world coil
axis agrees with four of the five sources: AG1103's source coil is vertical,
while the native coil remains horizontal. This rule intentionally does not
solve that world-pose difference. The `iteration21-routes-a` prototype
measures all five relative contracts and all ten physical legs successfully,
with all 25 ordered bindings intact and no selected coil-pose change. Its
broader routing changes fail whole-corpus physical preservation, so this is
a local result from a rejected combined candidate, not checkpoint approval.
The independent whole-pair audit remains a required gate after ablation.

Reproduce the source proof from the repository root:

```sh
python3 -B docs/research/figures/center_tap_tanks.py \
  external/examples /tmp/tank-source.json --check
```

Compare scored corpus directories without rebuilding:

```sh
python3 -B docs/research/figures/center_tap_tanks_native.py \
  external/examples /tmp/tank-native.json \
  --native before=/path/to/all-ag-before \
  --native candidate=/path/to/all-ag-candidate \
  --require-complete candidate
```

The strict native gate requires the exact five names to satisfy both the
relative geometry and both physical legs. It deliberately fails for the
initial glyph candidate. A frozen native inventory will accompany a
validated candidate; the source expectation remains unchanged.
