# Recognized amplifier outputs and two-MOS banks

The source drawings contain 21 complete, recognized analog blocks whose
unique output drives a two-MOS bank. All 42 actual source gate leads face
left toward that output. The preceding bank rule makes the two gates
face inward. The implementation adds a bounded exception to that rule; it does
not change bank rows or require every same-net terminal to share wire ink.

The [reader](figures/driven_banks.py) scans all 2,202 Analog-Genie and 734
AMSNet outer netlists independently of native layout reports. The
[frozen inventory](figures/driven_banks_cases.json) records every selected
name, declaration and call binding, actual SVG endpoint certificate,
conductor path, source hash, and the complete local reader import closure.
All selected cases are Analog-Genie. Replay every source field with:

```sh
python3 -B docs/research/figures/driven_banks.py external/examples /tmp/driven-banks.json --check
```

An optional `--native <directory>` adds a separately measured geometry
snapshot. It verifies the named output's ordered binding and hashes each
selected drawing. It is an observational adapter, not the full-corpus
artifact/provenance gate used by the release audits.

## Selection and actual source evidence

The source selector requires a complete recognized amplifier or reference
amplifier declaration, one named output, and exactly two same-polarity MOS
gate terminals on its nonrail output net. Each MOS has distinct drain,
gate and source nets. Other terminals on that net may belong to capacitors;
another block, channel terminal, source, resistor or third gate prevents
admission. These are topology and complete-contract conditions, not tests
of a circuit ID or of transfer function inferred from transistor topology.

The exact selected instances are:

| Contract | Instances |
|---|---|
| Complete signed or single-input amplifier | ag-735:x1, ag-952:x1, ag-981:x1, ag-994:x1, ag-2418:x1, ag-2423:x1 |
| Complete reference amplifier | ag-2415:x1, ag-2420:x1, ag-2421:x1, ag-2422:x1, ag-2425:x1, ag-2427:x1, ag-2428:x1, ag-2434:x1, ag-2435:x1, ag-2436:x1, ag-2440:x2, ag-2441:x1, ag-2443:x1, ag-2444:x2, ag-2447:x1 |

Every MOS D/G/S endpoint is checked against its own transformed SVG glyph
and its outer-card net binding. The output is the declared named output
lead, verified against the actual glyph. Where cached coordinates are
stale, a triangle's unique actual apex supplies the endpoint; the reader
does not choose the nearest label. Physical connectivity uses conductor
ink, including actual contact-dot junctions, independently of printed net names.
The inventory keeps verified named-cache strokes and unsupported cache
fragments separately. A supplemental positive path is certified between
two independently verified, equally bound output/gate endpoints using only
actual conductor strokes. Every negative checks the entire actual SVG
conductor graph, so a missing cached segment cannot manufacture separation.

All 42 gates face the output. Nineteen banks also have actual wire paths
from that output to both gates. In **ag-2435:x1** and **ag-2443:x1**, M5.G
is physically separate while M1.G is wired to the output. Both gates still
face left. Those two explicit negatives prevent treating gate-facing
evidence as a universal continuous-wire requirement.

Seventeen banks occupy unequal source gate rows. Only AG735, AG952, AG981
and AG994 have equal rows. Thus this evidence does not justify leveling
the bank or moving its devices to one row. Twenty selected output nets
have just the driver and two gates; AG994 additionally has C1 and C2.

The comparison inventory retains **58** broad named-output candidates,
including 37 excluded cases. Digital outputs are intentionally excluded:
AG744's inverter drives an inward-facing PMOS pair, while AG1076's AND
output drives gates facing away from the driver. These actual source
counterexamples rule out an unrestricted “all block outputs” exception.
An earlier native-block exploration found 52 of these candidates; that
engine-dependent denominator is not the source selector's census.

## Placement boundary and caller precedence

The implementation shares a small complete-contract output query
between block passage placement and bank facing. The second caller is
necessary for AG2427: VEA is an output only in its complete reference
contract. Treating it as an unknown generic port can leave the block's
actual output inside the bank even when its origin lies to the left.
Global `library.portRole` recognition should remain unchanged.

