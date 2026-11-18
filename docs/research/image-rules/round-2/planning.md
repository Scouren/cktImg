# Plan derived from the second image review

This is a research plan, not an implemented replacement engine. The completed
second pass reopened all 2,202 source/generated pairs and challenged the first pass's
proposed selectors. The generated drawings belong to the frozen prototype;
the current worktree has a different rule/source inventory. See the
[manifest](manifest.json), [current headers](current-worktree-rules.md) and
[complete header differences](worktree-rule-delta.md).

The user asked that continued research and planning take priority. A smaller
crossing count is not the finish line. A proposed change needs an identifiable
human pattern, a bounded condition, counterexamples, an owner in the pipeline,
and an independent way to reject a wrong result.

The [next implementation](next-implementation.md) selects the immediate order
and a finite visible milestone: complete parent collection, then six exact
source physical partitions, with local arrangement work where current poses
cannot satisfy them. Broader handwritten equivalence remains unfinished.

The [external-method cross-check](literature-crosscheck.md) records a small
primary-source literature review. It supports experiments with explicit
organization before geometry, but our nested-pair and competing-owner
counterexamples prohibit blindly copying strict-subset pruning or truncated
match sets as unique-owner evidence. The existing image proofs remain the
acceptance basis.

## Separate the decisions that the current pipeline couples

| Decision | Evidence it may use | What it must not decide implicitly |
|---|---|---|
| Electrical identity and ordered pins | Raw SPICE declarations, complete registered contracts | Visible grouping, omitted terminals, or physical wire continuity |
| Matching devices | Verified terminal/model/parameter correspondence and admitted caller symmetry | One global geometric axis, inward glyphs, or one shared supply bar |
| Local group membership | A bounded circuit pattern with all participating terminal roles and interfaces | That every gate-sharing device belongs in the same physical group |
| Group arrangement | Admitted relations, actual occupied frames, intergroup connections | Changes to group membership made just to lower wire cost |
| Symbol pose | Actual class terminals, allowed poses, contextual input order and caller geometry | Reordering SPICE bindings or reflecting unrelated bias/supply leads |
| Physical wire pieces | Net identity, group interfaces, explicit routes and supported contact semantics | New electrical nets or deletion of hidden signal connections |

AG1080 motivates local axes but does not prove a universal decomposition.
AG928 retains one core and has a same-facing pair. AG77's source PMOS gates
face outward while the generated PMOS gates face inward; its input pair
does not need the same change. AG220 contains two source-degeneration
resistors between the input sources and the tail. Its human group therefore
cannot be defined solely by transistor D/S adjacency. These are distinct
questions, not evidence for removing all symmetry or joining through all
passive devices.

## Current owners and the required insertion points

This table is a code-reading plan against the worktree captured by the
manifest. It does not claim these are the owners in every earlier prototype.

| Existing stage | Present responsibility | Planning constraint |
|---|---|---|
| `structure.analyze` | Canonical ranks, row/stack groups, device/net mates, admitted hints | A local-group selector must expose its membership before column/core and shelf decisions consume it. |
| `skeleton.place`, `columns`, `wrap` | Lattice cells, common mirrored core, shelf cuts | Narrow core indivisibility only for certified groups; preserve one-core controls and honored row/order/above constraints. |
| `block_symbols.identify/draw`, library registration | Complete named contracts, ordered terminals and glyph operations | Add a symbol only with every formal accounted for. A global supply declaration does not add an undeclared formal pin. |
| `opamp.place` | Alternative whole-circuit signal layout after admission | A recognized triangle and a signal-layout candidate are different contracts; changing one predicate does not prove the other. |
| `sketch.orientAll`, `schematic.settleDevice` | Choose orientation and derive the actual terminal frame | Any contextual pose must settle before downstream room reservation and actual-pin placement. |
| Pattern collectors and placement in `sketch.drawValid` | Collect candidates, place bounded groups, reserve rooms | Competing candidates must not commit overlapping ownership by call order. Use existing specific owners until a second concrete shared case justifies a seam. |
| `power_compact.squeeze` | Close gaps while preserving supplied actual-terminal orders | Any new group relation must survive compaction or reject that compaction result; checking only the initial lattice is insufficient. |
| `sketch.keepAts` and final `wireUp` | Apply admitted final-coordinate requests and route final frames | Revalidate any automatic proposal against honored caller geometry. A failed automatic proposal leaves the prior valid path. |
| `Placed`, ABI and exporters | Preserve card pins, materialize leads/wire pieces, export drawing | Stored pin identity and visible contact correctness are independent acceptance conditions. |

