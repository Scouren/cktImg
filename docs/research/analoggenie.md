# Learning layout rules from AnalogGenie

The useful unit is a drawing decision with its conditions: which path a
device belongs to, whether it stands upright, what it lines up with, and
where a connection branches. A circuit name alone does not decide these.
The same MOS symbol is upright in a gain stage and horizontal in a sampler.

## Sources and method

The references are the cached
[AnalogGenie SVGs](../../external/examples/analoggenie), not the generated
gallery in `assets/`. Each `ag-N.svg` is the Analog Canvas redraw of figure
N; `index.json` records its description and preview revision. Its paired
`ag-N.human.json` records the redraw's terminal coordinates, nets and wires,
and `ag-N.cir` is the corresponding circuit. These are textbook-derived
redraws, not scans of the original textbook pages. The download and
conversion provenance lives in [fetch.py](../../tools/site/fetch.py) and
[convert.py](../../tools/site/convert.py).

For each proposed rule:

1. View the source SVG, identify the devices and name the geometric
   relation. Record a positive case and a nearby counterexample before
   changing the engine.
2. Express the condition using connectivity, pin roles and already known
   structure. Keep figure IDs, component names and clock spellings out of
   the decision procedure.
3. Check that condition across the source geometry. Count eligible devices
   and report the named failures, not just the drawings that look better.
   Repeated sampler and converter families are not independent evidence
   for unrelated circuit classes.
4. Put the rule in the stage that owns the decision. Record it in that
   file's `Human Rules`, including its scope and whether it is an
   invariant, a measured habit, or an unmeasured choice.
5. Write the regression against the source's geometry. For a horizontal
   transistor, its drain and source have equal y and different x; this is
   independent of the code that chooses its form. Assert the corresponding
   relation on the generated terminals, rather than snapshotting whatever
   the generator emits.
6. Keep negative cases and circuit-preservation checks alongside the new
   examples. Permuting cards must preserve the decision; renaming devices
   must preserve the selected form. An explicit `upright` line wins;
   existing `above` and `face` constraints that require upright form still
   apply. The current hint language does not accept `bridge` for MOS devices.
7. Inspect the resulting whole schematic. Correct orientation alone does
   not prove good placement, readable routing, or equivalence to the input
   circuit. Run the existing connectivity, shorts and round-trip oracles.

## What the engine already represents

| Human decision | Existing owner and scope |
|---|---|
| Recognize pairs, mirrors, banks, cross-couplings and stacks | [structure.zig](../../src/structure.zig); connectivity supplies the groups. |
| Preserve an exact left-right circuit symmetry | [symmetry.zig](../../src/symmetry.zig), [mates.zig](../../src/mates.zig); terminal identity is preserved. |
| Current paths upright, signal transfer left to right | [forms.zig](../../src/forms.zig), [levels.zig](../../src/levels.zig), [columns.zig](../../src/columns.zig), [span.zig](../../src/span.zig). |
| A gate level with its driving junction; a tail between the pair | `levels` and `columns`; matching and current paths take precedence over wire length. |
| A series connection placed between its endpoint columns | [bridges.zig](../../src/bridges.zig); channel endpoints must be used for a transistor, not its gate or body. |
| Rails, local gate lines and repeated bias ports | [wires.zig](../../src/wires.zig), [trunk.zig](../../src/trunk.zig); patterns precede general routing. |
| Feedback around amplifier blocks, signal chains along inputs | [opamp.zig](../../src/opamp.zig), [opamp_grow.zig](../../src/opamp_grow.zig); applies to amplifier blocks and two-pin parts. |
| Close empty space without changing established relations | [compact.zig](../../src/compact.zig); [checks.zig](../../src/checks.zig) independently checks electrical drawing guarantees. |

These stages already express much of the textbook grammar. The gap studied
here is the exception to `forms.4`: a MOS channel can belong to a horizontal
signal or compensation path even though its gate and body remain connected.

## Sixteen source observations

Every link opens the person's drawing. Device names below are the paired
deck's names; a redraw can print a different name on the symbol.

