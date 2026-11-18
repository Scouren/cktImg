# Eleventh ports study: complementary-stack outputs need a physical-part policy

The proposed raw pattern has **four parent tuples in three circuits**, not just
AG1080 FN1/FP1. All six output nets in its three acyclic tuples have a source
2+1 partition. The fourth tuple, in cyclic AG1053, has two continuously wired
three-pin outputs. It is a real contrary case and remains in the raw census.
Filtering cyclic parents first would hide it.

This supports a narrow **N0 implementation experiment under the already stated
complete acyclic-parent boundary**. It does not prove a general “two drains plus
one remote gate” naming rule, or that removing feedback causes a human author
to use labels. Current frozen placement also does not establish that every
proposed two-part route is geometrically feasible. G1 arrangement and actual
route admission remain separate requirements.

The [census and proof](eleventh-partition-candidates.py) and
[exact result](eleventh-partition-candidates.json) re-read all 2,202 decks and
recompute their complete ninth-parent records. Every previous disposition is
preserved. The script changes no engine code, compiles nothing and executes no
new CLI/host run. It reads hash-bound frozen native artifacts and the existing
actual-ink machinery. All three matching source/native pairs were freshly
viewed; their independent PNGs, hashes and observations are recorded.

## The raw question, before geometry and caller eligibility

Start with the ninth strict ordered four-terminal MOS input boundary and its
complete unique nontrivial reflection. Retain every raw D/G/S/B occurrence,
model/parameter suffix, outer formal, admitted rail and typed gate interface.
Consider a parent only if it contains exactly four devices and is closed under
that reflection. Its two private drain nets must each have:

* One PMOS drain and one NMOS drain inside the parent. Both devices have
  S=B on their admitted polarity rail.
* Exactly one other raw occurrence: a gate outside this parent. There is no
  hidden-body, source, extra drain, passive or additional gate occurrence.
* No outer DUT formal or rail authority on the drain net.
* A reflected sibling stack that preserves P/N/D/G roles, maps the two output
  nets and outside gate devices, and preserves their outside-parent ownership.

The complete parent gate dependencies are retained. A cycle is recorded, not
used to erase a raw tuple. Neither source geometry, native geometry, net
spelling, shared-control polarity nor a caller's held pose chooses membership.
The result records which P or N gate control is shared; this is an observation,
not an extra filter. Original caller requests must be considered later when
admitting a partition or arrangement. A literal control adds wire/fixed requests
to the same complete raw context and keeps the raw candidates unchanged.

The census retains all seven original disposition-name sets. In particular,
2,106 input declines, ten internal-control declines, 29 involution declines,
40 single-channel keeps and four reflected single-core keeps remain distinct.
The two cyclic-parent cases are still cyclic. Only AG1053 contains this new
raw tuple; AG924 does not. No unsupported deck or rejected attachment is silently
reduced to its visible MOS subset.

## Exact tuples and all eight physical partitions

`D` and `G` below identify original card indices 0 and 1. The result stores
every complete ordered card and all parent/interface witnesses, not just this
abbreviated table.

| Case and parent | Output net and exact three occurrences | Source | Frozen native |
|---|---|---|---|
| AG1053 {MN4,MN5,MP4,MP5}, cyclic | net1: MN5.D, MP5.D, MP0.G | All three continuous | All three continuous; keep |
| Same parent | net3: MN4.D, MP4.D, MP1.G | All three continuous | All three continuous; keep |
| AG1079 {M6,M7,M8,M9}, acyclic | RN: M7.D, M9.D, M11.G | Drains together; gate separate | All three continuous; extra joins |
| Same parent | RP: M6.D, M8.D, M12.G | Drains together; gate separate | All three continuous; extra joins |
| AG1080 {M15,M16,M17,M18}, acyclic | FN1: M16.D, M18.D, M29.G | Drains together; gate separate | Three named singles; missing local join |
| Same parent | FP1: M15.D, M17.D, M31.G | Drains together; gate separate | Three named singles; missing local join |
| AG1080 {M6,M7,M8,M9}, acyclic | RN: M7.D, M9.D, M27.G | Drains together; gate separate | All three continuous; extra joins |
| Same parent | RP: M6.D, M8.D, M28.G | Drains together; gate separate | All three continuous; extra joins |

