# Complementary mirrors feeding a center-tapped oscillator

The complete source census selects one seven-member stage: Analog-Genie
AG1146, `M1/M2/M3/M4/M5/M6/X1`. Two opposite-polarity diode mirrors feed a
reciprocal MOS pair whose drains meet one center-tapped inductor. The source
contains straight gate intervals for both mirrors. The native rule nominates
only the output mirror's actual `M3.G–M4.G` interval.

The [source reader](figures/ct_mirror_controls.py) and
[exact inventory](figures/ct_mirror_controls_cases.json) reselect all 2,936
paired decks, validate all 25,103 drawn transistor path/control bindings and
model types, and retain every source deck, SVG, human-cache and index hash.
The selected MOS leads come from actual transformed SVG primitives. The
coil's declared port order, call bindings and three actual leads are checked
against the frozen center-tap symbol certificate. Both gate paths use verified
conductor ink; cached-only strokes cannot supply a connection. Eleven named
mutation/permutation checks challenge admission. This is one correlated
source figure, not a universal current-mirror routing rule.

Admission counts the entire output-gate bridge and load-net incidences,
including body pins. The two mirror models must have known opposite
polarities and matching source/body rails; the two load MOS must have the
output mirror's polarity, reciprocal controls and the same body rail. All
seven members and six nonrail stage nets must be distinct. Every matching
complete center-tap contract counts before visibility or tap eligibility,
so an ineligible duplicate cannot disappear from ambiguity checks.

The cold routing query borrows the netlist and current canvas, returning an
optional pair of actual points. Its temporary stage is seven typed device
handles, 28 bytes, read together without an allocation or retained table.
It runs once per automatic net, outside candidate loops. Both gate leads
must be visible, on the same row, opposing, strictly between their own
aligned D/S ends, and equal to the actual routing pins. The interval must
pass current canvas clearance and contain no intervening same-net pin.
Explicit net styles, ports, routes, vias and first-net requests take
precedence, including a fixed pose on any stage member. Caller classes and
device poses are never rewritten. Original admitted routes and placements
are borrowed separately from the effective scaffold requests; scaffolding
may defer their execution without allowing automatic nomination to override
them. An unrelated fixed device does not disable the stage.

The trunk still compares full length, corner and crossing costs and retains
all obstacle and free-end checks. Only a full-cost tie may prefer candidate
ink covering the nominated interval. A cheaper legal route always wins.
The optional interval is real policy work; the separate fixed-target
`trunk_codegen.zig` probe checks only that the ordinary `draw` wrapper has no
extra overhead relative to calling `drawPreferred(..., null)` directly.
It is not a claim that the new feature is free.

The isolated private experiment used the immutable placement-a baseline.
Across all 2,936 drawings, only AG1146's JSON and report changed; the other
2,935 were byte-identical. Actual physical pin-pair comparison found no joins,
splits or unresolved correspondences, and retained existing mismatch
markers. Both compact modes retained the complete straight gate interval.
Six other named probe decks stayed byte-identical. An earlier broad tie
preference changed 56 AG drawings and introduced two source-disagreeing
joins in AG2511; it remains excluded. These isolated results do not replace
validation of the combined checkpoint21 implementation.

The focused regressions include the complete source deck, declared-port and
card reordering, a renamed control net, explicit caller directives with
parsed/admitted-request checks, and custom hidden/skewed/displaced pin frames.
Negative public comparisons give an opaque coil the identical caller glyph,
then compare every control-net conductor segment. A separate literal canvas
fixture compares two 1,180-unit, three-corner trees; it challenges the exact
cost tie, an extra foreign-wire crossing and forbidden collinear ink. The trunk-focused run passes all 60 tests, including the two new cost and
clearance cases. All four public tests now pass, including route/via/fixed
placement precedence and the unrelated fixed-device control. These tests
caught a scaffold bug: clearing effective routes and poses also hid caller
intent from nomination. Passing the two original borrowed slices fixes that
boundary without changing route execution or allocating another table.
The ordinary null wrapper initially produced two extra
instructions from error-union materialization; marking only that forwarding
wrapper `inline` makes the unchanged fixed-target check FOLDED, 19/19
instructions with identical direct call boundaries. Combined checkpoint
validation remains pending.

Reproduce the source certificate without a native binary:

```sh
python3 -B docs/research/figures/ct_mirror_controls.py \
  external/examples /tmp/ct-mirror-controls.json --check
```

The `--check` gate compares every field with the frozen inventory, including
exact names, source proofs and the transitive local reader dependencies.
The script requires no `/tmp` discovery artifact. Native validation remains
separate from source expectation: source continuity and straightness are not
changed to excuse an engine mismatch.