| Source | Observed decision and its condition |
|---|---|
| [ag-100](../../external/examples/analoggenie/ag-100.svg) | R1 and R2 form an upright divider; M1's gate lies at their junction. A driver-to-gate connection aligns a junction with a gate, not necessarily two device centers. |
| [ag-127](../../external/examples/analoggenie/ag-127.svg) | Two common-source stages run left to right while their devices remain upright. The stage ordering and device orientation are separate decisions. |
| [ag-208](../../external/examples/analoggenie/ag-208.svg) | RF is horizontal above the input gate, returning from the output. Feedback has its own path outside the gain device. |
| [ag-385](../../external/examples/analoggenie/ag-385.svg) | M1 lies along Vin-to-Vout; CH hangs down from Vout. The clock enters M1 from above. A sampler's channel follows the signal. |
| [ag-386](../../external/examples/analoggenie/ag-386.svg) | M1 and M2 form parallel horizontal transmission paths; the two clocks approach from opposite sides. A complementary pair is not automatically a vertical CMOS stage. |
| [ag-389](../../external/examples/analoggenie/ag-389.svg) | Two sampling paths occupy separate horizontal rows with their hold capacitors at the outputs. Repeated paths share orientation without becoming a differential pair on a tail. |
| [ag-514](../../external/examples/analoggenie/ag-514.svg) | Four mixer switches have horizontal channels and vertical LO controls. Their crossed connections do not make their channels vertical. |
| [ag-738](../../external/examples/analoggenie/ag-738.svg) | M6, printed Q1, and Cc lie in the compensation path between stages. Its connection to an active stage does not make the switch part of that stage's vertical current column. |
| [ag-995](../../external/examples/analoggenie/ag-995.svg) | MR1 is horizontal in series with Cc1 although its gate is tied to a rail. Clock-name recognition would miss this nulling resistor. |
| [ag-343](../../external/examples/analoggenie/ag-343.svg) | M15 is horizontal beside CC, controlled by a separate bias network. A transistor's channel and the circuit that drives its gate have separate layout roles. |
| [ag-769](../../external/examples/analoggenie/ag-769.svg) | M9, printed Q9, bridges the two source-side nodes horizontally. The surrounding gain and bias devices remain upright. This is a symmetry-spanning degeneration element, not a sampler. |
| [ag-771](../../external/examples/analoggenie/ag-771.svg) | M3 and M4 form two horizontal paths between Vx and Vy; their gates face away from the space between them. Parallel paths need their own rows. |
| [ag-236](../../external/examples/analoggenie/ag-236.svg) | M1 is an upright common-gate current buffer even though neither channel end reaches a drawn rail. Absence of a rail is insufficient evidence for horizontal form. |
| [ag-425](../../external/examples/analoggenie/ag-425.svg) | M1 remains upright inside a Colpitts tank model with capacitors on its channel and no conducting path to a rail. Its capacitors join its own terminals; the selected rule excludes them. |
| [ag-1039](../../external/examples/analoggenie/ag-1039.svg) | Reset/feedback switches M7 and M9 stand upright from output buses to capacitor-fed input nodes. A capacitor at a leaf channel endpoint can still belong to a vertical feedback branch. |
| [ag-1054](../../external/examples/analoggenie/ag-1054.svg) | M27 and M28 lie along the capacitor signal paths, while M23–M26 hang down toward VB1. A switch that clamps a signal to a bias follows the shunt branch instead of the signal row. |

## The selected form rule

The selected rule is a conservative MOS exception in `forms.classify`,
with bridge placement using the transistor's channel endpoints. It needs
no new public setting or name-based circuit recognizer.

For a drawn MOS device with channel ends a and b and gate g:

1. Keep the existing treatment of a shorted channel. Require distinct a,
   b and g for this rule, and require that neither a nor b is a rail.
2. Find a capacitor incident on a or b whose other terminal is none of
   a, b or g. A shorted capacitor, one across the channel, or one between
   the channel and its own gate supplies no evidence for this rule.
3. Lay the channel horizontally if its DC component reaches no supply or
   ground. Otherwise require both that the capacitor-bearing endpoint has
   no other DC channel element and that the opposite channel endpoint
   drives another transistor's gate or base. Retain upright form when
   neither condition holds.
4. Place the bridge using the actual drain and source nets; its gate lies
   on a side perpendicular to that path. A body connection must not be
   mistaken for a bridge endpoint.
5. Include a horizontal MOS in the existing series-chain placement when
   its channel joins a horizontal two-ended part through a net with just
   those two current paths. Keep the chain on one row in connection order.
   Gate and body connections on the junction do not add current paths;
   a shorted MOS channel does not extend a chain.

DC paths mean the existing device table's current-carrying terminals;
capacitors, gates, bodies and block ports do not create those paths. The
leaf condition with a gate load admits a series Miller switch even when
its other endpoint belongs to a stage with a path to a rail. The component
condition admits a transmission gate whose parallel transistor prevents
either endpoint from being a leaf. Restricting the new rule to MOS devices
avoids assuming that a BJT's collector-emitter path is an interchangeable
switch channel.

