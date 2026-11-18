# Ninth round: a small all-MOS local-parent experiment

AG1080's five parent groups can be recovered from raw ordered transistor cards
without using native coordinates, reported cells or source coordinates. The narrow
collector enumerates the identity and exactly one nontrivial full involution,
forms nonrail D/S components, then joins reflected components. AG928 remains one
core. This gives a concrete first collection experiment using existing MOS geometry;
it does not depend on new block-symbol contracts.

The same full-corpus experiment produces 11 raw multigroup candidates. Fresh views
and actual SVG channel-stub certificates show why they are **not** 11 automatic
disjoint-box admissions: AG1016's groups interleave, and AG364's output branches
surround its inner core. Keep these exact counterexamples. Membership can support
a parent composition without prescribing its arrangement. No numerical size filter
or name-based clock heuristic has been added to remove them.

All work here is unimplemented research. It does not change the engine, compiled
plugin, shipped rules or the existing native baseline.

## Inputs, raw enumeration and boundary

`ninth-local-groups-census.py/json` reads the exact 2,202 names in the corpus index
and compares them with the actual deck filename set. Every record retains complete
ordered raw cards, final DUT formals, model definitions, rail facts and a named
disposition. Only 104 final DUTs contain exclusively MOS cards. This is deliberately
a separate narrow experiment from `groups_candidates.py`'s broader source/resistor
collector; the two outputs are not silently unioned.

The supported input boundary is:

- All devices are literal four-terminal MOS cards with explicit `nmos` or `pmos`
  model definitions and key/value parameters. The complete ordered model/parameter
  suffix must match under reflection. Duplicate model definitions decline; no last
  declaration silently wins. Unsupported declarations, parameterized formals and
  unused final formals decline.
- The deck adapter accepts conventional `0`, `vdd`, `vss` only. Nonzero conventional
  rails must be declared DUT formals, and each rail is fixed individually. This is
  the bounded named-rail policy, not proof of a physical supply voltage. The pure
  collector accepts a separately admitted role map, including its bijective
  renaming. Private nets named VDD/VSS are not silently given rail authority.
- Each MOS body must be on the admitted rail of its model polarity. Private body,
  source/body ties off the rails, alternate wells and alternate supply names decline.
  Every D/G/S/B binding remains recorded. A hidden body pin does not disappear from
  incidence or ownership.
- Any passive, current source, block instance or other attachment declines the
  entire first experiment. No terminal of a rejected card is silently ignored.
  Explicit `*@` lines decline this observational adapter. A future implementation
  must inspect all caller channels, not just SPICE text, before entering this path.

After these checks, form a D/S component for every MOS, joining devices that share
a nonrail drain or source net. Enumerate every complete involution of ordered
D/G/S/B terminals and identical model/parameter suffixes. Preserve final-formal
membership and fix admitted rails individually. Iterative incidence colors prune
the exact search; they do not choose a mapping. The search has explicit state/map
bounds and would decline an incomplete enumeration. No corpus case hits either
bound. The 138 returned complete maps are retained, rather than just a winning map.

Exclude identity-net permutations from the reflection proposal. A multi-component
cell requires exactly one remaining complete device/net involution. More than one
declines even if one might look attractive. Joining each D/S component to its
reflected component creates **parent membership**, not row-pair membership or a
rectangular extent. Already-single-component cells keep their one core without
authorizing any new pose.

Every gate incidence is recorded as an admitted rail control, declared gate-only
input, or channel-produced control. An internal gate with no channel owner declines.
After parent composition, record all inter-parent gate dependencies. Cycles decline
the first serial/parallel composition experiment. The recorded topological order is
one valid serialization of this partial order; it is not a unique physical ordering.

## Exact census and falsifications

| Disposition | Count | Meaning |
| --- | ---: | --- |
| Non-MOS or other input boundary | 2,106 | 2,098 have a non-MOS card; eight additional all-MOS cases have body/formal boundaries |
| Unsupported internal gate ownership | 10 | Internal controls have no supported producer or declared interface |
| No unique nontrivial involution | 29 | 24 have none; five have multiple |
| Inter-parent gate dependency cycle | 2 | AG924 and AG1053 |
| Single D/S core keep | 40 | Includes AG928 |
| One core after reflected-component composition | 4 | AG1037, AG1112, AG1121, AG1154 |
| Raw multigroup candidate | 11 | Complete named list below; arrangement still requires a decision |

