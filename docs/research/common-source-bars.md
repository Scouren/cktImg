# Straight bars at reciprocal MOS source junctions

The complete 2,936-deck census finds 31 exact reciprocal-MOS pair/tail
junctions, all in Analog-Genie. Every one is physically connected in the
source. Four have a horizontal row of actual source/source/drain tips, with
the tail drain strictly between the two sources and the tail lead facing
opposite the source leads. All four are straight bars in AG1153. These are
four correlated observations in one figure, not a universal rule for MOS
common-source wiring.

The topology requires three distinct four-terminal MOS cards and exactly
three raw junction incidences: S, S and D. The pair's drains and gates are
reciprocal, all three models have the same known polarity, the pair shares
one body rail, and the tail source and body use that rail. The two branch
nets, common net, rail and tail gate are distinct. Raw incidence includes
hidden body pins. Extra attachments, aliases, unknown models, mixed
polarity and an internal body return fail the bounded certificate. The
source reader uses its named-rail convention; the engine uses admitted
Role values. No source ID or device spelling selects the engine rule.

[The source reader](figures/common_source_bars.py) records the exact 31
names, every deck hash, all nine actual D/G/S leads per triad, body bindings,
verified conductor segments and all 93 pairwise connectivity proofs.
[Its inventory](figures/common_source_bars_cases.json) retains unsupported
cases explicitly; currently there are none. Twenty literal topology
controls and five interval controls accompany the census. Cached wires
without actual SVG ink are recorded and excluded from conductor proofs.

| Net | Source tips, in left-to-right order |
|---|---|
| net2 | M12.S (210,60), M14.D (300,60), M13.S (390,60) |
| net1 | M7.S (210,440), M9.D (300,440), M8.S (390,440) |
| net0 | M16.S (90,270), M17.D (150,270), M15.S (210,270) |
| net3 | M19.S (390,270), M21.D (450,270), M20.S (510,270) |

## Engine boundary and independent tests

The settled native pins already share these rows. The change therefore
adds a cold direct-bar consumer before ordinary pattern routing. It leaves
placement and the general trunk corner/escape policy intact. It admits only
automatic internal nets with the exact raw topology and three matching,
visible, upright actual class frames. Each selected actual lead must equal
its projected Canvas pin. Original route/via and member-at requests,
explicit port/style requests and caller first-order requests take
precedence. Existing same-net ink or any foreign segment contact makes the
consumer decline. Rejecting even a proper foreign crossing is this bounded
pattern's choice, not a change to Canvas's ordinary crossing policy.

After the full certificate and collision checks, one three-point
Canvas.commit preserves the middle junction. Canvas grows its route,
segment and point buffers before appending. It creates no nodes or labels.
A successful bar bypasses generic mirror propagation; its mate must qualify
independently. Later thinning and normal fallback remain active.

The temporary certificate is three typed EdgeIds, asserted to occupy
12 bytes. It is read together once for the current three-pin net; fixed
terminal indices and three points remain stack data. No retained request
table or extra allocator is added. Wide arithmetic checks precede narrowing
of transformed actual coordinates. The sequential Canvas mutation follows
canonical net order; this is a cold bounded owner with no speed or
zero-runtime-overhead claim.

The original full-source regression failed only straight-interval coverage
in both compaction modes after binding, frame, connectivity and clearance
checks passed. A new literal exposed an oracle hole: sampling only integer
coordinates accepted a one-unit open gap, even with an alternate detour.
Those two mutations were first observed RED. The copied successor samples
half-unit positions using widened doubled coordinates, which detects every
open gap between integer engine endpoints. Its gap controls passed while
the two source failures remained RED before implementation.

The isolated implementation then passed the consumer suite (7/7), public
bar suite (6/6), frame suite (6/6), and unchanged whole26 source suite
(3/3). These cover original request deferral, all reflected frames, hidden
and skewed pins, malformed coordinate bounds, complete-prefix rollback,
proper-crossing abstention and every allocation failure. The whole26 oracle
still requires all 90 ordered bindings and all 148 source physical pairs.

## Measured isolated result

[The native companion](figures/common_source_bars_native.py) verifies every
named corpus artifact and its source/binary hashes before measuring the
same 31 native triads. [Its frozen result](figures/common_source_bars_native_cases.json)
records the four missing straight bars becoming four complete bars, with
no connectivity transition among the 93 triad pairs. Only AG1153's drawing
and report changed; the other 2,935 drawings and reports are byte-identical.
The separate full physical gate also preserves all 148 whole26 pairs in
both modes and all eight passive output-marker observations. The older
baseline20 comparison retains exactly its previous 48 known mismatches;
none is in AG1153. This does not establish whole-corpus physical parity.

The frozen trial native executable is 48,895,544 bytes, SHA256
`8e970800ca8fab9e7be28db8dcbe4d5e25f6aeee3d8b83c88900898604cf4e54`.
Its raw WASM is 607,040 bytes, SHA256
`68cfc4796b3b9eea4b34bb232037d79cbe2f393a602ac11f5820303a1f482b1d`.
It exceeds the 563,200-byte cap; this isolated trial is not a release gate.
Full promoted renderer suites and reproducible optimized-artifact gates
remain separate work.

The source still uses diagonal reciprocal-gate wires where native wiring
has Manhattan jogs. Output-bar/capacitor row offsets and the variable-cap
arrow absent from the plain-C netlist remain visible differences. The four
new bars improve a specific source pattern, not complete visual equivalence.

## Reproduce

```sh
python3 -B docs/research/figures/common_source_bars.py \
  external/examples source-bars.json --check
python3 -B docs/research/figures/common_source_bars_native.py \
  external/examples native-bars.json \
  --baseline-ag BASELINE_AG --baseline-ams BASELINE_AMS \
  --candidate-ag CANDIDATE_AG --candidate-ams CANDIDATE_AMS \
  --baseline-bin BASELINE_BIN --candidate-bin CANDIDATE_BIN \
  --check --require-bars
```

The frozen native inventory uses the isolated `series-marker-first` and
`common-source-bar-first` corpus/binary artifacts. `--check` compares every
field, including exact names and dependency hashes, rather than counts.
