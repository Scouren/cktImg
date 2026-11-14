# Private amplifier bias blocks

Seven source circuits place a private bias block beyond an amplifier's
actual bias lead. Their two bias leads face one another on the same column,
and actual conductor ink joins them. This is a bounded relative placement
observation. It does not establish a universal bias-block location, prove a
transfer function, or justify changing a caller's symbol definition.

The [reader](figures/bias_block_neighbors.py) reruns the existing biased
amplifier census and the complete reference-amplifier source certificates.
Its [frozen inventory](figures/bias_block_neighbors_cases.json) contains the
exact source names, declarations, full outer-card pin incidences, source
hashes, actual lead/body certificates, conductor proofs and exclusions.
The source evidence remains independent of the implementation. Checkpoint 20
now implements this relative geometry rule. All twelve focused regressions pass,
including the final far-edge lead mutation. The measured seven-case
relative relation improves, with the full suites and exact electrical
round trips passing. Whole-drawing equivalence remains unproved.

## Source scope and the counterexample

The census contains 85 complete known `opamp` instances and the 15 complete
unsigned reference amplifiers. These 100 bodies have 196 bias ports: 187
in the older cohort and nine in the reference cohort. Twelve older bias
ports have unresolved cached frames; the inventory names them and makes
no actual-side or connectivity claim from those frames. Of the 175 verified
older bias leads, 160 point down and 15 point up. All nine new leads are
verified: seven point down and two point up.

The older cohort supplies no private single-block neighbor case. For 185
of its bias ports, the net is an external DUT port with no other outer
device incidence. AG1639:X1.VB2 reaches a primitive network electrically,
but its certified source lead is physically separated from all four
primitive terminals; a whole-ink challenge also finds no connection.
AG1720:X1.VB3 reaches another primitive network, but its amplifier lead is
one of the twelve unresolved frames. No geometry is inferred for it.

The nine reference bias ports give the following exact comparison. The
gap is the projection from the amplifier's terminal to its peer terminal
along the amplifier lead's outward direction, in source SVG units.

| Amplifier bias port | Peer bias port | Source direction | Gap | Actual ink joins | Entire peer body outward |
|---|---|---|---:|---|---|
| ag-2421:X1.VBN | X2.VBN | up | 10 | yes | yes |
| ag-2422:X1.VBN | X2.VBN | down | 20 | yes | yes |
| ag-2428:X1.VB1 | external DUT port | down | — | — | — |
| ag-2436:X1.NB | X2.NB | down | 30 | yes | yes |
| ag-2440:X2.VBN | X1.VBN | down | -250 | no | no |
| ag-2441:X1.VBN | X2.VBN | down | 10 | yes | yes |
| ag-2443:X1.NB | X2.NB | down | 40 | yes | yes |
| ag-2444:X2.VBN | X1.VBN | up | 0 | yes | yes |
| ag-2447:X1.VBN | X2.VBN | down | 20 | yes | yes |

All seven connected cases have exactly two declared pin incidences on the
private bias net. The peer is a `bias` or `bias_circuit` block with the same
VDD/VSS bindings. Every other nonrail peer port binds an external DUT bias
port without another local device incidence. The guard counts hidden body
and optional BJT substrate incidences, repeated ports and aliases too.

AG2440 is the essential negative: its peer's extra VC port also drives
local transistor controls. Its source VBN leads are physically separated,
and its peer is above the downward amplifier bias lead. Both the verified
net-ink graph and a whole-ink challenge preserve this negative. The
additional local connection excludes it from the seven-case hypothesis;
the circuit itself is valid. AG2428 has no local peer at all.

Each selected source has opposite-facing leads on one column and a peer
body strictly beyond the amplifier terminal. **The endpoint gap may be
zero**: AG2444's leads touch. Visible peer ports are matched to their own
actual SVG leads. Missing cached VSS geometry remains unknown; it is not
evidence that the source SVG or the electrical contract omits VSS.

## Native observation and limits

The optional native adapter rechecks each block's own actual SVG body and
lead strokes, all ordered electrical bindings, and the selected physical
wire component. Its JSON must be byte-identical to the named scored corpus;
the complete 2,202-name Analog-Genie corpus and its recorded source, report
and binary hashes are validated before measuring the eight peer pairs.

