# N0: implement one complete two-part output contract

Keep the existing two-part drawing API. Add a concrete cold N0 collector and
caller-owned pair transaction, then validate the result through the existing
rewiring/thinning loop and export. The first experiment changes routing at
current final poses; it does not move a device or claim to solve G1 arrangement.
Its finite visible finish line is the six source partitions in
[next-implementation.md](next-implementation.md), including the retained cycle
and caller keeps. A geometric decline is safe but does not complete that goal.

This is a proposed implementation contract, based on production source reads.
No engine edit, build, new CLI execution or host run was performed for this
note. The [eleventh census](eleventh-partition-candidates.md) is executed
research: four complete raw parent tuples, six acyclic source 2+1 nets and two
cyclic continuous nets. The integration and new tests below remain prospective.

## Caller first: exact phase order

The native selected-cell producer and plugin cell producer first supply O0's
validated cold context: original model declarations, selected formals and
original admitted caller provenance, bound to the exact resulting netlist.
Borrow its ordered four-terminal cards and parameter slices. The
[tenth acceptance plan](tenth-acceptance-plan.md) defines this boundary. A
normalized `Netlist.models` table, generated `b<s>` name or synthesized role
line cannot recover the lost authority. Missing context declines only the
experimental collector, leaving ordinary drawing available.

Collect the complete raw reflected tuples before caller/class/pose eligibility.
Keep AG1053's parents, reflection and interfaces even though O0's initial
arrangement disposition is `decline_control_cycle`. The initial N0 policy then
requires the complete acyclic cohort. Do not turn that eligibility decision
into an empty raw candidate list. Exhausted global search is not a unique-map
certificate and does not prove every possible narrower local owner ambiguous.

Resolve requests from the original source before scaffolding clears effective
routes, before `keepAts` changes its mutable pose slice, and before thinning
changes effective styles. Retain the resulting candidate dispositions; do not
delete a competing same-net candidate because its geometry or request later
declines. The first trial rejects unsupported custom contact geometry and
incompatible original intent; it never replaces their actual classes or poses.

The existing order in `sketch.drawValid` is useful:

1. `pinned.read`, class/orientation selection, `netlines.read` and structural
   verdicts provide original admission evidence. Qualify the N0 requests here
   against complete O0 context, independently of any subsequent placement.
2. Existing lattice, local placement and compaction run unchanged for the
   initial N0 trial. Pass an empty N0 execution slice to the scaffold `wireUp`.
   This deliberately makes no claim that compaction reserved room for N0.
3. After `keepAts`, each final `wireUp` recreates actual device nodes/pins,
   selected-class boxes and hidden contact obstacles. Map N0's immutable
   endpoint identities afresh at these exact poses.
4. In `wires.wire`, caller routes/vias and ordinary rails keep their priority.
   At the existing after-rails, before-ordinary-signals boundary, execute the
   qualified N0 tuples alongside the specific CT/linked-load consumers.
5. Complete final routing, ordinary thinning/rebuilds and independent physical
   validation. Only the stable final pass can report N0 success. `Placed` and
   the plugin translation then receive final-output gates of their own.

Update the `seeded` predicate as well as adding the call: currently it tests
the presence of loops/load/four-side owners. Merely adding `n0.parts` inside
that block would skip a MOS-only N0 case when the older owner slices are empty.
Do not bypass a nonempty `first` list to reach this scheduling point. For this
first contract, any admitted `first` list declines the automatic N0 tuple,
matching the existing specific-owner boundary rather than overriding order.

The first trial intentionally draws N0 only after compaction. If those poses
cannot route all six targets, record the actual obstacle and move to a bounded
G1 proposal with N obligations already supplied. Once a proposal changes
coordinates, its A/F/H/W validation and whole-arrangement rollback are required;
the initial route-only integration is not a substitute for them.

## Concrete caller usage, not a new framework

The following is design pseudocode, not a proposed public API or compiled Zig:

For the first native experiment, its outer caller is the existing staged
diagnostic/test caller. Runtime additions are the bounded raw/actual mapping,
pair transaction and thin-withdrawal integration. The independent final
`Placed` conductor/name check is an **acceptance oracle**, not a mandate to
embed the research SVG reader or a full netlister in normal rendering. That
caller can retain cold identities while invoking the existing parse/layout/
`Placed.init` stages and write an artifact only after its check succeeds.
The plugin post-translation checker and actual same-build host netlisting are
also acceptance tests; the host is never called by the renderer.

