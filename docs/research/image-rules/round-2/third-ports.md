# Third study: complete the two extra contracts

AG808's clocked comparator and AG1242's left-facing four-bias EA now have complete raw binding certificates and all 13 visible own-symbol leads resolved. Their two declared VSS terminals remain undrawn in the source and explicitly require canonical placement. Together with the unchanged five-case round-2 certificate, this covers all seven raw extension candidates: 50 declared formals, 43 visible source leads, seven undrawn VSS terminals.

The new findings are material to the plan. AG1242's negative input belongs to a pair of separately labelled VFP1 wire islands, not a continuous wire. Its source VDD tip fails the global body-support rule despite a valid own attachment. AG808's other opamp has IB rather than a fourth VB port and remains outside the complete contract. The nine-port change also reaches a second narrow-index consumer, `bias_neighbors.Pair`, beyond `analogOutput`.

This study uses the same complete frozen/current rule context as round 2. It re-viewed both source/native pairs with new observations in [third-ports-views.json](third-ports-views.json). The PNGs remain individually rasterized frozen inputs whose commands and hashes are in [ports_rendered.json](ports_rendered.json). No engine or plugin edits were made. The existing frozen binary was run only to reproduce two native JSON/SVG artifacts; both SVGs matched the previously reviewed native SVG bytes exactly.

Evidence and replay code are [third-ports-contracts.py](third-ports-contracts.py), [third-ports-contracts.json](third-ports-contracts.json), and [native replay provenance](third-ports-native.json). The prior five-case certificate remains separate and is hash-bound by the new proof.

## All declared roles, actual leads and raw bindings

| AG808 X2 comparator index | Formal / raw net | Actual tip / own outward direction |
|---|---|---|
| 0 | VDD / vdd | `(450,430)` up |
| 1 | VSS / vss | Not drawn; no source coordinate invented |
| 2 | OUT / vout | `(490,500)` right; cached `(500,500)` is stale |
| 3 | INN / vx | `(400,480)` left |
| 4 | INP / vss | `(400,520)` left |
| 5 | CLK / phic | `(450,570)` down |

The output lead leaves the triangle apex `(479.282,500)` and joins actual Vout conductor ink. Its negative input reaches the other opamp's actual output, whose raw formal OUT binds VX. The positive input reaches an actual ground marker. VDD reaches the actual supply marker at `(450,420)`. The clock reaches the φc marker at `(450,600)` using the explicit literal φc→phic transcription already bounded in round 2. All five visible leads satisfy global body-behind-tip support; the clock has 30 source units of support beyond the triangle's maximum y540.

The neighbouring opamp's exact declaration is `VDD VSS VB3 VB1 VB2 OUT INN INP IB`; its bindings are `vdd vss vb3 vb1 vb2 vx net1 vss ib`. It has nine ports but no VB4. A larger port limit must not authorize an unknown IB role. The certificate expressly rejects this other call while still using its visible signed/apex geometry to witness the raw VX connection.

| AG1242 X1 EA index | Formal / raw net | Actual tip / own outward direction |
|---|---|---|
| 0 | VDD / vdd | `(570,-40)` up; cached `(570,-50)` is stale |
| 1 | VSS / vss | Not drawn; no source coordinate invented |
| 2 | VB1 / vb1 | `(530,90)` down |
| 3 | VB3 / vb3 | `(590,90)` down |
| 4 | VB2 / vb2 | `(560,90)` down |
| 5 | INP / vref | `(640,-10)` right |
| 6 | INN / vfp1 | `(640,50)` right; cached `(640,20)` is stale |
| 7 | OUT / vctrl | `(500,20)` left |
| 8 | VB4 / vb4 | `(620,100)` down; cached `(640,60)` is stale |

The actual body is `(630,-50), (630,90), (508.756,20)`, with positive mark centred at `(622,-10)` and negative at `(622,50)`. VREF reaches an actual external marker; VCTRL reaches MP15.G, whose raw binding is VCTRL. Each bias reaches its correctly named actual port marker. VB4's **own** lead runs vertically from `(620,84.226)` to `(620,100)`; the subsequent rightward segment to marker `(650,100)` belongs to external conductor ink. The overview phrase “bent fourth bias” described the combined appearance; it did not establish that the bend was owned by the glyph. This study makes that distinction explicit.

All 13 actual leads are consumed exactly once. Actual sign strokes determine the signed inputs. Actual apex geometry determines output. Every reachable port/rail marker must agree with the raw net. A stale cached terminal that happens to lie somewhere on an output wire is not the actual own-lead endpoint.

## VFP1 is a named two-island certificate

The negative input's actual wire is `(640,50) → (660,50)`. Its source net-label object is `label-04e85785-86c7-435d-91bd-1b1c012ee5e0`, actual text `VFP1`, anchor `(660,40)`. The older cache instead places the wire and label 30 units higher. The second actual `VFP1` object is `label-62d8d1ca-dcf2-497a-9d27-3d856bb1c8a7`, anchor `(418,265)`, associated with actual divider wire `(410,250) → (410,280)`.

The latter endpoints are independently verified as R1.2 and R2.1; both raw bindings are VFP1. The actual conductor graph has no path between the two islands. The certificate therefore records two actual labelled pieces of the same raw net and does not invent a continuous wire.

