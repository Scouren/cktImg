# Unsigned reference-amplifier contracts

This companion defines the 15 deferred cases in
[remaining-amplifiers.md](remaining-amplifiers.md). That earlier audit and
its 39 complete signed-contract candidates remain unchanged. The reference
contract is implemented in `src/block_symbols.zig`. Native and Schemify
checks establish the local glyph improvement; named physical-continuity
regressions remain below.

```sh
python3 -B docs/research/figures/reference_amplifiers.py external/examples /tmp/reference-amplifiers.json
```

The [inventory](figures/reference_amplifiers_cases.json) retains exact
selected/excluded names, ordered declarations, bindings, source hashes,
every newly certified terminal mapping, and named method checks. It scans
all 2,202 AG and 734 AMS decks; all selected cases are AG. Its actual outline
and lead parser is shared with the earlier audit, whose frozen inventory
already holds the complete SVG primitives. This companion does not infer
pin identities from SVG line order or choose the nearest text label.

## Bounded candidate

The exact case-insensitive families are `AEA`, `ERRORAMP`, `ERROR_AMPLIFIER`,
and `ERROR_AMP`. A complete reference contract has:

- one unsigned input named `VREF`;
- one output named `OUT` or `VEA`;
- optional, unique `VDD` supply and `VSS` ground;
- at most one bias named `VB1`, `VBN`, or `NB`;
- no other port, repeated role, second input or second output.

The observed declarations all contain VSS; AG2427 omits VDD. Allowing a
declaration without either rail is a complete-contract policy, not a claim
that the source cohort contains that exact variant. A missing declaration
must never cause a new electrical pin to be synthesized.

The exact cases are:

| Family | Instances |
|---|---|
| AEA | ag-2415:x1, ag-2421:x1, ag-2425:x1, ag-2428:x1, ag-2434:x1, ag-2435:x1, ag-2440:x2, ag-2441:x1, ag-2443:x1, ag-2444:x2, ag-2447:x1 |
| ERRORAMP | ag-2420:x1 |
| ERROR_AMPLIFIER | ag-2427:x1 |
| ERROR_AMP | ag-2422:x1, ag-2436:x1 |

All 15 actual source bodies are plain right-facing triangles with one
base lead, one apex lead and **zero polarity strokes**. VREF must remain
unsigned. Their 53 visible leads map bijectively to the 53 declared
non-VSS ports. Each has no VSS lead or cached VSS terminal: the 15 missing
source coordinates remain unknown, while a generated native symbol must
preserve all 68 declared electrical ports.

## Named lead evidence

Every actual apex has a continuous source conductor path to an independently
verified outside MOS gate whose declared net equals the OUT/VEA call
binding. M1.G is reached in every case; the inventory also retains other
same-net gates reached physically. This establishes the output lead even
where the custom-symbol cache is stale. It does not join detached labels
or assert that every remote member of that net is physically wired.

Of the remaining 38 visible leads, 27 reach actual named port or supply
markers; seven bias ports have exact declared-cache/actual-lead agreement;
four need the following literal label-and-stub certificates:

| Instance and port | Actual glyph endpoint | Reviewed label and connected stub |
|---|---|---|
| ag-2421:x1 VDD | (250, 140) | VDD text at (240, 160), actual stub ends at (250, 160). |
| ag-2427:x1 VREF | (-60, 70) | VREF text at (-80, 60), actual stub ends at (-80, 70). |
| ag-2435:x1 VREF | (-70, 50) | VREF text at (-90, 40), actual stub ends at (-90, 50). |
| ag-2440:x2 VBN | (190, 320) | VBN text at (198, 350), actual stub ends at (190, 350). |

These four label associations were reviewed in their full rendered source
sheets. The script asserts the exact text, object ID, text position and
connected stub; it does not treat a label's printed baseline as a terminal
or infer a remote wire. Mutating the label text or removing its conductor
must fail. The seven cache-supported bias cases are AG2421/2422/2436/2441/
2443/2444/2447; those named cached coordinates all meet their own actual
external SVG lead and their declared call binding.

