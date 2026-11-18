# Independent tenth arrangement and resource-contract review

The arrangement study supports a finite diagnostic candidate grammar and
eight caller-controlled pose witnesses. It does not establish an automatic
arrangement selector or a human preference for the invented tail circuit.
The complete interface stars match between AG1028 and AG364, while their
complete DUTs provably differ. The retained nested alternative is necessary
to express the observed AG364 source layout.

The replayable independent review is
[tenth-review-arrangement.py](tenth-review-arrangement.py), with results in
[tenth-review-arrangement.json](tenth-review-arrangement.json). It reads raw
decks and actual saved outputs; it does not execute the native CLI or a host.
All eight arrangement rasters and both original AG1028/AG364 source/native
pairs were actually viewed during this review. Their exact hashes and fresh
observations are in the result.

## Raw interface equality is local, not whole-DUT equality

The independent strict literal reader reconstructs every ordered raw row,
formal and model definition for all 11 cases. The review reconstructs all
764 D/G/S/B incidences and then each complete cross-parent channel-to-gate
boundary star. It does not copy the peer's filtered boundary list as its
incidence oracle. Removing a body incidence or one interface consumer from
the certificate fails the independent checker.

For the two internal boundary nets the exact transport is:

| AG1028 net and complete star | AG364 net and complete star |
| --- | --- |
| `net3`: `M1.D`, `M3.D`, `M6.G` | `X`: `M3.D`, `M5.D`, `M9.G` |
| `net1`: `M2.D`, `M4.D`, `M7.G` | `Y`: `M4.D`, `M6.D`, `M10.G` |

The transport preserves every occurrence, ordered role, producer/consumer
parent, exact model-and-parameter tokens, internal boundary status, and both
device and net reflection correspondence. The two model-definition tables
are independently read from the raw circuits and are identical. This is a
complete certificate for these two stars within these frozen circuits. It
does not transport all terminals or all devices of either DUT.

Whole-DUT isomorphism is impossible: AG1028 has 10 MOS and eight formals;
AG364 has 13 MOS and 11 formals. The complete stars therefore defeat a rule
that chooses horizontal, vertical or nested placement solely from this
interface signature. They do not establish that every larger structural
feature is equal. The original pair images show left/right source stages
for AG1028 and nested output branches for AG364.

The symmetric tail mutation changes exactly `M9.S` and `M10.S` from `vdd`
to `ptail`, and adds `M14 ptail vb3 vdd vdd pch l=0.15 w=1 nf=1 m=1`.
All original body bindings and all other original raw fields remain intact.
The same boundary stars remain intact; both proposed parents become single
channel components. A nested caller pose still exists. This is an expression
counterexample to treating single channel-component membership as a ban on
nesting. No source drawing or author preference exists for this invented
circuit, and its report metric winner cannot manufacture one. The peer's
one-sided source-change control declines involution; it is not evidence
that symmetric added tails are automatically acceptable layouts.

## Exact finite syntax and actual pose witnesses

An independent Python AST parser checks the entire tree grammar and exact
leaf coverage. For `k` parents, `k! * Catalan(k-1) * 2^(k-1)` ordered binary
H/V trees plus `KEEP_INCUMBENT` gives exactly the saved number of distinct
strings. The 11 lists contain 53,851 rows. This proves complete enumeration
of that declared syntax. It does not count distinct geometries, determine
spacing, resolve orientation, prove route feasibility, or bound production
costs. Non-slicing arrangements beyond the retained incumbent are outside
this grammar.

The eight saved native documents preserve 97 MOS records, all 388 raw
ordered terminal occurrences, complete model/parameter tokens, and all 291
exported D/G/S contact coordinates. The independent contact oracle reads
the literal `*@ at` requests, checks the frozen class's local D/G/S vectors,
and applies integer reflection/rotation matrices. It does not derive
expected coordinates from the saved native pin values. Across each
same-deck family, every member of the second parent translates by the same
exact offset: `(1000,0)` for right or `(0,800)` for below; every first-parent
pose is retained. Orientations and relative member geometry remain fixed.
The tail moves with its whole output parent.

These controls preserve the fourth electrical terminal as `bulk`; the
default three-contact glyph has no represented B endpoint. The proof does
not establish a B landing, complete wire/junction topology, text clearance,
or Schemify round-trip equivalence. The forced below/right arrangements
have long interfaces and large blank spans. In the invented tail views,
`vb3` text touches or is crossed by its core gate line. A successful pose
request is not a complete drawing-quality pass.

Independent arithmetic on the saved report metrics reproduces the peer's
crossings-then-bends diagnostic: AG1028 below wins `(0,8)` over nested
`(2,8)` and right `(2,6)`; AG364 nested wins `(0,2)`; the tail nested pose
wins `(0,4)`. These are comparisons of reported counts, not an independent
crossing detector or production acceptance gate. The AG1028 winner differs
from its observed horizontal source arrangement. That contradiction is a
useful reason to retain source-informed negative controls before adopting
this diagnostic as policy.

## Retained failures and repaired inventory admission

