# Source regions are facts, not placement groups

The proposed replacement “D/S connected components, then merge reflected
mates” fails on source degeneration and shared loads. Adding every resistor
to that connectivity does not repair it. A narrower source-region collector
retains useful facts, but AG517 shows that those facts can overlap in the
source drawing and cannot independently authorize rectangular placement.
All proposals below remain unimplemented.

## Scope and provenance

This round reread all 81 frozen/current-human-rule sections and the separate
84-header worktree delta, then actually viewed all 92 verified isolated
contact sheets of shard 0: exactly 734 source/native pairs, AG4–884 with the
assignment's gaps. The fresh append-only `groups/reviews.json` is complete;
`groups/fresh-sheet-notes.json` preserves the sheet observations. This is an
overview, not a claim of 734 topology or lead certificates.

The bounded certificate covers ten named circuits, 17 literal source
regions, every card, 278 ordered terminal bindings including hidden MOS
bulk, and 219 same-net visible-pin pairs. All twenty enlarged source/native
PNGs in [figures/groups](figures/groups) were actually viewed and recorded
with hashes. Source leads are extracted from actual SVG primitives; cached
coordinates must agree with those primitives. Wire continuity requires
actual conductor ink and actual contact dots at proper crossings. Labels
alone do not connect source pieces. Inductors use their own path ends.

The ten original decks were rerun through frozen executable SHA256
`bf7b0749bde5822a68aa93fd9df69eb6e007dee0c24d5e9961ff65b187483560`.
Every emitted SVG is byte-identical to its gallery native. The run directory
is `.objective/human-schematic-equivalence/runs/iteration21-resume1/image-rule-round-2/groups`:
`commands.json` records argv, status and byte checks; `evidence.json` records
source/deck/JSON/native/report hashes, full ordered cards, model declarations,
native values, actual leads, literal ownership, topology and physical pairs.
The frozen source is `resistor-output-integrated-common`; this is not a
measurement of the dirty production worktree.

## A correction to the overview

Enlargements correct the coarse impression that native AG459/701 interleave
the two local pairs. Both native drawings preserve each pair's adjacency;
AG717/718 also preserve local pair membership. The corrected observations
are appended to their review rows. These are counterexamples to the proposed
D/S selector, **not evidence of an existing native membership bug**. Keep
them as regressions for any future replacement. Native pose, ordering,
spacing and physical wire continuity are separate questions.

## Exact counterexamples and keeps

| Case | Literal source regions | Bare D/S components | Meaning |
|---|---|---|---|
| AG220 | M1/M2, two private Rs arms, centered tail M3 | M1; M2; M3 | D/S misses both degeneration and tail ownership. |
| AG396 | M1/M2, one Rs, separate ISS1/ISS2 | M1; M2 | Both source/native preserve the flat Rs and local pair. |
| AG459 | M1/M2 with R1; M3/M4 with R2 | M1/M3; M2/M4 | Shared drains cross the desired source pairs. |
| AG517 | M1/M2 with Rs; M3/M5; M4/M6 | All six | Source mixer pairs have nested horizontal extents. |
| AG558 | M1/M2/M3; M4/M5/M6 | All six | Shared output must not merge the two triples or choose two of three. |
| AG701 | M1/M2; M3/M4 | All four | Distinct direct-source pairs share output wiring. Native keeps pairs. |
| AG717 | M1/M2; M3/M4; shared M5/M6 loads | All six | Shared loads are interfaces, not automatic membership. |
| AG718 | M1/M2 with R1; M3/M4 with R2 | M1/M4/M6; M2/M3/M5 | Crossed loads contaminate both seed components. |
| AG675 | M1/M2 source seed, M3/M4 mirror load | All four | A useful four-device whole must not be split merely because the collector returns one seed. |
| AG884 | M1/M2 seed, mirror load and separate M5 stage | M1–M4; M5 | Flat compensation CC is a stage interface, not group union. |

AG220 is stronger than a missing edge: the unique transistor with S on the
rail, M3, cannot exchange with either input transistor in a rail-preserving
reflection. Merging mate identities therefore cannot attach that tail to
the two input devices. Conversely, a union operation can never split the
already-wrong AG459 D/S components. Including off-rail resistors repairs
AG220 but merges all four devices of AG459 and all six of AG718. These are
different failure directions of the same proposed partition.