The frozen iteration-17 and iteration-18 snapshots both preserve all seven
selected physical bias connections. In both snapshots, zero of seven
peer bodies are outward of the amplifier's own native bias lead, zero
have collinear bias leads, and zero have opposite-facing bias leads.
The native binaries are respectively
`cb0acd3ffc56619b5f008e1487a08f093e42aee54945b02a46422a8f20ace9d0`
and `c99fc4e18eaadd443a39c453207f50016710a387c0ea99cc339aaed061114248`.
Iteration 18 changes the amplifier from a box to a triangle with a downward
bias lead; the peer's canonical bias lead still faces left.

A whole-class rotation can make that peer bias lead face the amplifier.
It cannot reproduce every source port side. In AG2436, source VDD and VB1
both face left, while their canonical peer ports occupy opposite sides.
No rigid rotation or reflection turns opposite sides into the same side.
AG2421 and AG2444 also use upward source amplifier bias leads; their
canonical downward native lead is a separate unresolved difference.
These discrepancies must remain visible if only the relative placement
rule is implemented. Cached library classes must not be mutated per
instance to manufacture the source port arrangement.

Visual review also records a label-fitting limitation in AG2444.
Checkpoint 19 already overlaps its VBN port and centered `bias_circuit`
kind label; the rotated checkpoint-20 peer overlaps the kind label with
VDD/VSS port text inside the narrow body. The relative bias relation
improves, but this is not a whole-drawing visual improvement claim.
Orientation-aware block-label fitting remains separate future work.

For AG2436, the iteration-18 peer lies above and right of the amplifier.
Its bias wire has a vertical section at x=260 crossing the potential
M1.G–MSEN.G horizontal interval at (260,180). Geometry alone does not prove
why that gate connection becomes labels. The separately replayed
[routing trace](reference-routing.md) records the actual thinning rounds
and failed routes. This placement study does not promise that relocating
the peer alone repairs every physical connection.

## Checkpoint 20 measurement

The native measurement against checkpoint 19 changes exactly `ag-2421`,
`ag-2422`, `ag-2436`, `ag-2441`, `ag-2443`, `ag-2444` and `ag-2447`.
Each now has an outward peer body, collinear bias terminals and
opposite-facing leads: every individual condition and the complete
relative contract move from zero to seven. All seven bias connections
remain physically continuous. AG2440 retains its excluded, nonrelative
and physically separated observation; AG2428 still has no private peer.

The [native glyph audit](figures/bias_block_neighbors_native.py) preserves
each class's own outline, external leads and ordered electrical bindings
under whole-instance turns. It keeps the exact visible-port side
disagreements separately: 29 before and 15 after, across the seven cases
and AG2440. The two source-up amplifier biases and the remaining peer-port
differences are not erased by the relative-placement result. This local
glyph check does not assert interior-label fitting or unknown VSS geometry.
Its [final inventory](figures/bias_block_neighbors_native_cases.json)
retains every named observation and all 21 literal method checks. All
2,936 final drawings/reports equal the earlier candidate's bytes, and
one-job/four-job replay of all seven changed decks is byte-identical.

The [physical-connectivity audit](figures/bias_block_connectivity.py)
checks all 315 stable pin pairs on 84 nets in the seven changed drawings:
zero joins, zero splits and zero unstable pin identities. All seven moved
peer VSS endpoints remain explicitly unresolved in the source geometry;
none participates in a connectivity transition. Unchanged native
continuity does not supply their missing source coordinates. The complete
AMSNet corpus is unchanged.
The [connectivity inventory](figures/bias_block_connectivity_cases.json)
also retains all 129 historical mismatch markers, with the same three
previously reviewed resolutions and no new marker change.

The final native executable is 46,381,730 bytes, SHA-256
`b542f72061814938289649745b76ff44e3e6d78571d9cb6b605472796e5e22d6`.
The final WASM is 558,321 bytes, SHA-256
`fea14f566ffcf79784de52710978a31393cfe61e62eb0fbe0aa2b181ee0cb546`,
below the strict 563,200-byte cap. These measurements describe the frozen
`iteration20-bias-final` artifacts.