```text
raw = collect_complete_parent_context(original_context, nl)    // O0; no mutation
tuples = collect_raw_reflected_stack_tuples(raw)                // all competitors
eligible = qualify_n0(tuples, raw, original_admitted_requests)
frames = existing_placement_and_compaction(...)                // unchanged first trial

withdrawn = empty set owned once by the outer caller
for attempt in 0 .. eligible.count + 1:
    styles = copy(original_effective_styles_with_shelf_cuts)
    wipe_generated_drawing()
    for ordinary thin round:
        wireUp(frames, styles, original_requests, eligible - withdrawn):
            map original device pins; draw admitted paths; draw rails
            for tuple in canonical owner order:
                if both nets are eligible in this effective pass:
                    trial_tuple(c, tuple, original_pins_of, drawn, labeled)
            ordinary signals, ordinary mirror handling, late routes
        validate each successful tuple against all final Schematic ink
        proposed_styles = ordinary_thin_result(styles)
        if any tuple failed or either sibling would become label:
            withdraw every affected tuple; restart from original styles
        if thin stopped: finish
        wipe_generated_drawing(); continue with proposed_styles
    if no withdrawal:
        build Placed; validate its actual partition and names
        if validation fails: withdraw affected tuple(s); continue
        break

return the drawing plus separate candidate/admission/final N0 diagnostics
```

Every restart must newly withdraw at least one tuple. Thus there are at most
`C + 1` full attempts for `C` eligible tuples; keep the existing bounded thin
round count inside each attempt. Never silently retry the same failed tuple.
The outer caller retains this same set across whole layout/`Placed` attempts;
entering `drawValid` again cannot reset it. A later translator retry shares it.
Do not reset a withdrawn tuple on a later round. Original styles include the
existing shelf-derived cut initialization, recomputed from the unchanged
frame, rather than the styles left by the failed N0 trial. This avoids retaining
thinning decisions caused solely by a withdrawn route. Other surviving N0
tuples may still change ordinary routing competition; this is not a promise
that every unrelated wire has byte-identical coordinates.

The implementation may process all failures in one restart. It must not allow
unbounded geometry search, choose observed constants such as six as a capacity,
or treat an allocation error as a semantic decline. OOM propagates through the
existing operating-error channel after the live append transaction restores
its rows. The caller decides whether an independently retained old drawing is
returned; N0 does not invent an OOM-to-success fallback.

## What the two real consumers establish

[`ct_four_wires.parts`](../../../../src/ct_four_wires.zig) and
[`resistor_downstream.parts`](../../../../src/resistor_downstream.zig) both
borrow a qualified owner, recheck original requests, map the complete net to
actual selected-class pins, reject prior same-net segments, call
[`wire_parts.draw`](../../../../src/wire_parts.zig), then publish `drawn[net]`
and `s.labeled[net]`. CT uses two nonempty parts with up to six original pins;
linked-load uses exactly a local two-pin part and a remote gate. Both permit
ordinary cut behavior and decline when the effective style is `label`.
Their existing per-net independence remains unchanged.

`wire_parts.draw(c, net, local_drains, remote_gate, .name)` already expresses
N0's 2+1 result. It uses ordinary trunk competition and ordinary names, checks
cross-part contact, and rolls back newly appended rows on decline/OOM. There
is no need for an N-part API, routing callback, new terminal kind, changed cost
model or new hot `Netlist`/`Schematic` field. The two prior consumers justify
retaining this small seam; their different selection and retention rules do
not justify replacing them with a general policy registry.

The minimal new ownership is a concrete `n0_parts` consumer and cold request /
result slices carried through `sketch.wireUp` and `wires.wire`. The experimental
caller owns their storage through final `Placed` construction; `drawValid`
borrows them and records routing-round decisions/withdrawals in that same
caller-owned set across rebuilds;
`wires` owns scheduling and the current pass's `drawn` table; the N0 consumer
alone writes its tuple's route decision. `wire_parts.draw` and `thin.name`
need no new parameters for this first design. A thin-induced withdrawal is
handled by their caller, not a silent crossing-budget exemption.

