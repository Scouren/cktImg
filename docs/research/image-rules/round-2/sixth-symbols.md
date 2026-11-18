# Sixth study: digital glyph completeness and intentional control boxes

The full 2,202-deck scan found **no remaining conventional digital family
that is boxed because its actual complete contract is unsupported**. All 56
conventional instances still draw their expected gate, buffer, or inverter
glyph with the frozen iteration-21 binary. The useful new work is narrower:
complete graphical side contracts for four intentional boxes, a native/plugin
default-side disagreement, and a concrete source bus versus scalar-port boundary.

This is research and an implementation plan. No engine, plugin, wasm, or
compiler output was changed. Current rules, the 84-header worktree delta,
`block_symbols`, `library.blockFor`, and the plugin recognition/layout/export
owners were read in addition to the retained full round-2 rules review.

## Exact coverage and evidence

`sixth-symbols-census.json` reruns the prior digital inventory against the
frozen binary with SHA-256
`bf7b0749bde5822a68aa93fd9df69eb6e007dee0c24d5e9961ff65b187483560`.
Its input provenance covers all 6,606 source `.cir`, `.svg`, and `.human.json`
files. `sixth-symbols-proof.json` independently records **all 941 outer X
calls**, each complete ordered formal/binding list, and all 52 family counts.
Names, rather than counts alone, are compared to the older inventory.

| Exact conventional family | Instances | Raw complete contract |
|---|---:|---|
| inverter | 46 | VDD VSS A Y |
| buffer | 2 | VDD VSS A Y |
| and_gate | 3 | VDD VSS A B Y |
| nand_gate | 2 | VDD VSS A B Y |
| xor_gate | 2 | VDD VSS A B Y |
| xnor_gate | 1 | VDD VSS A B Y |
| or_gate, nor_gate | 0 | No corpus occurrence |

These 56 instances span 23 decks. Adding the named PFD/DAC/CP counterexamples
gives 25 decks; eight further mixed-control decks give **33 source/native
pairs actually viewed anew**. Each side was independently rasterized before
PNG composition; no SVG was embedded inside another SVG.
`sixth-symbols-renders.json` and `sixth-symbols-views.json` bind all 33 fresh
observations to their files and hashes. The larger repeated inverter scenes
were viewed as overviews; their ordered geometry was checked from actual
SVG and JSON rather than pretending each small label was visually resolved.

The bounded opaque cohort is **15 instances, 11 exact families, 66 raw
formals, and 57 visible source own leads**. All 15 actual source bodies and
all 15 native bodies are boxes. This does not classify every arbitrary
subcircuit in the 941-call census as digital, analog, or safe to reinterpret.

| Exact source/native instances | Family | Complete raw formals |
|---|---|---|
| 439:XPFD, 440:XPFD | PFD | A B QA QB |
| 515:X1 | DAC | OUT1 OUT2 |
| 516:X1 | DAC | O1 O2 |
| 1070:X4, 1070:X5 | CP | VDD VSS CAL_BAR OUT OUT_BAR VC |
| 715:X1 | CMFB | VOUTP VOUTN VCNTRL |
| 784:X1 | translinear | O1 O2 C1 C2 I1 I2 |
| 788:X1 | GM | INN INP VC OUT |
| 788:X2 | LPF | IN OUT |
| 923:X1 | CM_Detect | IN1 IN2 OUT |
| 1146:X2 | varactor_switched_caps | VON VOP B_3_ B_2_ B_1_ B_0_ VCN VCP |
| 1440:X1 | ZCD | VDD VSS INN OUT |
| 1457:X1 | ZCD | VDD VSS INN OUT VB1 |
| 2469:X1 | stage1 | VDD VSS VIN VREF VFB VX2 VX1 |

