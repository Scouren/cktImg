# Hinting a drawing to hand-drawn quality

cktImg knows a circuit's structure. It does not know its **intent**: which
path a reader traces first, what the designer thinks of as one stage, which
net is worth a wire. A person drawing by hand puts that in. You put it in
with `*@` lines, a few per circuit.

Measured on 13 hand-drawn reference circuits, hinted without seeing the
hand drawing: lines alone ended at 1 wire crossing and 62 corners in total,
where the people drew 2 and 68 and the unhinted engine 15 and 133. That took
0 to 6 **rounds** a circuit (one round: edit the lines, redraw, look) and
0 to 26 lines; relations (rung 2) were enough on 7 of the 12 that needed
any line.

## The target

A round's picture is at hand quality when all four hold:

1. No two wires cross where a line could part them.
2. Every corner is forced: its wire joins two pins on different rows *and*
   different columns, or goes round a symbol.
3. The signal reads left to right, supply down to ground.
4. A net is named only where its wire would cross more than three others.

`r.json`'s `metrics` counts crossings and bends; count again in the picture
before you stop.

## Intent, as five questions

Answer them from the netlist before the first line. Each answer is one line.

| question | a person's habit (5,263 hand drawings) | line |
|---|---|---|
| Where does the signal enter, and where does it leave? | The source stands left: the part farther from it stands right of the nearer in 90% of 1,676 pairs. A driven block stands right of its driver in 85% | `order` along the path: source, series parts, input device, output side |
| What is one stage? | Devices of one function share a row or a column; a degeneration or branch part stands in its transistor's column | `row`, `group stack <transistor> <part>` |
| Which way does each gate look? | Toward the net that drives it | `face <dev> g left\|right` |
| Which nets does a reader trace? | Feedback and the signal path are wires. A bias line is a port at each gate, never a written name (3,228 of 4,378 `vb*` and `bias*` nets) | `wire <net>`, `label <net>`, `role <net> ...` |
| What is a block's front? | Inputs left, output right, the inverting input on top (76% of 221); feedback over the block for the upper input, under it for the lower (96%) | `*@ left\|right\|top\|bottom <ports>` in the child `.subckt` |

## Rounds

Work down this list. Stop at the first round whose picture meets the target.

1. **Draw unhinted** with `--svg --report`; render the PNG. Read `requests`,
   then `grid`, then the picture. Done when you can name each crossing and
   each unforced corner by its devices or net. On a deck of 30 devices or
   more, draw once more with `*@ shelf off` before any other line: one row
   of columns is often the better start, and every later line is judged
   against it.

2. **Roles.** Four misreadings cost the most:
   - In a deck of only `.subckt`s every port the names do not settle is an
     input when only gates hang on it, else an output. Say `role vi input`
     for an input a drain or a part also touches.
   - A `vb*` net the circuit makes itself (a drain is on it) gets a port at
     each pin. `role vb3 internal` wires it.
   - In a parts-only circuit the reference net is a ground and refuses
     `wire`. `role <net> internal` frees it.
   - An input on pins far apart gets a port at each. `wire <net>` draws
     one port wired to them all.