The AG1080 FN1/FP1 parent has a shared P-device gate control; the other three
tuples share their N-device gate control. A predicate specialized to the FN1
spelling or P-side shared control would miss the RN/RP instances. In AG1053,
the outside PMOS gates feed the main core and the complementary side-stack
P gates read its outputs, producing the retained parent cycle. Its source
draws those feedback paths continuously around the core.

The source checks cover **all 24 pair relations** on these eight nets. Every
positive path has verified actual named-net conductor ink. Every separation
also checks all actual source conductor ink, so a missing cache assignment
cannot manufacture a negative. No pair is unsupported by the existing bounded
source schema. Literal expected source and native partitions are written
independently in the proof, and comparison uses complete equivalence classes.

Across the three matching circuits, **64 actual source glyphs and 256 ordered
D/G/S/B bindings** are checked against raw cards and actual native device
records. The 192 visible D/G/S contacts use actual own-lead geometry; logical
body bindings do not acquire invented visible B contacts. Source literal
labels are retained as evidence but never union physical pieces. This is a
physical-path proof, not a complete source-text attachment or target netlisting
certificate.

The source proof is bounded to these hash-bound original SVG bytes, the
supported geometric schema and the actual views. The independent reviewer
confirmed all 24 relations with a separate original-SVG segment reader, and
also showed that adding `visibility="hidden"` to an AG1080 conductor is not
rejected by the older imported ink helper. This study does not claim generic
CSS/visibility admission for changed SVGs. Its original evidence is unchanged;
a general changed-SVG contract must evaluate or reject unsupported visibility
and inherited style before treating a geometric path as visible ink.

Native JSON components and every reachable exported name are checked with the
repaired partition helper: conductor components precede marker association.
The exact mismatch list contains eight added physical pair joins on four nets
and two missing local joins on FN1/FP1. The two AG1053 nets are positive keeps.
There is **no source three-single match** in this raw census. Do not turn the
native FN1/FP1 failure into a source preference for three singles.

## Falsification and caller controls

Card reversal and bijective device/net renaming preserve all four tuples after
transporting outer-formal and admitted-rail facts. No requirement for identical
renamed pixels is inferred. Seven exact AG1080 near misses reject its FN1/FP1
parent tuple:

| Raw change | Result |
|---|---|
| Add reflected extra gate consumers on FN1/FP1 | Target tuple rejected; RN/RP tuple remains. |
| Add FN1 as M1's body binding | Strict body boundary declines; no hidden omission. |
| Add a resistor between FN1/FP1 | All-MOS cohort declines; no passive omission. |
| Export FN1/FP1 as outer formals | Private-net tuple rejected; RN/RP tuple remains. |
| Move the P-device sources to private net0 | Rail-ended target tuple rejected; other tuple remains. |
| Change only M16's complete model identity | Required whole-map uniqueness no longer holds. |
| Change M16.G to an unsupported private control | Internal-control boundary declines. |

An eighth control verifies that original wire/fixed requests do not remove
raw membership. It is a literal collector-input control, not execution of a
new admission path. All changed cards/formals and resulting dispositions are
recorded, so “rejected one tuple” cannot conceal removal of another valid one.

Two existing frozen caller runs supply exact contrary renderings on the same
AG1080 FN1 topology. `wire fn1` produces one three-pin tree; `label fn1` produces
three named singles. The proof re-reads those actual decks/native records,
checks complete ordered cards and parameters, and checks the final partition.
Their caller authority must survive. The study does not rerun them or claim
that whole-net hints can express 2+1.

These controls have different purposes. AG1053 is an actual-source continuous
counterexample to the broad raw tuple. Explicit `wire` and `label` are caller
counterexamples to automatic override even within an otherwise acyclic case.
The census does not find a natural-source three-single counterpart; that gap
remains explicit rather than being filled with a guessed example.

