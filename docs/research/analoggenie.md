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

## Source observations

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
| [ag-782](../../external/examples/analoggenie/ag-782.svg) | M7 and M8 lie horizontally in capacitor feedback branches terminating at the fully differential amplifier's inputs. An explicitly named block input supplies the same control-terminal evidence as a transistor gate. |
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
   drives another transistor's gate or base, or a block port identified as
   an input by `library.portRole`. Retain upright form when neither
   condition holds.
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

The block-input extension comes from ag-782 M7/M8. It binds actual nets to
the subcircuit's declared port order and uses the shared input-port contract;
it does not require a recognized glyph or amplifier family name. A renamed
block with reordered `VIP`/`VIN` ports remains eligible, while unknown port
labels supply no evidence. [mos_compensation.zig](../../tests/mos_compensation.zig)
checks those cases and excludes capacitors between the MOS's own terminals.

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
horizontal in the source. The rule selects 315 of those horizontal devices;
it addresses the stated conditions rather than all reasons for drawing a
MOS horizontally.

| Source subset | Horizontal in the source / selected | Circuits |
|---|---:|---:|
| AnalogGenie, union of both conditions | 315 / 319 | 217 |
| AnalogGenie, leaf endpoint with opposite gate/base or block-input load | 136 / 138 | 130 |
| AnalogGenie, leaf endpoint with opposite named block input | 80 / 80 | 78 |
| AnalogGenie, isolated DC component with a qualifying capacitor | 186 / 188 | 93 |
| AnalogGenie, source ID modulo five nonzero | 258 / 262 | 176 |
| AnalogGenie, source ID modulo five zero | 57 / 57 | 41 |
| AMS-Net, union of both conditions | 20 / 23 | 19 |

Seven AnalogGenie devices meet both conditions. The named block-input
extension adds 76 horizontal devices to the original 243-device selection;
74 are also covered by the converter-path rule, leaving ag-782 M7/M8 as
the two distinct additions. AMSNet has no eligible block-input case.
The modulo-five split is
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

## Source-degeneration bridges

A second, independent exception to upright MOS form joins the source nodes
of two gain devices. In [ag-769](../../external/examples/analoggenie/ag-769.svg),
M9 lies between those nodes while M1 and M2 remain upright; the p-channel
counterpart is [ag-770](../../external/examples/analoggenie/ag-770.svg).
[ag-771](../../external/examples/analoggenie/ag-771.svg) and
[ag-954](../../external/examples/analoggenie/ag-954.svg) use two parallel
bridges. Their channel orientation is distinct from the later decision
about bridge rows and gate-facing direction.

The conservative condition requires a MOS with distinct drain, gate and
source, neither channel end on a rail, and its body on a named rail. Each
channel endpoint must have a direct DC path to that same body rail and be
the source of another MOS of the same polarity and body. Those two gain
devices need distinct drains and gates; neither drain may be either bridge
endpoint, and each device's drain, gate and source must be distinct. Finally,
the bridge's gate must have no incident DC path. Gate and body connections
do not count as DC paths. Explicit upright hints still take precedence.

| Corpus | Selected | Horizontal | Additional beyond the capacitor rule |
|---|---:|---:|---:|
| AnalogGenie discovery | 5 | 5 | 5 |
| AnalogGenie holdout | 1 | 1 | 1 |
| AMSNet | 0 | 0 | 0 |

The complete positive manifest is **ag-769:M9, ag-770:M7, ag-771:M3/M4,
ag-954:M6/M7**. There are no selected upright examples. The holdout is
ag-770 under the same numeric-ID modulo-five split used above; its close
relation to ag-769 limits its independence. AMSNet contains no qualifying
examples, so it supplies no validation of this additional habit.

Removing the gate-path condition admits exactly nine upright devices:
**ag-2460:MD3 through ag-2468:MD3**. Their gates also terminate DC paths in
converter control circuitry. A rule that merely connects source-side nodes
would therefore overgeneralize. The public placement tests in
[mos_degeneration.zig](../../tests/mos_degeneration.zig) use the source
cards and terminal coordinates as the oracle, include that common clamp
topology, reverse bridge channels, rename and reorder cards, and preserve
upright hints.

Reproduce the complete device manifests and gate-condition ablation with
[mos_bridges.py](figures/mos_bridges.py):

