# Tenth round: bounded arrangement proposals without an inferred preference

The parent decomposition supports a finite placement experiment, but its boundary
graph does not choose the source arrangement. AG1028 and AG364 have exactly
transportable cross-parent boundary stars: on each of two exchanged nets, a
producer NMOS drain and PMOS drain meet a consumer PMOS gate, with identical full
model/parameter suffixes. AG1028's source separates the stages horizontally;
AG364's source nests its output branches around the inner stage. This falsifies
**boundary-star-only arrangement dispatch**. The complete DUTs differ; it does
not rule out a better full-context selector or an explicitly scored search.

The smallest useful G1 trial should compare an unchanged ordinary incumbent
against bounded H/V compositions of complete local-parent proposals. Keep the
incumbent as a real candidate, including its nested/interleaved geometry. Hard
electrical, caller, contact and retained-relation checks precede a documented
soft comparison. Selection need not prove a unique human arrangement or a global
optimum. These are proposed implementation steps; no engine code changed.

## Recomputed cohort and actual source evidence

`tenth-arrangement-graphs.py/json` rereads all 2,202 raw decks and re-executes the
ninth collector. Every disposition and complete returned record agrees. The exact
11 candidates remain AG1016, AG1028, AG1046, AG1047, AG1051, AG1071, AG1075,
AG1077, AG1079, AG1080 and AG364. No size, group-count or circuit-name filter was
introduced. The artifact retains every ordered terminal incidence, all gate
interfaces, rail/formal/model facts, complete boundary stars and component orbits
for those eleven cases.

All eleven original source/native pairs were freshly viewed again. Each view is
hashed and has a new arrangement-specific observation. The previous actual SVG
channel-stub certificates remain bound to the exact original SVG bytes. Their
extractor establishes the frozen originals' transformed endpoint coordinates;
it is not a general visibility/CSS/rendering certificate for arbitrary changed
SVGs. Actual views support the visible-layout observations below. The bounds are
channel-stub bounds, never full occupied glyph, label or conductor reservations.

| Source case | Producer relative to consumer for the two-parent interface |
|---|---|
| AG1028 and AG1071 | Left |
| AG1046 | Right |
| AG1047 | Below |
| AG1051, AG1075 and AG1077 | Above; AG1077's channel-stub bounds touch at their boundary |
| AG364 | Positive-area overlap: output branches surround the inner parent |

These eight cases all have the same one-edge parent quotient. Seven have two
cross-parent gate occurrences; AG1071 has four. The quotient alone omits the
complete internal graphs and therefore cannot distinguish the five arrangement
relations in the table. AG1079 and AG1080 additionally require mixed row/column
composition to resemble their sources. AG1016's five parent extents interleave,
with seven positive-area overlap pairs.

Every parent is either one self-mapped D/S component or a pair of exchanged D/S
components. All parents are self-mapped components in exactly AG1028, AG1046,
AG1047, AG1051 and AG1077. At least one paired-component parent occurs in exactly
AG1016, AG1071, AG1075, AG1079, AG1080 and AG364. The latter property occurs in
both separated and nested sources. It can supply an additional arrangement
alternative; it is not a compulsory nesting rule.

The AG1028→AG364 boundary certificate maps `net3→x`, `net1→y`, and
`M1→M3`, `M2→M4`, `M3→M5`, `M4→M6`, `M6→M9`, `M7→M10`. It covers **all**
incidences on those two nets, preserves their producer/consumer parents and
reflection, and checks full suffix equality. It does not omit an extra local
gate occurrence to make the stars match. Neither interface net is an outer
formal. No full-circuit equivalence claim follows from this certificate.

## Literal poses and a counterexample to the single-component shortcut

Eight named fixtures were executed with the unchanged frozen `bf7b0749…` CLI:
AG1028 and AG364 each have incumbent, right-translated and below-translated
variants; a tail-bridged AG364 has incumbent and right-translated variants.
All eight actual images were viewed. Complete checks bind 97 actual MOS records,
388 raw D/G/S/B occurrences, full model/parameter suffixes, selected classes,
origins, turns, mirrors and each actual D/G/S coordinate. All exact `at` requests
were honoured. Generated rail/port records are explicitly distinguished from raw
devices, and duplicate/unexpected device identities are rejected.

