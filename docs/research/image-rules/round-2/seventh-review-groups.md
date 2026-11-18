# Seventh study: independent final-relation and verifier review

The sixth groups study's three main classifications survive independent
review. The native axis failure is real, the stack case exposes conflicting
written and implemented contracts, and the remote fixed pose correctly takes
priority while the weaker relation's report lacks a final downgrade. Two
research-verifier cache gaps were found and repaired. No production behavior
was changed.

The [independent verifier](seventh-review-groups-proof.py) reads all **23
actual decks, reports and native JSON files**, checking **142 complete raw
M/R/I devices**, including every MOS body binding. Eight independently
executed frozen-CLI cases reproduce the prior JSON, SVG and report bytes.
The [result](seventh-review-groups-proof.json) records six freshly viewed
distinct PNGs and two byte-identical view aliases. These synthetic fixtures
are separate from the real-source audit ledger. The frozen binary remains
`bf7b0749bde5822a68aa93fd9df69eb6e007dee0c24d5e9961ff65b187483560`.

## Final coordinates and actual terminals

The independent oracle applies the literal affine reflection
`(x,y) -> (axis2-x,y)` to the actual origin and every corresponding pin. It
does not import the author's `mirror`, `pair_frame` or `quad_pairs` helpers.
A translated literal positive and an isolated gate-coordinate mutation
check this oracle separately from native output.

| Cases independently replayed | Actual result | Interpretation |
|---|---|---|
| `quad-axis-alone`, `quad-relations` | M1/M2, M3/M4 and R1/R2 origins and every corresponding pin mirror around x=240. I2's origin and both terminals are at x=340. Its actual report says honoured/ok. | Final axis violation. No exact-placement request explains it. |
| `pair-stack`, `pair-stack-compatible` | Both outputs have identical named device records. M1 is (80,90), M5 (80,170); both opposite stack requests say honoured. | They cannot both satisfy written top-to-bottom order. The code intentionally permits either order, so resolve the public contract before changing placement. |
| `pair-fixed` | M1 is (-800,-800), rotation 0, no mirror. Its actual M1/M2 terminal frames do not mirror. Both exact placement and symmetry report honoured. | Preserve the stronger caller pose; the relation report is missing a final disposition. |
| `pair-fixed-weak-compatible` | M1 is (-800,-800), rotation 3, no mirror. Both complete input/load mirror frames and the translated M5 axis hold. | Positive control: a compatible weak request can be honored without abandoning symmetry. |
| `quad-mate-conflict`, reversed | Later M1/M3 or M1/M2 wins respectively; the loser is dropped/conflict. Every actual pin of the selected pair mirrors. | Existing equal-strength request ordering is observable and must remain part of admission. |

The selected mate in `quad-mate-conflict` is a caller relation, not evidence
that two electrical source groups have merged. Likewise the displaced I2 in
the reversed conflict fixture is not itself a failed request: that deck does
not ask for `axis I2`. The same picture can have a different caller contract.

The actual images agree with these measurements. The remote fixed fixture
was viewed as an overview; its exact pose comes from native JSON rather than
claiming its small glyph labels were visually resolved. `quad-relations` is
byte-identical to the actually viewed `quad-axis-alone` image, and the two
stack images are byte-identical. Those aliases are recorded explicitly.

## Two reusable-verifier gaps, with retained RED witnesses

The earlier verifier checked file hashes, but consumed cached manifest rows
for reports and raw cards. Hash validity alone did not connect a changed
artifact to the derived row used by the proof. Both attacks update the
mutated artifact's path and hash while retaining stale derived data:

1. Change the actual `quad-axis-alone` report to axis I2 **dropped/conflict**,
   leaving cached requests honoured/ok. The old complete verifier passed and
   still reported the original final-axis discrepancy.
2. Change actual raw M4 body from **VSS to VDD**, leaving cached raw cards and
   native binding VSS. The old complete verifier passed its body-binding and
   automorphism checks against the stale cards.

The [before evidence](seventh-review-groups-before.json) preserves the exact
old script hash and an immutable script snapshot under the research run.
The independent replay runs both attacks through that old snapshot and the
repaired current verifier: **old accepts both, repaired rejects both**.
The repair re-reads actual report requests and actual unique ordered cards,
models and DUT formals before comparing the manifest or proving geometry.
Original saved native outputs were consistent; these were verifier boundary
defects, not new defects in those outputs. The exact five original RED names
remain unchanged after repair.

## Planning implications and smallest ownership boundary

Current and frozen `structure.3` promise an axis device on the mirror axis;
`structure.5` promises written stack order. `skeleton.choose` explicitly
accepts either stack order. `skeleton.lay` can clear a self-mate after its
column moves off-axis. `checks.drawnAs` gives no final answer for these
relations, and `report.evaluate` only downgrades a false answer.
`report.placedBy` recognizes exact placement superseding row/above/order/face,
with no symmetry/axis/group counterpart. These are code-reading facts; this
review did not trace which internal stage moved I2.

The smallest plan separates three responsibilities:

1. Admission retains the caller's selected relation, its typed members,
   request identity and authority. It must not lose that witness when a
   mutable mate table changes during placement.
2. A final validator checks bounded supported geometric relations against
   final actual origins and pins after every coordinate-changing owner has
   run. A pair uses the selected common axis; an axis device uses its origin.
   An asymmetric axis device's gate need not lie on the axis. Two separately
   mirrored pairs do not by themselves establish one shared caller axis.
3. Report finalization owns the disposition: retained relation, explicitly
   superseded by a stronger admitted request, or unmet/unsupported proof.
   The exact caller pose remains authoritative. A topology admission verdict
   cannot serve as a final geometry certificate.

Stack order needs a separate explicit policy decision: enforce written
order, decline an incompatible ordering, or change the public meaning and
its tests. No generic final-proximity test proves arbitrary group membership.
Keep membership/stage evidence distinct from final geometry and electrical
connectivity.

The change radius is the existing structure request witness, final geometry
check and report disposition path; placement fixes are separately justified
by stage evidence. A new report code need not change geometry, a compatible
caller pose need not change topology admission, and a raw net rename need
not change the affine geometry oracle. Unsupported relation checks must have
named limits rather than silently passing through a null check result.

```sh
python3 -B docs/research/image-rules/round-2/seventh-review-groups-proof.py \
  --execute --check docs/research/image-rules/round-2/seventh-review-groups-proof.json \
  --output /tmp/cktimg-seventh-review-groups.json
```