There is already duplicated actual-pin metadata checking in CT's `actual`
and linked-load's `map`. If factoring is useful in implementation, these two
existing callers justify one concrete free helper accepting the expected
device/index/net and returning its verified actual point. Preserve their
behavior and tests. Such a helper proves selected terminal metadata against
the routed point; it does **not** by itself prove an actual glyph lead, custom
class semantics or whole-net completeness. Those remain separate K and
consumer obligations. Factoring this helper is optional, not a prerequisite
for N0 or a reason to grow its API.

## Complete mapping before any handled flag

For each sibling net, reconstruct the complete raw incidence from O0: exactly
`P.D`, `N.D`, `outside.G`, with no fourth body/source/passive/control occurrence
and no outer formal. Recheck all declared model/parameter/rail/body/control
and reflected outside-owner relations. Do not replace complete incidence with
the current visible `pins_of` length. Different presentation policies may omit
logical pins, but that cannot erase an extra raw endpoint.

Then require exactly three original visible pin rows, each mapped once:

Both current net roles must be `.internal`, with no port/rail presentation
request. Raw privacy alone does not establish the current presentation role;
an admitted role/port request can make this automatic consumer ineligible.

* The raw device and ordered card index match the request and selected class.
  Indices are D=0 and G=1; B=3 stays an electrical binding, not an invented tip.
* The device is kept; the class shows this terminal; it is not a reference pin.
  Class side under actual orientation equals the current pin side.
* `canvas.pinAt` equals `device_origin - grid + orient(class_terminal)` using
  checked wide intermediate arithmetic. A projected copy-node contact with a
  different actual endpoint declines, even if the device origin looks right.
* K certifies the selected class's own lead and ordered role. For the initial
  default MOS experiment, bind the current class/stroke contract. A caller
  custom class is preserved and declined unless it has its own complete
  capability; matching a class name or terminal count is insufficient.
* Every expected raw device occurs exactly once in the actual artifact and
  has the expected selected model/polarity and complete ordered D/G/S/B plus
  parameters. The repaired eleventh inventory/class controls are regressions.

Reject already routed/drawn nets, an original request that reserves either
net, or any existing same-net route/segment or generated name/pin before the
trial. Scan the current Canvas as well as `pins_of`: that table was assembled
before later generated leaves. This conservative empty-net requirement avoids
pretending the append-only drawer can replace or separate arbitrary prior ink.
It does not restrict unrelated prior nets or suppress their obstacles.

Once the request is mapped, `a=[P.D,N.D]` and `b=[outside.G]` cover the entire
net. Precheck coincident cross-part contacts. Draw both components and verify
the resulting local D/D path, both absent D/G paths, and one correctly bound
new name attached to each component. Every other reachable name must agree.
Names do not join the physical-component graph: build conductor components
first and decline a marker touching two unjoined components. Preserve the
root's undotted-X/label regression, actual-dot, T and overlap keeps.

Inclusive same-net X contact is forbidden inside an N0 separation: the current
`dots.find` emits a junction there. The source/native proof's undotted-X test
protects the independent checker from making a false join; it does not grant
the router permission to rely on an undotted same-net crossing.

## Three transaction scopes, kept distinct

**One net.** `wire_parts.Checkpoint` saves six append lengths: Canvas segments,
points, routes and nodes, plus Schematic pins and xy. It restores those lengths
and rebinds `s.xy` after possible allocation movement. Existing rows must not
change while it is live. `Canvas.Checkpoint` alone is insufficient for generated
symbols because `Canvas.restore` asserts nodes were already restored.

**One reflected tuple.** The first N0 policy requires both sibling nets. Map
both before drawing, take one outer `wire_parts.Checkpoint`, then invoke the
existing per-net drawer twice in canonical net-rank order. No unrelated draw
runs between them. Keep `drawn`/`labeled` unchanged until both routes and both
physical/name checks pass. If the second fails, restoring the outer checkpoint
removes the first net's newly generated tree and names too. Only then can the
caller resume ordinary routing. An incompatible admitted caller request on
either sibling declines the whole automatic tuple; the explicitly requested
sibling still uses its ordinary admitted caller path. Invalid or rejected
caller text supplies no authority and does not by itself block N0.

```text
mapped = map_both_complete_nets_or_decline(tuple)
saved = wire_parts.Checkpoint.take(c)
committed = false
defer if not committed: saved.restore(c)
for each sibling in canonical order:
    if not draw_two_parts(sibling): return declined
if not complete_pair_physical_and_name_oracle(c, mapped): return declined
for both sibling nets: drawn = true; labeled = true
committed = true
return trial_success
```