```sh
python3 -B docs/research/figures/mos_bridges.py external/examples/analoggenie /tmp/analoggenie-bridges.json
python3 -B docs/research/figures/mos_bridges.py external/examples/amsnet /tmp/amsnet-bridges.json
```

The script uses model declarations and connectivity only for selection;
human D/S coordinates enter only the orientation oracle. It records the
same paired corpus hashes as the capacitor study, an explicit selected
device list, the split, and whether each choice was already covered by that
rule. Unknown cards and MOS models fail instead of disappearing from the
study.

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

**A channel between swapped nets is horizontal** cannot identify
degeneration reliably. A lone MOS
bridge such as ag-769's distinguishes its drain from its source and can
prevent the existing exact symmetry from swapping its endpoints. Testing
`st.net_mate[a] == b` alone therefore misses the intended case. Relaxing
pin identity globally would change the meaning of circuit symmetry; a
source-degeneration rule uses the endpoint branches described above instead.

**A four-switch ring is horizontal** remains research. Requiring a rail-free
DC component with exactly four same-polarity MOS, a four-node channel cycle,
and two alternating gate controls outside that cycle selects 32 horizontal
and four upright MOS. The upright exception is ag-1044:M0/M1/M2/M3, whose
clock-swapping drawing uses the same channel topology. Requiring both
controls to be explicit ports of the selected subcircuit narrows this to
24/24 horizontal devices in ag-511, ag-512, ag-514, ag-574, ag-786 and
ag-813. Twelve are additional to the capacitor rule. All 24 are in the
discovery split, and AMSNet has no qualifying cases. This boundary is
recorded by `mos_bridges.py`; its absent holdout and external evidence keep
it out of the production rule for now.

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

## Local switched-feedback cells

[ag-800](../../external/examples/analoggenie/ag-800.svg) and
[ag-801](../../external/examples/analoggenie/ag-801.svg) show why a switch's
form also depends on its branch. A capacitor and MOS channel form a
two-part feedback path between an amplifier input and output. Their shared
node has exactly one additional part, a ground-shunt MOS. The capacitor
and ground switch share a horizontal row, while the signal switch returns
vertically outside the amplifier. Paired cells share the capacitor column;
the branch starting with a capacitor at the input is nearer the amplifier.
In ag-800, the direct reset switch occupies the nearer feedback row.

[ag-803](../../external/examples/analoggenie/ag-803.svg) supplies the
conditional exception: a direct feedback capacitor is also present. It
takes the outer row, while the series capacitor and signal switch share
a straight row with the ground switch upright. The longer three-part
feedback path in [ag-799](../../external/examples/analoggenie/ag-799.svg)
does not meet this cell predicate and retains its existing local axes.

The independent [opamp_feedback.py](figures/opamp_feedback.py) selects
cells from SPICE connectivity and declared block ports, then reads human
terminal coordinates as its geometric oracle. It finds eight cells in
ag-800, ag-801, ag-803, ag-805 and ag-813: **55/55** axis, row, column and
branch-order checks agree with the source. Three pairs add **6/6** shared
column and relative-row checks. The modulo-five discovery split has five
cells and 33/33 checks; holdout has three and 22/22. AMSNet's 734 drawings
contain no eligible cell. The corpus hashes are the paired-source hashes
listed above. These textbook variants are correlated observations.

Four cells in ag-800/801/803 are inside the current switched-amplifier
admission. ag-805's control-generation transistors and ag-813's channel
connections to gate nets keep the other four on the general placement
path. Before this local rule, the iteration-two native drawings satisfied
21/55 cell checks and no complete cell; this includes the excluded cases.
The script reports them explicitly instead of changing admission to fit
the result. Its selector also checks source-card and D/S reversal,
removal of the ground switch, and an extra path on the shared node.

