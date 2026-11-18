# Tenth round: search completeness is part of the ownership contract

A bounded search can return a valid map without proving that it is the only
map. It can also return no useful map before a valid one would be reached.
The ninth research collector correctly declines its whole-map uniqueness
question when enumeration is incomplete. A future local-parent collector
must preserve that distinction at its caller seam; it cannot use the current
native symmetry result as an implicit uniqueness certificate.

This conclusion concerns the **stated search domain**. Exhaustion or
ambiguity of the global complete-map search does not prove that every local
owner is ambiguous. A separate bounded local collector can establish a
complete anchor/member/interface certificate without enumerating every
whole-circuit reflection. Such a collector must prove its own complete
competitor and incidence boundary, rather than inherit certainty from a
truncated global search.

## Executed counterexamples

[The exact Python reference and probes](tenth-search-proof.py) execute an
unchanged snapshot of the ninth collector. Each synthetic pair has its own
full model identity, two MOS devices and four distinct formal signal nodes;
only VSS is shared. Each pair can independently stay fixed or swap. A direct
Cartesian-product oracle therefore gives all `2^k` complete device/net maps
for `k` pairs, without using the collector's colors or backtracking.

| Literal or actual case | Observed result | What it disproves |
|---|---|---|
| `pairs1` | Two complete maps: identity and one useful reflection | Positive complete-unique control |
| `pairs2`, unrestricted | Four complete maps, three useful reflections | First useful reflection is not necessarily unique |
| `pairs2`, state budget 6 | Two stored maps, one useful reflection, incomplete; collector declines | Counting one observed useful map while dropping completeness falsely admits uniqueness |
| AG1078, budgets 28–42 | One useful reflection seen, incomplete; full 51 entries reveal three | The false-unique prefix also occurs on an actual corpus circuit |
| AG1080, budgets 1–47 | No useful reflection seen; full entry 48 yields its unique reflection | No witness before fuel exhaustion is not a proof of absence |
| `pairs3/4/5/6` | Complete sets of 8/16/32/64 maps | Small repeated structures already generate exponentially many alternatives |
| `pairs9`, default map trigger 256 | Stores 257 complete maps, then declines incomplete at entry attempt 786; literal total is 512 | The research map trigger is not a hard storage ceiling |

The full exact maps are compared for every complete synthetic search, and
every returned truncated map belongs to the independent literal set. A
wrong-model mate mutation fails that same validator. The reference also
demonstrates that two distinct valid useful maps are already a conclusive
ambiguity witness even before the remaining search is complete. It does not
call that prefix a complete map census.

For `pairs2`, the two model-defined local questions each retain all their
external interfaces and have no outside nonrail consumer. Each independently
has one complete local reflection despite the global ambiguity. Those exact
local member/interface records are in the evidence. This illustrates the
scope distinction; it does not prove an aesthetic arrangement or authorize
a production selector based on these literal names.

One initial reviewer assertion expected a one-witness incomplete prefix in
both actual circuits and failed on AG1080. The recorded counterexample is
stronger and more precise: its incomplete prefixes have **zero** useful
witnesses. The corrected reference retains the exact prefix-budget sets
instead of pretending the two circuits fail in the same way.

## What the current native contract actually provides

The complete current `symmetry.1–7` header and `find`, `complete`, `consider`
were reread. `symmetry.7` explicitly chooses a bounded search: at most 64
refinement calls and 16 complete candidate maps. `complete` returns when
either budget is reached; `find` returns the best valid found involution or
false. It exposes no exhaustive-search verdict. `consider` selects more
moved devices among the maps visited, retaining the earlier canonical choice
on ties. This is a valid bounded choice policy, not proof of uniqueness or
global optimality over unseen maps. A false result need not prove no map
exists. No native fuel counter was executed or inferred in this study.

The native predicate also differs from the ninth experiment: its initial
device type is kind/polarity/pin-count, and family pin labels allow the
documented unordered path ends. The ninth experiment requires literal full
model/parameter suffix correspondence and ordered MOS D/G/S/B. Therefore
neither its counts nor its search units can be substituted for the native
ones. Keep the current renderer's bounded-choice behavior separate from the
new ownership question; no public ABI change follows from this distinction.

Suggested amendment to `symmetry.7`: retain its bounded rendering choice;
state that a returned best witness is not an exhaustive uniqueness result,
and that an absent witness under a limit is not proven absence. Any caller
requiring complete ownership must receive a separate explicit certificate
or abstain. `symmetry.5/6` remain choice/tie policies, not ownership evidence.

## Cheapest proposed caller seam

Use a concrete borrowed-input collector and a closed cold outcome, with no
callbacks, runtime rule language or function-pointer machinery. Only the
unique outcome can supply a proposed new ownership map:

