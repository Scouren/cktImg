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
   each unforced corner by its devices or net.

2. **Roles.** Three misreadings cost the most:
   - In a deck of only `.subckt`s every port the names do not settle is an
     output. Say `role vi input` for each that only drives gates.
   - A `vb*` net the circuit makes itself (a drain is on it) gets a port at
     each pin. `role vb3 internal` wires it.
   - In a parts-only circuit the reference net is a ground and refuses
     `wire`. `role <net> internal` frees it.

3. **One `order` line along the signal.** The best-paying line: it turned
   the signal on 4 circuits and took 2 crossings to 0 on a fifth. An order
   across a mirrored pair names the device on the axis too
   (`order m9 m1 iss m2 m10`), or the axis device is pushed aside.
   Two independent tail current sources can share a requested axis on
   separate rows. With `--report`, a device symmetry request is honoured
   when both origins and all corresponding terminals reflect across the
   common axis. An honoured exact placement that breaks the reflection
   appears in the request's `blocked_by` entries.

4. **`face` for gates and flat parts.** Turn a stack's gates to the side
   their inputs come from. Turning a bias gate away from its mate needs
   `label <net>` with it, or one port is wired round. `face <part> <pin>
   left|right` turns a flat part end for end; its mate needs a line of its
   own.

5. **`group stack <upper> <lower>`** names members from top to bottom. For
   a pair in series, put their shared conduction terminals in the same
   column. A reversed request can select the intended branch while its
   final order is reported `relaxed/not_drawn`. The decision export uses
   the physical direction. Opaque blocks with their own port anchors can
   keep their horizontal positions while satisfying the vertical order.

6. **`row` for devices.** Name transistors and upright parts. A flat part
   named in `row` lands on the gates' level; left out, it settles on the node
   between the rows, which is usually where a person draws it.

7. **Blocks.** Set the port sides in the child `.subckt` before any line on
   the block's neighbours. Then `above <part> <block> <part>` puts feedback
   parts over and under the block, and `above <block> <block>` stacks two. A three-port part with two ends (a centre-tapped
   inductor) takes its ends left and right, the tap on top.

8. **`rail <supply> each`** when a wire must pass over the top, or when the
   bar joins only two pins (its two end corners go).

9. **Cells, as a full set.** The cell frame shifts when relation lines
   change, so numbers from an earlier round land elsewhere. Paste every
   `weak cell` line of one `--decisions 3` report, make them strong, delete
   the relation lines on those devices, then edit the cells.

10. **Places, as a full set.** `at` on some devices moves the others. Paste
    every `at` of one `--decisions 4` report, then edit. Read pin offsets per
    class and turn from `d.json` (a two-pin part's ends are half a unit from
    its centre). Use this when you already know the arrangement and the
    lattice has no cell for it (a part by one pin is `hang`, not this). An
    op-amp circuit starts here: its decisions are
    `at` lines already.

11. **`route <net> x,y ...`** for the one wire that must go a way the router
    does not take (a feedback wire over the top). `wire <net>` forces a wire,
    not a good one: when crossings rise, take it out.

Stop when every line is `honoured` and no crossing or unforced corner is
left that you can name a line for; or after three rounds in a row that fixed
nothing, handing over what is left as open complaints.

## What no line says

Spend no round on these; reach for the line beside each, or leave the
complaint open.

| you want | reach for |
|---|---|
| One pin of a net named, the rest wired | `label <net>` names the whole net; else leave it |
| A part level with a gate, or hung from a pin between two rows | `hang <part> <dev>.<pin>` |
| "This net goes over the top" | `route`, in coordinates |
| A mirror about a device that swaps two of its pins | cells, mirrored by hand |

A `group stack` reported `relaxed not_drawn` can reflect opposite series order or two devices anchored to the same rail at equal height. Compare the named device centers and shared conduction contacts. Other unexplained `not_drawn` verdicts belong in a bug report with the deck.
