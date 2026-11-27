# Human schematic rules: evidence and experiments

The [latest pattern comparison](more-human-layout-patterns.md) covers mirrors, bias and supply wiring, passive filters and bridges. The [rule coverage ledger](rule-coverage.md) accounts for all 63 claims tagged `unmeasured` and all 18 tagged `book` in the frozen inventory, including the questions that remain open. The [preceding study](human-layout-patterns.md) covers AG1080, divider alignment, amplifier feedback and regulator outputs.

The [second complete image pass and continued planning](image-rules/round-2/README.md)
records the preceding counterexamples, port-contract studies and adversarial review.
The [next implementation and finite milestone](image-rules/round-2/next-implementation.md)
turns those findings into a bounded sequence: collect complete local parents,
prove six human wire partitions, then satisfy the separate arrangement and
target gates. The [27 conditional rules](image-rules/round-2/proposed-human-rules.md)
retain examples and counterexamples for the wider algorithm.

The [first image audit](image-rules/README.md) compares the
actual AnalogGenie source drawings with a frozen experimental engine, records
each reviewed image, and tests the assumptions behind the current Human Rules.
The [AG1080 study](image-rules/ag1080-global-symmetry.md) follows the user's
five-group comparator example through controlled placement experiments.
The [measurement audit](image-rules/measurement-limits.md) corrects the
gallery's unsupported counts for source labels with unresolved net bindings.
The [decision set](image-rules/decisions.md) summarizes the completed 2,202-pair
overview review and 225 enlarged comparisons, including which current
assumptions need narrower conditions and which contracts must remain intact.

A rule needs examples showing when it applies and counterexamples bounding it.
The studies below retain source identities, terminal bindings, measured geometry,
and replay scripts. Their stated checkpoint and status matter: some rules are
implemented, others are prototypes, and some experiments were rejected. The
presence of a study here does not mean its algorithm is released or that the
complete drawing matches the source.

| Rule family | Proof by example |
|---|---|
| Symmetry, groups, and feedback | [AG1080 local groups](image-rules/ag1080-global-symmetry.md), [capacitive cross-coupling](capacitive-cross-coupling.md), [sampling cells](sampling-cells.md) |
| Amplifier glyphs and port contracts | [Aliases](block-aliases.md), [remaining amplifiers](remaining-amplifiers.md), [reference amplifiers](reference-amplifiers.md), [rejected single-input generalization](single-input-alignment.md) |
| Digital and coil symbols | [Digital symbol census](digital-symbols.md), [center-tapped inductor contract](center-tap-symbols.md) |
| Flying-capacitor converters | [Complete loops](converter-loops.md), [input buses](converter-bus.md), [output branch order](converter-branches.md), [auxiliary switches](converter-auxiliary.md) |
| Amplifier inputs, loads, and bias | [Input resistors](input-resistors.md), [driven banks](driven-banks.md), [bias neighbours](bias-block-neighbors.md), [resistor loads](resistor-load-stages.md), [paired input RC](block-input-rc.md), [input chokes](block-input-chokes.md) |
| Oscillator tanks and coupling paths | [Parallel tanks](center-tap-tanks.md), [series tanks](ct-series-tanks.md), [coupling chains](center-tap-chains.md), [block output tanks](block-tanks.md) |
| Complete oscillator groups | [Four-sided stage](ct-four-sides.md), [feedback stage](ct-feedback-stage.md), [mirror controls](ct-mirror-controls.md), [common-base controls](ct-common-controls.md), [antiparallel clamps](antiparallel-clamps.md) |
| Local conductor geometry | [Common-source bars](common-source-bars.md), [trunk rungs](trunk-rungs.md), [blocked taps](trunk-taps.md), [same-row endpoints](thin-row.md) |
| Physical wire partitions | [Local crossing budgets](thin-parts.md), [measured continuity changes](thin-connectivity.md), [competing routes](thin-interactions.md), [reference-amplifier regressions](reference-routing.md) |

The [source method](analoggenie.md) explains the corpus. The
[scorecard](corpus-scorecard.md) measures particular relations; it does not
certify visual equivalence. Earlier [decision inventories](decisions.md) and
[steering research](steering.md) describe their own historical code snapshots.
