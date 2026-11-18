# Fourth ports study: concrete ambiguity, class reuse and caller fixtures

Twenty-nine complete electrical decks were run through the unchanged frozen
native CLI. They resolve the two fixture gaps in the groups-to-ports review
and expose a third planning dependency: the plugin's generated definition
name does not retain the original exact symbol-family identity. No engine
source, compiled artifact, or committed file was changed by this study.

The executable observations are in
[fourth-ports-fixtures.json](fourth-ports-fixtures.json), with full commands,
deck/symbol/output hashes, reports, complete calls and final ordered pins.
[fourth-ports-proof.py](fourth-ports-proof.py) checks literal tuples and caller
coordinates, four full-incidence counterexamples, and six rejected policy
mutations. The frozen binary SHA is
`bf7b0749bde5822a68aa93fd9df69eb6e007dee0c24d5e9961ff65b187483560`.
Thirteen independently rasterized fixture SVGs were actually viewed; their
fresh observations and hashes are in
[fourth-ports-views.json](fourth-ports-views.json). These synthetic views do
not extend or replace the separately completed 734-pair corpus review.

## Cardinality belongs to a named ownership scope

Two disjoint regulators are not inherently competing local owners. The
base [dual-regulator deck](fourth-ports-two-regulators.cir) has these exact
raw tuples, each with its own amplifier, pass transistor and divider:

| Anchor | Ordered amplifier nets: VDD,VSS,INN,INP,OUT | Other owned cards | Protected raw incidence |
|---|---|---|---|
| XA | VDD,VSS,fba,VREFA,gatea | MA, RAU, RAL | fba: XA.INN/RAU.2/RAL.1; gatea: XA.OUT/MA.G |
| XB | VDD,VSS,fbb,VREFB,gateb | MB, RBU, RBL | fbb: XB.INN/RBU.2/RBL.1; gateb: XB.OUT/MB.G |

MA and MB each retain all four D/G/S/B occurrences; their bodies are VSS.
The model is explicitly `nch nmos`. Both references and both ends of each
pass channel are DUT interfaces; fba/fbb/gatea/gateb are private. The two
member sets are disjoint and share only rails. Fixing XB, fixing XA, applying
a caller class to XB, or reversing card order leaves both raw tuples in the
research census. Removing the second circuit leaves exactly the XA tuple.

These fixtures reject the premise of a **single whole-DUT regulator special
case**. They do not specify that a future local collector must reject XA
because XB is fixed. A collector capable of multiple independent stages
must instead check each anchor's competing raw embeddings and the complete
overlap/interface relations. Its decision about XA can be independent of
XB. The prior `automatic(['A','B'], eligible)` abstraction lacked this scope
and must not be promoted into a global rule.

The new research enumerator exhaustively checks bounded four-card regulator
and five-card sampling subsets, then compares protected-node incidences with
the **whole** DUT. Literal expected tuples, rather than counts, are the
oracle. This deliberately simple subset enumeration is not the proposed
production algorithm and does not claim to execute a production local
regulator/sampling collector. Four materialized negatives prevent subset
extraction from hiding another consumer:

- Add CX from fba to VSS: XA loses closure; XB remains.
- Add CX from gateb to VSS: XB loses closure; XA remains.
- Add RX from the sampler's SIN to VSS: the strict private-input sampling
  boundary declines; the regulator remains.
- Rebind MS1.B to regulator feedback fb: the sampler has the wrong body
  binding and the regulator feedback has an extra raw consumer; neither
  tuple remains.

## A same-anchor ambiguity actually exercised in the frozen engine

The [two-bias-peer deck](fourth-ports-two-bias-peers.cir) supplies the stronger
current-path witness. One complete seven-port amplifier has two private
candidate bias peers:

```spice
.subckt opamp VDD VSS INN INP OUT VB1 VB2
.ends opamp
.subckt bias VDD VSS NB
.ends bias
.subckt dut VDD VSS INN INP OUT
XAMP VDD VSS INN INP OUT ba bb opamp
XBA VDD VSS ba bias
XBB VDD VSS bb bias
.ends dut
```

The two raw occurrence lists are exactly `ba = XAMP[5]/XBA[2]` and
`bb = XAMP[6]/XBB[2]`. Neither net is a DUT formal. Both peers have the same
VDD/VSS as XAMP and the complete VDD,VSS,NB contract. The competing tuples
share the amplifier anchor. A fixed XBB remains a raw competitor for XBA;
discarding it before counting would incorrectly produce a unique peer.