## Placement exceptions and boundaries

Supply and bias sides are habits, separate from the glyph contract. Of
the 14 visible VDD leads, twelve end upward; AG2421 ends downward and
AG2444 has a bent lead ending rightward. Of nine bias leads, seven end
downward; AG2421 and AG2444 end upward. VREF always enters the left base
and the output always leaves the right apex in this finite cohort. No
source-specific side override should be baked into family recognition.

Exact `ERRAMP` in `ag-2442:x2` declares the familiar
`VDD VSS VREF VBN OUT` set but is an actual source rectangle. Its full
outline is retained in the earlier inventory. It is not one of the four
admitted family names. EA1 is also excluded: its unsigned multi-control
triangles and source box require a different contract.

The AEA family alone does not imply this single-input glyph. AG2384 has
VREF plus a positively marked INP lead and an extra VX control. AG2404 has
three actual base leads and additional controls. AG2430's IB and AG2429's
VBT remain unknown roles here. AG2423's one negative INN input belongs to
the earlier signed contract, not this unsigned one. Recognition preserves
that distinction and confines the new VREF/VEA/bias aliases to the complete
reference contract. Generic amplifier port-name recognition is unchanged.

The 15 named method checks cover case/permutation, optional rails, exact
family boundaries, unknown/duplicate/mixed roles, absent reference, added
polarity, removed base lead, changed label text and disconnected label
stub. They are compared by name. The source SVG review additionally viewed
AG2421, AG2427, AG2435 and AG2440.

## Implementation and data bounds

The six data answers for this change are:

1. Input is a family name and its ordered declared ports. Output is a
   verified shape, then the existing terminal and drawing-operation arrays.
   VREF selects the reference contract only within the four exact families.
2. Recognition runs once per registered symbol, scanning at most the
   existing eight-port limit. A valid reference contract has two to five
   distinct roles: input, output, optional supply, ground and one bias.
3. `Shape` remains `enum(u8)`; its appended `reference_amplifier` case
   preserves every older tag value. The existing private `Role` stays
   `enum(u4)`. No hot struct, handle width or retained table is added.
4. Bounded sequential scans resolve the complete contract before drawing.
   The existing triangle, terminal positions and lead construction are
   reused. Bias placement uses resolved roles so VB1, VBN and NB produce
   identical geometry while retaining their declared spelling.
5. The caller still owns the arena and port strings. Allocation and error
   cleanup follow the existing drawing contract; the new recognition path
   allocates nothing and retains no additional state.
6. Registrations are independent with caller-owned allocation. Each scan
   preserves declaration order and uses exact case-insensitive matching.
   This cold bounded work introduces no threading or vectorization, and
   makes no speed claim.

The public Zig shape enum gains one case, so downstream exhaustive switches
must handle it. The C ABI, drawing-operation types, renderer interfaces and
Schemify record format are unchanged. A caller-provided symbol, side hints
or conflicting PININFO retain their existing precedence.

## Geometry scope and validation

The exact triangle/lead certificate uses the canonical pitch of 20, also
used by Schemify. It requires one unsigned triangle, one outward lead per
declared terminal, and an attachment to that triangle's own edge. It rejects
missing, duplicate, detached and orphan leads. Source omission of VSS does
not authorize omitting the declared native pin, and canonical VSS placement
does not claim a recovered source coordinate.

The general drawing API already accepts integer pitches from 4 through
1,000,000 and quantizes coordinates by integer division. At an odd pitch,
a bias lead's sloping-edge attachment can fall between integer coordinates:
pitch 5 places it at (-5, 7), while the ideal edge is at y=7.5. This existing
quantization is unchanged. The exact canonical-pitch certificate does not
establish exact edge attachment at every accepted pitch.

Before implementation, the eight consumer tests produced three passes and
five meaningful failures: source glyphs, declaration permutations and
absent rails, bias-alias geometry, PININFO imports, and plain source calls.
The plain-call failure independently exposed VREF emitted as an output.
The three passing controls covered lead-oracle mutations, near-miss boxes
and caller precedence. All 15 plain-call fixtures check emitted directions
and physical terminal-to-net bindings, without adding PININFO to repair
the input. The source inventory remains unchanged; final native, artifact and full-suite
results are recorded below.


