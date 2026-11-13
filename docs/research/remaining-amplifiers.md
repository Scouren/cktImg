# Remaining amplifier glyph contracts

The engine now recognizes exact `A1`, `EA1`, and `AEA` names under its
existing complete amplifier port contract. The validation below preserves
port roles and caller-supplied electrical directions. The
reproducible inventory is
[`figures/remaining_amplifiers_cases.json`](figures/remaining_amplifiers_cases.json).

```sh
python3 -B docs/research/figures/remaining_amplifiers.py external/examples /tmp/remaining-amplifiers.json
```

The audit scans all 2,202 AG and 734 AMS outer decks through the existing
center-tap census. It then inspects each selected instance's own SVG group:
130 instances across 19 explicitly listed families unrecognized before this
change.
All 130 are AG. This is not an inventory of every incomplete contract in
already recognized families. The JSON retains exact names, ordered ports,
bindings, outlines, all external lead paths, polarity strokes, cached frame
disagreements, and hashes of every source triple and audit dependency.

## Small complete-contract extension

Exact whole names `A1`, `EA1`, and `AEA`, using the existing complete
amplifier contract, select 39 observed triangles:

- `A1`: 37, all with independently identified plus/minus input leads and
  one apex output. Exact names are `families.a1.complete` in the inventory.
- `EA1`: `ag-1233:x1`, plus/minus pair and apex output.
- `AEA`: `ag-2423:x1`, one negative input and apex output, with a separate
  `VB` bias lead. The source has no second input or plus mark.

The contract has one output, one signed/unsigned input or a signed pair,
optional unique supply/ground and `VB`/`VB1`/`VB2`/`VB3` roles, and no unknown
or duplicated role. It is insensitive to declaration order and case. This
is a bounded extension to `block_symbols.identify`, not a rule
that arbitrary `A*` names are amplifiers. The 12 literal, named predicate
checks are retained in `method_checks`; complete instance names are checked
against a literal list, not a count.

All 37 selected A1 triangles point right. In 36 the negative input is above
the positive; `ag-1708:x1` reverses that order. EA1's selected triangle points
left. These are separate layout observations, not additional aliases or
universal input ordering requirements. Existing facing/explicit symbol
precedence must remain independent of recognition.

Every selected source omits `VSS` from its cached terminal table and has
exactly one fewer external SVG lead than declared ports. This supports a
missing source lead, **not a known hidden terminal coordinate**. The native
glyph continues preserving every declared electrical port,
including VSS, rather than reproducing that omission electrically.

Nine complete candidates have stale cached signal coordinates:
`ag-1233:x1`, `ag-1464:x1`, `ag-1504:x1`, `ag-1593:x1`, `ag-1629:x1`,
`ag-1704:x1`, `ag-1705:x1`, `ag-1724:x1`, and `ag-2423:x1`.
Actual marks identify the signed input leads and the actual apex identifies
the output independently. The inventory preserves those corrected signal
points. Other mismatched source supply/bias positions remain explicitly
unmapped; notably AG1464's VB2/VB3 positions are not certified by this audit.
The contract can assign named canonical bias pins without claiming their
source-specific coordinates have been recovered.

## Counterexamples to broader recognition

The 63 A1 instances include five actual rectangles:
`ag-1751:x1`, `ag-1752:x1`, `ag-1760:x1`, `ag-1773:x1`, `ag-1778:x1`.
None passes the complete contract. More decisively, AG1510 and AG1752 have
the identical ordered declaration `VDD VSS INP INN OUT Z`, but the former
uses a triangle and the latter a box. AG1642/1751 similarly disagree for
the same unordered port set with `VZ`, `VB1`, and `VB2`. Thus merely admitting
unknown extra controls would erase an observed shape distinction. These
are finite source exceptions; this audit makes no claim that declaration
order or an instance ID is an acceptable rendering rule.