The symmetric mutation changes only M9.S and M10.S from VDD to `ptail` and adds
`M14 ptail vb3 VDD VDD pch l=0.15 w=1 nf=1 m=1`. The complete raw collector still
finds exactly one nontrivial involution, but now both parents are single D/S
components. Its boundary stars still match AG1028. Retaining the thirteen original
AG364 poses and placing the new tail above them produces an actual nested native
placement. Moving that entire output parent right produces another placement.
Changing only M9.S, plus the same tail, declines for lack of the required unique
involution.

This defeats the implication “one self-mapped D/S component per parent means
nesting is impossible or must be forbidden.” The mutation has no external human
source preference: it is an expressive, caller-controlled pose witness. It is
not proof that nesting is the best drawing for the invented circuit. The tail
images also have a `vb3` label touching its line. Thus the certificates establish
pose/contact/binding preservation, not complete label clearance, routed electrical
equivalence, or a host round trip. B remains a checked raw binding; no visible B
landing is invented for the three-contact default MOS class.

Direct per-parent reflection checks validate corresponding actual D/G/S positions
and mate origins. A self-mapped tail's origin lies on its parent axis; its
one-sided gate glyph is not required to reflect onto itself. Right translation
gives distinct local axes without changing the raw global device/net involution.
The fixtures contain exact caller poses, not caller `symmetric` or `axis` requests;
they do not weaken those requests' existing whole-circuit meaning.

The literal checker initially caught a mistaken hand-written expected M14 gate
coordinate; the expected MR270 transform was corrected using the frozen symbol's
local contacts. A separate report-field assumption was corrected before the final
pass. Independent review then found extra/duplicate device records could evade a
filtered dictionary comparison; the checker now validates the complete document
inventory. The original native outputs themselves did not change in these
checker repairs.

## Small finite G1 grammar and its exact scope

Start with an immutable admitted parent partition and independently qualified
local pose proposals. A leaf `P(i)` names a complete parent and its owned local
member coordinates, not a newly inferred electrical or physical object. Use:

```text
Candidate = KEEP_INCUMBENT | Compose(all admitted parent leaves)
Compose(S) = P(i)                                      if S={i}
           | H(Compose(A), Compose(S\A))               for every nonempty proper A
           | V(Compose(A), Compose(S\A))               for every nonempty proper A
```

`H(A,B)` proposes A left of B; `V(A,B)` proposes A above B. Both operand orders
are generated. No gate-dependency direction forces geometric order. Children
retain their internal member relations; composition translates complete proposals
and their interfaces. H/V can conservatively use bounding envelopes for initial
separation, followed by actual member/contact/reservation validation. Those
envelopes do not define membership or all physical net pieces.

`KEEP_INCUMBENT` is the complete ordinary plan, including reservations, retained
caller results and nested/interleaved member coordinates. It is **not** a binary
tree of disjoint parent rectangles. This minimal grammar can preserve AG1016/364
and compare them against separated alternatives; it does not yet invent new
nested arrangements. If the incumbent is unsuitable and a new nested construction
is needed, record the missing alternative explicitly. A future bracketing or
larger composed-placement owner needs its own whole-interface and geometry proof;
it must not silently merge the raw parent partition to reduce width.

The incumbent is always the rollback baseline. It does not automatically satisfy
G1's promised new organization postcondition. If it remains flattened or stretched
and therefore fails that postcondition, choosing it reports **no accepted
organization improvement**, not G1 success. Retaining a valid prior drawing and
passing a newly promised behavior are separate outcomes.

For k labelled parents the generated syntax has
`k! × Catalan(k−1) × 2^(k−1)` ordered H/V trees, plus the incumbent. The script
materializes and hashes every expression: five candidates for each two-parent
case, 49 for AG1079, and 26,881 each for AG1016 and AG1080, totaling 53,851 rows.
These are **syntactic alternatives**, not 53,851 different or feasible drawings.
Associative trees can evaluate to equal geometry. The independent count formula
and recursive coverage checks catch missing/repeated leaves. No new geometry was
generated from those 53,851 expressions; only the eight literals above executed.