## Native glyph and electrical-port certificate

The [native companion](figures/reference_amplifiers_native.py) compares the
frozen iteration17 and iteration18 executables using actual SVG strokes
assigned to each named native placement. All **15 boxes become unsigned
triangles**, with **all 68 declared electrical ports and ordered call
bindings preserved**. Each native port owns exactly one actual external
lead attached to its own body. The audit also rejects an orphan external
lead, a fabricated sign, an interior comparator step, or deleted VSS.

VREF and VEA are context-specific roles. The companion independently checks
VREF's lead against the unique triangle base and OUT/VEA against the apex;
a generic amplifier role lookup cannot establish this. The two signal
leads share the canonical local row and point outward in opposite
directions. This certifies local symbol construction, not agreement with
the source's world-facing direction or exceptional supply/bias placement.
The 15 absent source VSS coordinates remain unknown.

All 17 named source exclusions are retained: sixteen stay boxed and
AG2423 keeps its negative-input triangle. Twenty-four literal near misses
remain boxes. Eighteen positive policy variants check declaration order,
optional rails, and identical role geometry for VB1/VBN/NB across the four
families. Four explicit `*@ right VREF` declarations retain boxes with an
actual rightward reference lead. `*.PININFO` belongs to the Schemify parser,
so its compatible/conflicting shape decisions and exact I/O/B directions
are checked by the imported Schemify tests, not by the native JSON CLI.

The [native inventory](figures/reference_amplifiers_native_cases.json)
retains exact case and method names, source/dependency/executable hashes,
and a digest of every measured field. The complete 2,936-drawing comparison
changes exactly the fifteen selected AG drawings and their reports; every
AMS drawing/report is unchanged. All source, native and scorecard hashes
are checked. Fresh glyph renderings must match the scored JSON byte for
byte. The previously supported signed, comparator and digital glyph cohorts
also retain their independent actual-stroke checks.

```sh
python3 -B docs/research/figures/reference_amplifiers_native.py external/examples /tmp/reference-native /tmp/reference-native.json --baseline-bin /tmp/cktimg-human-rules/iteration17-bounded/cktimg-json --candidate-bin /tmp/cktimg-human-rules/iteration18-reference/cktimg-json --baseline-corpus /tmp/cktimg-human-rules/all-ag-iteration17-bounded --candidate-corpus /tmp/cktimg-human-rules/all-ag-iteration18-reference --baseline-corpus /tmp/cktimg-human-rules/all-ams-iteration17-bounded --candidate-corpus /tmp/cktimg-human-rules/all-ams-iteration18-reference --check
```

Nine literal and mutation checks challenge unsigned VREF/VEA geometry, added
polarity, an interior step, missing input lead, orphan lead, incorrect
binding, missing declared port, swapped signal positions, and native VSS
deletion. The baseline native SHA-256 is
`cb0acd3ffc56619b5f008e1487a08f093e42aee54945b02a46422a8f20ace9d0`;
the iteration18 candidate is
`c99fc4e18eaadd443a39c453207f50016710a387c0ea99cc339aaed061114248`.

## Physical continuity and named remaining failures

The [connectivity companion](figures/reference_amplifiers_connectivity.py)
compares every stable named device-pin pair on changed nets. The complete
corpus inventories, scored input/output hashes and exact fifteen changed
geometry/report names are checked first. The source report is independently
reexecuted against actual SVG leads before reference ports can enter the
connection graph. Primitive source pins keep their independent lead
certificates. Missing source VSS geometry and unknown custom blocks fail
explicitly; matching labels never connect physical ink.

The [full frozen result](figures/reference_amplifiers_connectivity_cases.json)
records twelve new physical separations and no new joins. Every transition
has source lead/ink evidence, with no unsupported case. Nine separations
break source-connected pairs; three match source separation:

