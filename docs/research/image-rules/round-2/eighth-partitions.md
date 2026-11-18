# Eighth study: physical distribution needs its own contract

A local placement owner cannot also decide which same-net terminals share a
continuous wire. AG1080 gives a measured counterexample: joining pins by the
five certified device regions would create **45 source-forbidden physical
joins**, even after removing the global-axis problem. AG928's one-core
control has none of those owner-only disagreements. The missing plan owner
is a cold **per-net physical partition proposal**, admitted independently
from device membership and realized through existing routing primitives.
No generic selector or routing implementation is proposed as proved here.

This study replays the previous actual-ink certificates, adds two contrary
cases, runs eleven frozen-CLI caller controls and turns partition/naming
requirements into executable research checks. No compiler, production edit,
wasm rebuild or commit ran.

## Evidence and exact scopes

The earlier [grouping and distribution study](../grouping-and-distribution.md),
its actual-lead/whole-ink negative certificate and dependencies were reread.
The retained certificate replays byte-for-byte: AG1080/928 have 164 complete
raw MOS bindings and 268 same-net visible D/G/S pairs. Source labels never
connect physical paths. Proper source crossings need actual contact dots;
a negative also checks all actual conductor ink so missing cache assignment
cannot create a false separation.

Four source/native pairs were independently rasterized and freshly viewed:
AG1080, AG928, **AG921 and AG1479**. The latter two are contrary cases from
the earlier study, not new cohort members. Seven caller-control SVGs were
also freshly viewed. The [view ledger](eighth-partitions-views.json) binds
all eleven observations to independent render inputs and PNG hashes. The
wide AG1080 pictures are overviews; its detailed pin/path conclusions come
from the actual SVG/JSON certificate.

The [fixture runner](eighth-partitions-fixtures.py) and
[manifest](eighth-partitions-fixtures.json) retain **11 runs and 941 ordered
terminal occurrences across those runs**, including repeated fixtures.
Every complete DUT card and X-call formal/binding order is checked against
actual native JSON, including hidden MOS/BJT body bindings. The four
unmodified native SVGs reproduce the earlier frozen gallery bytes. The
binary is still
`bf7b0749bde5822a68aa93fd9df69eb6e007dee0c24d5e9961ff65b187483560`.

The [partition proof](eighth-partitions-proof.py) and
[result](eighth-partitions-proof.json) preserve complete equivalence classes,
not component counts alone. A partition must cover the named terminal set
exactly once and agree with every positive and negative pair.

| Case | Independently supported finding | Limit |
|---|---|---|
| AG1080 | 255 visible pairs; 105 source/native differences: five lost source joins and 100 additional native joins. Owner-only grouping would still add 45 forbidden joins. | This does not establish an automatic full-context partition selector. |
| AG928 | All 13 visible pairs agree, and one owner does not create extra joins. | Gate-facing and source rail/bulk visibility remain separate contracts. |
| AG921 | New complete 31-pair visible MOS/R check: 19 source-connected and 12 source-separated; nine pairs become joined in native. Main/CMFB membership remains visibly coherent. | Group adjacency is a keep, not proof of matching physical distribution. |
| AG1479 | Eight connected and one separated Q/R pair agree. Complete raw/native bindings, including X1, remain intact. | Nine additional source pairs touching X1 are explicitly unsupported by this source-lead schema. No full partition claim is made for them. |

AG921's nine added joins are concrete: three on VCMC from the remote main
pair tail gate to the local CMFB path, two between the main and CMFB VDD
feeds, and four from VO1/VO2 local drain pairs to remote divider terminals.
This strengthens the earlier correction: distinct groups can remain intact
while their physical distribution changes.

AG1479 remains useful because its resistor/reference core is continuously
wired in both views. A rule that names all inter-device or inter-region
connections would destroy a valid keep. Its nine unsupported X1 source pairs
are a named next-proof boundary, not counted as passing or skipped silently.

## Device ownership does not supply the partition