The exact candidate names are AG1016, AG1028, AG1046, AG1047, AG1051, AG1071,
AG1075, AG1077, AG1079, AG1080 and AG364. Every other name and reason is listed in
the census's `disposition_names` and per-case records; counts alone are not its gate.
The five ambiguous cases are AG740, AG816, AG925, AG1073 and AG1078. The six body
declines are AG22, AG334, AG1057, AG1065, AG1102 and AG2397. AG236/511 additionally
decline for unused formals.

All 11 candidates and eight controls were rerun using the frozen `bf7b0749...`
native executable. Their SVG bytes match the existing gallery exactly. The 304
complete native device records are bound to the source cards. All 19 new source/
native raster pairs were actually viewed; notes and hashes are in the proof JSON.
This 19-pair detailed scope is distinct from the earlier exhaustive 2,202-pair
visual overview and from this round's 2,202-deck raw census.

The proof extracts both channel lead ends from the actual SVG primitives for all
200 MOS symbols in the 11 candidates plus AG928. Cached coordinates only associate
the primitive and must agree with its actual transformed endpoints. It records all
800 D/G/S/B incidences for these 12 cases. Bounds below are bounds of own channel
stubs, not full glyph, label, conductor or parent ownership bounds.

| Case or group | Source finding | Consequence |
| --- | --- | --- |
| AG1080 | Five parent groups have nonoverlapping channel-stub box interiors | Useful local-parent experiment; independent parent axes remain future geometry work |
| AG1028/1046/1047/1051/1071/1075/1077/1079 | Candidate parents are also separated in the source; several are stacked vertically | Do not infer left-to-right packing from a dependency edge |
| AG1016 | Seven pairs of proposed group boxes overlap in positive area | Five disjoint boxes are a falsified universal policy |
| AG364 | Inner nine-device and outer four-device parent boxes overlap | Preserve nesting or use a larger composed owner; membership need not be discarded |
| AG928 | Source/native retain one stacked core | Single-core preservation control |
| AG1037 | Two mirrored D/S branches compose to one latch | Do not give every D/S component its own independent axis |
| AG924 | Source separates a main core and a common-mode feedback block despite a dependency cycle | Conservative cycle decline has an explicit useful false negative |
| AG1053 | Feedback side branches integrate with the core | Cyclic parents cannot be assumed to form a serial cascade |
| AG459 | Source/native preserve source-degenerated local mates | All-MOS decline protects this native keep; it is not a native membership failure |

AG1080's exact parents are `{M1..M5}`, `{M6..M9}`, `{M10..M14}`,
`{M15..M18}`, `{M19..M32}`. The last is a **parent**: its two-device branches
`{M29,M30}` and `{M31,M32}` are separately drawn and connect to OUTP/OUTN by name.
It is not a claim of one compact box or one continuous conductor. The raw unique
reflection and parent sets exactly match the independently certified current
native reported reflection in AG1080 and AG928. That agreement is checked after
raw collection; the report does not seed the search.

## Smallest executable implementation plan

Start with a collection-only trial. This is the part the evidence now supports
without new symbols or coordinates. Input units are existing device/net handles;
the one owner is structure analysis. Store a parent ID per admitted device, parent
member offsets/members, one typed gate-interface row per MOS, and an explicit
collection disposition. Capacity is bounded by N parents, N member entries, 4N
terminal incidences and N gate incidences. Preserve existing pair/stack rows and
mate identities separately. No parent ID grants glyph, row, wire or physical-part
authority. Unknown syntax and exceeded search bounds leave ordinary analysis intact.

The first trial's output must be directly reviewable: complete raw candidates,
full reflection certificate, disjoint membership covering every admitted device
exactly once, all interfaces, exact decline reasons and the dependency partial
order. Compare exact names and partitions on the whole corpus. Keep the 11 raw
candidate names distinct from any later geometry admission set. Do not choose
AG1016/364 out of the set using a post-hoc numerical threshold.