The chain extension belongs to `bridges.1`, rather than a later repair of
wire routes. It uses each device's actual path, so ag-738's M6 and Cc and
ag-995's MR1 and Cc1 occupy consecutive positions on the same row between
their stages. The source geometry supplies two separate oracles: the MOS
and capacitor share a row, and the stage-to-MOS-to-capacitor-to-stage order
follows the connection. The regressions in
[skeleton.zig](../../tests/skeleton.zig) check that row and order;
[sketch.zig](../../tests/sketch.zig) checks the rendered terminals. These
checks caught the earlier implementation that changed the MOS's form
while placing the two series elements separately.

The gate-load requirement came from negative cases:
[amsnet-44](../../external/examples/amsnet/amsnet-44.svg) is an upright
capacitor-loaded device above a current source, and
[amsnet-181](../../external/examples/amsnet/amsnet-181.svg) and
[amsnet-182](../../external/examples/amsnet/amsnet-182.svg) are upright
cascode branches with a capacitor at a free channel end. The latter also
shows why a capacitor across the device's own channel is insufficient.

## Measured evidence and limits

[mos_forms.py](figures/mos_forms.py) independently parses the last
subcircuit of each paired deck, evaluates the predicate and reads the
human drawing's drain/source coordinates. It imports no engine code.
From the repository root, reproduce the two measurements with:

```sh
python3 docs/research/figures/mos_forms.py external/examples/analoggenie /tmp/ag_mos_forms.json
python3 docs/research/figures/mos_forms.py external/examples/amsnet /tmp/amsnet_mos_forms.json
```

The denominator is the MOS devices the predicate selects, not all MOS
devices and not the number of generated schematics that look good.
AnalogGenie's 2,202 drawings contain 21,495 MOS devices, of which 1,455 are
horizontal in the source. The rule selects 239 of those horizontal devices;
it addresses the stated conditions rather than all reasons for drawing a
MOS horizontally.

| Source subset | Horizontal in the source / selected | Circuits |
|---|---:|---:|
| AnalogGenie, union of both conditions | 239 / 243 | 143 |
| AnalogGenie, leaf endpoint with opposite gate/base load | 56 / 58 | 53 |
| AnalogGenie, isolated DC component with a qualifying capacitor | 186 / 188 | 93 |
| AnalogGenie, source ID modulo five nonzero | 197 / 201 | 117 |
| AnalogGenie, source ID modulo five zero | 42 / 42 | 26 |
| AMS-Net, union of both conditions | 20 / 23 | 19 |

Three AnalogGenie devices meet both conditions. The modulo-five split is
reproducible, but related textbook variants cross it: the second subset
is not an independent holdout. AMS-Net supplied additional counterexamples
while narrowing the rule, so its final result is not an untouched holdout
either. The script hashes the relative paths and contents of each paired
deck and human geometry file. The measured input hashes are:

| Corpus | SHA-256 |
|---|---|
| AnalogGenie | `fdf013de8f565cb5c545d9d938e1c7531b5f34b34ec9b179612be5a9a370e434` |
| AMS-Net | `4ba146113dad8102c57495a1259f1eb94f88ae68845ac057127a5df38b5b6fea` |

The retained AnalogGenie exceptions are **ag-1039:M7, M9** and
**ag-1054:M25, M26**: vertical feedback and bias-clamp branches. ag-425 is
excluded by the terminal-capacitance guard. AMS-Net's retained exceptions
are **amsnet-14:M1**, **amsnet-47:M1** and **amsnet-48:M1**. The
[first](../../external/examples/amsnet/amsnet-14.svg) depicts terminal
capacitances, including capacitors to a separately named body node; the
[second](../../external/examples/amsnet/amsnet-47.svg) and
[third](../../external/examples/amsnet/amsnet-48.svg) draw capacitive source
degeneration upright. A capacitor outside the excluded terminal pairs is
not necessarily a series signal capacitor.

This is a measured habit, not an identification of the electrical operating
region. The study uses named rails, keeps cell voltage sources inline,
and treats subcircuit blocks as opaque; unknown or hidden rail connections
can make a channel component appear isolated. Its counts measure form
selection alone. Series-chain placement has the separate source oracles
above; the counts do not prove parallel switch row placement, full
schematic quality or circuit preservation. Those require their own
placement and electrical checks. No test result is implied by agreement
with source coordinates.

