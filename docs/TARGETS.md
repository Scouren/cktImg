# Target manifests

`cktimg-json --target manifest.json deck.spice` adds a `"target"` block to
the document: for each device, the backend's symbol and the order it wants
the pins in. The manifest is JSON the backend's author writes; the library
never reads it (`tools/json.zig` does).

```json
{
  "target": "xschem",
  "version": 1,
  "units": { "scale": 2.0 },
  "style": { "anything": "passed through" },
  "unmapped": { "mode": "box", "sym": "devices/generic.sym" },
  "classes": {
    "nmos":  { "sym": "devices/nmos4.sym" },
    "nmos:sky130_fd_pr__nfet_01v8_lvt": { "sym": "sky130/nfet_01v8_lvt.sym", "pins": ["d", "g", "s", "b"] },
    "res":   { "sym": "devices/res.sym", "pins": ["b", "a"] },
    "res:res_high_po": { "sym": "sky130/res_high_po.sym" },
    "opamp": { "sym": "my_lib/opamp.sym" }
  }
}
```

| key | required | meaning |
|---|---|---|
| `target` | yes | the backend's name, echoed as `target.name` |
| `version` | yes | `1` |
| `units`, `style` | no | copied through untouched; nothing is rescaled |
| `unmapped.mode` | yes | a class with no entry: `box` (use `unmapped.sym`/`style`), `skip` (leave it out of the block), `error` (refuse) |
| `classes` | yes | key (`<class>`, `<class>:<model>` or a subcircuit name) → `{ "sym": string, "pins"?: [terminal names], "style"?: any }` |

## Which key a device uses

A device's class is looked up by name (`nmos`, `res`, `vdd`, `gnd`,
`ipin`, … — the names in the symbol set, `tests/symbols.zon`). A
subcircuit instance's class is `block:<subckt>`; its key may be the class
name or the **subcircuit name** alone, so `"opamp"` above maps every
`X… opamp` instance. That works for a subcircuit the deck defines (pins:
its `.subckt` ports, in order) and for one it does not (pins `p1`..`pN`).

A device whose card names a model is looked up first as
`<class>:<model>`, then as `<class>`, so one PDK flavour can carry its own
symbol and pin order while the class key covers the rest. The model is the
first word after the card's nodes that is neither a number (`1k`, `.5`,
`{expr}`, `'expr'`) nor a `key=value`, among the first two such words:

| card | model |
|---|---|
| `M1 d g s b nfet_01v8 w=1u` (also Q, D, J, Z) | `nfet_01v8` |
| `R1 a b 1k res_high_po`, `R1 a b rpoly l=10u` (also C) | `res_high_po`, `rpoly` |
| `R1 a b 1k` | none: `res` applies |
| `XM1 d g s b sky130_fd_pr__nfet_01v8 w=1` (an undefined PDK master drawn as a primitive, netlist.4) | `sky130_fd_pr__nfet_01v8` |

A subcircuit block has no model key. The deck is read lowercased, so keys
are matched lowercased: `"NMOS:NFET_01V8"` maps `nfet_01v8`; two keys that
differ only in case refuse the run. A model key's `pins` are checked like
any other: one that is not a permutation of the class's terminals refuses
the run when a device uses it.

A backend that maps `nmos` or `pmos` (by class or by any `nmos:<model>` key) keeps that geometry for MOS bodies.
Map its associated four-contact variant too (`nmos_body` or `pmos_body`
in the built-in symbol set, or `nmos_body:<model>`) to enable automatic B routing on that backend.
The four-contact entry may provide its own D/G/S/B permutation.

## `pins`

Absent: the symbol's own terminal order. Present: a permutation of the
class's terminal names, slot *j* naming the terminal that is the target's
*j*-th pin. A wrong length, an unknown name or a repeat refuses the run,
because a wrong permutation draws a schematic wired differently from its
netlist. Subcircuit entries are checked against the instance's ports when
the deck is placed.

## Output

```json
"target": {
  "name": "xschem", "version": 1, "units": { "scale": 2.0 },
  "devices": [
    { "device": 0, "name": "x1", "class": "block:opamp", "sym": "my_lib/opamp.sym", "pins": [0, 1, 2, 3, 4] }
  ]
}
```

`device` indexes the document's `devices`; `pins` indexes that device's
`pins`, already in the target's order. With `skip`, unmapped devices have no
entry. Nothing is written if the manifest is malformed or a mapping fails.

## Optional native port bundles

Pass `--bundles` to request a `port_bundles` array and draw proven groups in the SVG. Each row contains `device`, `label`, `contact` and `atoms`. Each atom contains its original zero-based `slot`, `term`, `net` and `xy`. The owning device retains its original scalar pin list and wires. A renderer can ignore the extra field or expand each row back to its individual atoms. An unsupported or caller-owned symbol yields an empty array. [Four-bit example](research/production-patterns/control-bus/README.md)
