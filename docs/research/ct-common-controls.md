# CT-linked common-base control line

AG1114 supplies one complete five-device observation: Q3/Q4 share collector
and base, their distinct emitters meet the outer ends of X1, and Rb1/Rb2
complete the four-incidence base net by connecting it to supply and the CT
tap. Its actual Q3.B `(350,0)` and Q4.B `(250,0)` leads share conductor ink.
This is one figure, not a universal common-collector rule.

The [reader](figures/ct_common_controls.py) reselects from all 2,936 exact
source deck/human/SVG names, hashes those inputs and both indexes, and
independently verifies the ordered path/control bindings and model types of
all 25,103 drawn transistors. It verifies the selected CT's declared role
bindings and actual leads against the frozen CT inventory, both actual
resistor leads, and four named conductor trees: the four base incidences,
the shared collectors, and each emitter-to-winding connection. Cached wires
without actual SVG ink are reported and excluded from proofs.

The weaker same-kind, same-polarity common-control/common-first-path-end
cohort contains 350 exact named pairs: 55 connected and 295 separated in
source ink. These are correlated observations, including multi-device
control nets. The [frozen inventory](figures/ct_common_controls_cases.json)
retains every pair's source proof. AG764 Q1/Q2, AG781 Q1/Q3 and Q2/Q4,
and AG2376/2381 M1/MSEN are explicit negative controls; separation is checked
against all actual conductor ink. An endpoint-facing or common-collector
shortcut would join some of these incorrectly.

## Engine boundary

The cold `ct_controls` query borrows the complete Netlist and current Canvas.
All four base incidences count, including hidden/body/control pins. Two
distinct nonshorted resistors, two four-pin known NPNs with the same sink
substrate, and one complete CT contract must match. Collector, base, both
emitters and tap are distinct nonrail nets. Duplicate complete CTs and raw
base ambiguity reject before visibility or caller-frame eligibility. Source
selection uses the documented rail-name vocabulary; the engine uses its
existing Role projection, not a recovered external DUT declaration.

The intermediate record is five typed EdgeIds, asserted 20 bytes; it lives
on the stack and allocates nothing. The result is one optional pair of
indices into the existing current net-pin slice. The sole consumer is
`wires.parts`: it adds one initial adjacency for an automatic cut and leaves
ordinary partitioning, full trunk-cost competition, whole-part fallback,
later crossing cuts and explicit routing intact.

Both actual visible base leads must share a row and face each other. Each
actual C/E path is vertical, with its base strictly outside and strictly
between C/E rows. The transformed caller terminal must equal the routing
point; a hidden/reference pin or projected copy cannot certify it. No own
pin may intervene, and the complete interval must pass `Canvas.fits` at the
current routing step. Explicit route/via/first requests and fixed placement
of any of the five members abstain. The routing spine borrows the original
admitted route and placement slices: compact scaffolding temporarily omits
executing those requests, but must still preserve their precedence. This
view adds no allocation or retained flags. Caller classes, cell and face
requests are read without mutation.

This adds no distance threshold, routing exemption or placement owner.
AG1114's native CT still occupies a separate shelf; preserving the local
base line does not establish whole-figure equivalence.

## Validation and reproduction

The existing full-source compact fixture was meaningfully RED after the
broad routing experiments were removed. The corrected focused suite passes
all five tests: source continuity, declaration/card/resistor permutations,
full-incidence and ambiguity exclusions, explicit caller controls, and
hidden/skewed caller frames. Negative tests use identical caller CT glyphs
under recognized and opaque family names and compare actual placement and
the four base incidences' physical partition.

The first boundary run exposed a fixture error: appended cards/hints lacked
a separating newline and became part of the preceding comment. The fix
keeps the physical oracle unchanged and verifies exact parsed hint verbs,
pre-drawing admission, and parsed/drawn extra-device presence. The passing
run is `iteration21-ct-controls-local4.log`; the subsequent request-guard
run also passes all five tests. Full checkpoint corpus and
release validation remain pending; the focused pass is not a parity claim.

```sh
python3 -B docs/research/figures/ct_common_controls.py \
  external/examples /tmp/ct-common-controls.json --check
```

The replay compares every frozen field, named source pair and dependency
hash. Literal topology mutations and independent conductor-graph method
checks accompany the actual source proofs. No `/tmp` discovery artifact is
required to reproduce the inventory.
