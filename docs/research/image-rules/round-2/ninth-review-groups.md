# Ninth independent review: complete raw interfaces before local decomposition

The reviewed collector is a useful bounded experiment for the global-core
problem. It preserves AG928 as one channel core and offers five raw parent
groups for AG1080. It does not establish a source-like arrangement, five
disjoint boxes, caller permission to move them, or a physical wire partition.
Three input-boundary failures were found and repaired without changing the
exact 2,202 corpus disposition lists.

## Preserved failures and independent replay

| Actual AG1080 input change | Original result | Repaired result |
|---|---|---|
| Append `+ unused_formal` to the `.subckt` declaration | Admitted five groups while silently omitting the declared formal | Declines `unused_formal_ownership_unresolved` |
| Move existing OUTP/OUTN onto the next continuation line | Still admitted, but the reported formal contract lost both ports | Admits with the complete original eight-formal contract |
| Add conflicting `.model nch pmos` before the original `.model nch nmos` | Last dictionary write erased the ambiguity and admitted the candidate | Declines `duplicate_model_definition` |
| Remove VDD/VSS from the DUT formals while retaining those local net names | Inferred “admitted” rails from names and admitted the candidate | Declines `unowned_conventional_rail` at this observational input boundary |

The card reader already joined continuation lines; the independent formal
reader did not. The repair now uses the same physical-line continuation
grammar. All actual candidate-stage corpus cases have their nonzero
conventional rails among their formals, so the stricter observational rail
boundary changes no named corpus result. A separately supplied, admitted rail
map remains valid input to the decomposition function, including transported
opaque names. Formal ownership is a necessary condition here; this still is
a declared conventional-rail profile, not a general proof that an arbitrary
formal called VDD is physically a supply.

The [review script](ninth-review-groups.py) writes and exercises the exact
mutated decks with both readers. Its predecessor is explicitly identified as
the peer's reconstructed pre-fix bytes, obtained by reversing only the
published parser repair; it was not archived before the edit. The failed
calls were actually executed before the repair, and the reconstruction
reproduces those results. [Evidence](ninth-review-groups.json) records each
deck and script hash, both dispositions and the complete reported formals.

## Independent checks and their denominator

The review rereads all 2,202 original decks using the separate body-study
parser and compares exact ordered card tokens and outer DUT formal lists.
Every card, including declined non-MOS attachments, remains in that
comparison. All 138 returned involutions independently satisfy bijection,
involution, complete D/G/S/B correspondence, full model/parameter token
identity, formal/internal membership and individually fixed admitted rails.
Repeated node occurrences remain ordered occurrences, not a set of pins.

For all 43 named circuits with at most eight MOS cards and returned maps,
the review enumerates **every device permutation** and directly applies the
role equations. This independently matches the complete returned map sets,
including identity and ambiguous alternatives. It imports neither the
peer's color refinement nor its backtracking enumerator. The larger cases
retain the peer's bounded exhaustive-search certificate plus independent
validity of every returned map; this review does not claim a second complete
enumeration of AG1080's 32-device graph.

Channel components are independently rebuilt by disjoint-set closure of
off-rail D/S incidences. Every gate's producer, consumer and boundary kind is
rederived from the complete raw row. Proposed ownership, intergroup
dependency edges and returned topological orders are then checked separately.
This extends beyond the peer's renaming normalization, which compares
partitions and maps without independently checking the interface/DAG records.

Four corruptions go through this same checker and fail: dropping an actual
formal, changing an actual raw B node, deleting a gate's producer, and removing
the identity map from a small complete map set. Exact candidate and decline
name lists are retained in the evidence. Names identify tests and output
records; they are not inputs to the decomposition predicate.

## Fresh actual-image check and planning boundary

I independently rasterized and actually viewed both source/native SVG pairs
for AG1080 and AG928 in this review. The [view ledger](ninth-review-groups-views.json)
binds each actual SVG and PNG and records the observations. This is a fresh
four-panel view, not a claim to independently view all eleven new candidates.

AG1080 has four small upper clocked regions and a lower latch parent. The
raw 14-member lower group includes the separately drawn `{M29,M30}` and
`{M31,M32}` side branches, joined electrically through OUTP/OUTN names. It
can be a useful parent with typed attachments/subregions; it is not one
continuous source conductor or one tightly packed source box. The native
comparison is a broad common rail with members distributed across flattened
rows. It already uses named cuts, so the new group collector alone cannot
be credited with solving those physical-piece choices.

AG928 stays one vertically stacked nine-device core in both drawings. That
positive keep result is independent of the facing policy of individual MOS
glyphs. Splitting every matched pair into its own box would lose this
control. Conversely, a unique graph involution only licenses consideration
of a relation; it does not prove a human axis, inward-facing gates, a sibling
layout or a common rail span.

The next admission boundary therefore needs the [C/G/F frame split](ninth-frame-plan.md),
full caller constraints, actual group interface/piece requirements and
bounded complete arrangement alternatives. Nested or interleaving source
examples must remain counterexamples to unconditional disjoint-box placement.
The all-MOS profile deliberately declines passive attachments, nonrail bodies,
floating internal gates, ambiguous reflections and unsupported control
cycles. Do not broaden it by dropping those incidences or by reading source
coordinates into the selector.

I subsequently read the completed `ninth-local-groups.md` and its source/native
proofs. The plan retains the two observed overlap counterexamples, AG1016 and
AG364, and explicitly distinguishes the nine separated own-channel-stub box
examples from future placement admission. It also keeps AG924's useful cyclic
source organization as a known false negative, rather than weakening the
acyclic admission gate. The source certificate does not call channel-stub
bounds full glyph, label or conductor bounds. Those scopes are appropriate.

The native artifact helper initially consumed cached census rows while merely
hashing the actual deck. It now requires that hash to equal the census case's
declared deck hash before using those rows; the composed source proof also
rereads the raw cards. This prevents repeating the earlier stale-witness
failure within this boundary. No native output needed regeneration.

One follow-up remains separate: the research enumerator safely declines when
its search reports exhaustion, but a production plan must preserve that
completeness status at its caller seam. Current symmetry's bounded choice of
one valid map is not a proof that the map or resulting ownership is unique.
The assigned tenth search-contract study addresses that distinction without
changing this ninth collector.

## Replay

```sh
python3 -B docs/research/image-rules/round-2/ninth-review-groups.py \
  --output .objective/human-schematic-equivalence/runs/iteration21-resume1/image-rule-round-2/bodies/ninth-review-groups/replay.json \
  --check docs/research/image-rules/round-2/ninth-review-groups.json
```

This review runs Python checks only. It changes no engine, source deck,
parent plan or peer file and makes no target-host execution claim.