With the local rule, all four admitted cells pass **27/27** geometry checks
and ag-801's pair passes **2/2** shared-column/order checks. The four
excluded cells retain 12/28, giving 39/55 over the complete observed set.
Across the same 83 switched-amplifier circuits, iteration two to three
reduces crossings from 31 to 30 and bends from 302 to 299; orientation
agreement rises from 486/519 to 492/519. Only ag-800/801/803 change their
geometry hashes; ag-799 is byte-identical. The new native binary's SHA-256
is `c387abe2f133ecaad6e67d309e8015c6b0a7e93470fcab016ae502d602858b51`.
Visual inspection then found inward-facing return gates on ag-800:M5 and
ag-801:M6. All seven source rectangles face those gates away from the
amplifier. An added gate-side oracle went red, including a D/S-reversal
metamorphism; reflecting the return symbol across its vertical channel
now preserves both connected endpoints and satisfies that condition.
The admitted cells pass 30/30 checks and ag-801's pair passes 2/2; across
all eight source cells, human geometry passes 62/62 and native geometry
44/62. The excluded ag-805/813 cases remain explicit exceptions.

Iteration four changes only ag-800/801 in the 83-circuit cohort. Gate-side
agreement increases from 247/319 to 249/319, with ag-800 at 5/5 and ag-801
at 6/6. Crossings stay at 30; bends rise from 299 to 301, both extra bends
in ag-801. The native binary SHA-256 is
`9052da1b689bb4a5386b8c11d3e4bfc57af4b470262818ca0c5b146bfc5f2db3`.
ag-803's other input branch remains misplaced. Passing the feedback-cell
oracle does not imply complete figure equivalence.

[opamp_feedback.zig](../../tests/opamp_feedback.zig) turns the admitted
source cases into actual placed-pin regressions. Its two positive tests
failed before the placement change and pass after it; AG799, card reversal
and an explicit upright hint already passed. The implementation remains
in the existing feedback-path procedure and does not change the global
MOS form rule.

## Internal return banks: remaining research

In [ag-803](../../external/examples/analoggenie/ag-803.svg), the internal
node `VG` joins only the sources of M8/M9/M10. These three same-polarity
devices share an external gate control and rail body; their distinct
drains form a two-capacitor chain, C3/C4. The return channels are upright
on a common row below the capacitor row. M3 connects the chain's middle
node to the main amplifier input vertically, between the two signal rows.
The expanded circuit [ag-3473](../../external/examples/analoggenie/ag-3473.svg)
has the same arrangement at `net1`: M4/M6/M8, C3/C4 and bridge M5.

[opamp_returns.py](figures/opamp_returns.py) records this narrower topology
without using either node's spelling. It requires exactly three exclusive
source incidences on a nonrail, nonport node, one shared external gate-only
control, one rail body and polarity, distinct drains joined by exactly two
capacitors, and one same-polarity bridge with a different external control
from the middle node to a separate nonrail node. A token-incidence guard
also rejects hidden loads and conservatively excludes token collisions
with model/value names. Card reversal, a missing capacitor and declaring
the common node as a port are explicit selector checks.

The full AnalogGenie scan finds these two banks and six return MOS; all
18 source geometry checks pass, compared with 7/18 for iteration-three
native drawings. Both are discovery cases; the holdout and AMSNet have
no matching example. They are related textbook circuits, so the evidence
does not establish a broad rule. This remains research, and `VG` is never
promoted to an electrical rail. The remaining solution needs a lower
signal row and its return bank as one group; changing that node's role
alone would still flatten the inter-row bridge in the current traversal.

## Single-input amplifier glyphs

The explicitly named family and complete port contract distinguish an
intentional single-input block from a block whose meaning is unknown.
[ag-1401](../../external/examples/analoggenie/ag-1401.svg) declares an
`opamp` with INN, OUT, rails and three bias pins; its triangle carries a
minus. [ag-1432](../../external/examples/analoggenie/ag-1432.svg) declares
a `comparator` with INP and OUT plus supply/bias pins; its triangle has a
plus. [ag-1422](../../external/examples/analoggenie/ag-1422.svg) uses IN and
OUT with a supply; its triangle is unsigned. None needs an invented second
input terminal.

[single_input_amplifiers.py](figures/single_input_amplifiers.py) selects
only the known `opamp`, `icm_opamp_vdd_vss`, `comparator`, `comp` and
`icm_ideal_comparator_vdd` families, with exactly one signed/unsigned input,
one output and unique optional supply, ground and VB1/VB2/VB3 roles.
The independent oracle reads the closed triangular SVG path and the line
segments strictly inside it: one horizontal line is minus, crossing
horizontal/vertical lines are plus, and no interior mark is unsigned.