The original `check_actual` filtered expected names and then built a
dictionary. It accepted both an appended copy of `M1` named `m_extra` and a
duplicate `M1` record. The archived original checker and exact mutated
documents are retained under
`.objective/human-schematic-equivalence/runs/iteration21-resume1/image-rule-round-2/bodies/tenth-review-arrangement/`.
Its original SHA is
`0b0c9aa317e4d25b3765ab5e28efc06cb8f8e29d5aca7702766abd69af6639e2`.

The repaired checker rejects duplicate document identities and unexpected
non-generated devices, and validates the admitted generated marker record
shape before comparing all raw devices. Independent replay shows both
retained attacks fail under the repaired checker while all eight originals
pass. Additional independent validator mutations reject changed actual
bulk, swapped G/S role names, one shifted actual contact and an extra MOS.
No native output or historical evidence was rewritten to hide the failure.

## Source geometry is a frozen-original subset

The ninth source helper transforms actual channel-stub vertices, associates
instances through cached centers/types, and checks cached D/S agreement. It
does not admit SVG visibility, display or CSS semantics. This review changes
only AG1028 M1's own stub
`-4.244186,-6.976744 10,-6.976744 10,-20` to
`visibility="hidden"`. The helper still returns the original vertical
endpoints `[(80,120),(80,160)]`. The exact mutated SVG, helper hash and
result are retained as `hidden-stub-probe.json` and
`ag-1028-hidden-own-stub.svg` in the review run directory.

The original images were actually viewed and their coordinate claim remains
valid within that frozen evidence. The helper must not be promoted to a
generic visible-ink certificate for edited SVG. It also does not certify
full glyph/wire ownership, text-to-instance identity, source author intent,
or full parent physical continuity. The separate eighth visibility proof
covers four external-body examples, not these 12 ninth source cases. Keep
this limitation explicit; no generic CSS implementation or retrospective
ninth artifact rewrite is required by this review.

## Acceptance-plan resource vocabulary

The final reviewed [tenth acceptance plan](tenth-acceptance-plan.md) now uses
the [tenth search contract](tenth-search-contract.md)'s outcomes:
`complete_none`, `complete_unique`, `ambiguous`, `unsupported`, `exhausted`.
`incomplete` describes coverage, and allocation failure is a separate
operating error. Single-core keep is not a uniqueness result. Two distinct
valid complete witnesses suffice for an ambiguous uniqueness decision; a
single witness or no witness requires complete search or another sound
certificate before asserting uniqueness or absence.

The plan preserves the whole-map scope: global ambiguity or exhaustion
does not refute every narrower local owner. A future anchored collector
needs its own complete membership/interface and competitor certificate.
The old 257-map high-water behavior is retained as research evidence;
pre-append capacity checks are a proposed production contract. No Python
timing or tree count becomes an invented production fuel limit.

The final [arrangement plan](tenth-arrangement-plan.md) also correctly
distinguishes arrangement optimization from ownership uniqueness. A bounded
arrangement heuristic may choose an already proved feasible complete
proposal without claiming global optimality, provided it names its policy,
records incomplete candidate coverage, honors every hard gate and retains
whole-proposal rollback through W. That permission does not allow an
incomplete ownership search to publish a unique owner. Its proposed owner
enters before global columns/wrap, while the ordinary incumbent remains an
independently prepared alternative. Its separate local axes preserve the
raw mate relation and cannot silently replace an admitted caller global
axis. These are proposed production contracts, not behavior established by
the eight exact caller-pose controls. No further substantive disagreement
remains after the inventory repair and explicit source-geometry scope.

Replay from the repository root:

```sh
python3 -B docs/research/image-rules/round-2/tenth-review-arrangement.py --check docs/research/image-rules/round-2/tenth-review-arrangement.json
```

The review changes research artifacts only. Engine, plugin, frozen CLI and
source-corpus bytes remain outside its write scope.

After this review, the peer clarified that retaining the incumbent does not
count as G1 success when it fails the promised organization postcondition,
and added a raw-model-derived selected-class assertion and its negative
control. Both changes were independently read and accepted. The parent
authorized a provenance-only refresh: the prior review JSON is archived as
`review-before-final-peer-delta.json` in the review run directory, with its
exact hash in `review-provenance-refresh.json`. The current review replay
updates reviewed-document hashes only; retained failures and observations
are unchanged. None of the eight caller pose witnesses proves accepted G1
organization improvement.

The root subsequently exposed PNG date/time chunk nondeterminism in a fresh
native replay; all native JSON, SVG and report bytes remained unchanged.
The peer's [raster proof](tenth-arrangement-raster-proof.py) retains the failed
comparison and shows deterministic rerenders with unchanged decoded pixels
against the archived root replay PNGs. Earlier original PNG bytes were
overwritten and are unavailable; only their old manifest hashes remain.
This reviewer read the repaired recipe/proof and actually viewed all eight
normalized PNGs again before updating the view hashes. The preceding review
JSON is archived as `review-before-raster-refresh.json` with its hash in
`raster-review-refresh.json`. The acceptance-plan update linking the completed
eleventh census was also read; its resource and admission boundaries are
unchanged. These are transparent provenance updates, not erased failures.