AG517 is a new interaction warning. In the actual source, input M1/M2 lies
left of the whole mixer. M3/M5 is the inner source pair and M4/M6 the outer
pair: their lead boxes overlap. Native places M3/M5, then M1/M2, then M6/M4.
The certificate checks these literal left/right/overlap relations. A future
local-axis implementation needs a larger mixer owner or must decline this
context. “Every source region gets a disjoint rectangle” is falsified.

The exact full-card ownership manifests are in [groups_expected.json](groups_expected.json).
They distinguish seed-owned attachments from explicitly listed boundary
cards and partition every fixture's cards once. They are a manual evidence
oracle, **not a claim that these seed owners are complete placement groups**.
AG517 especially requires a hierarchy above them.

Adversarial review found that a partition-only check accepted reversed owner
rows and swapped current-source/resistor attachments. The certificate now
checks that each core belongs to its own row and that each row contains
exactly its private resistors, rail-current attachments and non-core tail
anchors, justified by ordered region incidences. A drain from another core
is recorded as an interface, as in AG517. Reversed AG459 rows, swapped I1/I3
and swapped R1/R2 are independently rejected; the existing literal owners
remain unchanged.

## Raw census before admission

[groups_candidates.py](groups_candidates.py) reads all 2,202 named final
subcircuits, asserts equality with the actual deck filename set, and emits
all raw candidates before eligibility checks. Input facts are ordered
terminals and an explicit rail set. A raw region is an off-rail resistor-net
component containing at least two MOS source terminals; direct shared-source
nets are zero-resistor components. Every known terminal incidence, unknown
card, resistor, tail-drain anchor and current-source far end is recorded.
No capacitor, shared drain, gate or mate unions regions.

The review also exposed a fourth-terminal BJT gap. Q cards now retain
C/B/E and optional substrate under the explicit `nodes, model, key=value`
grammar; ambiguous bare area/OFF syntax is unsupported and declines. A
literal Q substrate on a source region is counted as terminal index three
and makes that region nonprivate. The independent review enumerated all 823
four-node Q cards; none touches an existing source region through substrate.
All 2,202 exact raw-region, incidence, disposition, D/S and shared-drain
records are unchanged by the fix. Pre-review evidence is preserved beside
the new replay, and the peer's `bodies_review_groups.py --require-fixed`
passes all four attacks.

The census contains 1,983 raw regions in 1,079 circuits; 301 circuits have
shared off-rail drains between regions. The resistor counts are 1,923 zero,
41 one, 14 two, three three, and two four. Thus 60 resistor-bearing raw
regions were considered, including all declines. [groups_census.json](groups_census.json)
preserves the complete named records and hashes the larger ordered-card run
artifact. Counts are summaries of those exact name/member sets.

The deliberately narrow shape screen retains 787 candidates **pending
ownership**: 780 direct-source, six one-resistor and one two-resistor. The
complete resistor-bearing retained set is:

| Circuit | Members | Resistors | Tail/interface |
|---|---|---|---|
| AG220 | M1, M2 | RS, RS2 | M3 drain at private center |
| AG396 | M1, M2 | RS | ISS1, ISS2 to rails |
| AG459 | M1, M2 | R1 | I1, I2 to rails |
| AG459 | M3, M4 | R2 | I3, I4 to rails |
| AG517 | M1, M2 | RS | I1, I2 to rails |
| AG718 | M1, M2 | R1 | I1, I2 to rails |
| AG718 | M3, M4 | R2 | I3, I4 to rails |

All seven have the detailed source/native certificate. A shape screen is
not placement admission: even AG517's passing input pair requires a global
owner check. The screen requires exactly two sources, identical complete
model/parameter tokens, distinct gates/drains, either no R, one R between
two source nets, or two equal private arms with one nonsource center; at
most one compatible drain anchor; and no unexplained incidence. Source-body
ties, unknown card grammars and extra branch/path incidence decline. This
conservative model-name requirement is a research bound, not a proven
necessity or an inference of electrical equivalence from model names.