The independent eleventh review exposed two native certificate holes: the
caller replay accepted an appended unrelated MOS record, and accepted an
actual `nmos` record changed to selected class `pmos` while its raw model value
stayed unchanged. The reviewer preserved the old proof and changed actual
JSON/provenance before repair. A shared complete-inventory gate now checks
every original/caller record: exactly one device per raw card, the admitted
default model-to-class relation, ordered d/g/s plus bulk, and full parameters.
Other records must satisfy the explicit generated-terminal schema. Four
literal regressions reject the extra MOS, duplicate MOS, wrong class and
swapped terminal roles. This bounded default-class check does not certify a
caller custom class; that needs its separate ordered-role/capability contract.

## A bounded N0 implementation question

The first proposed experiment can ask: **within the complete ninth acyclic
parent cohort, can this exact reflected-stack context retain its local D/D
tree and separate external G contact while preserving all original authority?**
Its current source-positive set is six named nets in three tuples. Names are
test identities; the runtime inputs are ordered roles, complete incidence,
parent reflection/interface facts and admitted caller provenance. Preserve
the cyclic tuple as a raw contrary even when this initial N0 boundary declines
its admission. Do not weaken the complete context to a local three-pin count.

The existing `wire_parts.draw` two-part mechanism can express the realization:
map the two actual drains to part A and the outside gate to part B, with an
ordinary internal name on each part. A new collector supplies the full context;
the seam itself supplies neither selection nor full-net ownership. Before any
net is marked handled, require exact coverage of all three original endpoints,
current raw node equality, correct selected-class role/index, own-contact
capability, admitted visibility and the actual current pose. Count body and
other contextual incidences before that visible mapping.

Reject incompatible original `wire`/`label`/rail/route/port intent according to
existing admission, including default-looking normalized requests. Caller
custom classes and held poses remain authority. A raw candidate can survive
while this proposed automatic route declines. Check contact against existing
same-net ink as well as between the two newly drawn parts; the local two-part
append transaction alone cannot prove that later routing will preserve them.

Use one complete-net checkpoint for routes, generated markers, pins, nodes and
coordinates. Prepare actual mapping and fallible work before publishing handled
status; a failure restores the prior net and ordinary path. If the route is part
of a provisional moved group, failure of its mandatory physical contract also
rejects that group proposal under the accepted arrangement fallback boundary.
Do not leave one side of the reflected output pair partially moved or silently
drop an admitted per-net requirement.

For the first N0 implementation policy, make the two reflected output nets
one trial unit as well. Map both completely, take an outer append checkpoint,
draw both with the existing per-net seam, and publish neither handled/labeled
bit until both pass. Failure on the second restores the first tree and names;
incompatible original caller authority on either declines this automatic
tuple. This is a proposed conservative policy, not behavior executed by the
research proof. The [concrete N0 integration contract](n0-implementation-contract.md)
separates this pair rollback from per-net rollback, thin-round withdrawal and
whole moved-group rollback.

The final oracle needs both the D/D path and absence of D/G contact. Names need
correct reachable attachment on both actual components. Recheck compaction,
mirror replication, normal thinning and exporter coordinate transport. A later
cut of the required D/D tree is a failed mandatory partition, or an explicitly
pre-admitted fallback with a different reported result. It cannot be called a
retained 2+1 success. The same-build target must netlist unchanged ordered roles;
electrical equality and physical separation are separate results.

No current-geometry two-part route was attempted here. Frozen RN/RP outputs are
continuous and FN1/FP1 are over-split; rearrangement, clearance or name placement
may cause a legitimate route decline. An N0 prototype can report candidate,
admission, route-feasibility and final-validation results separately. It cannot
declare G1 unnecessary merely because its raw partition fits a two-part API.

## Replay and finish line

```sh
python3 -B docs/research/image-rules/round-2/eleventh-partition-candidates.py \
  --check docs/research/image-rules/round-2/eleventh-partition-candidates.json \
  --output /tmp/cktimg-eleventh-partition-candidates.json
```

The script binds the ninth census, native provenance, source decks/SVG/cache,
actual saved caller outputs, ink dependencies and all three viewed PNGs. It
retains exact names and complete records, not a count-only summary. An eventual
implementation must add independent actual-route/rollback/target gates; this
research result is the bounded input and expected-partition specification for
that work.