All **47/47** selected AnalogGenie source glyphs are triangular and all
**47/47** signs match the declared input: 35 negative, one positive and
eleven unsigned. There are 40 discovery and seven modulo-five holdout cases;
AMSNet contains none. The script includes each source ID, complete port
list, asset ID and source hashes. Hashing all human JSON, SPICE and SVG
triples gives AnalogGenie
`f193fdb23c88b87ca27329d8c671d7519dda026da20c5945e950d14fdbffee07`
and AMSNet
`c0d304c90b355b63e2d69655f4a68d51e10b9910f907416dfa4c418c5393c725`.

The exact `comp` alias contributes ag-1363/1364/1366/1369/1427/1437/1442
with INN and ag-1446 with unsigned IN. The complete two-input alias in
[ag-1370](../../external/examples/analoggenie/ag-1370.svg) also has a
triangle: its three interior line segments form a minus at (-40,12) and
a plus at (40,12), matching INN and INP. It retains the existing two-input
contract and is outside the single-input count.

Unknown controls remain explicit exclusions: ag-1354/1355/1357/1360/1386/1389
have VX, ag-1372/1373/1377/1384 have TAIL, ag-1396 has VB4/VB5, ag-1405 has
VB4, ag-1420 has IB and ag-1433 has VBN. A missing input,
duplicate input or bias role, extra unknown control and unfamiliar family
are selector negatives. Reordering declared ports preserves recognition;
electrical pin count and order still come from that declaration.

The native SVG audit now finds the triangle and matching polarity in
**47/47** selected drawings, up from **0/47** in the frozen previous
binary. Both versions preserve all **47/47** ordered port lists and net
bindings. AG1370 separately changes from a box to a triangle with both
signs, retaining its seven ordered pins and connections. The new native
binary SHA-256 is
`81fe3d0b22f52f4e2fc7f0c86a92d1fbc08b51174471e75529add43f272c083e`;
the previous binary is
`9052da1b689bb4a5386b8c11d3e4bfc57af4b470262818ca0c5b146bfc5f2db3`.
The script's `--native-dir` option reads each selected ID's rendered SVG
and JSON, checking the closed triangle, interior polarity text and the
original SPICE terminal bindings. An unexpected additional triangle fails
this cohort's one-controller check.

The rebuilt plugin passes real Schemify import/netlist/`spicecmp` round
trips for all **48** selected source decks (the 47 single-input cases plus
AG1370) on v1.0.1: **97** named subcircuits are equivalent, with no refusals.
The current host also passes ag-1401/1432/1422/1363/1370/1446: all **12**
named subcircuits, covering the three input polarities and the single/paired
`comp` alias. Expected and observed subcircuit name lists match exactly.
This run uses module SHA-256
`5b471ad81cdf561002cb188fd44d1df978de0160e69380c8f6674aafa46035b1`.

These are glyph and electrical checks, not full drawing equivalence.
For example, the generated AG1401 controller still points right while
the source triangle points upward toward its switch gate. Controller
placement and the surrounding branch rows remain separate layout work.

## Converter shunts belong under their connection interval

The source does not usually align a grounded switch with the coil's
terminal. In [ag-1363](../../external/examples/analoggenie/ag-1363.svg),
MN1.D is at x=310 while the connected LRX terminal is at x=340;
MN2.D is at x=430 while its coil terminal is at x=400. Each shunt stands
below the horizontal wire between that coil terminal and the connected
main PMOS terminal. The same arrangement appears in
[ag-1401](../../external/examples/analoggenie/ag-1401.svg),
[ag-1370](../../external/examples/analoggenie/ag-1370.svg) and
[ag-1432](../../external/examples/analoggenie/ag-1432.svg).

[power_paths.py](figures/power_paths.py) retains the source and native
coordinates of these three electrical terminals, selected by their shared
net. Its topology predicate first requires the existing certified main
PMOS/coil/PMOS path, then a distinct-D/S/G grounded NMOS whose control net
touches MOS gates only. Requiring **one eligible shunt at the coil
endpoint** selects **353 devices across 252 drawings**. All **353/353**
source channel terminals lie within the connected main/coil x interval
and below the path; 352 are strictly inside. The boundary case is
[ag-1418:MN2](../../external/examples/analoggenie/ag-1418.svg), directly
under its coil terminal. Among the 101 circuits with exactly two eligible
shunts, both source upper channel terminals share a row in **101/101**.