The AG1080 five-region owner hypothesis is evaluated literally: all visible
pins on one net and inside one region become one physical part. All 45
mismatches are unwanted joins: CLK 10, CLKB 4, OUTP 5, OUTN 5, VDD 12 and
VSS 9. The lower fourteen-device region alone contains a source-separated
outer output branch, so even correct membership needs a finer wire contract.

Useful exact source partitions include:

* `net0`: M1.S, M2.S and M5.D are one tree. Native gives three named pieces.
* `FN1`: M16.D and M18.D share one local tree; M29.G is a separate named
  piece. Native gives three pieces. FP1 has the symmetric obligation.
* `OUTP`: five central latch terminals share one tree; M29.D is separate.
  OUTN has the corresponding five-plus-one split.
* `VDD`: M19.S/M20.S/M21.S/M22.S share a four-pin rail; nine other source
  pins are single pieces. Native has one thirteen-pin bar.
* CLK's nine and CLKB's five source pins are separate in both drawings.
  Naming clocks globally would not repair the actual defects.

These are fixture expectations by stable card-terminal identity, never
production tests on figure IDs, source coordinates or spellings. They show
why a proposal needs both required joins and forbidden joins. A positive
local-tree request alone lets an ordinary later router merge every piece;
a negative-only request can split a required local tail into labeled pins.

## Caller experiments expose a missing representational choice

All seven explicit requests below report honoured/ok and retain the exact
ordered circuit bindings. They demonstrate caller precedence with actual
final geometry, not merely a success report.

| Request | Actual final partition |
|---|---|
| AG1080 `wire net0` | All three net0 pins join, restoring this source tree. |
| AG1080 `wire fn1` | All three FN1 pins join, including the remote gate. |
| AG1080 `label fn1` | Three single-pin FN1 pieces. |
| AG1080 `rail VDD each` | Thirteen isolated supply pieces. |
| AG1080 `rail VDD bar` | One thirteen-pin bar, matching the default-looking picture. |
| AG928 `label VBIAS` | Two gate pieces, each named. |
| AG928 `wire VBIAS` | One gate wire with its written bias name. |

Neither `wire FN1` nor `label FN1` expresses source FN1's **2+1** partition.
Likewise neither whole-net rail alternative expresses the source VDD
**4+1+1+1+1+1+1+1+1+1** split. This does not justify silently overriding
those requests. It identifies a missing automatic internal contract; an
optional future caller partition API would need its own grammar, docs,
validation and exact terminal naming design.

An explicit `rail ... bar` may normalize to the same representation as the
default. Its original admitted request still blocks an automatic rail
partition. Read caller provenance before scaffold deferral or automatic
style mutation; comparing effective styles to defaults loses authority.

## Current owners and the smallest implementation boundary

Current `netlines` owns caller net styles, ports, rails and route order.
`wires` owns actual routing and terminal/name generation. `thin` owns
crossing-budget changes on eligible internal auto/cut nets. They have
separate concerns:

* `netlines.1/.2/.4/.6–9` protect explicit label/wire/rail/path choices.
* `wires.12/.13` choose nearby input/bias wiring versus ports;
  `.17–19` choose nearby cut parts and the whole-part label fallback.
* `thin.3` budgets actual physical components separately, including T,
  overlap and same-net X contact. `.6` excludes rails, ports and caller
  styled nets from automatic thinning. Crossing budgets cannot explain or
  repair the AG1080 VDD distribution.
* `sketch.14/.15` sets cross-shelf internal nets to cut and reruns wiring
  through at most three thinning changes. A shelf or bounding box is not a
  physical-part identity; `wires.parts` still uses pin proximity.
* `dots.2` joins a native same-net X with a dot. A required separation must
  reject that contact before drawing; removing its dot is not a repair.

The dirty current worktree already has a relevant concrete seam:
`wire_parts.draw` atomically draws two qualified parts using ordinary
trunk/leaf operations, certifies a correctly bound symbol on each part and
rejects inclusive contact. `ct_four_wires` and `resistor_downstream` are
independent consumers. They select full contexts, map actual class pins,
check full net membership and original intent, then mark the complete net
handled only after commit. Reuse that boundary where its two-part contract
fits. Do not infer a general context selector from their shared mechanism.