`sketch.drawValid` may wire scaffolding for compaction and then wire again
after caller placements, shelf cuts and thinning. Consequently a successful
early routing experiment does not establish correctness of the final
drawing. Final-output checks must examine the same phase users receive.

## Admission protocol for each proposed rule

1. Enumerate raw topology candidates without reading source coordinates,
   source instance IDs, or native layout output. Name every required pin role,
   allowed extra incidence and uniqueness condition. Preserve rejected names.
2. Check the selected source instances using actual visible strokes and
   independently bound terminals. Cached source terminal frames are evidence
   to verify, not an oracle by themselves.
3. Record the exact positive, negative and ambiguous name sets. A set found
   only in one 734-image assignment is a shard census, not a full-corpus census.
4. Test near misses: an extra branch, altered terminal role, competing owner,
   unknown symbol control, missing declared pin or conflicting caller request.
   Test card permutations and consistent renaming without using names as
   the detector. Recognition invariance does not require identical layouts
   after renaming because the existing layout uses names to break ties.
5. Choose one owner for each resulting table. Enumerate capacities and widths
   from devices, pins and candidates before allocating; all mutation waits
   until fallible collection and conflict checks succeed.
6. For multiple incompatible candidates, abstain or preserve the existing
   valid layout until a documented policy resolves the conflict. Array order
   or a lower crossing count is not a topology certificate.
7. State separately what the rule guarantees, what the fallback guarantees,
   and which desired source choices remain underdetermined by the netlist.

The existing priority of caller requests remains authoritative. A source
example cannot overrule an explicit symbol, side, orientation, group, route,
or placement instruction that the engine has admitted. Invalid and rejected
instructions must not acquire authority merely because their text exists.
This is a proposed consistency requirement, not a claim that every current
path already implements it: `opamp.steered` currently declines on the presence
of several hint verbs before checking their admission verdicts. A later change
needs explicit valid, invalid, rejected and weak-hint tests; broadening symbol
recognition must not silently change that separate behavior.

## Proposed work order and proof gates