Validation passes with 427 tests for LaTeX disabled, 428 with it enabled,
and 4,000 fuzz cases. Global formatting and modified-file style checks
pass; the same five legacy API style findings remain separately named.
The 31 gallery files are byte-identical, with `two_stage_opamp` also
visually inspected. Root independently replays the source, native and
full-pin inventories with `--check`. The fixture round trip preserves
98 named subcircuits and the same two named capacity refusals. All nine
selected decks preserve their exact ordered 26-subcircuit inventory in
both release and current Schemify; this includes the changed seven-deck,
21-subcircuit subset. The two outstanding VIN physical-routing failures
remain named, and their explicit failure-marker checker passes. These
electrical and regression checks do not remove the geometric and label
limitations above.

## Geometry owner and tests

The certificate recognizes the complete amplifier contract and
one private bias net using all declared incidences, then retains only the
two devices and their terminal indices. It rejects multiple qualified
private peers on one amplifier before geometry filtering. Raw ambiguity and extra
local connections must be rejected before filtering on drawn state,
orientation or caller instructions. Port spellings and circuit IDs alone
are insufficient. The production boundary must explicitly state its peer
contract; this observational scan does not certify arbitrary unknown
blocks with similarly named ports. The seven observed peers have complete
`BIAS` or `BIAS_CIRCUIT` declarations with VDD, VSS, exactly one NB/VBN,
optional VB1/VB2 and no other ports. That is a possible first contract
boundary, with the full-incidence guard still required independently.

The placement target is relative to the **actual transformed**
amplifier bias terminal: the peer body is strictly beyond it, its bias
lead points back, and the two actual bias terminals share the transverse
coordinate. The amplifier's existing world-facing side remains unchanged.
Existing whole-class orientation and `schematic.alignPin` are candidate
geometry operations. A single pure topology query may serve orientation,
placement and compaction without a retained role cache.

The skeleton currently has no library class geometry, so a skeleton-only
"put the peer below" rule cannot establish this contract for custom frames.
An owner must reserve a collision-free corridor after actual classes and
orientation are known, or explicitly limit admission to a frame proved at
that boundary. A post-coordinate move also needs body/rail clearance and
shelf consistency; moving one origin is not a complete placement plan.
Compaction must preserve successful actual-terminal order and alignment.
Explicit class definitions, definition sides, faces, cells, row/order
relations, symmetry mates and fixed positions take precedence. A caller
request must never be reinterpreted as permission to rewrite the class.

The geometry owner is `src/bias_neighbors.zig`, called from the existing
sketch geometry stage. It collects eligible pairs before relay consumes
weak `at` stays, then attempts whole-peer orientation and placement after
lattice coordinates/relay and before scaffold wiring. The amplifier and
all skeleton cells remain fixed. Positions in sketch are grid anchors,
so actual class origin is `at - grid`; both selected terminals use their
transformed class coordinates. The own lead must first reach a unique
closed body outline at its attachment: no outline edge may intersect the
open segment between tip and attachment. Sloped triangle edges remain
valid. Every body-outline vertex and any circle
extreme must remain strictly behind its own facing terminal. Unrelated symbol and terminal envelopes
bound a finite outward placement sweep; fixed obstacles use their actual
requested turns. A blocked attempt restores the peer's device row.

The source reader uses literal DUT declarations. Flattened engine decks
have no equivalent public-port table, so production explicitly projects
the other peer bias ports to `Role.isPort` plus exactly one full pin
incidence. An internal spare port, aliased pin, hidden body or extra local
control fails admission. This projection must not be reported as recovery
of the original DUT declaration.

Participants must already share a shelf. Admitted participant cell,
row/above/order, form and face requests, original strong/weak `at`s,
definition-side instructions and structural mates abstain. Existing group
rows also protect participant members, including the valid subset of a
relaxed partial group request. The sketch
cannot see skeleton's private inferred mate array, so a peer on a column
covered by its surviving mirror-axis promise also stays put. Caller
classes remain intact; valid custom frames may participate. The existing
single compaction pass accepts appended actual-terminal orders through
`power_compact`, without teaching the generic compactor bias topology.
It obtains those tips from the current scaffold, not stale coordinates.
Equality already shares a rigid track. This establishes only the relative
contract; source upward amplifier bias and other peer-port side mismatches
remain separately measured.

The six data answers for the geometry owner are:

1. Input is the existing netlist, complete block contract, roles, full
   pin-incidence rows, admitted hints and actual transformed class data.
   Output is existing orientation/placement data plus existing compaction
   orders; electrical pins and library classes are unchanged.
