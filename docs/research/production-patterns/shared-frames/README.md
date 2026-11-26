# Shared amplifier definitions and signed pin positions

A regulator's amplifier drives a pass NMOS from its output. A resistor divider returns the regulated voltage to its negative input. The positive input carries the reference. The AG2187 drawing puts that reference above feedback. In the sampled circuit exemplified by AG2658, the negative terminal carries the signal and the positive terminal is grounded. The two fixtures combine these source-derived roles in a single five-port definition named `opamp`. [Regulator drawing](https://raw.githubusercontent.com/xz-group/AnalogGenie/efc25358939c6bedd247f28d3df61066964f3a90/Dataset/2187/Book2187.png) · [Sampling drawing](https://raw.githubusercontent.com/xz-group/AnalogGenie/efc25358939c6bedd247f28d3df61066964f3a90/Dataset/2658/Book2658.png) · [Mixed fixture](../../../../tests/shared_frames/mixed.cir) · [Two regulators](../../../../tests/shared_frames/uniform.cir)

| Fixture and renderer | Before | After |
| --- | --- | --- |
| One regulator and one sampler, native | [Both negative inputs above](mixed.native.before.svg) | [Positive reference above on XREG, negative signal above on XSAMPLE](mixed.native.after.svg) |
| Two independent regulators, Schemify | [Both negative inputs above](uniform.schemify.before.svg) | [Positive reference above on both instances](uniform.schemify.after.svg) |

In the native mixed drawing, XREG's positive terminal moves from y=240 to y=200 and its negative terminal moves from y=200 to y=240. XSAMPLE retains the negative terminal at y=40 and the positive terminal at y=80. The signed marks move with their terminals. The supply, ground and output keep their local coordinates. Both devices still instantiate the same electrical definition with formals in the original order.

The local selector checks the literal source and drain, gate and bulk of the pass NMOS and every incidence of the private gate and feedback tap. The positive reference and any bias controls must each have one occurrence at an external interface. Another feedback consumer or a bulk connection to the private tap withdraws that owner. Disjoint regulators qualify independently. Native placement resolves each selected frame before geometry and routing. Caller-supplied family and instance symbols, explicit definition sides and honoured poses retain their authority. Reversing the cards, renaming both users or exchanging both formal and actual pin positions preserves the relation.

A Schemify component file supplies one ordered pin table and one glyph to all instances that reference it. When every use qualifies, its positive and negative pins use local y=−20 and +20 respectively. When only one use qualifies, both keep the common default frame. The host round trip checks that each original `X` still points to the same editable implementation, that its five actuals remain in source order, and that every passive and MOS card retains its bindings. [Host and native regression](../../../../tests/shared_frames.py)

Comparing all 5,274 example decks to the preceding production checkpoint found byte-identical native drawings and verdicts in all four collections. The two fixtures above exercise shared-use combinations absent from those decks.

Use a fresh directory for each run. The Schemify argument is the real executable beside `spicecmp`. Its last argument is the directory containing the built plugin and its `schemify.project`.

```sh
python3 -B tests/shared_frames.py zig-out/bin/cktimg-json /tmp/signed-native
python3 -B tests/shared_frames.py zig-out/bin/cktimg-json /tmp/signed-host --host /path/to/schemify --plugin .
```