Current sources are explicit interfaces. A current source wholly inside a
region, between two regions, or ending at an unrelated nonrail signal makes
the shape screen decline. It remains in the raw census with both ordered
incidences. A rail-ended current source is only a permitted interface;
voltage/value equality, direction, caller visibility and final attachment
ownership still require admission. There is no blanket current-source
exemption. A one-R source bridge can pass the shape screen; two competing
parallel Rs, unequal arms, asymmetric tail attachment and mixed-model tails
cannot.

Card-order invariance passes all 2,202 decks. Full device/net rename
covariance, including rail-role transport, passes all 1,378 decks in the
supported grammar; the other 824 explicitly record the unsupported grammar
and only claim card-order invariance. The comparison covers full member,
resistor, incidence, tail, interface, decline and competing-component data.
Literal controls include broken arms, extra paths, model/parameter changes,
gate-source intrusion, source-body ties and all three current-source cases.

The ink certificate independently rejects wrong ordered gate binding,
detached actual source lead, wrong hidden bulk and changed native model
parameters in every case. Its literal conductor controls distinguish T,
overlap, a gap, proper X with/without a dot, and cache-only geometry.

## Collection-first implementation plan

1. **Borrow facts; retain no geometry.** Inputs are the netlist's ordered
   terminal table, semantic roles/polarities, full model and parameter
   references, admitted caller requests, recognized row/stack blocks,
   visibility, existing mate identities and typed passive owners. Return
   cold source-region candidates with CSR offsets for members, interfaces,
   attachments and rejection witnesses. Use typed u32 handles and named
   capacities bounded by source/resistor counts; allocate before mutation.
   One collector owns this table. It must not change mates or coordinates.

2. **Collect all raw embeddings.** Count source regions, complete terminal
   incidence, all drain competitors and every current-source far end before
   value, visibility, hint or frame filtering. Compare candidate identities
   as exact device/net sets. A hidden or ineligible competitor still creates
   ambiguity. Keep a reason for each decline; never pick the first embedding
   or arbitrarily choose two members from a triple such as AG558.

3. **Resolve owners and precedence explicitly.** Admitted caller geometry,
   symmetry and groups retain today's semantics. `nogroup`, `grouping off`,
   `symmetry off`, explicit faces, positions, rows and orders each constrain
   the entire touched automatic owner. Existing cross before differential
   before mirror/bank precedence remains intact. Shared loads, tails,
   private Rs, compensation C and current-source interfaces require named
   ownership rules; passive connectivity alone grants none. Any competing
   owner, unexplained incidence or different possible embedding declines
   automatic local placement. Preserve the old pipeline unchanged on decline.

4. **Build dependencies before boxes.** A source seed may be a child of a
   larger recognized stage. Record overlap, shared loads, serial current
   paths, input-to-output direction and typed compensation edges separately.
   AG675 keeps a mirror-loaded stage whole; AG517 needs the whole mixer
   above nested seeds. AG884's CC links stages without merging them. If this
   ownership DAG cannot be resolved uniquely with a bounded recognized
   template, do not emit local boxes. No generic “merge everything connected”
   fallback is licensed by these observations.

5. **Separate identity, pose and wiring.** Mate identity alone grants no
   local axis, same-row requirement, glyph reflection or wire sharing.
   Enumerate bounded local poses for an admitted owner, then validate all
   ordered actual pin frames and each inter-owner interface. Same-facing
   reciprocal AG404 and diagonal reciprocal AG537/821 remain separate keep
   alternatives from round one; this round does not certify a universal
   diagonal or inward-gate rule. Compensation ownership similarly does not
   authorize turning CC or merging its endpoint wire parts.

6. **Preserve caller symmetry with a direct oracle.** Today `Skeleton.axis2`
   is one optional integer and inferred mates need a common x-sum; a local
   owner cannot silently replace this global contract. Initially decline a
   local candidate touching admitted `symmetric`, `axis` or incompatible
   `group` requests. For a future compatible path, assert the admitted
   structure member lists and order before placement; at the skeleton stage
   assert each requested symmetric pair has the same y, required reflected
   form/pose and shared x-sum, and each requested axis member lies at that
   axis. At final `Placed`, assert corresponding ordered actual leads and
   body frames reflect about the *same* admitted axis, including custom
   glyphs and self-mates. Check stack order and complete row-block membership
   directly. `checks.drawnAs` returns null for these requests, so a report
   saying “honoured” is not this geometric proof. A conflicting candidate
   must leave the shipped caller behavior unchanged and record abstention.