Within the existing two-member bank branch, a unique recognized output
can replace the inward override with facing toward the driver's settled
column. Hidden devices, nonvertical members, ambiguous incidences and
existing symmetry mates must retain the existing policy. Cell placement
precedes the facing decision; admitted explicit faces run afterward.
No new mirror, row, continuous-wire or input-bus policy is included.

This is a lattice-stage direction choice. Custom symbols still require
actual transformed terminals to satisfy the public physical oracle. A
caller-provided class, explicit face or fixed position is not permission
to manufacture a conventional terminal frame. The regression
set includes shifted valid MOS and amplifier leads and fixed-cell/explicit-face
cases. The direction decision uses the settled driver column, not an
arbitrary caller symbol's actual output coordinate. Arbitrary rotated,
asymmetric or overlapping driver frames are outside this facing guarantee;
the caller's class and explicit face requests still retain precedence.

## Data and implementation bounds

The six data answers are:

1. Inputs are the existing ordered external declaration, graph incidences,
   bank members, drawn/form/mate tables and settled columns. Output is the
   existing gate-direction entry; passage still writes its existing spot.
2. Complete recognition scans the existing maximum of eight declared
   ports. The bank check scans its shared gate net's CSR incidences once,
   resolving the candidate block contract once. No per-pin registration or
   stored output-role cache is introduced.
3. A successful output index needs values 0 through 7; an optional `u3`
   result is sufficient. Devices and nets keep their existing typed
   `u32` handles and sentinel contracts. There is no new hot record or
   retained table whose size needs a new assertion.
4. The shared seam is the concrete pure `block_symbols.analogOutput` free
   function at two current callers.
   It reuses the existing complete glyph contract, with no callback,
   generic framework, shape extension, role extension or C ABI change.
5. Callers own all input slices and output tables. The query allocates
   nothing, borrows nothing beyond the call and introduces no error or
   cleanup path. Every scan is bounded by an existing slice length.
6. Work remains sequential and deterministic in the existing placement
   pass. Multiple qualifying drivers cause abstention, not first-match
   choice. No SIMD or timing claim is made. A runtime-input assembly pair
   compares the shared query with its direct implementation. The final
   fixed-target comparison is IDENTICAL; a compiled extra-work mutation
   fails as RESIDUE. The scope and measured counts are recorded below.

## Tests and current status

`tests/driven_banks.zig` is imported. Root recorded eight consumer tests
against the preceding production state: three passed and five failed on
gate facing. The independent AG2427 passage check then failed on its actual
output-before-channel comparison in compact mode. A ninth fixed-cell test
failed with an exterior right driver because one gate still faced left.
The tenth test covers a shifted caller amplifier frame. Both complete
renderer configurations and the final artifact checks pass; the measured
source mismatches below remain explicit.

The tests retain full outer DUT cards for AG735, AG2427 and AG2436, exact
opaque external declarations, electrical identity and no-short checks.
They exercise actual source gate directions, selected output-to-gate ink,
capacitor loads, digital/opaque/competing-driver boundaries, exact symmetry
mates, explicit caller requests, declaration/card permutation and shifted
valid custom terminals. Internal subcircuit bodies are deliberately
omitted because this rule consumes their declared external
contract only.

The source reader's 18 named method checks cover complete signed and
reference contracts, contextual VEA, paired VIN/VIP spelling, digital and
opaque exclusions, duplicate outputs, extra channel/gate incidences,
capacitor loads, gate/body alias rejection, card permutation, actual lead
reflection and proper crossings with an actual contact dot, no dot, or a
dot away from the crossing. Unsupported
source geometry fails; no selected case is silently skipped.

In the frozen iteration-18 native snapshot, zero of the 21 banks have both
gates facing left: 21 of 42 gate directions match the source. One bank,
AG2427, has both native gates facing its output only because the output
lies between them. This is not source placement parity.