2. There can be at most one successful peer for each selected amplifier
   bias terminal. All loops are bounded by existing device, pin and net
   incidence slices. No count is inferred from the seven examples.
3. Device and net handles retain the engine's typed `u32` ranges. The
   recognized amplifier has at most eight ports, so its index needs `u3`.
   The five-port peer contract also fits `u3`; a wider generic
   class boundary would instead require `u6` for `max_pins == 64`. The
   implementation retains only two typed `EdgeId` handles and two
   `u3` port indices: a compile-time assertion checks the cold certificate
   is 12 bytes. Its shared net is checked during admission and is not
   retained without a consumer.
4. The query reads one complete contract and its incident nets together;
   its small result is consumed immediately. There is no per-device flag
   table, callback, new glyph variant or new C ABI surface.
5. The caller owns every table. The topology query allocates nothing and
   returns no borrowed storage. Collection reserves a caller-owned pair
   list and coordinate-order buffer before placement; one batch destructor
   frees both. Every geometry attempt restores the old peer fields on
   failure.
6. Placement remains sequential in the existing canonical device order;
   each successful move becomes occupancy for the next. Tests must prove
   declaration/card
   permutation invariance and identical one-job/four-job output. No timing
   or zero-runtime-residue claim has yet been measured for this proposal.

The regression oracle should use literal full outer DUTs from the seven
sources and actual terminals/body edges, with compact both off and on.
It should check opposite outward lead vectors, equal transverse position,
nonnegative terminal gap, strictly outward peer body, physical bias ink,
electrical identity and no shorts. AG2444 guards the zero-gap boundary.
AG2440 and AG2428 guard extra local controls and absent peers. Mutations
must add a hidden body/substrate incidence, alias another peer port, remove
a rail binding, add a competing peer and move a lead away from the actual
body. Caller classes with shifted or enlarged bodies and explicit
side/face/at/cell constraints need their own precedence checks.

The [regression file](../../tests/bias_block_neighbors.zig) now
contains twelve tests through the existing `np.place`/`Placed` API. It keeps
all seven complete outer DUTs plus AG2440, checks the transformed own-body
lead strokes and every ordered block binding, and covers valid shifted
custom classes without rewriting their fields. Its abstention comparison
renames the excluded peer to an opaque family while preserving its port
geometry; it does not make source disconnection a desired native outcome.
An independent frozen-18 native replay of all nine excluded/hint fixture
variants, with compaction both off and on, confirms their ordinary peer
orientation is `r0` without reflection. The tests assert that literal
orientation too, so an overbroad rule cannot pass by turning both compared
variants together. All block ports need their own actual body-boundary
lead, and default generated classes are compared to a fresh untouched
library; explicit custom classes are compared to their literal fields.
Fixed cells, exact `at` turns, definition sides and an admitted nearby MOS
gate face supply caller-precedence cases. Multiport blocks have no admitted
`face` operation in the current API, so the tests do not invent one.
Declaration/X-card permutations and literal relative/missing-lead
mutations challenge the oracle. A Python check matched all eight literal
outer-card and declaration inventories to their sources, and the style
checker passed. Root compiled the original eight tests against checkpoint
19: four source/custom/permutation relation tests failed and the four
negative/caller/literal-oracle tests passed. The first focused candidate
passed all nine geometry, caller and
negative tests, including the detached custom-lead case. Its allocation-
failure test exposed existing role-inference and skeleton allocation
cleanup leaks and a canvas postcondition that ran on allocation failure.
Those cleanup fixes are separate from the bias owner. The stable failure
sweep now passes, with resizing disabled in its backing failure allocator
so each growth takes a deterministic allocation path. A success assertion
also proves its minimal fixture actually places a nonempty selected pair.
The combined twelve-test focused run passes after these fixes. This is
not a full-suite or corpus-parity result. The additions reject a
detached custom lead and exercise allocation-failure cleanup. A further
public custom-frame test went red on body-circle ink beyond the facing
tip; the new circle-extreme guard addresses it. An explicit group-stack
case also went red when the inferred rule overrode its top member. The
guard now reads admitted group membership, and the regression includes
an honoured complete request and a relaxed request with an unknown name.
The orphan-attachment guard was independently removed in an isolated
mutation and the public abstention test failed as intended. Every
positive peer also has an independent
body-versus-other-symbol bounding certificate, including compaction off.
Final review extended the detached-lead regression with a stroke that
crosses its box interior to the far boundary. The independent own-lead
oracle rejected this frame, but initial admission still turned the peer;
the new case went red. Admission now checks every outline edge against
the open lead segment using integer intersections. The final twelve-test
focused run passes with this extension. An independent exact rational
segment oracle also agrees on 104,976 cardinal-lead/arbitrary-edge cases,
including all four directions and degenerate edges; this arithmetic
challenge supplements the public placement regressions.