The checkpoint does not save handled/labeled bits, pin homes, class IDs,
orientations, existing xy values, route contents, verdicts, compaction data or
structure tables. Deferring those two publication writes makes the local pair
transaction valid without expanding the checkpoint. It is unsafe to mutate
any of those other existing rows and assume truncation restores them.

**Whole changed arrangement.** The first N0 trial changes no pose, so a full
generated-drawing wipe/rebuild can withdraw a tuple at the same device frames.
For future G1, a mandatory N0 failure invalidates the complete affected
arrangement proposal. The current append checkpoint and `sketch.wipe` are not
an arrangement snapshot. `power_compact.squeeze` explicitly permits an error
after one coordinate axis has changed. No existing seam read here provides a
complete arbitrary pose/route/metadata rollback. Use the G/A-owned scratch
proposal and retained incumbent, or explicitly snapshot every table that the
proposal can write before applying it. Do not publish a moved half-pair and
restore only the last net's ink.

## Retain the D/D tree through thinning and export

Current `thin.name` changes automatic internal nets `auto → cut → label`; a
cut net advances only when a physical part exceeds its crossing limit. It
also advances the mirror mate where eligible. The current CT/linked-load
consumers intentionally allow a later label round to use ordinary labels.
That is their contract; it cannot be used to report N0's lost D/D tree as a
success.

N0's required local tree is allowed in `auto` and `cut` passes. The caller
must redraw its exact 2+1 request in either style. If ordinary thinning would
advance either sibling to `label`, withdraw the entire N0 tuple and rerun the
ordinary path, or reject its mandatory moved-group proposal. Do not pin its
style at `cut`, increase `cross_max`, omit it from crossing counts, or override
a caller's explicit `label`. A later clearance failure similarly withdraws it.
No declared N0 success survives a missing D/D path or added D/G contact.

Recompute maps after every wipe: pin and generated-node handles are transient.
Both siblings are drawn before ordinary signals, so ordinary mirror replication
must see both `drawn` bits and skip them. If the tuple declines, no stale mate
flag may suppress its ordinary route. Validate after the late `routes.draw`
and `joinRouted` phase, not merely at `wire_parts.draw` return.

`Placed.Builder.run` copies routes and may add connectors between routed pin
points and selected terminal endpoints. It also constructs dots, terminal
symbols and labels. Even though the N0 mapper rejects a projected endpoint,
validate the final `Placed` graph rather than assuming no exporter effect.
The plugin's `layout.translate` maps complete ordered pins, merges wire
segments, copies labels, adds hidden-body marks and may add stray/default
names. Its `nets_wired` statistic asks a whole-net question and cannot certify
2+1. Inspect actual translated wires/marks and the target schematic, with both
positive and negative physical relations independent of electrical netlisting.

There is a concrete missing retention boundary here: `root.stages` currently
calls `layout`, then calls `Placed.init` after `sketch` has returned. A local
`drawValid` scratch slice cannot support that later check or a replay request.
The diagnostic cold caller context must retain immutable N0 endpoint/tuple
identities and decisions through `Placed`, then through plugin translation for
that test caller. These identities suffice for acceptance tests; ordinary
rendering need not retain a second geometry model. Keep transient pin handles
out of this context. Use the same monotone withdrawal budget if a final
`Placed` failure triggers a rebuild at unchanged
frames; if the caller cannot retry, return a distinct validation failure and
do not publish N0 success. A failure with no attributable remaining tuple is
a validation error, not an excuse for a retry that makes no progress.

Likewise, a failed post-translation acceptance check cannot certify plugin
completion or promote the proposed artifact. If such a validator is later
adopted as a production runtime gate, its caller must not commit the known
broken proposal: the plugin caller can withdraw the affected tuple and
rebuild/retranslate within the same finite attempt budget,
or abort that proposal with an explicit validation result before target writes.
For a mandatory moved owner, restore the entire proposal's incumbent instead.
An actual host validation performed later is a separate acceptance gate; a
failed host gate blocks promotion rather than retroactively certifying the
already-produced native output. No universal ABI growth or hidden retained
Schematic flag follows from this concrete cold-context requirement.

## Six data answers and capacities

1. **Transformation.** Borrow the O0 complete parent/reflection/interface rows,
   immutable raw ordered pins/parameters, original admitted requests and current
   selected classes/frames. Emit cold qualified tuple identities and per-attempt
   decisions; append ordinary named ink only after complete mapping. Raw cards,
   net identity, device classes and poses are unchanged by N0.
