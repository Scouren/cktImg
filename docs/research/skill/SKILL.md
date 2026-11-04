---
name: cktimg
description: Schematics from SPICE netlists with cktImg. Use when the user wants a circuit or netlist drawn as a schematic (SVG, TikZ, Schemify cells), or a cktImg drawing changed.
---

<!-- RESEARCH RECORD (docs/research/steering.md): the draft written against
the steering interface before it existed, so the interface would fit its
caller. Shipped, revised, as skills/cktimg/ (rungs 0 to 5, `requests`,
`--decisions 1-4`); `--help-hints` and a rung-5 export were not built. Read
skills/cktimg/ for the tool as it is. -->

cktImg lays a netlist out the way a textbook draws it, and guarantees the
drawing is clean: every net one piece, no wire on another net's pin, no
symbol on another. You steer it with `*@` lines in the deck, on a **ladder**
of rungs from what the circuit means down to where each wire runs. Work from
the top of the ladder and **descend** one rung at a time, only for a
**complaint** the rung above cannot fix.

## Steps

1. **Write the deck so its names carry its meaning.** Supply `vdd`, ground
   `0` or `gnd`/`vss`, inputs `in*`/`vin*`, outputs `out*`/`vout*`, bias
   `vb*`/`bias*`; matched devices numbered side by side (`M1`/`M2`); one
   `.subckt` per block, its port sides in `*@ left|right|top|bottom` lines.
   Done when `cktimg-json --report r.json deck.sp` exits 0 and `r.json` lists
   no parse diagnostics.

2. **Draw at rung 0**: no hints.
   `cktimg-json --svg d.svg --report r.json deck.sp`.
   Done when you hold `d.svg`, `r.json`'s `gates` (all pass: the engine
   guarantees them) and its `metrics`.

3. **Review against [CHECKLIST.md](CHECKLIST.md).** Read `r.json`'s
   `decisions` and its text `grid` first, then the image for what they
   miss. Done when every checklist item is marked *ok* or carries a
   complaint that names its devices or nets ("`m5` beside `m6`, should sit
   on the axis under the pair").

4. **Fix each complaint on the highest rung that fixes it.** Find the rung
   in the table below; copy the matching line from
   `cktimg-json --decisions <rung> deck.sp`, edit it, add it to the deck,
   redraw. Lines from rungs 3 to 5 come as `weak` stays: drop `weak` from
   the line you edit, keep it on the rest. Done when every complaint from
   step 3 is gone or descended to rung 5, and no metric got worse that the
   complaint did not ask for.

5. **Read every request.** `r.json`'s `requests` gives each `*@` line a
   state: `honoured`, `relaxed` (with its residual), `dropped` or `rejected`
   (with the lines or guarantee in `blocked_by`). Fix a blocking line, or
   descend one rung for that complaint. Done when every line you wrote is
   `honoured` or `relaxed` by an amount you accept.

6. **Stop** when the checklist passes, or after three rounds that fixed
   nothing. Hand over the drawing, the deck with its `*@` lines, and any
   complaint still open with the rung you stopped at.

## The ladder

| rung | you say | lines | reach for it when |
|---|---|---|---|
| 0 | nothing | — | always first |
| 1 meaning | what the circuit is | `role`, `kind`, `class`, `group`, `nogroup`, `grouping off`, `symmetric`, `axis`, `symmetry off`, `driver`, `expand` | a net's role or a matched group is misread |
| 2 relations | where things stand to each other | `row`, `above`, `order`, `group stack`, `upright`, `bridge`, `face`, `label`, `wire`, `port`, `rail`, `first` | the parts are right, their arrangement is not |
| 3 cells | each device's lattice cell | `cell` | one device must stand at a given row and column |
| 4 geometry | exact coordinates and orientation | `at`, `refdes` | the lattice cannot express it |
| 5 wires | points a net passes, or its exact route | `via`, `route` | the router's path for one net is wrong |

Every rung below 0 is a constraint the engine honours when it can, and
reports when it cannot; the drawing stays clean either way. The vocabulary,
its arguments and examples: `cktimg-json --help-hints`.