| Executed fixture | XBA final origin/turn | XBB | Meaning |
|---|---|---|---|
| Two peers | (290,60), r0 | Ordinary (370,60), r0 | Ambiguous anchor keeps ordinary placement |
| Two peers, `at XBB -30 -30 r90` | (290,60), r0 | Fixed (-1200,-1200), r90 | Fixed rival still prevents automatic XBA placement |
| Same fixed deck, cards reversed | (290,60), r0 | Same fixed pose | Named device geometry unchanged |
| Remove XBB; export remaining VB2 | (100,200), r90 | Absent | Unique XBA turns below the actual VB1 lead |
| Same one-peer deck, family `opaque` | (290,60), r0 | Absent | Disable exact family recognition; ordinary placement returns |
| Unique XBA explicitly fixed | (-1200,-1200), r90 | Absent | Caller position wins |
| Unique XBA, unrelated RX strongly fixed | (100,200), r90 | Absent | Unrelated fixed device does not suppress the pair |
| Unique XBA, XAMP strongly fixed | (290,60), r0 | Absent | Fixed anchor defeats the pair |

Renaming `bias` to `opaque` in both two-peer cases leaves every final device
position, orientation and ordered pin coordinate identical. The one-peer
positive changes relative to its opaque control. Thus an absent pose in the
ambiguous case is supported by a working positive, not merely by two outputs
that happen to look similar. The two-peer fixed variant's report honours
the request, and the final JSON independently proves the requested world
origin and turn.

![Unique peer placed from the actual bias lead](figures/ports/fourth-bias-single-a.png)

Current and frozen `bias_neighbors.find` both test a second raw result
before returning to `collect`; `collect` subsequently checks drawn state,
fixed positions, shelves, mates, groups and admitted requests. The research
filter-first mutant incorrectly selects XBA in the fixed-XBB fixture and is
recorded as rejected. The cross-review also caught an overly global `not
fixed` check in the research admission helper. The added RX and fixed-anchor
decks now prove that only this pair's anchor/peer held state suppresses it;
the final RX origin and unchanged positive XBA placement are asserted.
This is the concrete same-anchor regression for a
future collector. `block_input_rc.collect` provides the analogous overlap
precedent: its overlap scan revisits all raw `find` results, including
competitors omitted by admission. Neither precedent justifies rejecting
unrelated disjoint local owners.

## One definition, opposite per-instance signed-slot needs

The [shared-definition deck](fourth-ports-shared-definition.cir) uses one
five-port `opamp(VDD,VSS,INN,INP,OUT)` definition for both stages:

| Instance | Exact ordered bindings | Local pattern | Conditional source-derived slot policy |
|---|---|---|---|
| XREG | VDD,VSS,fb,VREF,gate | MREG/RUP/RLOW pass-divider | Positive reference above negative feedback |
| XSAMPLE | VDD,VSS,sn,VSS,SOUT | MS1/MS2/CS/CF two-switch/shunt/feedback | Negative signal above positive ground |

The contexts are read from raw topology, not instance names. The named
fixture fields make the oracle readable; the research selectors never use
`XREG` or `XSAMPLE` as eligibility predicates. The desired policies apply
only after their respective local owners are admitted. This experiment
does not authorize placing the entire combined circuit through `opamp.place`.

The frozen default gives both instances `block:opamp`, with canonical INN
at (-60,-20) and INP at (-60,20). XREG therefore fails the proposed
positive-above policy; XSAMPLE keeps its desired default. Reversing device
cards preserves each named device's complete observed geometry. The shared
cache cannot be mutated to fix only XREG: the same class would change
XSAMPLE too.

A registered `caller_signed` rectangle provides an executable isolation
control. Its ordered terminals remain VDD,VSS,INN,INP,OUT, with INN at
(-90,30), INP at (-90,-30), VDD at (0,-60), VSS at (0,60), OUT at (90,0).
`*@ class XREG caller_signed` changes only XREG's class and signed order;
XSAMPLE retains the default triangle. Both desired signed orders now coexist
without changing either net binding or formal index. This proves current
per-instance class assignment can express the distinction; it does not
implement automatic selection.

![Independent caller class with unchanged sampling instance](figures/ports/fourth-shared-custom-reg.png)

The controls also put `caller_signed` on XSAMPLE instead. Its positive input
then stays above its negative input despite the automatic sampling preference.
An inferred policy must decline that caller-owned geometry. Six explicit
mutants fail the literal policy oracle: current default XREG, copying the
changed class onto XSAMPLE, swapping INN/INP net bindings, reordering terminal
records, swapping final input coordinates while leaving the cached canonical
frame unchanged, and vertically reflecting the entire symbol to exchange input
heights. The last moves VDD below the body and VSS above it. Signed-slot
selection changes the positions and marks associated with semantic roles;
it does not change the ordered electrical terminal table or silently set
`Orient.mirror`.
The final-coordinate mutation exposed a research checker gap during peer
review. The checker now recomputes canonical coordinates from the final
transformed pins and requires agreement before checking the policy. Shared
class and whole-symbol-reflection mutants change both actual coordinates
and the derived frame, so they cannot fail merely because of stale metadata.