Association between each label and its nearby route is a **literal, manually viewed bounded witness**: exact object identity, text, anchor, transform and route coordinates. It is not a general nearest-label heuristic. Both label objects must say VFP1. Changing either to VREF, moving the input label back to its stale anchor, or replacing the current wire with its stale coordinates fails. A source format without an unambiguous route-label association must remain unresolved until separately certified.

## Pose boundaries and orientation choices

AG1242's VDD own lead attaches correctly to the upper slope, but its tip y−40 is below the triangle's minimum y−50. The outward support minimum is −10. As with AG3492's clock, this is a **valid raw/visible lead contract with an unsuitable source pose for a stronger clearance policy**. A rigid rotation or reflection preserves the support deficit. The final canonical glyph must extend that terminal beyond the body support plane or use a separately certified rule for the immediate supply-marker convention.

AG1242 also separates facing from signed order. Reflecting horizontally changes its left-facing triangle into a right-facing one while keeping VREF above VFP1 and VDD above. A half-turn changes facing but moves VDD below and reverses the signed vertical order. The literal reflection/half-turn control checks those different results. The plan must first choose signed slot order, then apply world pose, and then derive actual-frame reservations. It cannot fold a contextual input-order request into arbitrary `Orient` reflection.

AG808 adds a useful successful bottom-clock control alongside AG3493's top clock and AG3492's short, insufficiently supported bottom clock. The evidence supports one clock role and multiple observed source placements; it does not establish a universal top or bottom clock side.

## Frozen native identity and caller consequences

The exact frozen native replay retains all six AG808 formals and all nine AG1242 formals in declaration order, with distinct terminal coordinates, including both source-omitted VSS terminals. It still draws boxes. The native JSON check compares every term and net against independent literal ordered lists. Deleting VSS, swapping the signed role names, or swapping their net bindings fails. This is a native artifact identity certificate, not an executed Schemify netlist round trip.

The shared `identify`/`draw` path remains the geometry owner, but caller checks precede it. Native `Library.blockFor` uses a registered symbol first and suppresses the conventional glyph for explicit side directives. The plugin's `boxPins` similarly honors explicit sides and additionally checks supplied pin directions against glyph sides. A new glyph must preserve those declines. A per-instance signed-order choice cannot mutate the cached family class or create a plugin-only geometry variant.

Neither exact glyph contract admits its whole surrounding circuit to a new local layout. AG808 includes four switches and a separate IB-controlled opamp. AG1242 is a larger converter with inductors, diode, switches and a transistor amplifier. The raw 40-regulator/36-sampling composition boundary remains independently owned by the interaction study.

## A second nine-port width dependency

The groups adversary identified `bias_neighbors.Pair.pins: [2]u3`, the amplifier index cast in `find`, and `u3` arguments in `tip`/`turn`. Recognition of a complete nine-port amplifier can therefore reach another index-eight failure even if `analogOutput` is widened correctly.

The [literal combined fixture](third-ports-width.cir) puts output at index four and VB1 at index eight. VB1 binds `private_bias`, whose exact raw incidence is `XAMP[8].VB1` plus `XBIAS[2].NB`; it is not a DUT formal. The BIAS peer has matching VDD/VSS and the other amplifier biases are external. This reaches the existing neighbour candidate's relevant electrical premises after the proposed glyph recognition extension. The [capacity proof](third-ports-width.py) records these bindings and checks index8>u3 maximum7, while the peer index2 fits. A paired declaration/binding permutation moves VB1 to index7 without changing the electrical mapping, proving the failure depends on representation width rather than circuit semantics.

This is a raw-contract/type-capacity witness, not a claimed executed Zig overflow. Its required RED regression is a recognized nine-port amplifier with this exact peer, followed through collect/place/orders and the actual-tip consumers. The amplifier index needs a range that includes eight; the peer remains independently bounded by four. Keep the `Pair` size assertion and document any chosen representation change. Do not broaden the bias peer role list to include VB4 without separate policy evidence.

The full plan's dependency order now includes role/arity recognition → per-instance signed-order request → immutable class/variant selection → port-index-safe consumer certificates, including bias neighbours → actual terminal geometry/support → local ownership/reservations → routing → shared native/plugin export. Extra bindings, unsupported controls, custom symbols and caller poses must retain explicit decline paths throughout.

## Controls and replay

The third source/native proof has 14 controls: contradictions in each VFP1 label, stale label position and negative wire, wrong EA object, wrong VB4 marker, complete target-cache corruption in each example, clock relabelled IB, preserved VDD support failure, reflection versus half-turn, and three native binding mutations. The width witness separately checks a positive private peer and an electrically equivalent paired permutation.

```sh
python3 -B docs/research/image-rules/round-2/third-ports-contracts.py --check docs/research/image-rules/round-2/third-ports-contracts.json --output /tmp/third-ports-replay.json
python3 -B docs/research/image-rules/round-2/third-ports-width.py --check docs/research/image-rules/round-2/third-ports-width.json --output /tmp/third-ports-width-replay.json
```

The original 734-pair review, the five-case detailed proof, and this two-case completion remain independently inspectable. A completed seven-case raw/actual-source certificate does not erase the seven missing source VSS poses, the two global-support exceptions, or the caller and topology boundaries.