Their thinning policy differs from `power_loop_wires`: CT and linked-load
parts allow ordinary cut/label rounds; the seven certified loop trees are
explicitly retained. A new proposal must state which positive joins remain
mandatory and when a finer named partition is an allowed fallback. A single
new global “protected” bit would conflate existing contracts.

## Complete acceptance gates for a future admitted family

1. **Electrical identity first.** Enumerate every ordered logical terminal,
   including hidden body/reference pins, all external interfaces and custom
   class terminals. Preserve their bindings and formal order. Separately
   enumerate the visible original terminal universe to be partitioned.
   Hidden terminals must not disappear or become invented visible endpoints.
   Unknown terminal schemas, extra controls or ambiguous raw matches decline.

2. **Select a contextual proposal independently of placement membership.**
   Enumerate every raw embedding before visibility, caller or frame filters.
   Distinguish compatible disjoint owners from candidates competing for the
   same net terminal or requested interface. The selector emits typed
   device/terminal identities and the whole net's proposed partition, with
   positive continuity and negative separation obligations. No spelling,
   distance threshold, crossing count or source coordinate chooses a source
   partition. Until a complete contextual census and contrary cases justify
   a family, leave the existing route path intact.

3. **Resolve shared-net composition before geometry.** Collect proposals
   from all touched owners. Check exact complete coverage, duplicates and
   contradictory join/separate constraints. Compatible pieces on a shared
   supply do not automatically union. One consumer may not hide an external
   same-net terminal by marking the net done. Either account for every
   visible original terminal or explicitly compose with the ordinary
   remainder before claiming a complete partition. A one-anchor-per-net
   table cannot represent multiple separated components.

4. **Preserve original admitted intent.** Caller label/wire/rail/port,
   route/via, first-net order, custom pin geometry and held poses take
   precedence under the existing admission rules. A normalized default-like
   rail instruction still counts. Initially decline the complete affected
   proposal when incompatible intent touches it; do not selectively erase a
   competitor or move a held piece to manufacture feasibility.

5. **Map actual final leads, then route atomically.** Verify each selected
   logical index maps to the retained class terminal after the actual pose,
   and to the routing point without an imagined connector. Check raw net,
   visibility, side and own-lead geometry. Use existing Canvas/trunk
   collision rules for each component. Every required join needs an actual
   path; every forbidden join needs absence of endpoint, T, overlap and
   same-net X contact against **all** same-net ink, including earlier trees
   and later mirror replication. Test foreign-pin/body/ink clearance
   independently. Commit a whole net or restore all appended route, marker,
   node, pin and coordinate rows; do not alter caller tables on decline/OOM.

6. **Certify naming per actual component.** After routing, recompute physical
   components from final ink. Each separate component needs a reachable,
   correctly bound name, rail symbol or direction-appropriate port under
   its declared representation. Enumerate all reachable markers before
   checking eligibility: an extra conflicting marker must reject even when
   another correct marker is present. Marker anchors must attach to their
   own component, and visible actual text/shape must agree with the binding.
   Free text near a wire is not an attachment certificate. Labels restore
   electrical identity through the exporter; they never connect ink.

7. **Revalidate after every relevant transformation.** Compaction, outside
   attachments, mirror replication, thinning, target rounding and export can
   change component membership or naming. Recheck the selected positive and
   negative obligations on final ink. If ordinary thinning may refine a
   proposal, report that disposition and do not call the original source
   partition retained. A required local tree either survives under its
   explicit existing contract or the automatic proposal declines; adding a
   blanket crossing exemption is outside this plan.

8. **Check actual export and caller-visible outcomes.** Preserve native and
   plugin ordered terminal bindings, marker net scopes and physical pieces;
   run an actual editor export/netlist comparison with the exact module/host
   hashes. Use an independent ordered-terminal guard as well as electrical
   comparison for opaque empty callees. Retain source physical-pair and
   glyph checks separately: electrical equivalence cannot distinguish the
   FN1 all-wire and 2+1 drawings.

## Data and pipeline plan