7. **Commit one complete geometry transaction.** All bodies, interfaces,
   spacing, caller constraints and downstream bridge slots must pass before
   any owner moves. If any check fails, restore/retain the old placement.
   A later routing failure cannot authorize silently deleting a mate or
   partially moving a group. Wire transactions retain electrical round-trip
   and per-physical-part crossing checks; source labels never serve as proof
   that two leads share a continuous conductor.

## Acceptance oracles and remaining work

The first implementation milestone should only collect facts, with exact
named candidate/decline comparisons against this census and literal controls.
It should produce identical existing geometry and mate tables. A subsequent
owner selector needs new literal competing-owner, duplicate-embedding,
hidden-tail, unequal source-direction/value and explicit caller fixtures
before any coordinate change is justified. The seven resistor-bearing
shapes are an exhaustively named starting cohort, not seven approved moves.

Placement acceptance must retain AG459/701/717/718 local adjacency, AG396's
flat bridge, AG675's complete stage, and AG884's compensation ownership;
AG517 must either acquire a separately proved larger owner or decline. Run
native geometry checks and source-ink checks independently. Source/native
physical-piece differences are recorded separately for AG675/701/717/718/884;
they cannot be scored as grouping errors merely because both concern the
same devices. No total crossing-count claim follows from this study.

The rules implicated are `structure.3–6, .8–12` (caller and row-block
ownership), `mates.1–5, .7`, `symmetry.1, .3, .5–7`, `columns.2–6, .10,
.12–13`, `skeleton.3, .5, .7–11, .14`, and `forms.10–11, .15` plus the
specific bridge rules a future pose actually touches. `checks.1–8` remain
independent acceptance constraints. The current/frozen `wires.24` difference
is not a license to attribute a current-worktree rule to these frozen images.

Reproduce the two independent certificates without building or modifying
production code (set `R` to the run directory above):

```sh
python3 -B docs/research/image-rules/round-2/groups_candidates.py \
  external/examples/analoggenie "$R/census-replay.json" --check "$R/census.json"
python3 -B docs/research/image-rules/round-2/groups_evidence.py \
  external/examples/analoggenie "$R/native" "$R/evidence-replay.json" \
  --check "$R/evidence.json"
```

Both replays pass. No engine implementation, rebuild or commit was made.

## Subsequent adversarial quad review

The root's quad study was independently checked by
[groups_review_quads.py](groups_review_quads.py). Its exact 2,202 deck name/hash
set, 5,811 raw rectangles and 26 retained raw shapes replay correctly.
Source/native pairs AG80/82/647/805/1093 were actually viewed, with additional
independent enlargements of AG805/1093. Fourteen view records and hashes are
in [groups_review_quads.json](groups_review_quads.json).

AG80/82's complete ordered-card, model, parameter and formal-order transport
passes, while source80 uses adjacent source pairs and source82 nested pairs.
That establishes a topology-only ambiguity. It does **not** establish equal
default role-coloured engine input: the transport exchanges `Vin*` with
`Vcont*`, which current name inference classifies as input and internal,
respectively. A stronger semantic-role claim must explicitly transport
caller roles; neither source arrangement follows uniquely from raw topology.

The review added a literal two-source/three-drain network with three raw
rectangles and two overlapping crossed-gate quads, sharing M2/M5. A later
visibility/model/hint filter must not erase one competitor and manufacture
uniqueness. A capacitor from a source node to an outside net leaves the raw
quad shape unchanged; it is a new interface requiring complete ownership
analysis. These controls confirm the collector's narrow meaning rather than
requesting that it become a placement selector.

AG647 is an orthogonal adjacent-pair keep. AG805 puts its timing quad on
multiple horizontal-channel paths, and AG1093 puts the quad in a two-by-two
stage with outputs above and below. Thus a matched crossed-gate quad cannot
select a diagonal, a mixer role, a nested pose or one horizontal row by
itself. The existing local-region plan should consume it as another raw
fact and require a unique whole-context owner or abstain.
