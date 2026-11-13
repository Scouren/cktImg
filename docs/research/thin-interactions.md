# Retained wire parts and competing routes

The initial17 part-budget trial preserved useful source connections, but
also disconnected source-connected pin pairs in four circuits beyond the
separate [AG2365 endpoint defect](thin-row.md). These are measured tradeoffs;
this study proposes no identifier exception, changed ranking, or forced wire.

The [audit](figures/thin_interactions.py) replays the existing source-pinned16
and pre-row17 diagnostic binaries. Each of eight named runs must exactly
match the corresponding frozen corpus geometry and report. Every traced
proper crossing is independently recomputed from the raw segment geometry.
The [inventory](figures/thin_interactions_cases.json) retains complete routing
rounds, greedy changes, partition results, actual source leads and conductor
paths, and exact named checks. The earlier15 and2365 inventories are unchanged.

| Circuit and net | Actual source connection lost | Traced interaction |
|---|---|---|
| AG1170 Q− | M4.D–M8.D | After Q− changes from automatic to cut, I+ has two residual parts with two crossings each.16 labels I+;17 retains it. The final Q− drain connection then disappears. |
| AG2486 VX | Six pairs among M16.D, M17.D, M18.D and M18.G | net2 has parts with 0/2/2 crossings.16 labels net2 and VX falls from four to two crossings.17 retains net2, cuts VX, then the existing all-pins partition fallback labels the VX terminals. |
| AG2571 VOUT | C2.2 to M1.D, M2.S and R2.1 | N3 has parts with 1/2 crossings.16 labels N3 and the next routing round recovers the C2 output connection.17 keeps N3 and makes no style change, so there is no next routing round. |
| AG989 net4 | Six pairs among CC.2, M11.D, M4.D and M6.G | net0 has parts with 1/2 crossings; net4 has a connected three-crossing part.16 labels net0 first, reducing net4 to two.17 exempts net0, so net4 is labelled instead. |

The pair lists in the inventory are exhaustive for these four circuits'
initial17 losses. Together they contain sixteen source-connected pairs and
three source-separated pairs. The separated pairs are exactly
`AG2486 VX M16.D–M22.G`, `M17.D–M22.G` and `M18.D–M22.G`: the source uses a
local VX label at M22.G. The entire source SVG conductor set also fails to
join those terminals. Reconnecting every terminal sharing VX would therefore
lose an intentional source distinction.

All studied terminal indices are bound independently to deck node order,
native terminal names, cached source roles, and actual transformed SVG
primitive endpoints. AG2571's R2 is a complete zigzag SVG path; its endpoint
verification reuses the existing resistor reader instead of accepting a
cache coordinate without matching ink. Every named source conductor segment
in these cases exists in the actual SVG. Rendered source inspection confirms
the local VX diode connection and remote M22 label, the C2 output branch,
the Q− vertical path, and the four-terminal CC feedback node.

AG1170 needs care when interpreting the baseline: its physical continuity
comes from two opposing labelled stubs meeting at `(870,60)`, between drain
pins `(870,40)` and `(870,80)`. They are not a paired trunk. Retained I+ ink
across that meeting point prevents both stubs in17; labels move to the actual
pins. The inventory retains the label coordinates as well as the wire tree.
This is a source-continuity loss, but it does not justify extending the
AG2365 horizontal trunk fallback to all orientations or named ports.

The bounded same-row fallback trial repairs2365 but retains all nineteen
loss identities above and introduces no new ones. Its independent all-pin
comparison is separate from this frozen initial17 trace. Stable horizontal
intervals alone miss these cases: bent paths, vertical pins, passive ends,
and coincident label stubs require the full physical pin-pair oracle.

## Replay

The diagnostic copies use the exact sources and printing-only preparation
recorded in [the 2365 companion](thin-row.md#provenance-and-replay). No build
or production edit occurs in this audit. Once those copies exist:

```sh
python3 -B docs/research/figures/thin_interactions.py /tmp/cktimg-thin-trace16-2365 /tmp/cktimg-thin-trace17-2365 /tmp/cktimg-human-rules/all-ag-iteration16-aliases /tmp/cktimg-human-rules/all-ag-iteration17-parts /tmp/thin-interactions /tmp/thin-interactions.json --check
```

The comparison includes exact source, binary, geometry, report and trace-log
hashes. An unexpected repair requires reviewing and updating the named
historical marker; it must not silently pass as the same experiment. This
inventory records failures for diagnosis, not desired routing behavior.

## Bounded candidate mismatch gate

The [native gate](figures/thin_interactions_native.py) and its separate
[inventory](figures/thin_interactions_native_cases.json) record the bounded17
candidate by its binary and drawing hashes. They do not substitute it for
the initial17 trace. The gate scans every native pin pair on the four affected
nets and requires exact terminal identities, coordinates, native loss names,
and the sixteen source-connected mismatch names. The three intentionally
separated AG2486 pairs remain separate evidence.

```sh
python3 -B docs/research/figures/thin_interactions_native.py /tmp/cktimg-human-rules/all-ag-iteration16-aliases /tmp/cktimg-human-rules/all-ag-iteration17-bounded /tmp/thin-interactions-native.json --check
```

Any unexpected improvement or new lost pair fails this gate until its named
marker is reviewed. Passing means the known mismatch set is unchanged; it
is not a claim that these connections are satisfactory. This bounded gate
covers four named nets, so the full-corpus physical-pair audit remains
required to discover regressions elsewhere.