The broader 365-device predicate has four interval violations:
[ag-1382:M12](../../external/examples/analoggenie/ag-1382.svg),
[ag-1383:M7](../../external/examples/analoggenie/ag-1383.svg),
[ag-1385:M12](../../external/examples/analoggenie/ag-1385.svg) and
[ag-1388:M5](../../external/examples/analoggenie/ag-1388.svg). These are
amplifier tail/bias channels, sharing the endpoint with its ordinary power
shunt. Six endpoints have two eligible devices, so the uniqueness guard
declines all twelve; it does not guess which device is the power switch.
The source images verify this distinction without using control-net names.

[converter_terminals.py](figures/converter_terminals.py) checks the actual
SVG lead strokes against the cached coordinates used here. All **976**
distinct shunt/main-switch/coil devices, comprising **1,952** electrical
path terminals, match their transformed SVG endpoints. The check retains
the exact expected and verified name lists and SHA-256 hashes of each
source deck, human JSON and SVG. Custom controller glyphs can disagree with
their cached port positions; they are excluded from this audit. That
limitation does not affect these verified builtin D/S and coil endpoints.

The implemented bridge postpass moves a unique shunt into an existing free
interior column, preserving its row and any already interior column.
It retains existing mates and admitted ordering constraints; cell hints
still run afterward. All 353 source cases have a free interior column in
the generated lattice. An adjacent-column reduction of AG1191 has none
and keeps ordinary placement, a named boundary test. The full AG1191 DUT
is the positive fixture. No global column expansion or new paired-row
assignment is needed for this cohort.

Frozen iteration four satisfied the actual terminal interval for only
**14/353** selected devices. Iteration seven satisfies **353/353 before
compaction** and **344/353 afterward**. The nine remaining misses are
AG1247:M4, AG1256:M3, AG1278:M3, AG1281:M3, AG1286:M4, AG1287:M4,
AG1290:M4, AG1356:MN1 and AG1455:M4. Each initially correct interval is
lost during compaction; preserving those terminal orders is the next
repair. The independent oracle is the terminal interval, invariant under
horizontal reflection, rather than exact source spacing. The script
stores every selected name, all excluded names, native JSON hashes and
the 252 source SVG hashes. Repeated converter variants remain correlated
evidence, and this relation alone does not establish full drawing quality.

```sh
python3 docs/research/figures/power_paths.py external/examples/analoggenie \
  /tmp/power-shunts.json --native /tmp/cktimg-human-rules/all-ag-iteration4
```

## Grounded reservoirs lie outside the main path

The same certified paths select **359** grounded capacitors in **252**
drawings, with exactly one at each eligible outer main-switch endpoint.
All **359/359** stand vertically, ground below, strictly beyond that main
switch's outer channel terminal on the side away from the coil. Their
signal pin is never above that terminal: 357 are below, while
[ag-1309:COP](../../external/examples/analoggenie/ag-1309.svg) and
[ag-1329:COP](../../external/examples/analoggenie/ag-1329.svg) start on the
power row. [converter_terminals.py](figures/converter_terminals.py)
independently verifies all **718** capacitor lead endpoints against the
transformed SVG strokes, retaining exact names and source hashes. This
condition is invariant under horizontal reflection; it does not prescribe
an absolute left-to-right signal direction.

The grounded-capacitor requirement excludes both CFLY and the floating CO
branch in [ag-1191](../../external/examples/analoggenie/ag-1191.svg), while
retaining COP. A shared capacitor/shunt row is unsupported: among 353
paired endpoints the source capacitor signal pin is above the shunt's
upper pin in 202 cases, level in 111 and below in 40. Multiple grounded
capacitors at one endpoint have no example in this cohort. The engine
therefore declines an ambiguous endpoint, including two grounded caps
when one is explicitly flat. It also excludes gate/coil-side branches,
non-ground rails and undrawn devices; a unique explicitly flat cap keeps
its caller-selected form.

Iteration nine keeps the capacitor's existing lattice cell and raises
the whole certified main path above its row. Shelf cuts keep that path,
its controls and its reservoirs together. Compaction preserves initially
true orders between their actual transformed electrical terminals,
including shifted or tall caller symbols. Row, above, mate, cell, exact
origin and face instructions retain precedence; a contradictory caller
placement does not acquire an inferred order afterward.