2. **Population.** For N admitted four-terminal MOS devices there are 4N raw
   occurrences and at most 4N used nets. Parent membership partitions N devices.
   Each qualifying parent owns four distinct devices, so candidate tuples
   `C ≤ floor(N/4)`. Each tuple owns two distinct output nets with exactly three
   raw occurrences: at most 2C net requests, 6C endpoint references and 4C new
   name nodes/pins/xy rows for successful output. Complete incidence establishes
   that different admitted tuples cannot claim the same private drain net;
   reject competing claims before filtering rather than relying on this count.
3. **Widths.** Reuse typed u32 device/net/owner handles with their existing
   sentinel and checked population bounds. MOS role indices span 0..3 and fit
   u2; fixed pair/endpoint counts need no general index width. Slice lengths,
   capacities and six checkpoint counters use usize. Check products/additions
   before allocation and conversions before append; do not reserve the sentinel
   as a valid handle. A small closed cold result enum needs only its stated
   range; there is no new flag in a hot net or device record.
4. **Access.** Collect once in canonical parent order; qualify against original
   facts once; map and draw complete pairs in each final routing attempt. Use
   separate arrays for owner handle, the two output nets and each P/N/outside
   device pair if storing resolved identities; borrow complete O0 context
   instead of copying all 4N incidence solely to resemble the research JSON.
   Per tuple, stack scratch is six pin handles and six actual points; routing
   reads all of that tuple together. No per-pin dynamic dispatch is required.
5. **Lifetime.** Original context and O0 records live through the draw call;
   qualified tuple identities and withdrawal/results live across its rewires
   and through the caller's final `Placed`/translation checks.
   Actual pin handles/coordinates and append checkpoints live for one Canvas
   attempt. Canvas/Schematic own output allocation. No pin-handle cache survives
   `wipe`; no graph or class geometry cache is retained by N0.
6. **Parallelism.** Raw per-parent candidate analysis can be partitioned after
   the complete ownership certificate is fixed, with canonical merged results.
   Shared-net conflict resolution and Canvas routing cannot be independently
   parallelized: earlier wires affect later costs/clearance. Preserve the
   deterministic serial canonical route order. One/N job byte equality remains
   a future gate, not a new speed claim.

The output bound also follows from the current drawer, not the six observed
nets. With p pins, `trunkLines` emits at most `2p−1` line rows: k paired rungs
give 3k rows, the remaining p−2k pins give at most one each, and p−k trunk ends
give at most p−k−1 linking rows. Each Line has at most six points. For N0's
p=2 local part, this is at most three line rows, plus at most one local-name
stub and one remote-name stub: five Route rows, seventeen segment rows and
twenty-four Canvas point rows per net, including the two leaf marks. Two
symbols add exactly two nodes/pins/xy rows. These are conservative bounds for
this exact `.name`, internal-net path; retain dynamic allocation or prove any
fixed capacity against the actual code before adopting it. A future drawer
change must update the derivation and tests, not silently reuse the numbers.

The outer pair checkpoint stores only lengths, so its rollback storage is
constant. Rewiring scratch remains bounded by the existing drawing population
plus the above appends. O0 uniqueness search has its own non-linear work limit
and explicit `exhausted` outcome; `C ≤ N/4` is not a bound on proving uniqueness.
Any proposed runtime fuel limit must include initial validation, candidate
construction, mapping, route candidates and final component checks. Observed
research search costs cannot set that limit.

## Exact first gates and finish line

