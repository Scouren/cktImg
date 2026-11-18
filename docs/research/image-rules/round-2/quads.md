# Four-device switching groups: membership does not determine arrangement

A four-transistor crossed-gate pattern has several human arrangements in this
corpus. It can justify collecting a candidate group; it does not justify
forcing a single row, independent rectangular source pairs, inward gates,
or diagonal wiring. AG80 and AG82 are a particularly strong boundary: their
complete ordered DUT cards, parameters, models and formal order correspond
under a literal bijective net renaming, while their source-pair arrangements
differ.

This is a new root study following the second complete visual pass. It makes
no engine change. Its generated pictures belong to the same frozen executable
as the other studies. Every one of the 26 selected source/native pairs was
actually viewed on seven newly composed sheets. [Per-example observations](quad_observations.json)
and the [render provenance](quad_rendered.json) retain the exact names and
hashes. Overview observations are not endpoint or physical-path certificates.

## Complete-circuit counterexample to a unique topology-only pose

![AG80: adjacent source pairs, source left and generated right](figures/quads/ag-80-pair.png)

![AG82: nested source pairs, source left and generated right](figures/quads/ag-82-pair.png)

[The transport certificate](quad_equivalence.json) checks nine cards and all
30 ordered terminal occurrences. The six MOSs retain D/G/S/B and the same
model/parameters; both resistors and the current source retain their ordered
terminals and values. Both `.model` declarations are exactly `nch nmos`.
The eight top-level formals correspond in the same order. The correspondence
is a literal recorded mapping, not a graph matcher allowed to swap pin roles.

| AG80 net | AG82 net |
|---|---|
| VDD, VSS | VDD, VSS |
| Vin+, Vin- | Vcont+, Vcont- |
| Vcont1, Vcont2 | Vin+, Vin- |
| Vout+, Vout- | Vout1, Vout2 |
| net0, net1, net2 | net1, net2, net0 |

Actual transformed SVG leads independently support all D/G/S endpoints of
the six MOSs in each source. Their quad drain order and source-pair intervals
are checked against manually read literals:

| Source | Quad order from left to right | M1/M2 source interval | M3/M4 source interval |
|---|---|---|---|
| AG80 | M1, M2, M3, M4 | 100–160 | 250–310 |
| AG82 | M1, M3, M4, M2 | 10–210 | 70–150 |

Thus AG80's two source pairs are disjoint along the row, while AG82's are
nested. Reflection of the complete drawing does not change that distinction.
The generated AG82's adjacent pairs are a failure to reconstruct this author's
arrangement, but the AG80 source prevents declaring that arrangement universally
inhuman. Port labels carry different possible functional intent; this result
is about topology and ordered contracts, not a claim that the two texts have
identical names or designer intent.

The adversarial reviewer identified a concrete limit: the current
`library.named(.net)` infers `Vin*` as input, whereas `Vcont*` stays internal.
The two decks therefore do not have identical inferred semantic roles under
the engine's default naming policy. A stronger role-preserving comparison
would need explicit caller roles transported along the recorded net map.
Generic semantic input evidence is legitimate context; a circuit-ID lookup
would not resolve this boundary correctly.

The executable controls reject a changed gate, changed bulk, D/S swap,
parameter change, swapped formal order and missing device. Card order may
change without changing the certificate. A source terminal cache shifted
away from its actual lead fails. This is structural correspondence, not an
executed simulator or Schemify round trip.

## Raw recognition census

[quad_candidates.py](quad_candidates.py) reads all 2,202 frozen DUT decks using
the model/callee-aware ordered-incidence parser. It enumerates two distinct
source nets and two distinct drain nets, with all four nets different. Before
any model, body, parameter or gate filtering, each of the four D/S slots must
have exactly one MOS. An ineligible extra MOS in a slot still makes that
candidate ambiguous.

The subsequent shape screen requires identical model/parameter tokens, one
shared body binding, and exactly two gate nets outside the four channel nets.
Those gate nets alternate across the four slots. This yields **26 raw shape
candidates from 5,811 raw channel rectangles**. Neither number is a count of
admitted layout changes. The screen does not resolve surrounding ownership,
formal port semantics, explicit caller geometry, body visibility, model
capability, or the best arrangement.

The exact names are AG80, 82, 496, 500, 504, 511, 512, 514, 515, 516, 517,
557, 570, 572, 574, 584, 647, 660, 786, 805, 813, 1044, 1091, 1092, 1093,
and 1098. [The census](quad_candidates.json) preserves every raw candidate,
rejection reason and original deck hash. Ten controls exercise actual altered
inputs, including a competing MOS with the wrong model, consistent renaming,
card reordering, and changed ordered terminals. A model/parameter equality
check is not semantic proof that a symbol family is supported.

## Cases that constrain the future rule