3. **One `order` line along the signal.** The best-paying line: it turned
   the signal on 4 circuits and took 2 crossings to 0 on a fifth. An order
   across a mirrored pair names the device on the axis too
   (`order m9 m1 iss m2 m10`), or the axis device is pushed aside. An
   `order` line reflows the columns it does not name: when you move one
   device, name the device after it too, or the rest close up around it.
   For a group of devices, name it once and move it whole: `stage <name>
   <devs>` makes a unit, and `row`, `order` and `repeat` lines take its
   name (a device's name is a unit of one). A unit moves rigidly; a device
   of no unit inside the box it lands on steps out to the nearest free
   cell of its row, and nothing else moves. Each unit's grounded devices
   share their own bottom row, not the drawing's. `row s1 s2` levels the
   units' tops, `order s1 s2` puts s2 wholly right of s1, `repeat s0 s1 s2
   s3` lays s1 to s3 as s0 is, level and left to right: list each stage's
   devices in one order (member k of every stage the same part of its
   cell). ag-1067, four pass-XNOR cells in series: 7 lines (four
   `stage`, `repeat`, a `stage` for the output, `order b3 out`) draw the
   four cells alike on one level, where 54 lines drew a staircase.
   `row` and `above` set no column: `row` keeps its devices level in no
   left-to-right order, `above` puts them in vertical order only.
   Two independent tail current sources can share a requested axis on
   separate rows. With `--report`, a device symmetry request is honoured
   when both origins and all corresponding terminals reflect across the
   common axis. An honoured exact placement that breaks the reflection
   appears in the request's `blocked_by` entries.

4. **`column` for devices that belong over each other.** `above a b` sets
   only the rows: a and b may stand columns apart. `column a b` stands b
   directly under a in one column, in parallel or not. A `column` line
   wins over an `order` line that would part its devices.

5. **`label <net> at <dev>.<pin>` for one far pin.** The pins named carry
   the name; the rest stay one wire unless it crosses too many (then
   named as cktImg would; other nets keep their wires). **`wire <net> at <dev>.<pin> ...` for a
   piece you want wired**: the pins listed are one wire with one name, the
   rest drawn apart and named once. Two such lines split a net into two
   named pieces (`wire vy at m15.d m12.d` keeps the facing drains wired).
   A net drawn as names keeps pins facing each other with nothing between
   wired, one name a piece.

6. **`face` for gates and flat parts.** Turn a stack's gates to the side
   their inputs come from. Turning a bias gate away from its mate needs
   `label <net>` with it, or one port is wired round. `face <part> <pin>
   left|right` turns a flat part end for end; its mate needs a line of its
   own.

7. **`group stack <upper> <lower>`** names members from top to bottom. For
   a pair in series, put their shared conduction terminals in the same
   column. A reversed request can select the intended branch while its
   final order is reported `relaxed/not_drawn`. The decision export uses
   the physical direction. Opaque blocks with their own port anchors can
   keep their horizontal positions while satisfying the vertical order.

8. **`row` for devices.** Name transistors and upright parts. A flat part
   named in `row` lands on the gates' level; left out, it settles on the node
   between the rows, which is usually where a person draws it.

9. **Blocks.** Set the port sides in the child `.subckt` before any line on
   the block's neighbours. Then `above <part> <block> <part>` puts feedback
   parts over and under the block, and `above <block> <block>` stacks two.
   A three-port part with two ends (a centre-tapped
   inductor) takes its ends left and right, the tap on top.
   Turn or mirror a block in the parent with `face <block> <port>
   left|right|up|down` (`face x2 n1 right`), not `at ... MR0`; on a
   `symmetric` pair of blocks the second is drawn mirrored. Child side
   lines keep a recognised glyph (amplifier triangle, centre tap), turned
   or mirrored, when one of its turns puts every named port on its side in
   the line's order (`*@ left vip vin` puts vip above vin); else the block
   is drawn as a box.

10. **`rail <supply> each`** when a wire must pass over the top, or when the
   bar joins only two pins (its two end corners go).

11. **Cells, as a full set.** The cell frame shifts when relation lines
   change, so numbers from an earlier round land elsewhere. Paste every
   `weak cell` line of one `--decisions 3` report, make them strong, delete
   the relation lines on those devices, then edit the cells.

12. **Places, as a full set.** `at` on some devices moves the others. Paste
    every `at` of one `--decisions 4` report, then edit. Read pin offsets per
    class and turn from `d.json` (a two-pin part's ends are half a unit from
    its centre). Use this when you already know the arrangement and the
    lattice has no cell for it (a part by one pin is `hang`, not this). An
    op-amp circuit starts here: its decisions are
    `at` lines already.

13. **`wire <net> over|under`** for a wire round the top or the bottom of
    the drawing (a feedback wire): each pin of the net is brought to the run
    on its own way, and the run ends at its outermost tap; a pin with no way
    joins the net's other wires, and with fewer than two taps the line is
    `relaxed no_room`. **`route <net> x,y ...`** for any other
    way the router does not take. `wire <net>` forces a wire,
    not a good one: when crossings rise, take it out. The patterns:
    `ladder` joins pins facing each other in pairs along rows (a
    mirror's gates), the pairs by a rung at their middles; `trunk` runs
    one straight wire along a row (or down a column) and brings every pin
    to it, on the row of its sideways pins when nothing stands in the
    way, else half a unit off their tips: this is the gate bus of a bank;
    `route` hands the net to the router, pin to pin. A bus through gates
    that face both ways, or across columns joined top to bottom, must
    cross each inner column's wire (no line runs through a symbol): on a
    bank of five cascoded legs `trunk` draws both buses at that floor
    (6 crossings), so turn the gates one way (`face`) before you blame
    the pattern.

Stop when every line is `honoured` and no crossing or unforced corner is
left that you can name a line for; or after three rounds in a row that fixed
nothing, handing over what is left as open complaints.

## What no line says

Spend no round on these; reach for the line beside each, or leave the
complaint open.

| you want | reach for |
|---|---|
| A part level with a gate, or hung from a pin between two rows | `hang <part> <dev>.<pin>` |
| A mirror about a device that swaps two of its pins | cells, mirrored by hand |

A `group stack` reported `relaxed not_drawn` can reflect opposite series order. One whose devices share no channel net but a rail (two devices anchored to the same rail) is `rejected unjoined`, as is a `mirror` or `bank` whose gates are on two nets. Compare the named device centers and shared conduction contacts. Other unexplained `not_drawn` verdicts belong in a bug report with the deck.