`zig build test-codegen` emits a fixed x86_64 Linux, x86_64_v3 ReleaseFast
object containing runtime-input generated/direct exports. The vendored
checker, repository call-boundary guard and self-tests are declared build inputs; `zig build test`
includes this gate. The probe object is neither linked nor installed, and
never enters the WASM product graph. The actual assembly and a deliberate
residue mutation were checked as described below. See
[checker provenance](../../tools/asm_probe.README.md).

The first static probe reported NEGATIVE for a 40-instruction generated
export against a 90-instruction direct export, but this was not accepted:
the generated path called the full role classifier while the direct path
called only `portRole`. A new fail-closed guard rejects their different
direct callees, as well as wrapper-only external tail jumps and indirect
calls. The helper now performs an output-only scan after complete contract
validation. A second real object exposed an extra wrapper call, so the
production helper is inline in both placement callers. A bounded shape
dispatch and the same optional three-bit result carrier in the direct
comparison yield **IDENTICAL** assembly: 90 instructions, ten branches and
the same two callees on each side. The hand path remains at its original
90-instruction cost; it calls no shared output helper. A compiled runtime
mutation is rejected as **RESIDUE**, 99 versus 90 instructions. The probe
does not compare functional behavior or establish a speed gain. Its separate
options exclude unrelated C ABI, ZON and LaTeX code from this test object.
These corrections change neither accepted families nor port-role semantics.

The first consumer run passed nine of ten tests. The permutation fixture
incorrectly reused one mutable symbol library for two different ordered
declarations of the same family; generated `block:<name>` classes are
cached by name. The corrected setup uses independent libraries and checks
each ordered terminal name before retaining the original exact geometry
and electrical comparisons. This is a fixture correction, not a relaxed
geometry oracle.

The corrected focused consumer suite passes all ten tests. Each negative
declaration also receives its own symbol library, so differently sized
contracts of the same family cannot reuse a cached class. The complete
suites pass **414 tests without LaTeX and 415 with it**, including the
assembly gate in both configurations. The separate native audits also
pass their recorded expectations; those expectations retain the three
facing mismatches and six earlier VIN continuity losses.

## Native facing and remaining guards

The final frozen executable is
`7e30dbb2d84bb5a03d944729039048da5cfcae9e03af0bf5e54dc867a9801e41`.
The [native companion](figures/driven_banks_native.py) and
[exact inventory](figures/driven_banks_native_cases.json) replay the source
census, every ordered block port and MOS D/G/S/body binding, and all 2,936
source, geometry, report, scorecard and executable hashes. They retain all
58 broad observations. The selected cohort improves from **21 to 39 of 42**
matching gate directions and from **zero to 18 of 21** banks with both
source-facing gates. Exactly those eighteen AG drawings and reports change;
the other drawings, including all 734 AMS cases, are byte-identical.

Three selected gate directions remain mismatched: **AG2428 M1, AG2435 M5,
and AG2443 M1**. The [guard probe](figures/driven_bank_guards.py) retains
all 21 complete normalized inputs, every engine-source hash, the standalone
probe, a single logging-only insertion and the actual private trace in its
[inventory](figures/driven_bank_guards_cases.json). Their public structural
mates are all absent. At the private placement guard, however, AG2428 M1
is paired with M8, AG2435 M5 with M9, and AG2443 M1 with M8. These are
non-self column mates propagated from other mirror blocks, not exact
whole-circuit symmetry. The present rule preserves them and leaves those
three drawings unchanged. Source evidence favors the driver-facing gates;
changing the priority of inferred mates is separate future work.

Replay the native evidence with the frozen corpus directories and binaries:

