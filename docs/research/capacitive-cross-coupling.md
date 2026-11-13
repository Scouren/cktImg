# Capacitive cross-coupling: a group and route problem

This is proposed work. No orientation or routing rule from this study is
implemented. The source evidence shows a coherent group; the temporary
prototypes below do not yet reproduce it well enough to ship.

`figures/cross_caps.py` selects pairs using the converted netlist alone:
same-polarity MOS or BJT devices; four distinct, nonrail drain/collector and
gate/base nets; one capacitor from each drain/collector to the opposite
control; and exactly one incident DC path at each control, a resistor to
the same third bias net. Device names, coordinates and source IDs do not
participate in selection. The script retains the broader reciprocal cohort
as named counterexamples.

The complete 2,202-drawing Analog-Genie scan selects these eight pairs:

| Circuit | Capacitors | Transistors |
|---|---|---|
| ag-538 | C1, C2 | M1, M2 |
| ag-1108 | Cnp1L, Cnp1R | MP1, MP4 |
| ag-1108 | Cpn2L, Cpn2R | MP2, MP5 |
| ag-1108 | Cpn3L, Cpn3R | MP3, MP6 |
| ag-1114 | Ccp1, Ccp2 | Q1, Q2 |
| ag-1131 | C3, C4 | M1, M2 |
| ag-1136 | C2, C3 | M3, M4 |
| ag-1169 | C1, C2 | M1, M2 |

Every pair has horizontal capacitors on one row above both associated
drain/collector terminals, between their columns, each capacitor closer
to its own drain/collector. Both controls face inward in the five circuits
other than ag-1108. Its six controls face outward. All eight pairs have
exactly one crossing between their capacitor feedback pieces, and every
one of the sixteen feedback pieces contains a diagonal segment.

This distinction is visible in actual wires. The ten inward controls have
continuous wires from the opposite capacitor. In ag-1108 the six capacitor
feedback pieces end inside the pair at net labels; the outward gates belong
to separate wire pieces of the same named nets. Combining all pieces by net
name would conceal this distinction. The script verifies all studied wire
segments against the SVG's actual conductor ink before testing continuity.
It also verifies all 80 capacitor and transistor channel/control endpoints
against transformed primitive strokes, including BJT base leads. Coordinates
are rounded to six decimal places only to remove quarter-turn trigonometry
residue. A displaced capacitor endpoint and a missing conductor segment were
both rejected by negative checks.

There are no selected holdout pairs under the established numeric-ID modulo
five split and no selected pair in the 734-drawing AMSNet corpus. The source
variants are correlated and this remains a small, unvalidated cohort. The
broader reciprocal-capacitor selector finds thirteen pairs: twenty horizontal
and six vertical capacitors. The vertical exceptions are ag-1062:CPp1/CPp2
and ag-1168:C1/C3/C5/C7. Two additional horizontal BJT pairs, ag-1149:C1/C2
and ag-1185:C5/C6, do not meet the common resistive-bias condition. The latter
uses inductive base bias and puts each capacitor nearer the opposite
transistor. They must not silently inherit the proposed placement.

Run the study with:

```sh
python3 -B docs/research/figures/cross_caps.py \
  external/examples/analoggenie /tmp/cross-caps-ag.json --native NATIVE_JSON_DIR
python3 -B docs/research/figures/cross_caps.py \
  external/examples/amsnet /tmp/cross-caps-ams.json
```

The paired source digest is
`f193fdb23c88b87ca27329d8c671d7519dda026da20c5945e950d14fdbffee07` for
Analog-Genie and
`c0d304c90b355b63e2d69655f4a68d51e10b9910f907416dfa4c418c5393c725` for
AMSNet. The report carries exact selected names, source and native file
hashes, actual terminal coordinates, feedback paths and crossing points.

## Rejected prototypes

`figures/cross_caps_probes.json` records the exact circuits, inserted hints,
hint verdicts, input/output hashes and results. All eighteen recorded probe
decks were rerun with one frozen native executable, SHA-256
`1d1a395380d1b7aed441630861190f25b51b7fa1c6c92d4aa4013e1b3a9561b2`.
Every recorded bridge, cell, face and wire hint was honoured.