All bindings and actual label text are in the proof JSON. For example,
AG1070:X4 binds OUT/OUT_BAR to `out/out_bar`, while X5 binds them to
`out_bar/out`. Their source boxes also face opposite ways. A family-wide
whole-symbol reflection would not express those separate electrical and
geometrical facts safely.

## New complete box-side certificates

The four source certificates use the actual unique SVG object, actual closed
box, each own lead, visible port text, and a reviewed literal label anchor.
The actual visible text must agree with `data-pin-name`; the metadata alone
does not establish the port. Each literal external tip has one own stroke,
that stroke ends at the first intersection with the actual box, and the
whole box lies behind the tip. No cached terminal or cached net is used to
establish a contact or binding.

| Source | Ordered bindings | Actual external tips, in formal order |
|---|---|---|
| AG439 PFD | a b qa qb | (80,140), (80,200), (180,140), (180,200) |
| AG440 PFD | a b qa qb | (70,140), (70,230), (170,140), (170,230) |
| AG515 DAC | net1 net0 | (30,110), (30,170) |
| AG516 DAC | net0 net2 | (30,80), (30,130) |

This proves **12 complete graphical contacts** for two exact box policies:

* Whole family `PFD`, exactly unique A/B/QA/QB: A and B on the left;
  QA and QB on the right. Preserve their raw declaration and binding order.
* Whole family `DAC`, exactly O1/O2 or exactly OUT1/OUT2: both contacts
  on the right. Do not accept a mixture, an extra control, or a prefix name.

These are graphical side choices for boxes. They do not certify a PFD truth
table, edge-trigger convention, output complementarity, DAC conversion
behavior, or electrical input/output direction. The relevant definitions
are empty stubs, so those functions cannot be recovered from their bodies.
No new conventional gate shape is proposed.

The research predicate's full-corpus set is exactly
`ag-439:xpfd`, `ag-440:xpfd`, `ag-515:x1`, `ag-516:x1`.
It is invariant to raw formal/call permutation, instance renaming, and net
renaming. Extra/missing/duplicate ports, short/long calls, a prefix family,
and lookalike names decline. Source mutations reject wrong object identity,
swapped visible text, swapped metadata, stale label anchors, a missing own
lead, and duplicate attached labels. Corrupting cached tips, cached nets,
wires, and labels leaves the independent source certificate unchanged.

Independent review found that translated or hidden actual text and hidden own
strokes could pass the first version while retaining the same cached anchors.
The repaired bounded certificate rejects unsupported visibility/style scopes
and transformed or independently shifted label descendants. Six new controls
cover those cases; all four original positives still pass. The independent
pre-fix witnesses and repair replay remain in `seventh-review-symbols-before.json`
and `seventh-review-symbols.json`. This is a conservative four-example source
certificate, not a general SVG text renderer.

## Native defaults, caller precedence, and the plugin boundary

AG439/440 native PFD contacts are all on the left in the **canonical frame**.
This is not a world-pose illusion: the native instances have no reflection
or rotation, and `library.defaultSide` falls back to `.left` for all four
names. AG516's O1/O2 contacts have the same issue. In contrast, AG515's
OUT1/OUT2 contacts already occupy the canonical right side; automatic
whole-symbol mirroring puts them on the world left. The two DAC observations
therefore require different conclusions.

The plugin's unknown direction fallback is different. `recognize.portDir`
returns `.inout` for A, B, QA, QB; `boxLayout` places every non-input on the
right. Thus source-reading the plugin predicts an all-right PFD box without
PININFO, while native execution produces all-left. This plugin prediction
has not been executed through a new wasm build or editor import here.

`sixth-symbols-fixtures.py/json` materializes **11 frozen-CLI experiments,
16 complete X calls**, with every ordered binding checked against saved
native JSON. All 11 resulting PNGs were actually viewed.

* PFD explicit left A/B and right QA/QB produces the intended two-sided
  box. Simultaneously permuting declaration and call preserves the same
  semantic contact coordinates and bindings.