The same named **359/359** native branches now satisfy vertical placement,
ground below signal, signal at or below the main channel, and an outer
position away from the coil. Frozen iteration eight satisfied all four
for **214/359**: outside was **330/359** and at-or-below **243/359**. The
earlier relations remain intact: 252 ordered collinear main paths, 353
unique shunts inside their terminal interval, all 365 shunts and 92 gate
drivers wholly below, and all 75 controller outputs below and aligned.
This is agreement with the bounded pattern, not exact source geometry:
AG1309:COP and AG1329:COP remain 40 native units below their main channels
despite being level in the source. Equality is permitted and preserved
when the caller specifies it; those two default placements remain open.

The public regressions in [power_reservoirs.zig](../../tests/power_reservoirs.zig)
first reproduced AG1374's shelf split and AG1191's signal-above-path
failure. [power_reservoir_bounds.zig](../../tests/power_reservoir_bounds.zig)
adds ambiguous parallel caps, excluded gate/coil caps, reversed terminal
cards, explicit reversed faces and a shifted 80-unit capacitor frame.
The tests check electrical connectivity and shorts alongside geometry.

```sh
python3 docs/research/figures/converter_terminals.py external/examples/analoggenie \
  /tmp/converter-terminals.json --native /tmp/cktimg-human-rules/all-ag-iteration9
```

## Controller direction is not determined by the outer circuit alone

Actual SVG leads point upward in 67 of the 75 topology-selected controller
instances. Eight point right: AG1354, AG1358, AG1366, AG1369, AG1372,
AG1377, AG1393 and AG1396, each at X1. The cached terminal coordinates
incorrectly suggest upward output alignment in all 75. For example,
[AG1393](../../external/examples/analoggenie/ag-1393.svg) has a right-facing
triangle whose output lead ends at (530,250), with a wire turning upward;
its cached OUT is (470,150).

[controller_glyphs.py](figures/controller_glyphs.py) can also emit exact
outer-graph mappings between right- and upward-facing examples. Normalizing
only the synonymous family labels `comp`, `cmp` and `comparator`, it finds
these pairs: right AG1354 matches up AG1357 and AG1360; right AG1366 and
AG1393 each match up AG1394 and AG1445; right AG1369 matches up AG1395.
Every mapping preserves all outer devices and connections, MOS D/G/S/B
roles, rail roles and the complete declared controller port names. The
script checks the bijection and every labelled edge directly, and retains
the mappings, graphs and source hashes without a third-party graph package.

This establishes a limit for selectors based on outer connectivity and
complete port roles. It does **not** claim identical full netlists: hidden
controller implementations and component values are outside the comparison.
No electrical condition justifying these direction exceptions has been
established. All eight remain named mismatches for the upward habit; source
IDs and family spelling are not direction selectors.

```sh
python3 -B docs/research/figures/controller_glyphs.py external/examples/analoggenie \
  /tmp/controller-glyphs.json --topology
```


## Horizontal channels in two bounded bridge patterns

The remaining transistor-axis mismatches include two small, distinct patterns.
[channel_bridges.py](figures/channel_bridges.py) selects them from the final
SPICE cell, independently of generated placement. It reads the actual two
channel lead polylines and their SVG transforms, then checks them against the
cached terminal endpoints. Cached rotation never determines the oracle's axis.
All **32 selected channel endpoints** agree with the SVG ink. Unknown models,
unsupported SVG transforms, ambiguous instances, or missing native devices fail.

An **always-on transmission pair** has exactly two parallel MOS channels of
opposite polarity, distinct non-rail channel nets, and gates outside those nets.
The NMOS gate is on a supply and the PMOS gate is on a sink. All **8/8** selected
source devices lie horizontally: [AG387 M1/M2](../../external/examples/analoggenie/ag-387.svg),
[AG440 M5/M6](../../external/examples/analoggenie/ag-440.svg),
[AG550 M5/M6](../../external/examples/analoggenie/ag-550.svg), and
[AG987 M9/M10](../../external/examples/analoggenie/ag-987.svg). These four pairs
also stack the NMOS above the PMOS with controls outward. The deterministic
numeric-ID modulo-five split contains four devices in discovery and four in
holdout. Existing capacitor-qualified transmission pairs remain a separate case.