| Outcome | Required proof and allowed caller action |
|---|---|
| `complete_none` | Supported search domain exhausted with no qualifying map. Keep ordinary analysis; do not claim the circuit has no other kind of local group. |
| `complete_unique` | Entire declared competitor domain checked; exactly one qualifying complete map. Pass its certificate to caller/frame/arrangement admission. |
| `ambiguous` | Two distinct independently valid qualifying maps or owners witnessed. Decline this uniqueness-dependent choice; full enumeration is unnecessary for that decision. |
| `unsupported` | Syntax, complete terminal roles, body/interface policy or caller authority falls outside the declared domain. Preserve the reason and ordinary path. |
| `exhausted` | Search stopped before uniqueness/absence was established. Report the resource reason and optionally the valid witness already found; do not commit it as unique. |

If two witnesses exist before a resource limit, `ambiguous` is already a
valid answer to the uniqueness question. If an exact complete name-set census
is requested, that same prefix remains incomplete. State which output is
being requested. A caller may independently choose a valid aesthetic map by
a documented heuristic, but must not relabel that choice as uniquely proved
membership. Likewise, uniqueness of a partition and uniqueness of a complete
device/net map are different predicates; the ninth collector deliberately
uses the stricter map predicate.

This does not require storing every complete map in production. A
uniqueness-only collector can retain the first valid witness and stop with
ambiguity on a second distinct witness. Completion with one witness still
requires exhausting the remaining search. Borrow the immutable netlist and
caller facts; allocate bounded scratch before mutation; let the ownership
resolver alone commit accepted records. The old global mate table is not a
scratch table for an incomplete local search.

## Resource contract and observed costs

The archived research implementation increments the entry-attempt counter
before its state-limit check and tests `len(found) > LIMIT_MAPS` before the
next visit. Thus budget 6 can report seven attempts, and a declared map
trigger of one can store both maps of `pairs1` and finish complete. The ninth
code and evidence remain unchanged. These are high-water trigger semantics,
not a production fixed-capacity guarantee, and the returned maps still have
correct validity/completeness meaning in these controls.

A production fixed-capacity owner must check available capacity **before**
appending a map or candidate. If no slot remains and the search is unresolved,
return `exhausted/capacity` with no overflow and no committed owner. Charge
work in explicitly named deterministic units before consuming each unit;
distinguish an attempted entry from an expanded state. Input validation,
initial color refinement, candidate construction and allocation also require
their own bounds: a recursive-state counter alone does not bound all work.
Allocation failure remains an operating error to the caller, not semantic
`complete_none`. Neither failure may leave partial accepted ownership.

The saved census contains 86 actual search cases, 1,241 total entry attempts
and 138 returned complete maps. All 86 completed. The maximum is 51 attempts
for AG1078; AG1080 uses 48; the largest returned set has six maps. Exact names,
device/net populations, map counts and dispositions are retained per case in
[the evidence](tenth-search-evidence.json). The other 2,116 corpus cases do
not enter this search after their input/control boundary decisions. These
are observed research counters, not a production worst-case bound, timing
measurement, or justification for setting a production limit to 51 or 64.

For N admitted four-terminal MOS devices, raw terminal occurrences are 4N,
distinct used nets at most 4N, member references N and the parent count at
most N. The bipartite incidence representation has 8N directed adjacency
entries. Those populations can bound structural arrays using checked sizes
and existing typed handles. Search alternatives are not bounded linearly by
N; the independent-pair family proves that. Keeping two witness maps avoids
the research collector's hundreds of retained maps, but does not by itself
bound exploration time. Depth, scratch lifetime and total work need explicit
contracts; Python object sizes or timings are not production estimates.

Already-single-channel-core cases can keep their existing geometry without
proving a new unique reflection. That is a separate keep outcome, not
`complete_none`. A future production trial can avoid an unnecessary global
enumeration for that question while leaving existing mate analysis intact.
Conversely, arbitrary local pruning, selecting only the first raw competitor,
or filtering an ineligible competing member before uniqueness changes the
question and requires a new complete certificate.

## Replay and limits

```sh
python3 -B docs/research/image-rules/round-2/tenth-search-proof.py \
  --output .objective/human-schematic-equivalence/runs/iteration21-resume1/image-rule-round-2/bodies/tenth-search/replay.json \
  --check docs/research/image-rules/round-2/tenth-search-evidence.json
```

The snapshot, seven exact literal decks, source-rule bytes and census input
are hashed in the result. This round changes no production code, ninth
collector, compiled artifact or prior evidence. It does not execute a native
symmetry implementation, choose production fuel, or establish that any
proposed local arrangement is visually correct.
