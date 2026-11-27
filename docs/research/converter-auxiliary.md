# Converter auxiliary switches and their separate loads

This is source research for a future placement change. It makes no engine or
test expectation change. The retained baseline is `all-ag-iteration13-final`.

The existing [bus study](converter-bus.md) proves that each of the 145 selected
flying-capacitor loops has one auxiliary PMOS on its input bus. Source ink joins
that switch to the two loop switches in 144 drawings; native13 joins 107. The
38 source-connected/native-separated cases are retained by exact name in
[`converter_auxiliary_cases.json`](figures/converter_auxiliary_cases.json).

## A repeated load explains 36 of the 38 remaining cases

The new predicate starts from that existing loop and bus certificate. It reads
declared device types and D/G/S bindings, never instance or net spelling:

1. The auxiliary PMOS's other channel end supplies exactly three PMOS sources.
2. One PMOS is diode connected. A second shares its gate and has its drain on
   the loop's input coil node. The third is the controlled branch.
3. The controlled branch's drain supplies one grounded NMOS diode and the gate
   of one grounded NMOS whose drain meets the PMOS diode.
4. One further grounded NMOS drains into that controlled node and has a
   gate-only control. This distinguishes the local bias branch from an extra
   amplifier output on the same net in ten drawings.

The five signal nodes are distinct. PMOS body connections do not count as
source branches; source-tied wells occur in the corpus. Multiple qualifying
devices reject the six-role query. The predicate selects **103 expanded loads**,
including **36 remaining bus misses**. The other two misses are **AG1196:M5 and
AG1330:M1**, whose downstream circuits are subcircuit blocks. All 42 cases
outside this predicate remain explicitly inventoried. The reused loop
certificate selects no AMSNet circuit.

The script independently verifies **1,854 actual SVG D/G/S lead endpoints**
for these six-device loads. It reuses the earlier hashes and actual-lead proof
for the auxiliary and ten loop devices. It does not count cached coordinates
as visible ink without matching the glyph primitives.

## The switch belongs beside the bus; its load need not

All 103 source auxiliary bus leads are above the main incoming switch. In 101
the auxiliary channel is horizontal, bus on the left; **AG1199:M1 and
AG1202:M5** are upright. In 87 the auxiliary bus lead shares the main and lower
switches' bus-pin column. Native13 has 24 above the main, none horizontal, and
none on that shared column.

The load has a different set of habits:

| Actual source relation | Agree / selected |
| --- | ---: |
| All three PMOS upright, sources above drains | 103 / 103 |
| All three NMOS upright, drains above sources | 103 / 103 |
| PMOS diode directly above its NMOS mirror mate | 103 / 103 |
| Three PMOS source leads on one row | 93 / 103 |
| Controlled PMOS directly above NMOS diode | 95 / 103 |
| All six devices above the main power path | 78 / 103 |

The first three relations already hold in native13. They are useful guards,
not new wins. Native13 places all six above the main in only 15 cases, but the
25 source exceptions forbid making this a universal group order.

The four non-ground load nets demonstrate why the whole mirror must not be
moved with the auxiliary:

| Actual source tree | Continuous / selected |
| --- | ---: |
| Auxiliary output to all three PMOS sources | 74 / 103 |
| PMOS mirror gates/diode to NMOS mirror drain | 91 / 103 |
| Controlled PMOS drain, NMOS mirror gates/diode, bias drain | 103 / 103 |
| Output PMOS drain to the main input coil node | 82 / 103 |

Every positive certificate retains the exact named terminal targets and
spanning conductor segments. Every negative also stays disconnected when the
search uses **all actual SVG conductor ink**, so missing cached segments do
not account for these separations. Labels supply no graph edges. Only one
cached segment in this audit lacks actual ink: an AG1192 coil-return segment;
the actual verified tree still joins that case.

Visually checked examples:

- **AG1193:** horizontal auxiliary above the main, with its six-device load
  nearby and continuous supply and coil return.
- **AG1207 and AG1222:** horizontal auxiliary stays on the power bus while
  the six-device load is remote; its supply and coil return use separate
  labeled pieces. Both are among the 38 native bus misses.
- **AG1257:** auxiliary supply reaches the nearby load, but the load's coil
  return uses a label. Even a nearby load does not imply every net is wired.
- **AG1202:** upright auxiliary still physically joins the main bus and load.
- **AG1199:** upright auxiliary moves with a separate mirror block and uses
  its own VIN port; it is the source's sole separated auxiliary bus.

## Topology does not uniquely determine the exceptions

The inventory contains a literal **28-pin isomorphism certificate** for the
seven devices in AG1193 and AG1199. All D/G/S/B bindings map exactly, including
the auxiliary's D/S order and the supply/ground roles. Their source auxiliary
orientation and bus continuity differ. This is a local induced-graph
certificate, not an assertion that their full circuits are isomorphic; outside
incidences and the overall composition differ.

Reversing auxiliary D/S cannot decide the upright case either: AG1202 uses bus
at D, but horizontal AG1192, AG1215, AG1227, AG1265, AG1329 and AG1330 do too.
The 101-horizontal habit is therefore a bounded default with two recorded
exceptions, not a topology theorem. The broader existing 143/145 horizontal
bus habit includes the same two exceptions.

## Smallest next implementation experiment

`power_paths.2` deliberately leaves the auxiliary unresolved. Its mirror
neighbors retain ordinary placement; `loop_place` then relocates only the ten
loop members. The resulting auxiliary can be remote and upright. The existing
six-unit input-tree proximity guard in `wires.near` consequently retains
separate ports. Changing that routing distance alone would join distant
devices without recovering the source composition.

For a first bounded experiment, use the expanded-load certificate above but
move **only the auxiliary** into an extra row above the incoming loop switch.
Make its channel horizontal and bus end face the local bus; preserve the
load's existing placement. Align actual bus terminals, reserve the auxiliary's
full frame and gate approach, and extend shelf/compaction protection to the
new row. A common gate direction is not established: the source uses both.
The existing bus seed or ordinary attachment must then provide a continuous
three-switch tree without forcing the load's supply or coil-return labels
into long wires. This is an ownership proposal, not measured native results.

Keep explicit form/face/row/order/cell/at, custom frames, mates, port sides and
wire styles as admission boundaries. If the extra placement cannot fit, keep
the existing loop and ordinary auxiliary behavior. Do not silently enlarge
the ten-device loop's existing topology claim or relax unrelated route limits.

The first public regressions should pair literal AG1193 with AG1222: both
require the auxiliary's source row/axis, an actual three-switch input tree,
the seven existing local loop trees, and electrical correctness after wrap
and compaction. AG1222 must not require moving the separate mirror beside the
loop. Test explicit upright/placement constraints and actual shifted frames
separately. The source exception lists and isomorphic counterexample remain
part of the assessment rather than circuit-name exclusions in production.

## Reproduce

```sh
python3 -B docs/research/figures/converter_auxiliary.py \
  external/examples/analoggenie /tmp/converter-auxiliary.json \
  --native /tmp/cktimg-human-rules/all-ag-iteration13-final
```

The script checks source and native hashes against the existing certificates,
retains exact selected/excluded/miss and relation lists, and runs 13 named
method checks, including ambiguity, wrong pin roles, D/S permutation, a
source-tied well, card permutation, and crossing-versus-T-junction negatives.
It requires no engine execution. The converter variants are correlated
examples of one family, not 103 independent validations.