EA1 has 21 triangles and one rectangle, `ag-1289:x1`. The same unordered
set `{VDD,VSS,VFP1,VREF,VX3,VCTRL}` appears as triangles in AG1249, AG1263,
and AG1276. Seven EA1 triangles have a signed pair; the other 14 triangles
have no polarity marks. Naming `VREF` negative and `VFP1` positive globally
would invent marks in those unsigned cases.

Other apparent amplifier names also retain real boxes: `OTA` in AG1730,
`PREAMP` in AG748, `GM` in AG788, `DA`/`PA` in AG1103, and `DDA` in AG1094.
AG788's `LPF` has an otherwise simple `IN OUT` contract but remains a filter
box. Exact `ERRAMP` in AG2442 is a box, while distinct `ERROR_AMP` instances
use triangles. No fuzzy family matching is justified.

## AG1316's unsigned eight-port EA1

Its exact declaration is `VDD VSS VFP1 VREF VX2 VB1 VISR VX1`. All seven
visible source leads can be identified without trusting SVG line order:

| Port | Actual endpoint | Actual source evidence |
|---|---|---|
| VDD | (220, -100) | Conductor reaches the labeled VDD supply's actual terminal at (220, -110). |
| VREF | (250, -70) | Conductor reaches the labeled VREF port at (260, -70). |
| VB1 | (190, -100) | Labeled VB1 port has its actual terminal at this point. |
| VISR | (160, -50) | Unique triangle apex; physical wire reaches actual M5.D at (90, -70), whose declared net equals VISR's call binding `net0`. |
| VFP1 | (250, -30) | Declared cached port agrees with its actual base lead; source labels it VFP1. |
| VX2 | (210, 20) | Declared cached port agrees with its actual lower lead; source labels it VX2. |
| VX1 | (140, 20) | Declared cached port agrees with the bent lower lead; source wire joins the input-side coil node. |

The proof retains the actual conductor paths, marker identities, label text,
and named external transistor binding. Four cached coordinates disagree:
VDD, VREF, VB1, and VISR. VSS has neither a cached terminal nor an eighth
external lead. The body is left-facing and unsigned; VREF/VFP1 enter its
right base, VB1/VDD attach above, and VX1/VX2 below. This exact contract is
a plausible additional glyph with two unsigned base inputs and extra control
leads. It needs distinct port roles and tests before implementation; it does
not fit the existing single-unsigned-input amplifier contract. The drawing
alone does not establish current-transfer behavior or justify treating
every auxiliary lead as an electrical output.

## Next bounded followup

Fifteen instances in exact `AEA`, `ERRORAMP`, `ERROR_AMPLIFIER`, and
`ERROR_AMP` families declare a `VREF`, one `OUT`/`VEA`, optional supply/ground,
and at most one observed `VB1`/`VBN`/`NB` bias. All have one unsigned base
lead and an apex output. Exact names are `unsigned_reference_followup`.
This is an explicitly deferred candidate: many cached coordinates are stale,
so recovering all named supply/bias mappings from actual labels and wire
ink remains necessary before calling it a complete source mapping. Larger
AEA contracts include extra controls and, in AG2404, three base leads;
they must not be swept into a one-input reference-amplifier rule.

The source inspections include visual checks of AG1316, AG1510, AG1752,
AG1708, and AG2423. The source audit performs no native build, glyph
generation, or electrical direction override.

## Implementation validation

The runtime change adds three whole names to the existing amplifier alias
list. The existing shape, port-role validation, drawing, declaration order,
and caller precedence remain the shared implementation. The native and
Schemify tests in `tests/remaining_amplifiers.zig` cover all 39 literal source
contracts, named signs, case and declaration permutations, unknown controls,
explicit sides, caller classes, PININFO metadata and project library cells.
The older generic A1 box control now uses AG1752's actual six-port contract
with its unknown `Z` terminal.

Before the alias change, the source glyph, permutation and compatible
PININFO tests failed; exclusion and caller-precedence controls passed.
Afterward all six focused groups pass, with 377 tests without LaTeX and
378 with it, 4,000 randomized circuits, global formatting and changed-file
style checks. All 31 gallery SVGs are unchanged. All 39 changed drawings
reproduce identical geometry and reports in serial and four-job runs.
The full corpus and previous named layout cohorts remain validated; the
[scorecard](corpus-scorecard.md) records the measured scope and limits.