* The same two-sided box with `*@ at XPFD -30 -30 mr90` preserves the
  caller's exact `(-1200,-1200)`, rotation 1, mirror true frame. Its
  canonical contacts remain unchanged. The very large world route is a
  consequence of the requested remote placement, not an automatic policy.
* DAC O1/O2 explicit right hints establish canonical right contacts. Its
  automatic pose can still mirror the whole box; a side policy does not
  claim to reproduce the source world arrangement.
* Adding PFD `*.PININFO A:I B:I QA:O QB:O` leaves native SVG bytes exactly
  unchanged. Code reading predicts the intended plugin two-sided box.
* A complete XOR draws conventionally. Adding an ENABLE formal or changing
  the whole family to `xor_gate_extra` produces a box with all ports retained.
* Explicit `*@ right A` makes the XOR use a caller-directed box. A conflicting
  `*.PININFO A:O ... Y:I` leaves the native XOR byte-identical, while the
  plugin's `boxPins` would reject the conventional glyph because explicit
  directions disagree with its left/right terminals.

These fixtures prevent a future implementation from treating native comment
handling as proof of plugin parity. Registered caller library classes also
precede generated classes in `blockFor`; the fourth-study custom-symbol
fixtures remain the independent controls for that boundary.

## Source omissions and the bus boundary

AG1146's eight-port declaration cannot be certified as eight distinct source
contacts. Its actual box has five own leads: VON, VOP, VCN, VCP, and one
visible `B<3:0>` contact. The human cache assigns that bundled contact no
single net. The native box retains all four `B_3_` through `B_0_` scalar
bindings separately. The source proves a bundled visual representation;
it does not prove a short between those four nets or a scalar tip for each.

Any future bus display needs an explicit ordered member-to-display-contact
relation, with the four logical terminals retained through export and
round trip. It must not be implemented as four terminals sharing an ordinary
electrical coordinate unless the editor/exporter has a proven bundle type.
This is separate from recognizing a conventional gate and from the nine-port
amplifier capacity work in the third study.

CP1070 and both ZCD examples omit a declared VSS lead in source ink; stage1
omits both VDD and VSS. These omissions account for six more missing scalar
source contacts. The 66 raw formals therefore map to 56 individually named
source contacts, plus one bundled contact representing four scalar bits,
plus six undrawn rail terminals. All 66 native scalar pins remain present.
Neither caption words nor VC/VX naming certify a new gate or signed role.

## Actual digital body contact: a precise remaining RED set

The independent ray/outline oracle intersects each actual native own-lead
ray with its own polygon and, where relevant, its inversion bubble. Of the
232 native digital terminals, 226 strokes terminate at their first body
contact. Exactly six strokes overshoot slightly into the outline:

`ag-438:x1:vdd`, `ag-438:x1:vss`, `ag-545:x1:vdd`,
`ag-545:x1:vss`, `ag-1076:x5:vdd`, `ag-1076:x5:vss`.

At pitch 20, their external tip is `(0,±60)` and their attachment is
`(0,±35)`. The actual slanted edge crosses x=0 at
`y=±35.263157895`, so the stroke extends 0.263157895 along its own direction
inside the outline (0.250943 perpendicular distance in the earlier audit).
This is an **attachment overshoot**, not a terminal-tip containment failure,
missing wire, or changed binding. The terminal remains outside the whole
body. The defect is small and graphical, but the exact named RED set prevents
an inflated claim that every stroke already stops at its own boundary.

A literal square gives independent exact-contact, gap, and overshoot controls.
The known RED set is asserted by name; an unexpected disappearance fails the
research replay until the marker is deliberately retired. Source digital
rails are not drawn, so their 112 native power contacts are a completeness
choice rather than matched source geometry.