Production need not allocate that list or evaluate all of it. Stream proposals
under an explicit candidate/work budget, charge frame evaluation and routing as
well as generation, and retain only the incumbent and current best complete
proposal. Report attempted/skipped families and budget exhaustion. Exhaustion
prevents a completeness/global-optimum claim; it does not prevent choosing a
proved-feasible candidate under an explicitly bounded heuristic. This is distinct
from O0's uniqueness search in the [search contract](tenth-search-contract.md).

## Where the future owner enters

O0's context and membership owner is described in the
[acceptance plan](tenth-acceptance-plan.md). G1 should consume it in skeleton
placement **before** the global `columns.order`/`sequence.columns` assignment and
`wrap.shelves`. Merely translating parents extracted from an already stretched
global core preserves that unwanted internal span. The diagnostic local-placement
owner must instead propose each parent's own closed chains, columns and rows,
while retaining every original interface and existing admitted pair/stack fact.
No copied subnet may drop controls, bodies or another parent's boundary contacts.

Keep the current global `Structure.device_mate/net_mate` identity relation. Store
local parent-axis/relative-pose proposals separately. `Skeleton.axis2` continues
to mean one common geometric axis; do not put an arbitrary local axis in that
field. If the chosen arrangement has different parent axes, a global-axis consumer
must use an explicitly compatible path or decline this experimental branch.
An admitted caller whole-circuit axis is never cleared to make the proposal fit.

