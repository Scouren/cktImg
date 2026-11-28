# Drawing a netlist by intent: the four statements

You say what the circuit **is**. The tool turns that into a drawing. You never give a
coordinate, a row, a column, a rotation or a wire path, and no statement takes one.

With no statement you get a plain, legal drawing (the baseline, below). Each statement adds
what the netlist cannot say. Write the fewest that describe the circuit: the 48 circuits of
the blind trial took 1 to 13 lines, 6 on average.

Names are the deck's own (devices `M1`, `R2`, `X1`; nets `vout`, `net3`), case-insensitive.
One statement per line; `#` starts a comment. Put the lines in a file of their own, or in the
deck behind `*@` so a simulator skips them. The order of names inside a `match` or a `stage`
means nothing: only `flow` states an order.

    python3 -m cktintent deck.sp [statements.ctl] -o drawing.svg

## 1. `net <nets> : supply | ground | bias | clock | signal` (what a net is)

| role | say it for | what it does |
|---|---|---|
| `supply` | a rail the reader does not follow | drawn at the top; parts on it stand upright, that end up |
| `ground` | the bottom rail | parts on it stand upright, that end down |
| `bias` | a static line that sets an operating point (`vb1`, `vcasc`, a reference into a gate) | a name at each pin, never wired across the page |
| `clock` | a line that switches devices on and off (`clk`, `phi1`, a gate drive) | a name at each pin; a transistor it gates may be a switch (baseline B1s) |
| `signal` | a net the reader must trace (a feedback line, a long output) | one wire, however far it runs |

