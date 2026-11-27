# The `cktimg` Python package

```python
import sys; sys.path.insert(0, "<cktImg>/python")   # until it is packaged
import cktimg

placement, report = cktimg.place(deck, symbols="set.zon", target=manifest, start=previous)
svg, report = cktimg.draw(deck, start=previous)
```

`deck` is netlist text (ngspice, or SPRack's `cktimg` dialect), or any object
with a `netlist("cktimg")` method, such as a `sprack.Circuit`. The package
imports nothing of SPRack's, and SPRack's `Circuit.place/draw` delegate here.
Hints are the deck's own `*@` lines (`skills/cktimg/SKILL.md`).

| argument | given as | flag |
|---|---|---|
| `symbols` | a path, or `.zon` text | `--symbols` |
| `target` | a path, JSON text, or a dict (`docs/TARGETS.md`); `classes` keys are `<class>`, `<class>:<model>` (`"nmos:nfet_01v8"`, matched first) or a subcircuit name | `--target` |
| `config` | a path, or `lint.zon` text | `--config` |
| `start` | a path, JSON text, or a placement dict: an earlier placement whose devices stay put | `--from` |
| `exe` | the `cktimg-json` to run; else `$CKTIMG_JSON`, else `PATH` | |

A string is read as a path only if it is a single line naming an existing
file. Anything else is taken as content, so Pyodide callers pass text.

Both calls raise `cktimg.CktimgError` with cktImg's own diagnostic when the
deck, symbols, manifest or config is refused. Nothing is returned then.

This version runs `cktimg-json` in a temporary directory. An in-process
binding and a wasm build for Pyodide will use the same call.

## The placement

The document `cktimg-json` writes as its output file, and the C ABI's
`cktimg_json`. Coordinates are integers in symbol units (`unit`: 40 in the
built-in set), y down.

```json
{
  "devices": [
    { "name": "m1", "class": "nmos", "value": "nch", "rot": 3, "mirror": false,
      "pos": [100, 100],
      "pins": [ { "term": "d", "net": "x", "xy": [120, 100] } ],
      "bulk": "0" }
  ],
  "nets": ["0", "x"],
  "wires": [ { "net": "x", "segments": [ [ [120, 100], [120, 60] ] ] } ],
  "junctions": [ [120, 60] ],
  "labels": [ { "net": "vb", "at": [40, 20], "side": "left" } ],
  "no_connects": [ [200, 40] ],
  "target": { "name": "xschem", "version": 1, "devices": [ { "device": 0, "name": "m1", "class": "nmos", "sym": "n.sym", "pins": [0, 1, 2] } ] }
}
```

| field | meaning |
|---|---|
| `devices[].name` | the card's name, lowercased. Names starting `_` are the rail and port symbols cktImg added (`_vdd3`, `_ipin7`) |
| `devices[].class` | the symbol class (`nmos`, `res`, `vdd`, `block:<subckt>`, ...) |
| `devices[].value` | the card's value or model |
| `devices[].pos` | the symbol's origin, its centre in the symbol's own frame |
| `devices[].rot`, `mirror` | mirror about the vertical axis first, then `rot` quarter turns clockwise |
| `devices[].pins[]` | one per class terminal the card has: terminal name, net, and drawn point |
| `devices[].bulk` | present when the card has one node past its terminals (a MOS body on a three-pin symbol): that net, with no drawn point |
| `devices[].hidden` | instead of `bulk` when there are two or more such nodes: the nets in card order |
| `nets` | every net name |
| `wires[]` | per net, its drawn segments as point lists |
| `junctions` | the connection dots drawn on wires |
| `labels[]` | a net written as a name at `at`, its text on `side` |
| `no_connects` | the points drawn as an unconnected cross |
| `target` | only with `target=`: each device's backend symbol, and the indices of its `pins` in the backend's order (`docs/TARGETS.md`) |

## The report

`report["requests"]` holds every `*@` line of the deck, each with its file
`line`, `text`, `state` (`honoured`, `relaxed`, `dropped`, `rejected`),
`code`, `blocked_by` and, for a refused name, `name`. `skills/cktimg/SKILL.md`
lists the codes. The report also has `gates`, `text_overlaps`, `metrics`,
`decisions` and `grid`.
