# Private coupling chains between paired center-tap banks

AG1180 contains two reflected banks, each with two center-tapped coils, one
parallel capacitor and a reciprocal NMOS pair returning to ground. Two
private capacitor–switch–capacitor paths connect corresponding bank ends.
Both paths are straight, their actual tips are strictly ordered, and their
outer tips lie on the inner winding columns. The upper path lies above the
upper drain row; the lower path lies below the lower drain row. These are
two correlated observations in one source figure, not a general placement
rule for arbitrary switched-capacitor circuits.

[The source reader](figures/center_tap_chains.py) scans all 2,936 deck/human
pairs and replays the complete 19-symbol center-tap inventory and nine
[parallel tank relations](center-tap-tanks.md). It selects exactly
`ag-1180:coupling-bridges`. The [frozen evidence](figures/center_tap_chains_cases.json)
contains exact corpus names and hashes, the twenty devices' actual own
symbol leads, their declared bindings, four private conductor paths, and
all 32 named terminals on the four outer buses. Actual contact dots join
crossings; labels and cached strokes absent from the SVG cannot establish
continuity. Coil identity comes from the complete declared contract.
"Inner" is determined from both winding columns, independently of LE/LO
names or card order.

The source also has two corresponding-end switches on the drain rows and
two crossed-end switches between the banks. Their actual geometry is
recorded separately. The six-device chain owner does not place these four
switches. A separate four-device owner now places them from the same bank anchors.
The complete eight-pin outer-bus physical requirement remains a separate
acceptance condition.
Local private-chain continuity is insufficient to claim that the whole
network matches the source.

## Bounded implementation

The complete network also supplies a bounded reflection preference. Reversing
the outer-terminal bindings of both second windings exposed a separate
structural choice: the ordinary search selected an involution moving 18 of
the twenty devices, with winding and NMOS partners inside each bank. The
source arrangement moves 16 devices and reflects whole banks; its two chain
switches and two corresponding-end switches lie on the reflection axis.
Both involutions satisfy the electrical graph. The failing whole-bank
permutation oracle therefore required an earlier source-context choice,
not a placement exception to exact mates.

`coil_network.preferred` nominates the source reflection only when there are
exactly two complete, disjoint reciprocal NMOS banks, two unique private
C–S–C paths and all four unique direct/cross switches. Existing raw queries
were moved without changing their bodies into this cold shared module.
Twelve typed device-pair requests cover all twenty members; the request is
96 stack bytes, with no copied net table or retained state. All scans are
bounded by the existing graph tables. A third complete bank, a second
complete context, missing path or competing member excludes this preference.

The structure owner first admits caller symmetry constraints as before. It
then tries the automatic requests together with the admitted constraints,
using the same graph search to validate every original edge and terminal
binding and to write both mate tables. An incompatible trial falls back to
ordinary caller-only search. Global grouping off and symmetry off exclude
the trial. No CT terminal-equivalence rule changes. The temporary request
list is caller-owned and released on every allocation failure; the cold
query allocates nothing. This is a source preference for one measured
context, not a general replacement for the maximum-moved-device objective.

Caller pose and grouping constraints still apply in their existing later
phases. A held member prevents automatic owner placement, but does not
promise the same unheld global symmetry as an opaque-family control.
The reversed-winding tests explicitly verify admitted `at`, `cell` and
group requests, as well as compatible and incompatible symmetry requests.
The full-corpus effect of this choice remains a separate validation step.

The existing successful paired-bank placement is a read-only anchor.
`coil_chains.collect` requires exactly one private C–S–C path between each
pair of corresponding outer nets and exactly one direct switch for each of
the four possible cross-bank outer-net pairs. Every private junction has
exactly the two expected incidences. Hidden devices and switch controls
count before visibility or geometry filtering. An extra load, duplicate
complete path, competing direct switch or reused member excludes the
owner. The six chain devices must form their own exact mate closure: the
outer capacitors are paired and each middle switch is self-mated.

One candidate moves all six devices together. It anchors actual outer
capacitor tips at the inner winding columns and each switch path midpoint
at the banks' actual reflection axis. The two candidate rows sit outside
the complete bank body envelope with the existing clearance. This spacing
is an implementation choice; the source certifies relative positions, not
an absolute distance. All proposed bodies clear each other and every
unowned visible body. An incompatible path frame or collision restores
every changed device row, and no coordinates commit until all checks pass.

The source switch glyph exposes two path contacts. Its electrical card has
four pins, but there is no observed control-terminal geometry to copy.
All four native pins and the caller's complete rigid glyph are retained.
An early draft required every visible control to lie on the path midpoint
axis; that condition was unsupported and would reject the standard
controls at transverse offsets −6/+6. It was removed before the positive
implementation run. The custom-frame regression checks off-axis controls
at their actual transformed caller coordinates, their ordered bindings,
and private-path continuity. No control is hidden or repositioned within
its class.

An admitted pose, relation, grouping request or fixed coordinate on any
owned member excludes the entire six-device transaction. Global grouping
off also excludes it. Rejected and dropped requests do not acquire
precedence. Exact compatible mate relationships are retained; mixed
shelves or explicit routing, port or style requests on private nets exclude
placement. A bank rejected by its own owner cannot activate a descendant
chain. Equal actual rows and outer columns use real compaction tracks;
at most ten horizontal and two vertical strict orders preserve the
remaining relations through the existing compactor. No routing exemption,
new crossing budget, remote-pin removal or wire-style override is added.

## Separate four-switch placement

