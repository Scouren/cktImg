# Architecture

One pipeline: a SPICE deck and four kinds of statement in, a judged drawing out. Everything
is plain data between stages; no stage calls back into an earlier one.

## The spine

`cktintent/draw.py` is the whole program, one line per stage:

| # | stage | reads | writes |
|---|---|---|---|
| 1 | `netlist.read_netlist` | deck text | the schema (devices, nets, ports, no geometry), the `*@` statements, notes |
| 2 | `controls.parse` | statement text | `Controls`: roles, stages, matches, flows, the lines it refused |
| 3 | `circuit.Ckt` | schema | the circuit model: devices, `net_pins`, rails, ports |
| 4 | `contract.derive` | `Ckt`, `Controls` | `Contract`: the relations the drawing must show, the notes, and the facts a placer needs. `defaults.add` fills in what the tool does where nothing is promised |
| 5 | `place.place` | `Ckt`, `Contract` | a position and an orientation for every device, the axis groups, the band of the page each device is in |
| 6 | `symbols.stamp` | the placement | the schema's devices get coordinates and pin positions |
| 7 | `route.route` | schema, `Contract` | wires, rail symbols, ports, names, junction dots, the crossing and corner counts |
| 8 | `gates.pieces`, `boxes.boxes` | the finished schema | how many wired pieces each net is in; the stages that stand alone, boxed |
| 9 | `judge.check` | a `Ckt` of the finished schema, the statements | for each relation: does the drawing show it |
| 10 | `gates.check` | the finished schema | what makes the drawing illegal (nothing, for a legal one) |

`render.render_svg` and `report.read_back` turn the result into an SVG and into the text an
agent reads. `__main__.py` is the command line around `draw`.

Placement is itself a small spine, in `place.place`: rows (`rows.assign_rows`), columns and
bands (`columns.assign_columns`, with the mirrored groups in `axes.Axes`), gate sides, then
the parts that hang on what is already placed (bridges, lanes, loops, the rest).

## One schema

The drawing schema is the only shared format, and it is the corpus's own (`human.json`): a
dict with `devices` (name, type, nets per pin, and once drawn x, y, pin positions,
orientation), `wires` (net, segments), `markers` (rail symbols and ports), `labels` (net
names), `junctions`, `ports`. The same schema is a netlist with no geometry (after stage 1),
the tool's drawing (after stage 8) and a person's drawing. That is why the judge and the
gates can read all three, and why `tools/corpus.py --people` can ask of 5,232 hand drawings
exactly what it asks of the tool's.

Lengths are px on a 10 px grid; a MOS drain-to-source length is 40 px (`unit`).

## Who owns what

One module writes each table; everything else reads it.

| table | owner |
|---|---|
| schema `devices[*].name/type/nets/card`, `ports` | `netlist` |
| `Controls` | `controls` |
| `Contract.relations`, `notes`, `upright`, `flat`, `top`, `bot`, `around`, `axes`, `images` | `contract.derive` |
| `Contract.cross`, `tails`, `loops`, `joints`, and the stance of string parts | `defaults.add` |
| rows | `rows` |
| x of every unit, lanes, bands | `columns` (the groups about an axis: `axes`) |
| the placement dict, gate sides | `place` |
| schema `devices[*].x/y/terminals/orient/band/gate_side/source_dir` | `symbols.stamp` |
| schema `wires`, `markers`, `labels`, `junctions`, `crossings`, `bends` | `route` (the grid: `maze`) |
| schema `net_pieces` | `gates.pieces` (called from `draw`) |
| schema `boxes` | `boxes` |
| `Result.outcome` | `judge` |
| `Result.findings` | `gates.check` |

## Module dependencies

Arrows point from a module to what it imports. There is no cycle.

```
draw ──> netlist, controls, circuit, contract, place, symbols, route, boxes, gates, judge
contract ──> view, circuit, defaults          defaults ──> circuit
place ──> rows, columns, symbols              columns ──> axes, symbols
route ──> maze, symbols                       boxes ──> gates, symbols
judge ──> contract, controls, geom, circuit   gates ──> symbols
render ──> symbols                            report (reads a Result)
```

The oracle side (`judge`, `gates`) imports nothing from the placer or the router. `gates`
shares only `symbols` (where a pin is, what a symbol covers) with them; `judge` shares only
`contract`, which never reads a position.

## Where behaviour varies (the seams)

| what varies | where it sits | how |
|---|---|---|
| the kind of device | `symbols.pins` / `body` / `label`, `render._transistor` / `_two_pin` / `_block` | a closed set of kinds (`t`, `blk`, two-pin kinds), switched on in those functions only |
| the kind of relation | a row `(rule id, kind, payload, sentence)` made in `contract.derive`, judged in `judge.holds` | a closed set of kinds; `holds` raises on a kind it does not know, so a new kind cannot go unjudged |
| the statements | `controls.parse` | four verbs into four tables |
| how a net is drawn | `route.route`, by role and by the wiring defaults | rails, named nets, wired pieces, in that order |
| the output format | `render.render_svg(schema, c)` | a free function over the schema; `--json` writes the schema itself |

No class hierarchy, no plug-in point, no callback: each of these has more than one case
today and is a function over plain data.

## Three changes, and what each would touch

| change | edits | existing function bodies changed |
|---|---|---|
| a fifth statement (the report's candidate: "these two are parallel lanes of the flow") | a verb in `controls.parse` and a field on `Controls`; rows in `contract.derive` and a line in `RULES`; a branch in `judge.holds`; the placer reads the new fact where lanes are laid (`place._lanes`) | 4 |
| say of one device that it is a switch (the report's second gap) | a verb in `controls.parse`; `contract.derive` adds the device to `flat` with its relation. The placer and the judge already read `flat` | 2 |
| a second output format (Schemify records, TikZ) | a new module with one function over the schema; a flag in `__main__.main` | 1 |

## Invariants

- **Legal or said so.** `draw` always returns; `Result.findings` is empty for a legal
  drawing. Every net is joined by wire or by name and nothing else is joined, no symbol
  overlaps another, no wire enters a symbol. The gates check this from the finished geometry
  alone, after the fact, on every drawing.
- **The contract never reads a position.** `contract.derive` and `defaults.add` see
  connectivity and statements only, so the same contract judges the tool's drawing and a
  person's.
- **A default is not a promise.** What `defaults` and the wiring defaults do is never judged;
  only the relations in `Contract.relations` are, and the read-back marks each one the
  drawing does not show.
- **Same input, same bytes.** No clock, no randomness, no dependence on set order: two
  processes with different hash seeds write the same SVG.
- **Everything on the 10 px grid.** `symbols.stamp` and `Maze.pin` assert it.
- **No file over 500 lines of code; every public item says what it is for.**
  `tools/check.py` enforces both.

## Adding a feature

1. If it is something the drawing must show, it is a relation: add the row in
   `contract.derive`, its sentence, its judge in `judge.holds`, and measure it on the
   people's drawings (`tools/corpus.py --people`) before trusting it.
2. If it is something people usually do but not always, it is a default: `defaults.py` for
   placement, `route.py` for wiring, with the count beside it.
3. Write the test first, at one of the three seams the tests use: `draw()`, the schema it
   returns, the read-back text. A drawing that changes on purpose changes `docs/gallery/`:
   run `python3 tools/gallery.py` and commit the pictures with the code.
4. Run the sweeps in `TESTING.md` and put the numbers in the commit message.