Independent frozen-CLI OR/NOR sibling fixtures also show the same exact 5/19
inward rail overshoot; a supply-less XOR keeps all three signal contacts at
first contact. Those results extend the shared-outline mechanism coverage,
not the corpus counts: OR/NOR still have zero occurrences here. The peer
review records an exact rational edge oracle in `seventh-review-symbols.json`.

## Smallest implementation plan

1. Keep the 56 conventional contracts and all unknown-control declines.
   Do not add PFD, DAC, CP, ZCD, GM, or a bus-controlled analog block to the
   gate-alias table on naming alone. Existing glyph admission needs no
   broader alias change for this corpus.
2. If adopting the four box-side cases, resolve the complete exact contract
   once at the cold class boundary. A small closed two-case policy is enough:
   PFD and the two exact DAC pair schemas. Borrow ordered port names and emit
   side defaults into existing caller-owned side/slot storage; maximum four
   ports, no hot table, retained allocation, or index-width expansion.
   Keep names/indices/raw bindings untouched. The result owns graphical
   defaults only; it does not change electrical directions.
3. Have native `library.blockFor` and plugin `recognize.boxPins` consume that
   same policy before the existing box slot layout. Caller classes, explicit
   sides, and explicit PININFO remain authoritative. An explicit QA-left or
   A-output instruction must not be silently undone. In the plugin, resolve
   this before `layout.library`/`cellDeck` replace original families with
   generated `b<s>` names; preserve the existing registered class and export
   geometry. No generated-name prefix recognition is acceptable.
4. Keep world-facing selection separate. The DAC515/516 pair and the mirrored
   fixed PFD fixture distinguish canonical contact choices from pose. A class
   cache may share this immutable side layout, but a caller's per-instance
   pose or custom symbol remains instance-owned.
5. For rounded gate attachment cleanup, make the outline and attachment
   construction share an exact integer contact. One concrete option is an
   explicit x=0 outline vertex at the chosen rail attachment, scaled by the
   same integer routine; another is an exact supported intersection rule.
   Do not merely round a floating intersection independently and claim exact
   contact. Check legal small/odd pitches, maximum pitch, every rotation and
   reflection, and the extra XOR input curve. This changes only glyph ink;
   semantic pin coordinates, class bounds, and raw port order can remain.
6. Before acceptance, turn the three native canonical-side disagreements
   into RED assertions (PFD439/440 QA/QB; DAC516 O1/O2), retain DAC515 as a
   keep control, and retain all exact 56 digital names and 15 opaque names.
   Run the 25 source/raw/contact mutations, the 11 frozen fixtures, and new
   actual plugin import/netlist round trips for PFD/DAC/PININFO/custom-class
   cases. A plugin code-read expectation is not that round-trip oracle.

The side-policy change radius is the shared cold resolver, native box fallback,
plugin box fallback, and their literal/round-trip tests. It requires no global
`named()` QA/O prefix rule, no drawing-library interface redesign, and no
placement or routing owner change. A new box family changes only the exact
policy table and its proof; a new caller pose changes no policy code; a new
net spelling changes no policy code. The rounded-outline cleanup is a separate
`block_symbols.draw` change and test set. Bus presentation remains a separate
editor/exporter capability requiring its own data contract.

Replay the retained evidence without a compiler:

```sh
python3 -B docs/research/image-rules/round-2/sixth-symbols-proof.py --check docs/research/image-rules/round-2/sixth-symbols-proof.json --output /tmp/cktimg-sixth-symbols-proof.json
python3 -B docs/research/image-rules/round-2/sixth-symbols-fixtures.py --execute --check docs/research/image-rules/round-2/sixth-symbols-fixtures.json --output /tmp/cktimg-sixth-symbols-fixtures.json
```

The prior full-corpus producer remains executable as
`docs/research/figures/digital_symbols.py`; supply the pinned binary and a
fresh native output directory to regenerate the corpus evidence. Source
provenance, current code hashes, independent raster commands, fresh view
notes, and the exact unresolved geometry names are retained separately.