`vdd vcc avdd dvdd` are supplies and `0 gnd vss vee` are grounds without a line; say every
other rail. A power input that the path starts from (a converter's `vin`) is the start of a
`flow`, not a supply. Call a line `clock` only when the devices it gates are switches: a
clocked device that sits inside a transistor stack stays upright anyway, and a line that
both switches one device and drives another's gate cannot be split (leave it unsaid).

## 2. `stage <name> : <devices>` (what belongs together)

The devices are drawn as one cluster; no device of another stage stands inside it. Use it
for a gain stage, a bias generator, a feedback network, an output buffer, one cell of
several. A device belongs to one stage at most. Devices you leave out are placed by what
they connect to.

A stage is also how far a mirror reaches (next statement): images in the pair's stage share
its axis.

## 3. `match <a> <b> [<c> ...]` (what is drawn as copies)

Two devices (a differential pair, a mirror, a cross-coupled pair, matched loads):
- they share a row and are mirror images about a vertical axis;
- the parts in their own columns (their cascodes and loads, in series above or below them)
  are mirrored about that axis with them;
- the one part under both (a tail) sits on the axis;
- every other upright device that swapping `a` and `b` would swap with a twin shares a row
  with that twin. It is **promised** the pair's axis only in the pair's `stage`. The tool
  also gives it that axis when no stage separates them (default D2); put the twins in a
  stage of their own to have them stand as their own group beside the pair;
- gates face each other on a shared gate line or a cross-coupled pair, face outward for a
  pair on one source node with its own gate nets, and are on opposite sides otherwise.

So an input pair with folded-cascode branches is drawn around one axis when all of it is
one stage, and as two modules side by side when the pair and the branches are two stages,
each with its own `match`. Both are common; say which you mean.

A pair whose tail is itself half of another matched pair stands over that half: `match q5
q6`, `match q1 q2`, `match q3 q4` draws a Gilbert cell's two switching pairs over its input
pair.

Three or more devices (a mirror with several outputs, a bank): one row.
Stages: `match cellA cellB` draws the second stage as the mirror image of the first; three
or more are copies in a row. List each stage's devices in corresponding order.

Parts that lie flat (series parts, switches) and blocks are not promised a row by `match`:
they follow the pins they feed.

## 4. `flow <a> -> <b> -> <c> ...` (which way the signal goes)

Each element is one or more devices or stages, taken as a group; the first and the last may
be nets (the inputs and the outputs).
- Each element is not left of the one before it.
- Nets at the start are inputs and enter from the left; nets at the end are outputs and
  leave to the right. On a mirrored element each may instead stay on its own half.
- A two-pin part named as its own element between the two things it joins lies flat, in
  line (a series resistor, a coupling capacitor, an inductor in a power path), and the nets
  it hands on are wired, never named.
- A clocked transistor named between the things at its two channel ends lies flat in the
  path.

Several `flow` lines are allowed (a second input, a side chain). A line that would reverse
an earlier one is refused. Write a feedback amplifier or a divider forward, as the stage
after the thing it senses; its return is a net (`net fb : signal` wires it).

## The baseline (no statement)

Promised, and checked on every drawing:

| id | rule |
|---|---|
| B1 | a transistor stands upright, source toward its rail (NMOS source down, PMOS source up) |
| B1s | it lies flat when it is a switch: no current path to a rail runs through its channel; or a `clock` gates it and a channel end carries a capacitor, an inductor, a port or a block |
| B2 | a two-pin part with one end on a rail stands upright, that end toward the rail |
| B3 | a transistor and the part in series with it share a column (load, cascode, degeneration; a divider whose tap is read) |
| B4 | a part from a device's output back to its own input is drawn around the device, on the input's side |
| B5 | a two-pin part with an end that feeds only gates, ports or capacitors lies flat |
| B6 | a gate faces what drives it; an input gate faces its port |

Done by default, not promised (what people do often, with the count in `cktintent/defaults.py`
and `cktintent/route.py`):

| id | default |
|---|---|
| W1 | ground is a symbol at each pin |
| W2 | a supply of up to four pins is one bar; a symbol at each pin beyond |
| W3 | any other net is one wire while its pins stand near; a net that spans far is cut where its pins stand apart, the pieces joined by name. `net x : signal` keeps it one wire |
| W4 | wires run level and upright; a 45-degree stroke is used only in the X where a cross-coupled pair swaps its two gate wires |
| W5 | with no `flow`, devices stand left to right in the order the deck first names them |
| D1 | a cross-coupled pair shares a row, looks inward and draws its X, with its tail on the axis, whether or not you match it |
| D2 | every image of a matched pair mirrors about the pair's axis unless a stage separates them |
| D3 | a series string of parts with one end on a rail is one column |
| D4 | a series string from a device's output back to its input (Miller compensation) lies in one row on the input's side |
| D5 | a part between a supply and a ground stands upright, the supply's end up |

A drawing much wider than it is tall is folded into bands, like lines of text. A band never
splits a stage, a `flow`, or devices a `match` holds to one row; nets that run from one band
to another are joined by name.

## What comes back

The exit status (0: a legal drawing; 1: the drawing breaks a gate; 2: no device in the
deck, or a file that cannot be read) and this, in circuit terms:

    11 devices, 8 statement lines
      note      flow vout -> in: refused, an earlier flow line already puts in before vout
      M1   M1 M2 are matched: one row
      M2   M1 and M2 are a pair on one source node with their own gate nets: gates face outward
      M4   M5 is the one part under both M1 and M2: on their axis
      S1   stages in and out do not interleave
      F1   flow in -> out: out is not left of in
      F2   output vout leaves to the right
    outcome: 29 of 29 relations shown
    drawn by name or symbol: vb vss
    wire crossings: 0

- A `note` for every line that was refused or adjusted, with the reason; for every terminal
  the router had to join by name for want of a clear path (`net n2: 1 of its 4 terminals
  joined by name, no clear path for a wire (M6.g)`); and for anything it had to move.
- The read-back: each relation the tool took from your lines, as a sentence, marked
  `[NOT SHOWN]` when the finished drawing does not show it. Read it before you accept a
  drawing: a `match` that found no images, or a stage that swallowed a device you meant
  elsewhere, shows here.
- The outcome: how many relations the drawing shows, which nets are drawn by name or by
  symbol, how many times two wires cross.
- `ILLEGAL <gate> <sentence>` lines, if any. A legal drawing has none: every net is joined
  by wire or by name and nothing else is (`lvs`), no two symbols overlap (`overlap`), no
  wire enters a symbol (`pierce`).

## Examples

Two-stage op-amp (`M1 M2` pair, `M3 M4` mirror load, `M5` tail, `M6 M7` second stage,
`Cc Rz` compensation, `M8` bias diode):

    stage in  : m1 m2 m3 m4 m5
    stage out : m6 m7 cc rz
    stage ref : m8 iref
    match m1 m2
    match m3 m4
    match m8 m5 m7
    flow ref -> in
    flow vinn vinp -> in -> out -> vout

LDO (`X1` error amplifier, `MP` pass device, `R1 R2` divider, `CL` load):

    net vb1 vb2 : bias
    stage div : r1 r2
    flow vref -> x1 -> mp -> div -> cl -> vout

Switched-capacitor sampler (`M1`, `M5` series switches, `CS` sampling cap, `X1 X2` amps):

    net phi1 phi2 : clock
    flow vin -> m1 -> cs -> x1 -> m5 -> x2 -> vout

Folded cascode as two modules (input pair, then the cascode branches about their own axis):

    net vb1 vb2 vb3 : bias
    stage in   : m1 m2 m3
    stage casc : m4 m5 m6 m7 m8 m9 m10 m11
    match m1 m2
    match m4 m5
    flow vinp vinn -> in -> casc -> voutn voutp

The same circuit around one axis (pair in the middle, branches flanking it):

    net vb1 vb2 vb3 : bias
    stage amp : m1 m2 m3 m4 m5 m6 m7 m8 m9 m10 m11
    match m1 m2
    flow vinp vinn -> m1 m2 -> voutn voutp

The decks in `tests/decks/` carry their statements inline; `docs/gallery/` holds what each
draws.
