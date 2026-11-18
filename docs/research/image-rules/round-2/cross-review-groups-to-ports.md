# Adversarial review: port contracts and their placement consumers

This review found three missing boundaries, reproduced them independently,
and sent exact counterexamples to the ports study. Its owner added the
rejections and regression controls. The full candidate name sets remain
unchanged. No production engine was edited or rebuilt.

The reviewed files are `ports_contracts.py/json`, `ports_predicates.py/json`,
`ports.md`, `ports_pose.py/json`, `interactions.md` and
`interaction_candidates.py/json`. Actual current `block_symbols.zig`,
`Library.blockFor`, its output-index callers and `checks.drawnAs` were read
alongside the current human-rule headers. The frozen binary remains the
image baseline, distinct from the current worktree.

## Reproduced gaps and resolutions

| Independent counterexample | Pre-review result | Resolution |
|---|---|---|
| Remove the last AG2212 binding while keeping all nine formals; separately add a tenth binding | `candidate` returned `four_bias_signed` in both cases | Exact binding/formal arity is now checked. The ordinary deck parser already protected corpus calls; the reusable contract boundary now protects itself. |
| Body `(-6,-6),(-6,6),(6,0)` and lead `(-6,0)→(-8,0)→(0,0)→(8,0)` | Initial exit and final body-support checks passed although the lead re-entered the body | Every segment is now split at body intersections and every open interval must stay outside. The source-coordinate rounding allowance is limited to the initial attachment. |
| AG2187 and extended-contract AG2212: bind amplifier VDD to regulated VOUT | Strengthened local-pose screen accepted an extra supply consumer on the regulated output | Conservative automatic pose now declines this interface. It is not a declaration that the circuit is electrically invalid. |
| AG2187/2212: independently export NET0 or FB through the DUT declaration | Internal incidence counts still called the gate/feedback nets private | DUT formals now count as external interfaces and suppress this local pose. |
| AG2658: independently export VCX/junction or negative-input NET0 | Sampling screen likewise accepted externally exposed protected nodes | The same interface boundary now declines those sampling cases. None of the 36 real positives exposes either protected node. |

The last three rows demonstrate one general mistake: private **internal**
incidence is not a complete privacy proof. The outer declaration is also a
consumer boundary. Source pictures need not draw every possible caller
connected to that boundary, so a local owner must explicitly accept the
interface or decline it.

Historical observed results and the pre-fix peer script hashes are retained
in `groups/review-ports-baseline-observations.json`. The earlier successful
peer replays remain beside it. [groups_review_ports.py](groups_review_ports.py)
now independently requires no malformed-contract acceptance, observes all
eight conservative interface mutations decline, and confirms rejection of
the re-entering lead. It does not modify peer files.

## Full composition, checked by names

The independent review scans all 2,202 deck names, compares them with
`index.json`, checks every deck hash against the interaction inventory and
runs the **strengthened** screen with both contract readers. This closes the
composition question left open by the first interaction note:

| Research contract plus strengthened screen | Regulators | Sampling | Exact change |
|---|---:|---:|---|
| Existing complete contract | 39 | 36 | Same complete-corpus names as the old interaction scan |
| Add exact nine-port, four-bias contract | 40 | 36 | Only regulator AG2212 added |

Every old regulator's complete strengthened record is identical under the
extension, and the entire sampling record dictionary is identical. Each
positive also survives card-order reversal and consistent net/formal
transport. These are acceptance relations, not a claim that output record
ordering is itself canonical under every renaming. The earlier converter
assignment remains exactly 39/35; AG789 is the one extra global sampling
keep. The exact symbol-contract census remains three four-bias instances
(AG1242/1674/2212) and four clocked comparators
(AG808/3492/3493/3495), separate from placement candidates.

The raw nine-port AG2212 declaration was independently permuted so output
occupies every index 0–8. Complete role-to-net mapping survives all nine.
The present `analogOutput` return type `?u3` cannot represent index eight;
the plan correctly calls for a bounded index-width change and both compiler
listed placement callers. A cast-only change would leave port limits,
storage assertions, documentation and shared exporter contracts inconsistent.