## Reproduction

The source-only command replays both source censuses, actual leads and ink,
ten literal method checks, every named exclusion and dependency hash:

```sh
python3 -B docs/research/figures/bias_block_neighbors.py \
  external/examples /tmp/bias-block-neighbors.json --check
```

To add native measurements, first obtain SVG/JSON pairs from the frozen
native renderer for the eight peer decks (2421, 2422, 2436, 2440, 2441,
2443, 2444 and 2447), using the same default CLI options as the corresponding
complete scored corpus. Then pass matching named directories:

```sh
python3 -B docs/research/figures/bias_block_neighbors.py \
  external/examples /tmp/bias-block-neighbors-native.json \
  --native baseline=/path/to/baseline-svg-json \
  --corpus baseline=/path/to/baseline-scored-corpus \
  --native candidate=/path/to/candidate-svg-json \
  --corpus candidate=/path/to/candidate-scored-corpus --check
```

`--check` freezes the complete source evidence. Optional native results
are separately measured and hashed; that option does not freeze a native
placement failure as desired behavior or claim that a changed native
snapshot matches the source.

The separate [native companion](figures/bias_block_neighbors_native.py)
checks both complete scored corpora, renders fresh SVG/JSON pairs, and
compares every evidence field with its
[frozen native inventory](figures/bias_block_neighbors_native_cases.json).
Its 21 method checks include a lead crossing its own body to the far edge.
`--require-relative` requires all seven selected source relations and bias
wire connections, independently of the retained world-side mismatches.
The [continuity companion](figures/bias_block_connectivity.py) compares
every stable pin pair on changed nets, replays the source ink, and keeps
unknown source VSS geometry explicit. Its historical marker gate accepts
only the same three AG2436 repairs from checkpoint 19.

For the frozen checkpoint artifacts and scored directories:

```sh
snapshot_dir=/tmp/cktimg-human-rules
python3 -B docs/research/figures/bias_block_neighbors_native.py \
  external/examples /tmp/bias-native-replay /tmp/bias-native.json \
  --baseline-bin "$snapshot_dir/iteration19-banks-inline/cktimg-json" \
  --candidate-bin "$snapshot_dir/iteration20-bias-final/cktimg-json" \
  --baseline-corpus "$snapshot_dir/all-ag-iteration19-banks-inline" \
  --baseline-corpus "$snapshot_dir/all-ams-iteration19-banks-inline" \
  --candidate-corpus "$snapshot_dir/all-ag-iteration20-bias-final" \
  --candidate-corpus "$snapshot_dir/all-ams-iteration20-bias-final" \
  --require-relative --check
python3 -B docs/research/figures/bias_block_connectivity.py \
  external/examples /tmp/bias-connectivity.json \
  --source-work /tmp/bias-connectivity-source \
  --baseline-label iteration19-banks-inline \
  --candidate-label iteration20-bias-final \
  --baseline-bin "$snapshot_dir/iteration19-banks-inline/cktimg-json" \
  --candidate-bin "$snapshot_dir/iteration20-bias-final/cktimg-json" \
  --baseline-ag "$snapshot_dir/all-ag-iteration19-banks-inline" \
  --baseline-ams "$snapshot_dir/all-ams-iteration19-banks-inline" \
  --candidate-ag "$snapshot_dir/all-ag-iteration20-bias-final" \
  --candidate-ams "$snapshot_dir/all-ams-iteration20-bias-final" \
  --accept-resolved ag-2436:net4:m1.1--msen.1 \
  --accept-resolved ag-2436:net4:m1.1--x1.4 \
  --accept-resolved ag-2436:net4:msen.1--x1.4 --check
```