Next, a diagnostic placement experiment can consume these parent facts using the
existing MOS classes. It must carry multiple composition alternatives—separate,
stacked, nested or larger parent—until a policy can select among them. AG1016/364
prove that membership plus an acyclic dependency graph is insufficient to commit
disjoint boxes. The nine separated examples are bounded experimental oracles,
not an ID-based production selector. No justified universal arrangement predicate
has been established in this round. This unresolved choice belongs in parent
composition, not in unrelated symbol-capability work.

When a composition is admitted, local placement operates in each parent's frame;
whole-circuit placement translates those frames. Keep per-parent axis facts
separate from any caller's whole-circuit axis. Mapped device/pin reflection and
single-core preservation need direct final-geometry checks, not only honoured
reports. A current global `axis2` must not be reinterpreted as a local axis merely
because a parent was found. Apply explicit caller priority before the experimental
path; initially decline it when exact placement, symmetry, axis, grouping, face,
off/nogroup or other relevant caller requirements would need new semantics.
The sixth-round caller controls remain required, including their known native
axis report deficiencies and the published/implemented stack-order contradiction.

Physical routing is later and separately owned. Carry every cross-parent interface
through frame translation; preserve raw ordered nets and each admitted physical
part. A parent can have several physical pieces. No component union authorizes
electrical contact at a drawing crossing, a new label cut, a diagonal route or a
hidden-body rewrite. On a failed placement/routing/caller certificate, restore the
complete ordinary plan rather than leave some transformed parents committed.

Acceptance gates for that future experiment are:

1. Exact raw maps, complete terminal and interface ownership, name-set census,
   unsupported/bounded declines and card-order/explicit-role renaming invariance.
2. The exact AG1080/928 parent partitions, preservation of AG459/701/558/517 narrow
   declines, and the AG1016/364 arrangement counterexamples. Parent membership and
   arrangement verdicts remain independently inspectable.
3. Direct final origins and all actual terminal positions for each admitted local
   reflection, explicit whole-circuit caller relations, no unintended glyph
   collisions, and preserved
   single-core/control geometry. A report-only oracle is insufficient.
4. Native raw binding checks plus a real target round trip for any implemented
   translation. Complete ordered interface checks remain required even when a
   comparator reports equivalence, as the eighth-round empty-PFD control proves.
5. Source/native image review for composition and physical-wire behavior, including
   AG1080's detached side pieces and the vertically arranged positive examples.

Affected existing rules are `structure.1–6` (determinism/caller ownership),
`structure.7–12` (existing pair/stack facts must survive), `skeleton.3/5/7/8`
(links, mates, axes and distinct cells), and `skeleton.9–11/14` (pose is a separate
decision). The proposed parent layer adds facts above these mechanisms; it does
not grant a blanket exception to their current contracts.

## Adversarial review and replay

Literal controls decline asymmetric gate ties, changed model identity, passive
attachments, private body/source ties, unsupported internal controls and explicit
caller hints. Bijective device/net renaming transports formal and rail facts;
card order changes neither admission nor the complete map set. Independent review
in `ninth-review-groups.py/json` validates all 138 maps and compares all 43 cases
with at most eight cards against a separate brute-force permutation oracle.

That review found and repaired three input-authority holes: continuation lines
were omitted from final formals; duplicate models silently overwrote a definition;
and unowned private VDD/VSS names were treated as admitted rails. Preserved literals
now reject an extra continued formal, contradictory duplicate models and removed
rail formals. Moving the original OUTP/OUTN onto a continuation preserves the full
eight-formal contract and candidate. All corpus dispositions remain unchanged.

```sh
python3 -B docs/research/image-rules/round-2/ninth-local-groups-census.py \
  --check docs/research/image-rules/round-2/ninth-local-groups-census.json \
  --output /tmp/cktimg-ninth-census.json
python3 -B docs/research/image-rules/round-2/ninth-local-groups-native.py \
  --check docs/research/image-rules/round-2/ninth-local-groups-native.json \
  --output /tmp/cktimg-ninth-native.json
python3 -B docs/research/image-rules/round-2/ninth-local-groups-proof.py \
  --check docs/research/image-rules/round-2/ninth-local-groups-proof.json \
  --output /tmp/cktimg-ninth-proof.json
```

`ninth-local-groups-native.py --execute` is the recorded frozen-CLI/raster producer.
Saved replay does not count raster generation as viewing. No compiler or build is
needed for any command above.