Start with an observation/qualification pass that changes no geometry.
Borrow the existing typed device/net handles, raw terminal order, admitted
caller views and successful owner facts. Qualified rows describe nets;
separate CSR ranges describe parts and their original pin references. A
terminal belongs to exactly one row of that net's complete partition. Bound
part rows and pin references by the visible terminal count, and request
rows by the actual contextual candidate count. Use u32 handles and the
already-correct terminal-index width; do not reintroduce the nine-port u3
limitation. Bounds and capacities are validated before allocation or commit.

One cold collector owns proposals; one resolver owns admission/composition;
Canvas owns output ink and generated symbols. The caller owns allocation
and lifetime. No persistent graph or per-segment dispatch is needed. Keep
selection before temporary scaffold intent is removed; map coordinates only
after the actual frames for that draw phase exist. Rails must be partitioned
before the ordinary global bar claims space; ordinary signals follow the
existing after-rails boundary. These are two scheduling points of one
qualified contract, not two independent selectors.

Initially use the existing fixed two-part seam for an independently proved
2+1 or 5+1 context. A general N-part API is justified only when admitted
consumers actually require it; AG1080's ten VDD pieces are evidence of a
missing policy, not permission to hardcode ten routes. If extending that
seam, preserve its checkpoint and exact complete-net mapping obligations,
and make later routing consume one boundary/anchor per physical part.

The concrete change radius is contextual selection/qualification, the
existing wiring consumer seam, final partition/name verification and report
provenance. Ordinary trunk cost, general net roles and global routing search
need not change. A new contextual family changes selection and its literal
certificate; a new pin pose changes only mapping/feasibility; a new net name
changes neither. A new component count may require the bounded row API and
must be stated explicitly rather than hidden in the selector.

## Executable RED gates and unresolved evidence

The research checker validates every exported component/name record in all
11 runs. A valid two-part literal establishes the positive oracle. Fourteen named controls cover missing,
wrong or detached markers, a forbidden same-net bridge, a lost local join,
omitted/duplicated terminal coverage, changed binding, rename covariance and
route/marker order invariance. The positive literal is independent of native
layout; eleven mutations reject, two metamorphic relations pass, and an actual dotted-X keep passes.

Independent review caught a defect in the first native naming checker:
adding a label at an undotted proper X inserted a graph vertex and merged
its two physical components without any wire or dot change. The retained
old script still reproduces that failure. The repaired checker constructs
conductor components first, then associates marker anchors with existing
segment components. A marker touching two unjoined components explicitly
declines as ambiguous; it cannot join them. The same literal with an actual
dot passes as one component. Endpoint/T/overlap joins remain governed by the
physical ink oracle. The root witness is retained under
`image-rule-round-2/root-partition-review/label-crossing-before.json`, with
its script hash and unchanged before/after replay bound in the new result.
No production defect is inferred from this research-checker repair.

Future engine acceptance keeps the exact AG1080 positive/negative pair set,
AG928's 13-pair keep, AG921's membership keep separately from its nine
partition differences, and AG1479's proven subset with the nine unresolved
X1 pairs explicit. Add actual-frame shifted custom terminals, two proposed
owners sharing a net, an ineligible raw competitor, same-net X/overlap,
foreign-body contact, caller default-equivalent rail, allocation failure,
later thinning and target-rounding mergers. Unsupported cannot mean skip.

The old source certificate retains literal label text but does not bind every
free label to a source conductor component. The new native marker check
binds exported JSON anchors; it is not a new SVG visibility or host round-trip
proof. These limits matter: no claim is made that topology uniquely recovers
source label positions or that all named source pieces are already certified
through the editor. Complete those obligations before promoting any source
partition to an engine default.

```sh
python3 -B docs/research/image-rules/round-2/eighth-partitions-fixtures.py \
  --execute --check docs/research/image-rules/round-2/eighth-partitions-fixtures.json \
  --output /tmp/cktimg-eighth-partitions-fixtures.json
python3 -B docs/research/image-rules/round-2/eighth-partitions-proof.py \
  --check docs/research/image-rules/round-2/eighth-partitions-proof.json \
  --output /tmp/cktimg-eighth-partitions-proof.json
```