The actual consumer audit found another index boundary: `bias_neighbors.Pair`
stores `[2]u3`, and `find` casts the amplifier's bias-port index after accepting
its recognized shape. A complete nine-port declaration placing VB1 at index
eight, with that pin attached privately to a valid `BIAS(VDD,VSS,NB)` peer,
satisfies the other raw conditions but cannot fit that slot. The independent
literal probe records both ordered occurrences of `local_control`: amplifier
index eight and peer index two. Recognition must not expose this narrowing
cast. Audit `Pair`, `find`, `turn` and `tip`; the amplifier side needs four
bits while the bounded peer side still needs only three. The current engine
rejects the nine-port shape before this point, so this is a required combined
future regression, not a claimed present crash. The ports owner received the
concrete fixture for inclusion in the plan.

## Actual source/native review

Ten enlarged PNGs were actually viewed again: source and frozen native for
AG2212, AG808, AG1242, AG2637 and AG789. The review JSON records every image
hash, original SVG hash and fresh observation.

- AG2212 supports separate signed-slot policy: positive reference above
  negative feedback, with four bias leads below and supply above. Native is
  a nine-port box with the opposite signed order. Whole-symbol reflection
  would also move the auxiliary leads and cannot implement this policy.
- AG808's source comparator has a bottom clock, while its separate opamp
  has `IB`. Four switches and two blocks remain outside the two-switch
  sampling owner even after recognizing the comparator glyph.
- AG1242's actual EA faces left in a much larger converter. Its four-bias
  contract cannot authorize whole-circuit placement or a universal rightward
  pose. The bent fourth bias is visible.
- AG2637's source has the expected flat sampling path, shunt and upper
  feedback. Native already recognizes the biased triangle but places the
  feedback far left and shunt far below. Symbol recognition alone did not
  grant local sampling placement.
- AG789 is an actual keep: both source and native retain the flat two-switch
  path, junction shunt and upper feedback. It belongs in global validation
  even though it was outside the original converter assignment.

These ten views do not replace the ports study's five detailed source-lead
certificates or imply that the two extra raw-contract matches have equivalent
own-lead certificates. Their scopes remain explicit.

## Implementation plan requirements retained by review

The plan's staged split is appropriate: complete ordered role contract → raw
topology candidates → owner/admission decision → selected signed-slot policy
→ complete actual frame → reservation/placement → one terminal/export table.
The evidence gives no authority to jump from the first stage to the fourth.

Two production fixtures remain necessary before implementation claims:

1. A real electrical deck containing two raw local patterns, with only one
   eligible after caller/visibility checks. The current `automatic(['A','B'],
   eligible)` controls prove the intended cardinality policy, but not that a
   production collector enumerates both embeddings. The existing whole-DUT
   predicates reject a second block and therefore are not that collector.
   A future collector must return both raw tuples before any eligibility
   filtering; both card orders must decline local automatic ownership.
2. Two instances of the same complete block definition, requiring opposite
   signed-slot policies, plus a registered caller symbol and explicit side
   directives. `Library.blockFor` caches `block:<family>` before drawing.
   Mutating a shared class for one instance would alter the other. The final
   per-instance variant or request must preserve original formal indices,
   survive final world transforms and leave caller-owned classes unchanged.

The nine-port feasibility witness establishes distinct, supported tips for
96 constructed frames. It does not yet establish marks/labels at production
font sizes, final reservations, routing, plugin serialization, or electrical
round trip. Those remain explicit acceptance oracles, with output at index
eight and hidden-but-logical VSS among the required cases.

Caller constraints need stage and final geometry checks. A report alone
cannot prove `group`, `symmetric` or `axis`, because `checks.drawnAs` returns
null for them. The local candidate should initially abstain whenever such a
request touches its owner unless a direct compatible-frame proof exists.
Explicit sides, custom classes and strong positions must be asserted on the
actual final ordered terminals and bodies; the symbol recognizer must not
override them to obtain a preferred source-like frame.

The affected rules are `block_symbols.1–2, .4, .6, .8, .10`, the library's
caller-symbol/side and class-cache contracts, `opamp.1–4`, plus the specific
`skeleton`/`bridges` output consumers. `structure.3–6` and `checks.5–8`
constrain caller precedence independently of contract recognition.

## Replay

```sh
python3 -B docs/research/image-rules/round-2/groups_review_ports.py \
  --check docs/research/image-rules/round-2/groups_review_ports.json \
  --output /tmp/cktimg-groups-port-review.json
```

The peer's three original replays and this independent review replay pass.
No universal shape, owner, glyph pose or electrical admission rule is claimed.