Real Schemify round trips retain 98 fixture comparisons and the same two
capacity refusals. The 39 source decks yield 79 exact subcircuits, and six
representative current-host decks yield 13, including excluded AG1752 and
AG1289. Exact subcircuit names are checked against their declarations;
the nine overlapping release/current comparison certificates agree.

The plugin is 562,726 bytes, eight bytes larger than pass 15, SHA-256
`cb8ddfc507833aba15480a38970357247c0c9190252ff8e518abcaf63e1a1922`.
It remains 474 bytes below the strict 550 KiB cap. Repeated native and
plugin builds are byte-identical. Actual source/native views of AG1233,
AG1464, AG1708 and AG2423 confirm the restored symbols and the remaining
facing, input order, bias position and whole-layout differences.

## Independent native glyph replay

[`figures/remaining_amplifiers_native.py`](figures/remaining_amplifiers_native.py)
replays every source field for all 108 exact A1/EA1/AEA instances before
inspecting their own native SVG ink. Frozen pass 15 draws all 108 as boxes.
Pass 16 changes exactly the 39 complete contracts into plain triangles with
the expected signed base leads and apex output. All 69 incomplete source
contracts stay boxes, including the source triangles with unknown controls;
13 literal prefix, suffix, missing-port, duplicated-role and extra-control
counterexamples also remain boxes in both snapshots.

The audit preserves all 680 ordered declared port/net bindings across those
108 source instances, including all 210 bindings in the 39 promoted glyphs.
Every native pin must end at a distinct lead attached to its own body's
boundary. The SVG transform is fitted from wire coordinates and verified
against every wire vertex before assigning a body, sign or lead. Neighboring
triangles cannot satisfy a target box. Literal mutations reject a missing,
wrong or displaced sign, an extra comparator step, a misplaced output, and
changed ordered electrical bindings.

All 39 new bodies measure 80 by 80 native units, rendered at scale 1.6 as
128 by 128 pixels, with 11-pixel reference labels. This confirms the observed
display dimensions; it does not establish source dimension, facing or bias
order parity. The nine cached signal-frame disagreements and missing cached
VSS geometry remain explicit in every replay. The AEA case has exactly its
single negative mark, with no invented positive input.

The full directory comparison checks every named source drawing against
both completed scorecards and their frozen renderer hashes. Across all
2,936 paired drawings (2,202 AG and 734 AMS), exactly the 39 selected AG
drawing names change; all other native JSON bytes are unchanged. This is
separate from source agreement and from the electrical round trip.

The frozen binaries are pass 15
`0bb2a942947e5d2a602a2cb23695c56ef4da90f43e8521ff8b0a3976757738cb`
and pass 16
`bc2600ab737626e56098dbf7c2c5610c720ddc9dd2feb65783e8f50759fc9fac`.
[`figures/remaining_amplifiers_native_cases.json`](figures/remaining_amplifiers_native_cases.json)
retains exact positive and negative names, summaries, dependency hashes,
and a canonical digest of every complete replay field. `--check` verifies
that digest, including all native outlines, leads, signs and file hashes.

```sh
python3 -B docs/research/figures/remaining_amplifiers_native.py \
  external/examples /tmp/remaining-native /tmp/remaining-native.json \
  --baseline-bin /tmp/cktimg-human-rules/iteration15-corrected/cktimg-json \
  --candidate-bin /tmp/cktimg-human-rules/iteration16-aliases/cktimg-json \
  --baseline-corpus /tmp/cktimg-human-rules/all-ag-iteration15-corrected \
  --candidate-corpus /tmp/cktimg-human-rules/all-ag-iteration16-aliases \
  --baseline-corpus /tmp/cktimg-human-rules/all-ams-iteration15-corrected \
  --candidate-corpus /tmp/cktimg-human-rules/all-ams-iteration16-aliases \
  --check
```
