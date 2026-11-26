# A complete four-sided center-tapped stage

The complete source census selects one 26-device scene, AG1153: two
center-tapped coils, four series inductors, two capacitors and eighteen
known NMOS. The coils share an axis and point their taps inward. Five-MOS
groups stand above and below the tanks; four-MOS groups stand outside them.
The upper group has its sources up and the lower group has its sources
down. Each side group has an upright reciprocal pair, a tail below and a
horizontal bypass above the upper coil.

This is one correlated figure among 2,936 decks, not a universal transistor
orientation rule. The two directed bypass channels distinguish upper from
lower. The selector enumerates both coil orders and both side assignments
and requires exactly one complete raw candidate before model or rail
eligibility. It counts every incidence on all sixteen stage nets, including
bulk pins, rails and controls. Extra attachments conservatively exclude the
first version of this complete scene.

The [source reader](figures/ct_four_sides.py) checks all ninety original
card bindings. Actual SVG strokes certify seventy-two visible endpoints.
Eighteen substrate bindings retain unknown source coordinates. An electrical
bilateral involution preserves every binding, explicitly allowing CT outer
end exchange and unordered passive ends. It is not the engine's exact mate
table, and it is not full pin reflection: the two center-tail gates, M14.G
and M9.G, both face left. Their exceptions are recorded by name.

Physical partitioning is a separate requirement. Among the 148 visible
same-net pairs, actual source ink joins 81 and leaves 67 separate. Every
negative is challenged against all actual conductor ink, so cached wires
or repeated labels cannot supply a false proof. The source keeps each
outer grounded transistor's gate separate from the other output terminals;
it also separates each lower coil/inductor pair from its remote three-MOS
branch. These source expectations remain immutable even when the native
renderer makes a different electrical-net partition.

The earlier [three-passive LCL prototype](ct-series-tanks.md) failed the
whole-circuit check: it added thirty source partition mismatches and resolved
one. The whole-stage prototype replaces that placement hook, with no partial
fallback. A cold 104-byte handle group owns all26 rows; caller requests,
exact mates and blocks extending outside the group veto it. Fully contained
automatic blocks remain. One proposal derives spacing from actual symbol
bounds and existing clearance, checks all325 member-body pairs and foreign
bodies, and commits all coordinates together. Unsupported frames restore
all rows. Its semantic shelf span is cut-only and can precede later frame
abstention; this is not a promise of byte-identical whole-deck fallback.

Real midpoint/drain/near-terminal tracks preserve equalities. Forty-two x
and thirty-five y adjacent-pin inequalities enter the existing single
compaction pass. An actual successful midpoint supplies the local symmetry
axis; the fixed center-tail gate exceptions remain. No source distance,
routing proximity exception or crossing-budget change is part of this
proposal. The public RED demonstrated both missing geometry and a false source
join. The whole-stage geometry and earlier eight local paths now pass; the
complete physical partition check is measured separately below.

The first whole-stage placement prototype passed complete geometry and ninety
bindings, but had one missing shared-tap join and thirty-two excess joins in
both compact modes. The bounded wiring consumer now borrows that successful
complete owner and preserves the unchanged source partitions.

Its six data answers are: (1) transform existing actual pins into checked
ordinary routes and one symbol per physical component; (2) process four
six-pin outputs as five-plus-one and two five-pin internal nets as three-plus-two,
plus the two-tap supply; (3) retain the existing 104-byte handle group, u5 member
and u2 terminal indices, u32 pin handles and usize checkpoint lengths;
(4) map each bounded request outside ordinary trunk candidate loops;
(5) borrow group/request tables for the drawing, keeping only per-net stack
scratch while Canvas owns output allocations; and (6) serialize these requests
within one Canvas because earlier ink is an obstacle, retaining existing
parallelism between independent drawings.

Each net commits both components and their correctly bound names together.
Actual same-net endpoint, T, overlap and X contact rejects the partition.
Failure truncates appended nodes, pins, coordinates and ink and rebinds the
coordinate slice even when allocation moved its buffer. Caller routes, poses,
first-net ordering, styles, port sides and admitted tap-rail directives take
precedence. The ordinary trunk costs, later crossing budget and label fallback
remain. The shared tap request runs before ordinary rails to avoid duplicate
symbols. This is a one-scene physical-partition observation, with no generic
connectivity or distance exception. Before implementation, the concrete
consumer had three intended positive failures while its boundary/contact
controls passed. The resulting eleven-test run passes, including every
allocation-failure path and late rollback. Deliberately omitting pin restoration
fails the unchanged rollback oracle: 73 pins remain where 72 are required.

The complete public pipeline passes all three tests, all ninety bindings and
all 148 source pairs in both compact modes. The independent native replay
reduces the latest feedback baseline's eighteen source-pair mismatches to zero.
The full 2,936-deck comparison changes only AG1153's drawing and report. Its
physical preservation gate against that feedback baseline passes. Against
checkpoint20, the broader study still records 48 known source disagreements
across other scenes, down from 49; none belongs to AG1153.

This is physical partition and scoped geometry parity, not whole visual
identity. Native output-port sides still differ from the source; the source's
diagonal crossed branches remain Manhattan wires in the native drawing.
Eighteen substrate coordinates remain unassigned in the source evidence,
although their original electrical bindings are checked. The isolated native
SHA is `49ed9cb18d76dea013f144667be1909bd0b3b6a9675b620d0924b4434062f4f1`.
Its WASM is 602,314 bytes, SHA
`e82efcbf6c1c8361e2e532d99f27e82f32968c6970cececa2636b87e2a975928`:
39,114 bytes above the strict 563,200-byte cap, so release acceptance remains
blocked on size and the remaining broader gates.

The [test provenance](figures/ct_four_wires_tests.json) records exact source
and native-frame hashes, ten literal declaration token hashes, all eight
consumer test names and unchanged test-body bytes. The prepared-to-repository
split separates actual-device setup, independent graph/rollback oracles and
frozen data; it changes neither an assertion nor a source expectation.

Replay the source inventory:

```sh
python3 -B docs/research/figures/ct_four_sides.py external/examples /tmp/ct-four-sides.json --check
```

The [frozen inventory](figures/ct_four_sides_cases.json) records exact names,
all source/corpus hashes, the full local Python dependency closure, twelve
named topology/permutation controls, actual lead geometry and every physical
pair certificate. Portability changes preserve every previous source row
and census observation exactly. This source replay does not assert native
geometry or physical parity.