An **antiparallel diode-connected pair** has two same-polarity MOS or BJT
channels on reversed endpoints; each gate/base is tied to its own drain/collector.
Neither channel endpoint is a rail, and there is exactly one other parallel
transistor of that kind. All **8/8** source channels are horizontal:
[AG739 MD1/MD2](../../external/examples/analoggenie/ag-739.svg),
[AG1048 M5/M6](../../external/examples/analoggenie/ag-1048.svg),
[AG1052 M6/M7](../../external/examples/analoggenie/ag-1052.svg), and
[AG1149 Q3/Q4](../../external/examples/analoggenie/ag-1149.svg). The six MOS
are NMOS, the two BJTs NPN. All eight fall in the discovery partition; there is
no held-out example. AG1149 offsets the two clamps horizontally, so the evidence
supports horizontal channels without requiring every pair to share one column.

The scope matters. Opposite polarity and shared endpoints alone select **42**
AG devices, of which **26 are vertical** in the actual SVGs. For example,
[AG175 M1/M2](../../external/examples/analoggenie/ag-175.svg) form a biased
complementary gain stage. The analogous broad AMSNet cohort has four horizontal
and two vertical devices; the vertical pair is AMSNet415 M1/M2. Every such name
is retained in the inventories. Likewise, cached coordinates show **1,460 of
1,469** off-rail diode-connected AG transistors upright; the eight antiparallel
clamps account for eight of the nine horizontal cases. The remaining horizontal
case is AG3103 M13 and is not admitted by either bridge predicate. Neither a
same-polarity pair with unrelated controls nor an opposite-polarity pair of
diodes supplies the new certificate. Rail-connected channels, incorrect control
rails, additional parallel transistors, and explicit `upright` instructions must
preserve the existing default or the caller's choice.

The scan covers all **2,202 AG** and **734 AMSNet** drawings. AMSNet contains no
member of either narrow cohort, so it supplies exclusion checks rather than
independent positive evidence. These are small observational cohorts, not a
claim about every electrically equivalent drawing. Base/emitter-shorted Q2 in
AG1116 and AG1117 are also horizontal; the inventory retains those two devices
as sparse research only, outside the proposed change.

The checked-in [AG inventory](figures/channel_bridges_ag.json) and
[AMSNet inventory](figures/channel_bridges_ams.json) include exact selected names,
source deck/JSON/SVG hashes, actual channel endpoints, broader counterexample
names, and split counts. The source triples hash to
`f193fdb23c88b87ca27329d8c671d7519dda026da20c5945e950d14fdbffee07` (AG) and
`c0d304c90b355b63e2d69655f4a68d51e10b9910f907416dfa4c418c5393c725` (AMSNet).
Frozen iteration-six native binary
`9fd18dffd77da9555f06aa82b9cbeb8a930fb911e728b0df89fbf5165d5295e1`
draws all **16** selected devices vertically: **0/16** axis agreement. This is
proposed work; source-derived placement tests belong to its subsequent
red/green implementation cycle.

```sh
python3 docs/research/figures/channel_bridges.py external/examples/analoggenie \
  /tmp/channel-bridges-ag.json --native /tmp/cktimg-human-rules/all-ag-iteration6
python3 docs/research/figures/channel_bridges.py external/examples/amsnet \
  /tmp/channel-bridges-ams.json
```

## Keeping a learned relation through later transforms

The seventh pass placed all 353 unique converter shunts inside their
connected main-to-coil terminal intervals, but generic compaction lost nine
of those relations. It also let AG1356:M12's upper channel terminal become
level with the power row. The eighth pass preserves already-true terminal
inequalities through the generic compaction graph. Both final checks now
pass, 353/353 intervals and 92/92 drivers strictly below. An offset, tall
custom M12 regression verifies that the rule follows D/S rather than the
device origin. Explicit caller geometry remains authoritative.

The [capacitive cross-coupling study](capacitive-cross-coupling.md) finds
another instance of this problem: a source-derived capacitor pair can be
placed correctly, then separated by the shelf pass. Its eight source pairs
also use a joint crossover, with distinct continuous-wire and labelled-wire
cases. The study records actual SVG evidence, counterexamples and rejected
prototypes. It remains proposed work; a capacitor-axis change alone is
insufficient.