## Caller precedence is asserted on final geometry

All 29 CLI runs preserve every raw X formal/binding pair, every MOS D/G/S/B
binding and both pins of every R/C. The twelve shared-definition variants
exercise more than report strings:

| Caller case | Observed canonical geometry and ownership |
|---|---|
| Per-instance `class XREG caller_signed` | Only XREG uses the custom complete class |
| Per-instance class on XSAMPLE | Only XSAMPLE changes, even when contrary to the desired automatic sampling slot |
| Registered family class named `opamp` | Both instances use caller geometry |
| Definition `right INN`, `left INP` | Both use generated boxes: INN (40,-20), INP (-40,0) |
| Registered family class plus those side directives | Both retain registered caller geometry; `blockFor`'s registered-family precedence is explicit |
| Strong XREG at (-30,-30), r90 | Final origin (-1200,-1200), rot=1, no mirror |
| Custom XREG plus that strong position | Same requested origin/turn and all five custom transformed terminals |
| Custom XREG at (-30,-30), mr90 | Exact mirrored world frame; other instance unchanged |
| Both instances strongly fixed | Both requested origins and r0 poses retained |

The mixed custom/fixed test has literal final VDD,VSS,INN,INP,OUT points
`(-1140,-1200),(-1260,-1200),(-1230,-1290),(-1170,-1290),(-1200,-1110)`.
Its mr90 counterpart instead places INN/INP at y=-1110 and OUT at y=-1290,
while the supply/ground points are unchanged. These are independent final
coordinate assertions, not an inference from an honoured request report.

Native `Library.blockFor` first uses a registered definition-name class,
then an existing `block:<definition>` cache entry; otherwise it constructs
a glyph or side-directed box. `schematic.initDevices` subsequently resolves
per-instance class requests. Classes are append-only: same-name different
terminal geometry is refused. `opamp.steered` currently disables its
whole-circuit placer when any strong position/turning request appears. A
new local admission rule must state its own touched-member scope rather
than silently inheriting or weakening that whole-DUT behavior.

The CLI also projects DUT formals into weak role hints when their names do
not already select a role. For example SIN is marked output because a MOS
channel drives it. The research census uses literal DUT interface membership,
not those heuristic input/output labels. A future engine rule using
`Role.isPort` must call out this projection, as `bias_neighbors.2` already
does; `sin` spelling is not a semantic input proof.

## Generated plugin names are a separate contract boundary

Actual plugin code reads show four dependent owners:

1. `recognize.boxPins` verifies the original complete family/ports, sides
   and explicit PININFO directions; its generated symbol stores `shape`.
2. `layout.library` registers one engine class `b<s>` per generated block
   symbol. `layout.cellDeck` writes `.subckt b<s>`; named formals survive
   for recognized shapes. Unrecognized BIAS boxes and external project
   symbols instead get p1…pN stub formals, although their registered class
   terminal names and ordered electrical bindings remain available.
   `names.cardOf` writes each X call with that tail.
3. `layout.translate` consumes the engine's result against the recognized
   symbol geometry. Its contract requires actual pin positions to agree.
4. `emit.graphics` draws the recognized shape again through the shared
   glyph generator, while `Parts.sym` selects the symbol per instance.

The [b17 projection fixture](fourth-ports-shared-projected.cir) models that
boundary with a registered literal five-port triangle. All raw ordered
bindings and canonical pins match the original shared-definition fixture.
The two independently rasterized SVGs have zero pixel differences under
ImageMagick's absolute-error metric. Their SVG bytes differ only in the
serialization order of nonoverlapping sign text and lead strokes. Yet the
exact family-based research selectors find no candidates, because `b17`
does not carry the original `opamp` contract identity.

This is a CLI proxy, not an executed plugin import. Its consequence is
nevertheless precise: an engine selector cannot infer original semantics
from an opaque generated family name, visible triangle, or `b` prefix.
This limitation belongs to exact family-based contract readers, not every
placement path: current `opamp.amplifier` reads the complete formal names
without requiring the original family. That path can still recognize the
named-input generated stub when its other admission conditions hold.
Likewise, rejecting every registered class as caller-owned would exclude
plugin-generated conventional glyphs. `Origin.sub`/verified generated shape
and `Origin.lib`/project caller geometry have different authority even
though both reach the engine as registered classes.

The smallest viable plan must therefore include explicit trusted contract
and generated-geometry capability transport, or a shared request producer
before the plugin translates definitions. The caller's original formal
indices and net bindings remain authoritative. If that seam is not included
in the first implementation, plugin automatic signed policies must remain
explicitly unsupported; native success cannot be reported as plugin parity.
Even after semantic transport, an engine-only class variant would disagree
with the plugin's old per-definition symbol and later regenerated graphics.
The per-instance symbol reference and shared glyph policy must travel with
the selected terminal geometry through translation and emission.

