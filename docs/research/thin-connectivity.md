# Physical connectivity after wire-part thinning

Iteration17 budgets crossings for individual physical wire parts. The
[paired audit](figures/thin_connectivity.py) compares iteration16 with the
bounded iteration17 candidate, then checks every changed pin-pair connection
against actual source SVG ink. It records **307 newly connected pairs and
19 newly separated pairs**. Source agreement improves for **206 pairs and
worsens for 120**. These are correlated observations; several pairs can
share one changed wire. This is a measured tradeoff, not equivalence to the
source drawings.

## Metric and evidence boundary

The script verifies all **2,202 AG and 734 AMS** paired drawing names,
source-deck/cache hashes, native drawing/report hashes, scorecard inputs,
and frozen executable hashes before examining changed native drawings.
A pair uses the same two named device/card-pin indices, terminal names,
and net bindings in both snapshots. Generated ports are excluded as pair
members. Changed or missing terminal identities fail explicitly.

Native physical connectivity follows same-net wire strokes through
endpoints, T junctions, overlaps, and explicit junction dots. A proper
crossing without a dot does not join. Matching labels never connect pieces.
This includes bent paths; a straight-line-only metric would miss some
connectivity losses. The audit examines 7,293 stable pairs on 613 changed AG
nets and 30 pairs on nine changed AMS nets. Unchanged native pairs receive
no new source-agreement claim.

For every transition, the source certificate checks the ordered SPICE
binding and actual transformed primitive leads. Resistor endpoints come
from the zigzag path; inductor endpoints come from the coil path. A positive
source connection requires a path made from named-net cache segments that
are independently supported by actual SVG conductor strokes. Unrelated
cache-only segments remain recorded and cannot invalidate an already
verified path or close a gap. A negative source connection additionally
checks **all** actual conductor ink, without cached net assignments. Actual
SVG contact dots join crossing strokes; cached dots cannot invent a join.
An unassigned actual path makes the case unsupported, rather than a false
negative. All 326 changed pairs have supported source certificates.

## Measured changes

| Transition | AG | AMS | Source interpretation |
| --- | ---: | ---: | --- |
| Newly connected, source connected | 199 | 4 | 203 agreements gained |
| Newly connected, source separated | 104 | 0 | 104 agreements lost |
| Newly separated, source connected | 16 | 0 | 16 agreements lost |
| Newly separated, source separated | 3 | 0 | 3 agreements gained |

The gained native connections span 33 AG circuits and 36 circuit/net
combinations, plus one AMS circuit/net. The 104 source-separated new joins
span 23 AG circuits and 24 nets. **Every one of those 24 nets also has a
source-supported new connection.** The source uses mixed physical
partitions within a single electrical net; joining the whole net does not
preserve those choices. Literal same-net label text is recorded on all
104 source-separated gain pairs, but labels do not establish physical
continuity or prove the author's intent. AG2309, AG2318, and AG2319 each
have three agreeing and eight disagreeing newly joined pairs.

The 19 newly separated pairs are confined to four named circuit/nets:

| Circuit/net | Source-connected losses | Source-separated losses |
| --- | ---: | ---: |
| AG1170, `q-` | 1 | 0 |
| AG2486, `vx` | 6 | 3 |
| AG2571, `vout` | 3 | 0 |
| AG989, `net4` | 6 | 0 |

The [frozen inventory](figures/thin_connectivity_cases.json) retains every
exact pair name, classified source expectation, and candidate mismatch:
104 extra joins and 16 missing joins. It also retains the 203 missing joins
and three extra joins resolved from the baseline. These lists describe
only the changed cohort. They do not claim to enumerate every mismatch in
the full source corpus. Source expectations remain independent of the
candidate: recording a known mismatch does not make that behavior desired.
Added **and resolved** mismatches require review before updating the gate.

There are no orientation, gate-facing, or broad source-equivalence gains
from this checkpoint. Whole-corpus crossings increase by 93 and bends by
146. The [scorecard](corpus-scorecard.md) records the wider validation and
these remaining costs. A general rule for preserving the source's mixed
physical partitions remains unfinished.

## Reproduction and oracle checks

The baseline executable SHA-256 is
`bc2600ab737626e56098dbf7c2c5610c720ddc9dd2feb65783e8f50759fc9fac`;
the candidate is
`cb0acd3ffc56619b5f008e1487a08f093e42aee54945b02a46422a8f20ace9d0`.
The script reads the frozen native JSON and copied executables; it does not
build or run Zig.

```sh
python3 -B docs/research/figures/thin_connectivity.py external/examples /tmp/thin-connectivity.json --native-root /tmp/cktimg-human-rules --baseline iteration16-aliases --candidate iteration17-bounded --check
```

The output includes full named component inventories, native coordinates,
ordered source bindings, actual source glyph object IDs, conductor paths,
contact dots, literal labels, and source/native/dependency hashes. The
frozen inventory exposes the exact transition and mismatch lists; its
canonical evidence digest fixes every remaining evidence field. Dependency
hashes are reported separately so an implementation change can be reviewed
alongside unchanged measured evidence.

Twenty-four literal and mutation checks cover native graph topology,
foreign-net exclusion, ordered primitive bindings, ambiguous schemas,
zigzag and coil endpoint attachment, cache-only gaps and spurs, unassigned
actual paths, label-only separation, and actual-dot crossing semantics.
Unsupported source geometry and unstable native identities fail rather
than skip. This is a manual research checkpoint gate, as distinguished from
CI and electrical round trips in [TESTING.md](../../TESTING.md).