| Drawing and net | Exact changed pairs | Source continuity | Candidate result |
|---|---|---|---|
| AG2415 VIN | M1.S–MCHG.S, M1.S–MRES.S, MCHG.S–MRES.S | Connected | Three missing joins |
| AG2428 VIN | M1.S–M4.S, M1.S–M8.S, M4.S–M8.S | Connected | Three missing joins |
| AG2436 net4 | M1.G–MSEN.G, M1.G–X1.OUT, MSEN.G–X1.OUT | Connected | Three missing joins |
| AG2434 VIN | M1.S–MCHG.S, M1.S–MRES.S, MCHG.S–MRES.S | Separate | Three source-agreeing splits |

These are correlated pair observations across four nets, not independent
examples or a whole-corpus agreement rate. The source expectations remain
unchanged. `--check` requires the exact recorded evidence and named
tradeoffs, including review of a future resolution. Adding
`--require-preserved` still fails on all nine source-connected losses.
That failure is not converted into a claim of preserved physical parity.
The earlier preservation oracle also remains unchanged.

```sh
python3 -B docs/research/figures/reference_amplifiers.py external/examples /tmp/reference-source.json
python3 -B docs/research/figures/reference_amplifiers_connectivity.py external/examples /tmp/reference-source.json /tmp/reference-connectivity.json --baseline-ag /tmp/cktimg-human-rules/all-ag-iteration17-bounded --candidate-ag /tmp/cktimg-human-rules/all-ag-iteration18-reference --baseline-ams /tmp/cktimg-human-rules/all-ams-iteration17-bounded --candidate-ams /tmp/cktimg-human-rules/all-ams-iteration18-reference --check
```

The [routing trace study](reference-routing.md) distinguishes the causes.
The three VIN groups stay in one routing round: their cluster spans grow
from 240 to 270, 230 to 260 and 240 to 270 against the existing 240-unit
limit. The input-port path chooses separate ports before attempting a
shared trunk; no thinning round causes these splits.

AG2436 has a different trace. Its first automatic route is connected but
crosses nonrail nets four times: net0 twice, VERR and VOUT. After thinning,
the next round forms the two-pin M1.G/X1.OUT group and the MSEN.G singleton.
The finite upper/lower routing candidates for the first group touch or
overlap the foreign net0 spine at x260, fail, and leave three labeled pins.
This is not a collapse of all pins into one named part. The full source
connection is bent, so an oracle restricted to source-straight gates would
miss this loss. Both compaction modes retain the named failure.

## Final checkpoint validation

The full suites pass **403 tests without LaTeX and 404 with it**, plus
4,000 fuzz cases, formatting and the checkpoint's style checks. All 31
gallery SVG names and bytes match the previous checkpoint. Each of the
fifteen changed drawings reproduces identical geometry and reports with
one and four jobs. All 2,936 corpus drawings render with the same two
source issues and no native findings. Partial all-relation counts remain
289/2,202 AG and 243/734 AMS; axes, gate-facing and block-flow measures do
not change. AG crossings rise from 4,982 to 4,988 and bends fall from
20,677 to 20,668; AMS remains at 203 crossings and 1,545 bends.

Real release-host Schemify round trips retain **98 exact fixture
comparisons**, with only the same named `rstring_ladder.spice` and
`write_dac.spice` capacity refusals. The selected fifteen source decks
produce **38 exact named subcircuits**. Current-host AG2420, AG2422, AG2427
and AG2444 produce **ten exact named subcircuits**, covering all four
families. Source deck hashes, full ordered comparison-name lists and
completion trailers were checked. Electrical equivalence does not erase
the nine physical-continuity regressions.

The final native SHA-256 is
`c99fc4e18eaadd443a39c453207f50016710a387c0ea99cc339aaed061114248`.
The plugin is **556,733 bytes**, SHA-256
`29d0644fef19fa0e969035d26a5f43ff14f3c80de35ea8e03f3157b38de73728`,
6,467 bytes below the strict cap. Repeated native and plugin builds are
byte-identical. This checkpoint establishes fifteen correctly recognized
local glyphs with preserved declared ports, while retaining failed
physical-parity evidence for the next placement/routing work.