## Smallest staged implementation plan

The current pipeline initializes classes, analyzes structure and skeleton,
reads fixed requests, tries the whole-circuit opamp placer, settles initial
orientations, collects local groups, reserves actual geometry, places,
compacts and routes. A signed-slot policy cannot be applied after those
reservations. The plan should retain these distinct responsibilities:

| Stage / writer | Inputs and output | Required scope and change radius |
|---|---|---|
| Complete contract reader | Original family plus every ordered formal/binding, or an explicitly transported verified contract | Pure bounded role/index result; prior nine-port width audit remains required |
| Raw local collector | All raw terminal occurrences and outer interfaces | Enumerate per amplifier anchor; reject competing embeddings and overlaps before caller/visibility filtering; allow independent disjoint anchors |
| Admission owner | Caller class origin/capability, sides, fixed/weak stays, admitted groups, mates, shelves and local style/route constraints | One typed accepted/declined record per proposed owner; no class or position writes |
| Signed-frame selector | Accepted owner plus positive-above/negative-above policy | Append/reuse an immutable generated variant keyed by complete ordered contract, pitch and policy; assign only the target device's existing ClassId field |
| Geometry/placement owner | Selected actual class, all ports, own-lead/body support, caller pose | Resolve before opamp frames, lattice reservations, local peer collection and compaction requests consume geometry; failures leave prior class/pose intact |
| Native/plugin consumers | The same selected ordered terminals, marks, body and instance variant identity | JSON/SVG and plugin translation/emission agree; caller custom symbols remain untouched |

For storage, use a bounded cold list keyed by existing typed device handles.
Capacity is no greater than the number of candidate blocks; no per-device
hot flags or callback layer is justified. Use the existing ClassId field to
refer to accepted immutable variants. A retained boolean cannot distinguish
an untouched default, a caller class, a failed frame and an admitted source
policy. Variant capability/provenance belongs to the class/request owner;
do not guess it later from a class-name prefix. The raw incidence table and
ordered terminal rows remain single-owner facts.

The production collector should walk named anchor pins and their bounded
raw incidences, not copy this research script's subset combinations. The
current `bias_neighbors.find`/`collect` separation is a useful small model.
A second raw peer must survive until ambiguity is decided; a third hidden
incidence cannot disappear in a visible-neighbor query. Candidate conflicts
must name their common anchor or member intersection. A later decision to
support several independent stages then changes the ownership combiner,
not the contract reader or glyph generator.

Three likely future changes have contained owners: an additional exact
auxiliary-port contract changes the complete role/geometry reader and its
bounded index consumers; an additional signed-slot use changes the local
policy producer; an alternative body shape changes the variant geometry
owner. The compiler-listed integration sites are `block_symbols`,
`Library.blockFor`/variant registration, `schematic.initDevices`, the early
`sketch.drawValid` phase and whichever local collector is introduced.
Plugin semantic transport, `Parts.sym` variant selection, `layout.library`,
`layout.translate` and `emit.graphics` form a separate mandatory downstream
change radius when parity is claimed. Existing `analogOutput` and
`bias_neighbors.Pair` index widths remain the earlier nine-port dependency;
these five/seven-port fixtures do not remove it.

Before an implementation is called complete, convert these materialized
cases into production oracles for exact raw candidate tuples, exact accepted
owner requests, final transformed terminal/mark positions, caller geometry,
class immutability and complete exported bindings. The present native
default is recorded RED for XREG's proposed policy; no Zig test was added or
run. Add same-anchor fixed/hidden rival and overlapping-member cases to the
actual collector tests, then keep the dual disjoint regulators as a positive
multi-owner planning control. Plugin parity additionally requires a host
round trip proving both differently drawn instances netlist back to the same
original five-port definition with unchanged signed bindings. Rendering alone
cannot prove that relation.

## Replay

```sh
python3 -B docs/research/image-rules/round-2/fourth-ports-fixtures.py \
  --execute --check docs/research/image-rules/round-2/fourth-ports-fixtures.json \
  --output /tmp/cktimg-fourth-ports-fixtures.json
python3 -B docs/research/image-rules/round-2/fourth-ports-proof.py \
  --check docs/research/image-rules/round-2/fourth-ports-proof.json \
  --output /tmp/cktimg-fourth-ports-proof.json
```

The first command reruns only the frozen CLI and verifies its completed
artifacts. The second verifies the current saved outputs and research
relations. Neither invokes a compiler. Exact corpus membership remains the
separate 39/36 existing-contract and 40/36 extended-contract result; no
synthetic fixture is added to those real-example name lists.
