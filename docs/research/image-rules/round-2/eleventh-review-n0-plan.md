# Independent review of the prospective N0 integration

The proposed [N0 contract](n0-implementation-contract.md) uses the existing
two-part drawer at the correct scale. This is a source review of a plan,
not execution of a new integration, allocator failure test or target import.
The executed [partition review](eleventh-review-partitions.md) supplies the
exact raw tuples and original physical expectations independently.

## Confirmed boundaries

* `wire_parts.Checkpoint` captures the Canvas segment, point, route and node
  lengths plus the Schematic pin and coordinate lengths. Its restore order
  truncates generated nodes before `Canvas.restore`, and rebinds `s.xy` after
  possible allocation movement. It cannot restore existing row edits, poses,
  class changes, handled flags or caller verdicts. An outer checkpoint around
  both sibling draws is valid only while those existing rows remain unchanged
  and both `drawn`/`labeled` writes wait for complete pair acceptance.
* The current two consumers use independent per-net commits. N0's proposed
  sibling transaction is a new caller obligation; it must not silently alter
  CT or linked-load failure/retention behavior. The drawer needs no new part
  count or callback for the literal local-two/remote-one contract.
* `wires.wire` creates `pins_of` before generated rail/name nodes. Thus a
  current-Canvas same-net inventory is needed in addition to complete raw
  incidence and the original-pin mapping. Adding only a new call inside the
  seeded block is insufficient; a nonempty N0 slice must affect that block's
  predicate. Original `first` authority must remain effective.
* `thin.name` changes styles after all fallible temporary work. It may advance
  a cut net or its eligible mate to label. An N0 D/D tree cannot be reported
  retained after that transition. Withdrawal plus a fresh ordinary rebuild
  preserves the existing crossing policy; freezing the style at cut would be
  a different policy. Resetting styles must retain shelf-derived initial cuts.
* `Placed.Builder.run` can append terminal connectors and names after routing.
  Therefore final Schematic acceptance is insufficient for Placed or plugin
  output acceptance. Electrical identity alone cannot establish the required
  positive and negative physical relations.

## Capacity and progress reasoning

For disjoint certified four-device parents, at most `floor(N/4)` qualifying
tuples exist. This bounds their result/withdrawal storage, not O0's ownership
search. Every full retry must add a previously active tuple to the permanent
withdrawn set, yielding at most `C+1` attempts including the final ordinary
fallback. The existing finite thinning loop remains inside each attempt.
An allocation error remains an operating error, not a semantic decline or a
successful fallback.

The proposed output bound matches the current source. A trunk with `p` pins
has at most `2p−1` Line rows: three rows per paired rung, at most one per
unpaired pin, and at most one fewer trunk links than trunk endpoints. Each
Line has at most six points. For N0's two-pin local component, at most three
Line rows plus a local and remote name stub give five routes, seventeen
segments and twenty-four Canvas points including the two generated marks.
Exactly two names add two node/pin/xy rows. Double those per-net bounds for
one sibling tuple. These are source-derived append bounds for this internal
`.name` path, not measured runtime or a production fuel allowance. New fixed
storage must prove checked arithmetic and the same source assumptions.

## One caller disposition to make explicit

The plan places the final Placed and target checks after the routing retries.
At review time it required those checks but did not specify their caller
failure branch as concretely as the inner pair rollback. A failed final gate
must not publish an N0 success or deliver the invalid partition as accepted.
For the unchanged-pose experiment, either withdraw the affected tuple and
rebuild from the same frames under the monotone retry bound, or return a
distinct validation failure to a caller that retains a valid incumbent. A
mandatory moved-owner failure rejects the complete provisional arrangement.
The diagnostic acceptance caller must likewise withhold certification or
promotion of an invalid translated candidate. If later adopted as a production
runtime validator, its caller must reject the known broken proposal before
target writes; an engine append checkpoint cannot undo a published host edit.

The final plan revision resolves this finding. The existing staged diagnostic
caller owns cold immutable endpoint identities and one monotone withdrawal set
through layout, `Placed.init` and test translation. A re-entry to `drawValid`
cannot reset that budget. A failed gate withdraws an attributable active tuple
and rebuilds, or returns a distinct validation failure; a failure with no
remaining attributable tuple cannot trigger a no-progress retry. The original
plan hash and read record remain archived, and the current provenance records
the reviewed final revision.

Final graph checks are acceptance oracles in this initial experiment. This
review does not demand a runtime SVG reader, host netlister or new public API.
Later host comparison is a separate external acceptance gate. No such
integration or failure/recovery path has been executed by this review.

The retained provenance JSON records the reviewed plan and source bytes.
It is a source-read record, not an additional executable proof.