```sh
python3 -B docs/research/figures/driven_banks_native.py external/examples /tmp/driven-banks-native /tmp/driven-banks-native.json \
  --baseline-bin /tmp/cktimg-human-rules/iteration18-reference/cktimg-json \
  --candidate-bin /tmp/cktimg-human-rules/iteration19-banks-inline/cktimg-json \
  --baseline-corpus /tmp/cktimg-human-rules/all-ag-iteration18-reference \
  --baseline-corpus /tmp/cktimg-human-rules/all-ams-iteration18-reference \
  --candidate-corpus /tmp/cktimg-human-rules/all-ag-iteration19-banks-inline \
  --candidate-corpus /tmp/cktimg-human-rules/all-ams-iteration19-banks-inline --check
```

The guard reconstruction deliberately requires the recorded iteration-19
source checkout or archive. It refuses later engine sources. With that
checkout at `src`, prepare a separate diagnostic copy, run it, and compare
every fresh observation with the recorded trace:

```sh
python3 -B docs/research/figures/driven_bank_guards.py external/examples src /tmp/driven-bank-guards.json --prepare /tmp/driven-bank-guards
nix develop -c zig test --dep NetlistParser -Mroot=/tmp/driven-bank-guards/probe.zig --dep build_options -MNetlistParser=/tmp/driven-bank-guards/src/root.zig -Mbuild_options=/tmp/driven-bank-guards/build_options.zig --test-filter 'guard observation:' > /tmp/driven-bank-guards.log 2>&1
python3 -B docs/research/figures/driven_bank_guards.py external/examples src /tmp/driven-bank-guards-replay.json --log /tmp/driven-bank-guards.log
```

## Separate physical-continuity audit

The [all-pair companion](figures/driven_banks_connectivity.py) compares every
stable named device-pin pair on changed nets, resolving each transition
against actual source leads and conductor ink. Its
[frozen inventory](figures/driven_banks_connectivity_cases.json) records
**nine newly connected pairs, all source-supported, and zero losses**.
These correlated observations include AG2436's three repaired output/gate
pairs. The other six iteration-18 VIN losses in AG2415 and AG2428 remain
named failures; facing alone has not repaired their input clusters.
The 129 earlier named mismatch identities are checked explicitly, with
only those three AG2436 pairs accepted as resolved. The two source-detached
AG2435/2443 gates remain negative controls, not inferred wire requirements.

```sh
python3 -B docs/research/figures/driven_banks_connectivity.py external/examples /tmp/driven-bank-connectivity.json \
  --source-work /tmp/driven-bank-connectivity-source \
  --baseline-bin /tmp/cktimg-human-rules/iteration18-reference/cktimg-json \
  --candidate-bin /tmp/cktimg-human-rules/iteration19-banks-inline/cktimg-json \
  --baseline-ag /tmp/cktimg-human-rules/all-ag-iteration18-reference \
  --baseline-ams /tmp/cktimg-human-rules/all-ams-iteration18-reference \
  --candidate-ag /tmp/cktimg-human-rules/all-ag-iteration19-banks-inline \
  --candidate-ams /tmp/cktimg-human-rules/all-ams-iteration19-banks-inline \
  --accept-resolved ag-2436:net4:m1.1--msen.1 \
  --accept-resolved ag-2436:net4:m1.1--x1.4 \
  --accept-resolved ag-2436:net4:msen.1--x1.4 --check
```

## Completed validation and artifact

The final artifact passes 4,000 fuzz cases, global formatting and changed
Zig-file style checks apart from the same five pre-existing API findings.
All 31 gallery SVG names and bytes remain unchanged. Real release-host
Schemify round trips retain 98 exact fixture comparisons and the two named
capacity refusals. The 21 selected complete source decks yield 51 exact
subcircuits on both release and current hosts, with ordered names and source
hashes checked. The two remaining manual VIN regressions still fail at their
physical-ink assertions and pass the exact expected-failure marker check;
AG2436 is now an ordinary passing regression.

The final WASM module is **558,107 bytes**, SHA-256
`1b125c81bcea45c64d1297ddf16b71f6ac1de20836d9a2f722a965ada54b6cab`,
5,093 bytes below the strict cap. Repeat native and plugin builds are
byte-identical. These checks establish the bounded rule and its declared
limits; they do not establish whole-drawing equivalence.