For the first staged diagnostic, build the ordinary incumbent through the existing
pipeline, then independently prepare the experimental local proposal from the
earlier immutable facts. G owns proposed poses; it does not publish one child
before evaluating the others. The C/G/F/N/A boundaries and exact world-frame
checks are those in [the frame plan](ninth-frame-plan.md) and
[implementation packages](implementation-packages.md#c-f-and-a--evaluate-a-complete-candidate-before-committing-it).
They do not require implementing unrelated new block-symbol families for the
already supported MOS cohort.

The existing `wrap.shelves`, lattice-coordinate expansion, later specialized
placement, `power_compact.squeeze`, caller `keepAts` and final routing are all
potential later writers. A writer may translate a whole accepted owner, with all
contacts/reservations, or prepare and revalidate an internal move. If it lacks
that contract, decline the experimental proposal and restore the entire ordinary
incumbent. Do not apply the old global mirror/axis assumption to a locally
translated pair. Direct final origins and terminal coordinates remain the oracle;
an honoured report alone is insufficient. Initially, original relevant caller
symmetry/axis/group/pose/face overrides decline the new automatic arrangement,
while their existing priority remains intact.

## Hard gates, soft comparison and retained uncertainty

A concrete first comparator can rank complete candidates lexicographically by
proper crossings, introduced signal-piece naming, bends, wire length and occupied
area, retaining the incumbent on exact ties. This is a proposed diagnostic policy,
not an inferred human law. Count a named physical piece only after N has supplied
its required partition; membership does not authorize arbitrary label cuts.
Deterministic syntax order may resolve remaining experimental ties, but must not
be described as a unique human preference. Record the score tuple and chosen
policy version for every attempted candidate.

Before that ranking, require complete members and raw interfaces; selected-class
contact capability; the stated human-organization postcondition; all retained
local and caller relations; actual body/contact/
label/escape clearance; exact-grid representability; and preservation of required
physical pieces. Use wide exact arithmetic and explicit doubled coordinates for
half-grid comparisons; decline a proposal that cannot be represented by the
selected integer output instead of rounding its reflection. Required routing
needs a scratch routing proof or a pending W gate with whole-proposal rollback.
The actual final exported frame and a target round trip remain separate gates.

The organization gate must be operational before an implementation trial: name
the admitted local relations/frame requirement and independent expected witnesses
that distinguish a compact local core from the current flattened one. Neither
parent membership nor successful evaluation of the candidate's own expressions
is that oracle. The nine separated sources and two nested/interleaved controls
provide concrete contrary witnesses, but this round has not implemented a general
organization-quality predicate. A bounded search can choose among candidates
that pass the chosen postcondition; it need not recover one unique source image.

The proof performs one deliberately smaller, reproducible arithmetic comparison
of the **reported** native crossing/bend metrics on our eight literal outputs:

| Family | Incumbent | Right | Below | Winner by crossings, then bends |
|---|---:|---:|---:|---|
| AG1028 | (2,8) | (2,6) | (0,8) | Below |
| AG364 | (0,2) | (3,10) | (0,6) | Incumbent |
| Tail-bridged AG364 | (0,4) | (4,12) | Not executed | Incumbent |

This comparison was actually executed, but it does not run the full hard gates
or proposed five-term policy. It selects vertical AG1028 despite its source's
horizontal preference. That is an explicit heuristic tradeoff, not evidence that
the source is wrong. It also demonstrates why the nested incumbent must be compared
instead of being excluded by the parent partition.
None of the eight pose witnesses or these score winners is an accepted G1
organization improvement. In particular, translating existing parent poses did
not independently repair their inherited internal spacing.

Before G1 can be accepted, name the specific policy and check source organization
and contrary controls: all original eleven parents stay intact; AG1016/364 retain
valid nested options; AG1046/1047 prevent fixed left-to-right/top-to-bottom claims;
AG1080 retains its five parent memberships and detached bottom side pieces;
AG928/1037 and the passive-containing keeps remain unchanged. No arrangement score
can alter the electrical partition, silently omit a competitor, or erase a caller
constraint. A locally improving heuristic is allowed; what remains unproved is
its quality and interaction behavior on this exact set, not the possibility of
ever choosing an arrangement.

Affected rules remain `structure.1–12`, `skeleton.3/5/7/8/9–11/14`, plus
`sketch.12/13` and `pinned.1/4` at later movement boundaries. This research proposes
their new composition contract; it does not claim current code implements it.

## Saved replay

```sh
python3 -B docs/research/image-rules/round-2/tenth-arrangement-graphs.py \
  --check docs/research/image-rules/round-2/tenth-arrangement-graphs.json \
  --output /tmp/cktimg-tenth-arrangement-graphs.json
python3 -B docs/research/image-rules/round-2/tenth-arrangement-literals.py \
  --check docs/research/image-rules/round-2/tenth-arrangement-literals.json \
  --output /tmp/cktimg-tenth-arrangement-literals.json
python3 -B docs/research/image-rules/round-2/tenth-arrangement-proof.py \
  --check docs/research/image-rules/round-2/tenth-arrangement-proof.json \
  --output /tmp/cktimg-tenth-arrangement-proof.json
```

Only `tenth-arrangement-literals.py --execute` reruns the frozen CLI and separate
SVG rasterization. Saved proof replay is not a new native or target execution.
The fresh visual scope is eleven original source/native pairs plus eight literal
native images; the raw scope is all 2,202 decks. No production edits or builds.

## Final replay raster correction

Root's first `--execute --check` replay failed because all eight PNG hashes
changed; native JSON, SVG, report, stdout, stderr and exit bytes still matched.
The root replay PNGs contained `tIME` and `date:create`, `date:modify` and
`date:timestamp` text chunks. The producing command now uses
`-define png:exclude-chunks=date,time`. It removes only those volatile chunks,
retaining the exact remaining PNG chunks and compressed image data.

The original script, literal/proof manifests, failed root comparison and root
replay PNGs are archived in `groups/tenth-raster-repair` under the round-two run.
The original earlier PNG bytes had already been overwritten: their manifest
hashes survive, but those unavailable bytes are not claimed as archived pixels.
All eight normalized images were actually viewed again after the repair, and
the proof's view hashes and notes were refreshed.

`tenth-arrangement-raster-proof.py --execute` produced two independent normalized
rerenders per saved SVG. Both are byte-identical to the normalized figure. Its
separate PNG filter decoder preserves all 16 bits of every RGBA sample and finds
zero changed decoded bytes against the archived root replay image for all eight.
The repeated native `tenth-arrangement-literals.py --execute --check ...` also
passes. This repairs research artifact determinism; no native behavior changed.

```sh
python3 -B docs/research/image-rules/round-2/tenth-arrangement-raster-proof.py \
  --check docs/research/image-rules/round-2/tenth-arrangement-raster-proof.json \
  --output /tmp/cktimg-tenth-arrangement-raster-proof.json
```

That command verifies saved rerenders and decodes their pixels; add `--execute`
only to perform two new rasterizations per SVG. It does not run the native CLI
or a target import. Exact PNG bytes are tied to the current rasterizer setup;
this is not a cross-version ImageMagick byte-reproducibility claim.