| Gate / fixtures | Independent expected relation | Required result |
|---|---|---|
| O0 plus raw N0 census over all 2,202 | Eleventh exact four tuple identities and complete records; all prior dispositions retained | No geometry or caller filtering changes raw membership. |
| AG1079 RN/RP; AG1080 RN/RP and FN1/FP1 | Six literal D/D joins and twelve absent D/G joins; exactly two actual physical components with correct attached names per net | All six pass after final native layout for the native milestone; actual target geometry is a separate completion gate. |
| Cyclic AG1053 net1/net3 | Both source/native three-endpoint continuous trees | Keep raw tuple visible; decline initial N0 policy; ordinary output retains these relations. |
| AG1080 `wire fn1` / `label fn1` | One three-pin tree / three named singles from the saved actual caller controls | Preserve caller authority; decline automatic FN1/FP1 tuple. |
| Extra raw gate/body/passive, exported outputs, wrong model, private source, unknown control | Eleventh exact seven near-miss outcomes, surviving unrelated tuple identities | Reject only according to complete declared scope; no filtered competitor. |
| Raw rename/card order and permuted visible-pin order | Identity transport from literal roles/model/formal/rail facts | Same candidate/partition relations; canonical order determines routing. |
| Extra/duplicate actual MOS, wrong selected class, swapped terminal roles | Complete actual inventory against raw ordered D/G/S/B and model schema | Reject; retained eleventh red-before-green proof attacks become regressions. |
| Missing/extra/hidden/projected/wrong-index pin; conflicting own contact; prior same-net ink/name | Complete raw-to-actual endpoint bijection, independent own-lead and final component oracle | Decline before publication; no missing endpoint or accidental old/new join. |
| Second sibling fails after first tree/name succeeds; every allocation failure | Literal saved prefix of all rows plus both handled/labeled states | Exact pair rollback; original rows and earlier independent successes survive. |
| `auto→cut` then `cut→label` pressure; mirror mate pressure | Positive D/D tree and both absent D/G paths, plus original crossing policy | Retain exact2+1 in cut or withdraw tuple; never silently call three singles N0 success. |
| Caller route/via/first/role/side/class/strong/weak pose, including scaffold deferral and default-looking admitted intent | Original request provenance and final caller geometry/partition, independent of report summary | Preserve authority; initial unsupported cases decline N0 while ordinary semantics remain. |
| Moved group with late mandatory route failure | Full proposed/retained poses, classes, reservations, pins and routes | Whole proposal rollback; append rollback alone fails this gate. |
| CT and linked-load current consumers | Existing named raw/actual/rollback tests, their own ordinary cut/label semantics | No change in selection, draw API, retention policy or same-build before/after outputs. |

First capture an unchanged **current-worktree build** baseline for O0/N0 tests;
the frozen bf7b artifact has an older compiled rule set and is historical
evidence, not the byte baseline for current 84-rule code. The old frozen six-net
failures still supply independent expected bad relations. Test oracle red
controls directly: delete the local D/D path, add D/G bridge, add a foreign
reachable marker, and add an ambiguous undotted-crossing name. The oracle must
reject each before its success result is trusted.

Separate same-build target gates require the target caller's complete cold
context, import of the two positive circuits, the cycle keep and exact caller
variants with the candidate plugin, and inspection of their actual records,
coordinates and marks. All six actual target conductor/name partitions must
pass independently, followed by netlisting and comparison of complete ordered
device bindings and parameters as well as electrical equivalence. Do not substitute
native JSON, `nets_wired`, a report saying honoured, or an older plugin/host run
for this result. Custom-class/hidden-body cases stay explicit declines until
their required capability and identity transport is proved.

The native gallery milestone is all six native positive nets plus the named
native keeps/declines and complete raw ordered identity, with no remaining
mandatory N0 route failure. Target completion separately requires original
cold context, all six actual target physical/name partitions and the same-build
ordered netlist/electrical comparisons above. Target electrical identity alone
cannot complete the physical contract.
Partial success or safe fallback remains useful diagnostic evidence, but is
unfinished visible work. If geometry blocks a target, its named obstruction
becomes the next G1 fixture; changing the candidate set to avoid that case is
not completion. This finite N0 result still leaves other AG1080 physical
partitions and complete page organization outside its claim.

## Small change radius

The proposed implementation touches the cold O0/native-plugin context seam,
one concrete N0 collector/consumer, `sketch` request/result lifetime and bounded
retry, the experimental caller's post-`Placed`/translation validation lifetime,
and `wires` scheduling/signature/seed predicate. It need not change
`wire_parts.draw`, Canvas collision semantics, trunk costs, thin thresholds,
global mate identity, class-cache keys or the public C ABI. If new own-contact
capability is missing, close that specific K proof instead of guessing from a
terminal cache. Tests and final-output checks cover `Placed` and plugin
translation without giving those exporters a second N0 selector.

Three likely changes have named owners: another selector changes its concrete
raw/qualification consumer; another arrangement changes G/F and consumes the
same immutable N obligations; another exporter validates/transports committed
geometry and ordered identity. Neither requires widening the fixed two-part
drawer. General part-count storage, a universal retention flag and arbitrary
snapshot machinery need additional admitted consumers before adoption.
