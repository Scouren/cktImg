# One visible four-bit tuning control

The published 6 GHz LC VCO connects a single line marked “4-Bits” and “B3-B0” to its switched-capacitor bank. The other four box leads carry the differential output and analog tuning voltages. The cached redraw labels the bundle `B<3:0>`. The converted SPICE provides the bit order independently on both the bank definition and its X2 call. [Published Figure 1](https://raw.githubusercontent.com/xz-group/AnalogGenie/efc25358939c6bedd247f28d3df61066964f3a90/Dataset/1146/Book1146.png) · [Redraw](../../../../external/examples/analoggenie/ag-1146.svg) · [Deck](../../../../external/examples/analoggenie/ag-1146.cir)

| Schemify before | Schemify after |
| --- | --- |
| [Eight scalar leads](ag1146.schemify.before.svg) | [Five leads, one ordered bundle](ag1146.schemify.after.svg) |

The Schemify editor exported these views of the original DUT. The generated bank and its parent both have an editable interface pin and matching schematic port named `B_3_,B_2_,B_1_,B_0_`. Schemify expands the comma expression into those exact four names. The bank symbol has five leads and displays the compact caption `B<3:0>`. X2 still opens the original bank definition. The complete ngspice output before and after is byte-identical. The independently netlisted result passes spicecmp with twelve devices and fourteen nets.

The grouping requires four consecutive declared control bits on the otherwise opaque differential tuning bank, contiguous matching parent formals, one direct instance and no consuming parent above it. Each actual bit must reach exactly one device pin. The final host geometry must show those four ports directly on their respective contacts with no intervening wire or additional marker. A valid individual port or wire presentation retains the scalar drawing. Explicit bit sides and incompatible directions also retain independent contacts. Permuting the actuals, adding a consumer of B_2_, or instantiating the containing cell elsewhere each retains all eight scalar contacts. Across the 5,274 example decks only AG1146 declares this bank interface.

Reproduce the actual editor exports and verify the slot order with the local Schemify executable and built plugin directory.

```sh
python3 -B tests/control_bus.py /path/to/schemify . /tmp/cktimg-control-bus
```