## Symbol and import checkpoint

The same source inspection exposed conventional symbols hidden behind
generic blocks. `block_symbols.zig` supplies amplifier and comparator
triangles, buffers, inverters, AND/NAND/OR/NOR/XOR/XNOR gates to the native
engine and Schemify. It requires a recognized whole family name and a
complete, unambiguous port contract, with every supply retained in SPICE
order. Explicit side hints and caller-provided classes win; extra bias or
control pins, differential outputs and unknown families keep their boxes.
The source oracles are ag-807, ag-750, ag-806, ag-1044, ag-438, ag-1070 and
ag-1076, with ag-1677's bias ports and ag-1070's custom charge pumps as
negative cases. Appearance does not replace the electrical `X` card or its
implementation.

The full AnalogGenie render pass initially succeeded on 2,194 of 2,202
decks. The failures were ag-1101, ag-1103, ag-1122, ag-1128, ag-1157,
ag-1163, ag-1171 and ag-1190: each tried to register a drawable class for
a pinless coupling card. Keeping such cards without a class makes all
2,202 render. Successful rendering is a prerequisite for comparison, not
evidence of visual equivalence.

At this checkpoint, both renderer configurations pass (237 tests without
LaTeX, 238 with it), and 4,000 random decks pass termination, connectivity,
shorts, reversed-card determinism and hint-verdict checks. Eleven selected
source decks pass 25 component round trips through the current Schemify
host; ag-1101 and ag-1157 also preserve their coupling cards. Both current
and v1.0.1 hosts dispatch `netlist.import` and `cktimg.import` to identical
cells and circuit-equivalent exports. The release host's full fixture run
accounts for all 91 names: 89 equivalent circuits and the two expected
capacity refusals (`rstring_ladder.spice`, `write_dac.spice`). The full
current debug-host run was stopped because of its interpreter overhead;
the selected current-host checks above completed. The rebuilt plugin is
550,771 bytes.

The 172-circuit MOS comparison before the symbol addition reduced wire
crossings from 241 to 211 but increased bends from 1,588 to 2,035. That
trade remains a placement/routing gap. The transmission pair in ag-386
still lies beside itself instead of on two parallel rows; complex switched
capacitor networks also lack the source's feedback organization. These
results are a starting checkpoint for further rules, not completion.

## Rules rejected or left for a later pass

**Every rail-free transistor is horizontal** is rejected by ag-236 and
ag-425. **Every switch is horizontal** is also too broad: ag-1054's clamps
and the upright bank between two mixer buses in
[ag-598](../../external/examples/analoggenie/ag-598.svg) follow their local
branch. Recognizing a clock spelling cannot resolve either case.

**A channel between swapped nets is horizontal** is promising for
degeneration, but is not implemented by the selected rule. A lone MOS
bridge such as ag-769's distinguishes its drain from its source and can
prevent the existing exact symmetry from swapping its endpoints. Testing
`st.net_mate[a] == b` alone therefore misses the intended case. Relaxing
pin identity globally would change the meaning of circuit symmetry; a
later rule needs evidence about the two endpoint branches instead.

**Parallel transmission gates** remain further work. Among the 143
selected AnalogGenie circuits, exactly two pairs have the same unordered
distinct drain/source nets, complementary MOS types and distinct gates
outside those channel nets: ag-386 M1/M2 and
[ag-751](../../external/examples/analoggenie/ag-751.svg) M1/M2. Both source
pairs have equal channel-midpoint x, separate y, NMOS above PMOS, and gates
facing outward: 2/2, no exceptions. These are placement and orientation
oracles for a later pair rule, not evidence that the present placement
implements it. It needs coordinated row placement and gate-side selection,
and must yield when `row`, `order`, `cell` or `at` lines split the pair.

The same-type generalization needs another condition. ag-771's parallel
pair faces outward, but
[ag-761](../../external/examples/analoggenie/ag-761.svg) M6/M7 has both gates
upward: the lower device's gate faces into the gap. Equal channel nets
alone do not imply outward gates.

**Local axes** also remain further work. ag-1039 draws an input pair and
a latch as distinct groups, and
[ag-1077](../../external/examples/analoggenie/ag-1077.svg) puts two comparator
stages one above the other with a horizontal supply switch beside the
lower latch. The present skeleton carries one mirror axis; changing forms
does not implement multiple local axes or stage composition. These
decisions need their own examples, counterexamples and placement oracles.