The four-switch owner requires the same complete private-chain topology
and successful bank key. Each corresponding-end or crossed-end pair must
have exactly one switch, counting hidden candidates before frame checks.
The two direct switches are self-mated; the crossed switches are exact
mates. Any held switch, unsupported frame, shared ownership or collision
rejects the complete four-device transaction. The six chain positions and
ten bank positions remain read-only anchors.

Both actual direct paths lie on the corresponding drain rows, with their
midpoints on the bank axis. The crossed paths stand vertically at distinct
mirrored columns: upper contacts share the upper drain row, and lower
contacts remain strictly above the coil midpoint. Their full terminal
frames reflect, including all visible caller controls. A body-derived
horizontal gap is an implementation choice, not a measured source distance.

The first native candidate was rejected correctly: its upper direct-switch
control body, expanded by ten units of clearance, spanned y=-60..-20 and
intersected the upper chain switch body at y=-78..-58. The source has no
control leads whose side could settle this choice. The owner now tries
two rigid direct-frame alternatives, reflecting the upper and lower
frames together while keeping their actual path endpoints unchanged.
Every candidate retains all four electrical pins and must pass the same
complete body checks. This is a finite orientation choice for omitted
source controls, not a new source claim about their positions.

The cold record is 24 bytes: a typed parent handle, four typed switch
handles and four `u1` semantic end indices. The draw caller collects,
places, supplies compactor requests and frees it. Collection reserves both
buffers before any writes. Each candidate saves four device rows on the
stack, commits coordinates only after all checks, and restores all rows
on failure. Two candidates with at most eight rigid poses per member bound
the scan. The existing compactor receives at most eleven horizontal and
five vertical strict orders within twelve slots per axis. Equal actual
drain rows and the bank axis already use shared coordinate tracks.
These are cold geometry scans, not new routing-cost abstractions; no
assembly or performance claim is made.

The separate transaction oracle first fails against the single-pose owner
and passes against the two-pose owner. Literal off-path bodies force the
alternate control sides; a body on the unchanged direct path defeats both
candidates and requires complete rollback. Allocation failure is swept
before placement. The shifted full caller-frame test also passes. A
horizontal `face so1 a right` fixture was corrected after its verdict was
shown to be `rejected/not_placeable`: the endpoint alias is valid, but the
existing horizontal face interface accepts only two-card-pin parts.
That rejected case remains a separate unchanged-default control; the
atomic caller test uses an explicitly admitted upright/downward face.
All three final frame tests pass, including the explicit admission and
rejection verdict controls. The full native physical audit remains a
separate gate.

## Data and failure contract

1. Inputs are complete incidences, successful-bank candidates, exact mates,
   admitted requests, current coordinates and actual caller frames. The
   output is a caller-owned list of six-device placement requests and
   existing-compactor coordinate orders.
2. One candidate owner per paired-bank record bounds collection. Raw shared
   membership rejects both owners before any geometric writes. Placement
   tries one candidate and at most eight rigid poses per member.
3. The cold record is 36 bytes, asserted at compile time: one typed parent
   coil handle, six typed device handles and six `u1` path-end choices.
   The parent handle remains valid when the successful bank list compacts.
   No net table, copied bank or active flag is retained.
4. The draw caller collects, places, appends orders and frees the batch.
   These are cold layout scans, outside routing cost loops. The shared
   actual-anchor helper is the unchanged operation needed by both bank
   and chain placement; it is not a public ABI addition or a speed claim.
5. The caller reserves both buffers before writes. Orders reserve 24
   coordinate-pair slots per collected owner, twelve per axis. Six old
   device rows and proposed positions live on the stack. Collection OOM
   leaves geometry unchanged; a rejected placement restores every row and
   leaves the caller's coordinate array untouched.
6. Parent order follows the existing canonical bank order; semantic net
   direction determines path order. Source and native permutation oracles
   compare actual named endpoints, rather than accepting arbitrary card
   order or a different witness device.

## Validation state

The source oracle has twelve topology/geometry method checks, including
all eight rigid poses, reordered winding cards, an inward-moved alternate
winding, a bent path, an internal path row, a moved direct switch and a
wrong-axis cross switch. Seventeen separate wire-oracle controls include
gaps, labels, foreign nets, contacts, unjoined crossings and cache-only
strokes. The exact methods and dependency hashes are stored in the source
inventory.

The complete source chain tests first failed on geometry before this
owner was added. The focused suite now passes all six tests: geometry
in both compaction modes and both shelf settings, private physical ink,
reversed path cards, caller/count boundaries, the literal source oracle,
and separate direct/cross switch geometry. Both additional caller-frame tests pass, including shifted
80-unit paths and visible off-axis controls. The separate transaction test
also passes: it sweeps collection allocation failure and requires complete
rollback against a blocker placed on a previously successful candidate.
The whole-bank suite subsequently exposed the reversed-winding symmetry
choice above. Its failing actual-geometry oracle and a separate exact-mate
regression were recorded before the preference was added. The focused
reflection suite now passes all seven tests, including the second complete
context and allocation-failure sweep; all eight whole-bank tests and all
six coupling tests pass. These suites are imported into the ordinary API
test gate. This focused result does not imply global source equivalence.
The complete native network audit remains required before checkpoint
acceptance. This note does not claim whole-corpus validation or human
equivalence.

Replay the complete source evidence without a build:

```sh
python3 -B docs/research/figures/center_tap_chains.py \
  external/examples /tmp/center-tap-chains.json --check
```