| Probe over six circuits | Crossings | Bends |
|---|---:|---:|
| Existing engine | 27 | 85 |
| Make only the selected capacitors horizontal | 30 | 118 |
| Also place each pair above/between its transistors | 26 | 122 |
| Also face the ten continuous-feedback controls inward and force feedback nets to remain wires | 48 | 148 |

The paired-cell probe puts capacitors in distinct interior cells closest to
their own transistor columns, on the first free common row above both
transistors. Final geometry retains the above/between/near-own relations in
seven of eight pairs. In ag-1169 the later shelf pass separates the capacitors
from their transistors. The horizontal-only probe reaches only six interior
pairs and four pairs near their own drains. Classifying the capacitors also
changes inferred gate directions: the last probe puts all sixteen controls
inward, disagreeing with the six outward source controls in ag-1108.

Forcing only these feedback nets to remain wires removes their names while
making routing worse. This isolates thinning after poor placement/routing
as the main cause of the missing continuous feedback. A global crossing
budget increase would hide the failure.

A further local seed experiment froze the settled device positions and
requested a Manhattan crossover with exactly one transverse crossing. One
wire has three segments; the other has five. Both seeds are honoured in
ag-1136. Seeds in ag-538, ag-1114 and ag-1131 are rejected by the existing
geometry guarantee: intervening parts occupy their routes. Ag-1169 fails
the initial settled-geometry certificate after shelf separation, so emits
no seed. Ag-1108 is deliberately outside this continuous-feedback experiment.
These outcomes and exact seed coordinates are retained in the probe record.

## Missing local request and its boundaries

The existing transistor path uses the general lattice pipeline. The other
local feedback implementation, `opamp_grow.feedbackCell`, applies to an
amplifier block's C/MOS return rectangle. `opamp.applies` requires at least
one admitted amplifier block and external gate-only MOS controls; it does
not admit these transistor feedback circuits. Its canvas reserves space
for bodies and runs, but those reservations do not become seed routes for
the generic router.

`wires.wire` draws every admitted ladder/column/trunk pattern before calling
`routes.draw` for its waiting nets. Moving a feedback net earlier in the
net order therefore does not reserve a corridor ahead of all competing
patterns. `routes.mirrored` copies an already drawn net when the result
fits; it does not jointly choose two crossover tracks. There is currently
no local coupled-pair request that reserves both tracks. `thin.name` then
cuts automatic internal nets with excessive crossings.

A candidate request must carry the two capacitors, two transistors and two
control nets together through form selection, placement, shelf wrapping
and routing. It should reserve a clear crossover corridor while placing
other parts, certify the actual settled terminals and bodies, then commit
the two seed routes atomically before unrelated patterns. Existing explicit
instructions must win. The corridor certificate needs inward-facing control
pins, horizontal capacitor leads above them, enough quarter-grid spacing,
no body or forbidden marker in either seed, exactly one crossing between
the two nets and no junction there. No room or a failed certificate must
leave the normal pipeline intact. The source's labelled ag-1108 convention
requires a separate admission decision; netlist-only discrimination remains
unproven.

The narrow Manhattan candidate has cap control endpoints `A` and `B` on the
upper row, with `A.x < B.x`, and inward gate endpoints `L` and `R` on the
lower row. Choose interior columns `A.x < xL < xM < xR < B.x` and an
intermediate row `yM`. Route `A → (xM,A.y) → (xM,R.y) → R` and
`B → (xR,B.y) → (xR,yM) → (xL,yM) → (xL,L.y) → L`. Their only crossing is
`(xM,yM)`. Selecting which net uses the shorter route by canonical rank is
deterministic but makes the wires asymmetric. This is a candidate for a
human-readable Manhattan version, not proof of exact source equivalence.

The exact source X uses diagonal wires. `include/cktimg.h` and
`placed.Placed.wire_pts` explicitly promise Manhattan polylines;
`Canvas.fits`, maze occupancy, crossing checks, route hints and downstream
export assumptions rely on that promise. A source-identical diagonal X
therefore needs a deliberate compatible representation and downstream
validation. It cannot be inserted silently into the current wire arrays.
Two exactly mirrored Manhattan paths also cannot form one transverse crossing
on their mirror axis: their reflected segments there are collinear. This
representational gap remains open alongside the placement/routing work.