| Observed source form | Named examples | Consequence |
|---|---|---|
| Adjacent upright source pairs with orthogonal wires | 80, 647, 1044, 1092 | Nesting and diagonals cannot be compulsory. AG1044 also contains an inverter that participates in control distribution. |
| Nested upright source pairs, often a drain crossover | 82, 500, 504, 515, 516, 517, 557, 570, 572, 584, 1091, 1098 | A two-device source relation can be a subrelation of a four-device layout; it is not necessarily an independent rectangular owner. AG82 remains orthogonal. |
| Horizontal channel symbols in a vertical bank | 496, 511, 512, 514, 574, 786, 813 | A channel-directed vertical stack heuristic does not identify the human reading direction. Nearby ports and neighboring stages constrain the frame. |
| Two-dimensional quad, outputs above and below | 1093 | A whole candidate need not fit one device row or one globally downward flow. |
| Quad inside a wider stage or timing network | 660, 805 | Raw recognition does not establish a standalone group or identify a mixer. Additional devices and control interfaces need ownership proof. |

AG517 is the clearest group-ownership example. The human places the PMOS
input pair to the left of the entire NMOS switching bank. The generated
drawing puts that input pair between the two NMOS source pairs. The [group
study](groups.md) supplies actual lead bounds and ordered bindings: the two
NMOS source-pair bounds overlap because one pair nests around the other.
Treating both as disjoint independently packed rectangles cannot reproduce
that relation. Joining every pair through every common load would overmerge
other cases; the four-device relation needs its own bounded evidence.

AG514's local gate-drain capacitors, AG570/572's coupled lower-gate paths,
AG660's wider upper bank and AG805's timing devices remain unresolved owner
boundaries. AG786's source labels Qp/Qn are also a warning against inferring
device polarity from text: the converted raw deck uses four `nch` MOSs. The
study records that difference instead of silently replacing the netlist's
model.

## Algorithm and implementation plan

1. Collect immutable raw four-device relations from complete ordered
   incidence, retaining all competing slots and external terminal occurrences.
   Do not yet change the existing pair table, symmetry axis or device cells.
2. Resolve overlapping candidates with the existing specific owners and
   caller directives. A candidate may contain pair subrelations; those pairs
   must not simultaneously become competing independent placement owners.
   A shared-load connection alone cannot establish this containment.
3. Construct a small set of supported arrangements only after two real
   source cases justify each. The current evidence includes adjacent pairs,
   nested pairs, a vertical bank, and a two-dimensional arrangement. Each
   option has a literal member-to-frame relation and preserved ordered pins.
   A source-specific permutation is evidence for that fixture, not a runtime
   lookup table keyed by circuit name.
4. Apply admitted caller group/order/pose/axis constraints first. Evaluate
   actual terminal frames and neighboring stage interfaces for remaining
   options. Record when multiple human-valid choices remain. Name-based tie
   breaking may select a deterministic default; it does not recover missing
   designer intent.
5. Keep wire capability independent. An orthogonal option must remain valid
   until diagonal geometry, contacts, thinning, ABI and host export are
   supported. A diagonal may connect a certified local crossover without
   making every quad use an X or every route use diagonal search.
6. Reserve and place the complete selected owner atomically. Validate actual
   occupied frames, external interfaces, source-pair subrelations, honored
   constraints and final compaction. A failed option leaves the prior valid
   drawing and all ownership tables unchanged.

The six data questions follow from that plan. Inputs are ordered MOS rows,
complete net incidence, existing owner relations, admitted caller constraints
and immutable class frames; outputs are bounded candidate member/role rows
and later an admitted arrangement. E devices and P pin occurrences bound the
input; four distinct devices bound each candidate's local record. The Python
all-pairs scan is a research enumerator, not a production complexity proposal:
the number of raw rectangles can grow combinatorially. Production collection
needs a stated capacity, overflow result and a bounded per-net join strategy
before choosing index widths. Use existing typed device/net handles. Store
candidate IDs and roles in cold borrowed/scratch tables until ownership is
resolved; do not add per-device flags to the hot layout path merely for this
experiment. Collection can be partitioned only if its final order and conflict
resolution are deterministic. One owner commits membership; other stages
consume it. No speed or zero-residue claim is made here.

The first implementation oracle should be the AG80/82 distinction plus
AG517's external input-pair separation, with forced caller variants and
near-miss ownership cases. A geometry-only test must retain exact ordered
D/G/S/B identities and actual lead contacts. Circuit correspondence cannot
prove correct visible grouping, while matching the source's pixel order
cannot prove electrical correctness. Neither oracle substitutes for the
other.

## Replay

```sh
D=docs/research/image-rules/round-2
R=.objective/human-schematic-equivalence/runs/iteration21-resume1/image-rule-round-2
python3 -B "$D/quad_candidates.py" --check "$D/quad_candidates.json" --output "$R/quad-census-replay.json"
python3 -B "$D/quad_equivalence.py" --check "$D/quad_equivalence.json" --output "$R/quad-equivalence-replay.json"
```

The exact 26-name expectation is a frozen, manually reviewed census set.
It is not proof that every human switching topology was recognized, and the
declined 5,785 raw rectangles must not be described as visually negative
examples without further inspection.
