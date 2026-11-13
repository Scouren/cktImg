# Converter input buses and auxiliary branches

The 145 certified flying-capacitor loops in [converter-loops.md](converter-loops.md)
have a main input switch and a lower input switch. Their local source bus stands
strictly left of both actual channel terminals in 141 drawings; AG1267, AG1280,
AG1312, and AG1345 instead use the shared terminal column. Iteration13 tries the
existing tap distance to the left, then that column when the first path is
blocked. This is a default preference with a collision fallback, not a rule
that identifies the four source exceptions from topology.

The broader input bus contains another branch outside the ten selected loop
members. [converter_bus.py](figures/converter_bus.py) finds **exactly one extra
branch in each of the 145 drawings** using the existing gate-only PMOS input-bus
certificate and actual D/S net membership. Gates and bodies are not channel
branches. Instance names identify the evidence; they never choose membership.

The audit checks the existing source hashes, rechecks all source bus conductor
segments against transformed SVG strokes, and verifies another **435 actual
D/G/S lead endpoints** for the 145 auxiliary switches. It reuses the certified
main/lower switch leads and retains exact source and native names, coordinates,
wire paths, source hashes, and native JSON hashes in
[converter_bus_cases.json](figures/converter_bus_cases.json). Missing or stale
sources and unsupported lead geometry fail. Labels and port names never supply
an edge to the physical connectivity certificate.

## Source habits and a real exception

The source bus physically joins all three switches in **144/145 drawings**.
AG1199:M1 is the exception: its displayed S5 switch belongs to a distant
`I_SR` mirror block and has its own VIN port. Inspection of the source rendering
agrees with the disconnected actual-ink certificate. That is evidence against
unconditionally forcing every auxiliary branch into the selected local loop.

All 145 auxiliary bus terminals stand above the main input switch's bus
terminal in their source. **143/145 auxiliary channels are horizontal**, with
the bus on the left; AG1199:M1 and AG1202:M5 are vertical. Of the horizontal
switches, 95 gates face up and 48 face down. In 117 drawings, all three bus
terminals share a column. Exact member lists for every relation and exception
remain in the inventory. These related converter variants are correlated
observations, not 145 independent designs.

These placement habits are not yet implemented for the auxiliary branch.
In the measured native snapshots all 145 auxiliary switches remain upright.
Source AG1199's remote block separation is also not preserved by the current
native placement: its auxiliary terminal can lie close to the local tree.
A native distance choice therefore cannot identify that source exception.

## Physical continuity regression and repair

The original seven-tree oracle covers only the selected local terminals. It
correctly found all local trees continuous, but did not cover the auxiliary
switch. Visual review of AG1316 exposed the missing broader oracle.

| Snapshot | Three-switch buses physically joined |
|---|---:|
| Frozen iteration12 wrap | 64/145 |
| First iteration13 boundary-port trial | 1/145 |
| Iteration13 retained-pin distance repair | 61/145 |
| Final iteration13 component proximity | 107/145 |

The first trial consumed the local tree's retained anchor before applying the
ordinary input grouping rule. It preserved electrical connectivity through
ports but lost **63 named physical connections**. Its sole surviving joined
bus was AG1237, whose bus has an output role and follows a different path.
The retained-pin repair restored 60 losses. AG1249:M5, AG1263:M5, and AG1294:M5
still lost their physical connection: their distances from the retained main
pin grew from 230 to 280, 230 to 280, and 230 to 250 native units respectively,
across the existing 240-unit input limit. Their nearest actual tree points
were only 100, 100, and 60 units away.

The current rule uses the outside pins' whole bounding-box half-perimeter plus
the minimum extra span needed to reach an actual same-net tree segment. The
sum must fit the existing six-unit input limit. This keeps a multiple-pin
outside cluster bounded; it does not admit widely separated pins independently
or grow a chain one pin at a time. The retained anchor remains a routing
handle. It no longer stands in for the tree's physical extent.

The boundary port is placed before outside branches attach, while the seeded
ink is one verified connected component. Nearby outside pins then route onto
that component. Distant outside clusters retain ordinary input ports. A failed
route retains the existing name-based electrical fallback. No source ID or
new persistent geometry state participates in this choice.

`tests/converter_bus_remote.zig` requires actual three-terminal continuity,
full electrical connectivity, and no shorts for literal AG1316, AG1249, AG1263,
and AG1294 DUTs. All three retained-pin failures went red before the component
proximity change. AG1316's compact drawing, with default or requested-left
port, also went red before the first repair. Without compaction, AG1316 was
already disconnected in iteration12: its retained-pin span was 500 units.
Its temporary named known-gap assertion then failed on an unexpected
improvement, because the actual lower tree stood only 200 units away. That
marker was removed and both uncompact variants now require the same source
continuity oracle.

Private literal proximity checks cover the middle and end of a long tree,
threshold equality and one-unit excess, wrong-net and empty ink, the sum of
cluster extent and reach, and rejection of a large cluster whose individual
pins each stand close to the tree. Public bus tests independently check a
complete left spine and a connected requested-left port outside it; source
terminal names and a remote-only spur cannot satisfy those tests.

The final component-proximity corpus joins **107/145** auxiliary branches and
preserves every one of the 64 frozen iteration12 physical connections. Its
43 gains include **42 source-supported gains** and **one new source mismatch,
AG1199:M1**. That branch now joins the native bus because its native placement
stands close to it, while the source puts it in a distant separate block.
The exact source continuity agreement is therefore **106/145**, not 107/145.
The inventory names all **38 source-connected branches still separate** in the
native result, and retains AG1199's opposite mismatch. This rule does not
establish equivalent placement or wiring for all 144 source-connected branches.
There is no ID-specific exception to conceal the remaining block-placement gap.

## Reproduction

The source audit works without native results. Add repeated named snapshots to
retain comparisons; no engine build or execution occurs in this script:

```sh
python3 -B docs/research/figures/converter_bus.py \
  external/examples/analoggenie /tmp/converter-bus.json \
  --native iteration12=/tmp/cktimg-human-rules/all-ag-iteration12-wrap \
  --native trial13=/tmp/cktimg-human-rules/all-ag-iteration13 \
  --native near13=/tmp/cktimg-human-rules/all-ag-iteration13-near \
  --native final13=/tmp/cktimg-human-rules/all-ag-iteration13-final
cmp docs/research/figures/converter_bus_cases.json /tmp/converter-bus.json
```

Seven named audit-method checks cover a real extra channel, D/S card reversal,
exclusion of gate/body incidences, wrong-polarity rejection, an actual
T-junction, and a same-net wire gap. Complete input-file hashes and the loop
inventory hash are retained. Compare complete JSON results to replay exact
names and geometry; aggregate counts alone are not the oracle.