The first finishable organization experiment is now the
[ninth round's collection-only all-MOS trial](ninth-local-groups.md): exact
raw parent/interface facts with unchanged rendering. Its eleven candidates
include interleaved and nested source arrangements, so a subsequent
placement experiment still needs a justified composition decision. This
first gate does not fulfill the user-visible layout goal. Symbol, body and
diagonal work below are separate cohorts; unrelated new glyphs do not block
the existing-MOS experiment. The dependency order and candidate-frame split
are specified in [implementation-packages.md](implementation-packages.md).
The [tenth acceptance plan](tenth-acceptance-plan.md) supplies caller-first
context producers, exact named cases, mutations and separate native/target
finish lines. Its manifest keeps all new-engine outcomes pending. The
[search contract](tenth-search-contract.md) separates a valid best-found
mapping from proof of unique ownership and gives an independent finite-map
oracle for resource exhaustion.

| Work package | Entry evidence | Smallest experiment | Gate before broader work |
|---|---|---|---|
| Narrow MOS parent collection | All 2,202 raw inputs; 138 complete maps; 11 raw multigroup candidates, including two separate-box counterexamples | Add inspectable parent/interface facts while preserving ordinary rendering | Complete exact dispositions and maps; AG1080/928 partitions; continued formals/model/rail controls; bounded-search and caller authority |
| Complete known-bias sampling admission | 36 global candidates, including AG789 outside the original 35-image cohort; three biased failures | A selector-only RED example plus phase/body/bias and unknown-control near misses | Complete ordered port contract; no extra phase incidence; DUT formals count as interfaces; caller/custom-frame behavior |
| Conditional regulator signed-input order | First pass's 39 signed-order examples, contrary AG1709/2665 | Change only signed input locations within an admitted complete contract | Actual lead mapping, retained supplies/biases, extra-divider/load ambiguity controls, all poses and caller symbols |
| Four-bias and clocked symbols | Seven exact raw contracts; five initial own-lead certificates and two follow-up cases | Contract recognition and terminal table before any placement change | Every formal present exactly once; unknown extras rejected; output AND bias index consumers support index eight; role permutations and class-cache controls |
| Body terminal visibility | Twenty focused cases; body-only shared wells and mixed visibility on one net | Independent logical-pin and visible-contact counterexamples | Raw four-pin identity, supported glyph attachment, local tie vs remote label vs routed body, all consumers/exporters |
| Local groups and axes | Ten focused source-region cases; 26 four-device shape cases with multiple arrangements | Collect candidate membership without changing coordinates | Complete substrate/control incidence; typed attachment ownership; overlap/degeneration controls; explicit symmetry/group conflicts |
| Joint passive feedback placement | Bounded reciprocal-capacitor evidence and flat feedback controls | One complete group's poses and terminal orders | Whole member set, unique ownership, actual frame and clearance, compaction survival |
| Diagonal reciprocal wires | Positive actual X strokes and orthogonal AG404 | Geometry/contact capability isolated from recognition policy | Endpoint/intersection/junction/clearance/partition/ABI/export tests; Manhattan default remains valid |

These rows are research packages, not one total dependency order. A discovered electrical representation defect
would take priority over appearance once independently established; a missing
visible lead alone does not establish that defect. The body study must decide
which it is. An enlarged symbol contract also does not automatically authorize
more complex whole-circuit layout.

## Decisions changed by cross-review

These are changes to the proposed rule set. They do not report production
fixes, and a failed research certificate is not automatically a failed
electrical circuit.

| Previous simplification to reject | Replacement boundary | Proof or counterexample |
|---|---|---|
| A source pair is an independent rectangular placement group. | Pair membership is a relation; an admitted parent group may contain nested pair relations. | AG517; [quad study](quads.md) and actual group lead bounds. |
| Complete topology uniquely determines the original pair arrangement. | Evaluate a bounded set of human arrangements using semantic/caller context; report unresolved choices. | AG80/82 complete-card transport. Default name-inferred input roles differ, so the certificate is explicitly topology-only. |
| A component partition proves which attachments each group owns. | Every owned resistor, tail and current source needs an ordered-incidence witness. | Peer mutations swapping AG459 owner rows, I sources and R bridges originally passed. |
| Visible pin incidence proves a private group boundary. | Count every ordered electrical occurrence plus outer DUT formals before visibility or eligibility filtering. | Optional BJT substrate; exported feedback/sampling nodes; MOS bulk consumers. |
| Correct-net ink at a cached point proves attachment to the intended device. | Require own-symbol geometry and actual named conductor support separately. | AG1014 cached B moved to a distant VI1 marker originally passed the body certificate. |
| A lead's first exit and final tip are enough. | Every intervening segment must remain outside the body after its supported attachment. | Literal leave/re-enter path defeated the original port proof. |
| Hidden body-only nets can be omitted because they have no visible consumer. | Preserve and represent each electrical relationship; source style and class capability decide the presentation. | [All 23 source certificates](fourth-bodies.md): 22 dashed bridges and AG1236's explicit omission. |
| Widening a recognized symbol's output index covers nine-pin support. | Audit every downstream index and storage bound; test each role in the ninth position. | `bias_neighbors.Pair.pins`, `find`, `turn`, `tip` retain three-bit amplifier indices. |
| The same contract predicate can safely admit a symbol and its whole-circuit placement. | Keep recognition and each layout owner's incidence/admission contract separate; rescan their composition. | Exact extension adds only AG2212 to the strengthened regulator set: 39→40; sampling remains 36. |

The peer notes retain the actual failing inputs and the repaired research
gates: [ports to bodies](cross-review-ports-to-bodies.md),
[bodies to groups](cross-review-bodies-to-groups.md), and
[groups to ports](cross-review-groups-to-ports.md). The original body certificate
did not independently reject contradictory external label-to-formal text.
[The fifth body study](fifth-bodies.md) now closes that specific gap for ten
body terminals through six attached port objects in four cases. Its seven
unassociated free/route labels remain named and outside the proof; this does
not turn the earlier certificate into a general visual netlist extractor.

[The fourth ports fixtures](fourth-ports.md) add two important boundaries.
Raw competition is scoped to a shared anchor or overlapping ownership, not
the whole page: two disjoint regulators can coexist. Plugin-generated names
such as `b17` preserve geometry while obscuring original exact-family identity;
semantic contract and generated-versus-caller geometry authority must cross
that boundary before a new local policy can claim plugin parity. Shared
definitions also require immutable per-instance signed-slot variants through
plugin emission. These dependencies are ordered in the
[implementation packages](implementation-packages.md).

## Concrete finish lines for implementation

The eventual finish line is a schematic that preserves the circuit and
expresses the human relations appropriate to its supported case. Matching
one source's crossing count, shrinking its viewBox, or replacing a box with
a triangle does not establish this. Source examples can have several valid
arrangements, and some cached source metadata is demonstrably stale.

Each work package therefore finishes with four separate results:

1. **Electrical identity:** exact named cards, models/parameters and ordered
   pins survive the actual target importer/netlister round trip. Every
   omitted display pin still has its original electrical identity.
2. **Visible meaning:** each required visible relationship has a real contact
   or a target-valid named attachment. Glyph role marks and ordered terminals
   agree. Unresolved representation is reported instead of invented.
3. **Human organization:** literal source-supported group, relative order,
   pair, local axis, feedback-side and facing relations pass on the named
   admitted cohort; contrary examples retain their appropriate alternatives.
4. **Pipeline and caller integrity:** these relations survive final placement,
   compaction, routing and export; explicit caller constraints remain intact;
   capacity/allocation failures preserve the previous valid result.

A bounded package is ready to merge only after its own gates and the existing
repository checks pass, including both renderer configurations, style, native
and plugin contracts, reproducible committed WASM and the size cap. Keep the
current named failures visible. A green narrow package is progress toward
equivalence, not permission to describe all 2,202 images as equivalent.

## Group composition: the smallest shared mechanism worth testing

The source-region and switching-quad studies now supply two real cases for
a shared ownership check. They do not justify a general pattern language.
Keep each existing collector concrete. Each appends immutable candidate
member slices and typed attachment/interface witnesses; one composition
step accepts or rejects their ownership before any collector changes cells.

Do not equate the containment of device sets with disjoint drawing boxes.
AG517's inner and outer pairs have disjoint member sets but overlapping
geometric bounds. A parent can arrange both. Conversely, the independent
quad cross-review constructed a two-source/three-drain network with two
crossed-gate quads sharing two devices. Those are competing embeddings,
not independent boxes to pack and not automatically one larger pattern.

The first literal composition oracles should be:

| Member relations supplied by concrete collectors | Required decision |
|---|---|
| Pair A={1,2}, pair B={3,4}, certified parent P={1,2,3,4} | Keep both pair relations inside P; only P's selected arrangement commits final coordinates for these members. Pair boxes may overlap. |
| Quad A={1,2,3,4}, quad B={2,3,5,6}, no certified parent | Report competing ownership before visibility/model/frame eligibility filtering. Do not select whichever collector ran first. |
| Two disjoint groups share a drain load, compensation net, gate control or body net | Preserve that interface; connectivity alone cannot create a parent owner. |
| Caller group overlaps an automatic owner without a proved compatible containment | Preserve admitted caller grouping and decline the automatic placement proposal. |
| Caller supplies one global symmetry axis across two automatic local groups | Retain that global relation or decline automatic local axes. Independent local reflection is not evidence that the global request is honored. |
| First child can be placed but the second collides or exceeds capacity | Commit neither child proposal; no partially moved devices, reserved corridors or added labels remain. |

Raw membership, ownership and arrangement remain separate tables or borrowed
slices. The immutable netlist owns identity; a concrete collector owns its
candidate facts; one resolver owns admitted placement ownership; an admitted
placement owner writes coordinates; downstream compaction/routing consumes
its protected relations. A parent is accepted only with its own bounded
topology and interface proof. Set containment by itself is insufficient.

The initial experiment should leave the existing global mate table and caller
axis contract unchanged. Collecting alternative local relations is reversible
and directly checkable; replacing all symmetry semantics at once would join
too many independent questions. When local placement is admitted, check the
actual final terminal frames, child order and axis relations directly. The
current report does not have geometry oracles for every group/axis hint.

This is a proposed composition boundary with explicit literal expectations,
not an implemented resolver. Its capacity must be based on the number of raw
candidates and total member references, with named overflow and allocation
failure outcomes. Reuse typed handles and bounded roles. Do not infer a
constant maximum from the present 26-quad or 787-pending-region census.

## Proof obligations shared by the work packages

The six data questions are answered per package before implementation: inputs
and outputs; maximum population; field widths; access pattern; lifetime; and
parallelizability. Record table ownership and the independent invariant as
well. Start with the existing SoA tables, typed `u32` handles and `none`
sentinels. Use a bounded enum for a genuinely new policy dimension only after
two concrete cases require it. Research prose is not a mandate for a general
rule interpreter or a retained object graph.

Keep these outcomes separate in every experiment:

- Ordered electrical bindings survive, including hidden supply/body pins.
- Every required visible pin has the correct actual endpoint and contact.
- Same-net physical components match the intended local joins and cuts.
- Group membership, glyph facing and terminal order match the bounded rule.
- No foreign body, terminal, lead, label or reserved corridor is obstructed.
- Explicit caller behavior, determinism and capacity failures retain their
  documented contracts.
- The native and plugin consumers agree; both renderer configurations pass;
  rebuilt WASM remains within the existing 550 KB cap.

Use literal/source-independent expected relations before writing code. A
fresh failing example is trusted only after the old implementation actually
fails it. Preserve exact baseline failure names; do not hide old failures by
reporting only net improvements or a total count. Byte equality remains useful
for unrelated families, while a deliberate glyph/placement change needs
relation and contact checks rather than a regenerated image alone.

## Next research rounds

### Diagonal capability: independent literals before implementation

These are code-reading counterexamples to extending the existing Manhattan
predicates unchanged, not claims of bugs on currently admitted input. They
make the earlier [consumer audit](../feedback-and-symmetry.md#2-add-a-diagonal-option-without-making-all-feedback-diagonal)
executable without depending on source screenshots as a geometry oracle.
[The independent third-round probe](third-diagonals-plan.md) now executes
these rational literals and adds actual-ink distance, odd-span label anchors,
f32 transport, full-width arithmetic and rollback-domain checks. These remain
research reference/formula tests, not production regression passes.

| Literal geometry | Required result | Existing assumption challenged |
|---|---|---|
| Segment (0,0)–(10,10), foreign point (2,8) | The point is off the segment. | `Canvas.fits` currently treats segment bounding-box containment as point contact. |
| Segments (0,0)–(10,10) and (0,10)–(4,6) | Disjoint; infinite lines meet at (5,5), outside the second segment. | `thin.touches` currently treats intersecting bounding boxes as contact. |
| One diagonal arriving at (0,0) from (-10,-10), one leaving toward (10,-10) | Exactly two rays, no junction dot. | The current cardinal projection produces three occupied bits for these two rays. |
| Distinct-net diagonals (0,0)–(10,10) and (0,10)–(10,0) | One proper crossing at (5,5), no connecting dot. | `checks.crossing`/report and thinning count horizontal/vertical crossings. |
| The same two segments on one net | A junction at (5,5), split into endpoint-connected pieces. | `dots.find` searches cardinal intersections; `Placed.strictlyInside` returns false for diagonal interiors. |
| Diagonals (0,0)–(9,9) and (0,9)–(9,0) | Intersection is (4.5,4.5), not (4,4) or (5,5). | Integer exported junction coordinates require an explicit supported-grid policy; rounding silently changes geometry. |
| A second paired route collides after the first is admitted | Neither new route nor its extra labels/pins remains. | Allocation and collision rollback must cover the entire paired proposal. |

The first useful capability experiment can retain cardinal terminal stubs
and use interior diagonals only. That does not avoid these consumer checks:
thinning, reporting, export and future route contacts still see the interior
segments. Generic maze search need not gain arbitrary-angle moves just to
represent an admitted local crossover. Conversely, choosing only 45-degree
diagonals is a policy that needs source/pose evidence; it is not established
by a visually X-shaped source.

The C ABI currently promises Manhattan polylines. Define compatibility and
capability negotiation before returning diagonal output to existing callers.
The fact that a point-array format can store two diagonal endpoints does not
make old consumers compatible. Keep the default intact until the full path
and actual Schemify host round trip are demonstrated.

### Cross-review sequence

The complete second visual pass is followed by cross-review: each agent tries
to falsify another agent's strongest rule and its admission boundaries.
The third round focuses on interactions that a single-family study misses:
symbol contracts versus layout admission, group ownership versus caller
symmetry, and hidden-terminal treatment versus physical partitions. Each
round keeps its own observations and names which previous conclusion changed.
Repeated inspection is useful when it answers a new question; repeating a
positive example without a new test does not strengthen the selector.

The second full visual pass and first adversarial cross-review have produced
the linked studies and executable research gates. Focused follow-ups now
cover all seven additional symbol contracts, all 23 internal body-only
circuits, external body-marker association, diagonal geometry, and materialized
shared-definition/caller fixtures. Sixth and seventh rounds additionally
retain actual final-axis failures, hidden-glyph contact, exact rounded-gate
overshoot, and repaired stale/visibility/transform proof gaps. The eighth
round executes an older target import/export boundary and proves why
physical partitions need their own contract. The ninth round separates
immutable local capability, tentative world frames and final validation;
its complete raw census recovers local parent candidates while preserving
interleaved/nested counterexamples. The tenth round defines a finite arrangement
grammar, distinguishes bounded optimization from uniqueness proof, and locates
input authority that must survive normalization. Its eight actual caller-pose
witnesses are not accepted organization improvements. The eleventh round
preserves a continuous feedback contrary while identifying six source 2+1
output nets for a narrow physical-partition experiment. The
[twelfth trial](twelfth-organization-gate.md) makes one local organization
postcondition operational: five common-control five-MOS parents within the
eleven-case multigroup domain, with staggered-input and offset-tail source
contraries to broader rules. Six isolated and two full-DUT controls separate
compact local reconstruction from translation. Actual directed D/S roles
join the center relations after an independent rotation attack; a retained
compressed candidate proves that separate lead clearance is still required.
The reference footprint is fixed for the default-class diagnostic and does
not certify full-context routing or human scale. No automatic G1 acceptance
or new N0 route was executed. The
[27 conditional rules](proposed-human-rules.md) consolidate their implications;
the [implementation packages](implementation-packages.md) define the next
bounded work. The [first acceptance plan](tenth-acceptance-plan.md),
[arrangement contract](tenth-arrangement-plan.md) and
[physical-partition experiment](eleventh-partition-candidates.md) keep
collection, geometric organization and physical routing as separately measured
steps. The ordinary incumbent remains a fallback; selecting it while it still
fails a promised organization postcondition is not a completed improvement.
Nothing here certifies visual equivalence or
promotes the oversized experimental plugin to main.
