# Center-tapped winding with a series L–C–L branch

AG1153 contains two instances of the same local drawing pattern. Each
center-tapped winding has one series inductor on each outer net, with a
capacitor joining their far nets. The two inductors stand perpendicular to
the winding and outside its outer terminals. The capacitor is parallel to
the winding, centered between the inductors, on the side opposite the tap.

This is evidence from two correlated groups in one figure. It does not
establish a general frequency, prescribe distances, or determine how to
place the entire circuit. The upper group has its capacitor above the
winding; the lower group has it below. A world-direction rule would fail
one of them. The relative rule is “opposite the tap.”

The certificate selects exactly `ag-1153:xl1:series_lcl` and
`ag-1153:xl2:series_lcl` after scanning all 2,936 corpus netlists and all
19 supported center-tapped contracts. The selector requires a unique
winding across the two outer nets, one inductor incident on each outer
net, a unique capacitor across their far nets, five distinct nets, a
supply tap and four nonrail path nets. Ambiguous raw candidates count
before any drawing eligibility check.

The geometry oracle reads actual SVG winding, inductor and capacitor
leads and checks their declared bindings. It verifies eight continuous
source wire paths using actual wire strokes and junctions. Cached pin
positions and repeated net labels do not establish continuity. Twenty
named method checks per group cover topology ambiguity, card order,
eight rigid poses, translation, swapped bindings, skew, wrong-side
placement and lost midpoint alignment.

Replay from the repository root:

```sh
python3 -B docs/research/figures/ct_series_tanks.py external/examples /tmp/ct-series-tanks.json --check
```

The frozen evidence is
[`ct_series_tanks_cases.json`](figures/ct_series_tanks_cases.json). The
script records corpus and source hashes plus its local reader dependencies.
The first engine prototype preserves the actual coil and places only its
three passives, with a full-row rollback on unsupported frames or collisions.
A semantic four-member span prevents a shelf cut even when an actual frame
later abstains. Therefore geometry rollback does not promise byte-identical
whole-deck wrapping. Caller relations retain the existing wrap precedence.

The isolated first run passed both source geometry cases in both compact
modes, but only 15 of the 16 mode/path observations were physically joined.
After compaction, XL1 N2 and LS2's near terminal were disconnected. A copied,
printing-only routing trace reproduced both complete output JSONs exactly:
the M4 net crosses four foreign wires against the ordinary budget of three,
then its five pins form one proximity group and are all labelled. Before
compaction the local two-pin and remote three-pin groups each get a wire.

The full source comparison rejects this prototype: it adds 30 named source
partition mismatches in AG1153 and resolves one earlier mismatch, changing
that comparison's total from 49 to 78. P4's remote trunk failure, a net2 shelf
split, and both lost and excessive output-net joins are also retained. All
other 2,935 drawings are byte-identical to the preceding candidate. Local
shape is insufficient evidence for accepting the owner. The next study is
the complete 26-device arrangement and its actual source partitions; no
routing-proximity or crossing-budget exception is justified by this result.
