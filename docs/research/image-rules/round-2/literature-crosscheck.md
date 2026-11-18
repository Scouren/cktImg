# External methods checked against the image evidence

This is a bounded literature check made during the continued planning round
on 2026-11-17. The primary publications below inform experiments; none proves
the cktImg implementation or replaces the actual AnalogGenie image review.
No external generator was installed, benchmarked or incorporated. Published
performance numbers are not comparable to this corpus without a common
dataset, output contract and independent checker.

| Primary source and access | Relevant method | Consequence for this plan |
|---|---|---|
| Hsu and Lin, *Automatic Analog Schematic Diagram Generation based on Building Block Classification and Reinforcement Learning*, MLCAD 2022; [author institution's publication record](https://scholar.nycu.edu.tw/en/publications/automatic-analog-schematic-diagram-generation-based-on-building-b/). Abstract and bibliographic record read; full method not obtained. | Building-block classification precedes learned generation. Reported evaluation distinguishes block compliance, bends and crossings. | Treat recognized organization and wire cost as different results. This record provides no basis for importing an unseen classifier, reward definition or claimed universal rule. |
| Liu and Chitnis, *EEschematic*, [arXiv v1, 2025-10-19](https://arxiv.org/html/2510.17002v1), sections II–IV read. | Six basic substructures guide placement. Rendered-image feedback iterates on placement and wiring. Evaluation uses three circuit types and distinguishes correctness from subjective appearance; the discussion retains connectivity errors and scaling limitations. | Actual image inspection is useful for generating hypotheses. Repeated visual refinement alone cannot close our electrical, caller or full-corpus gates. A small example library is a candidate mechanism, not evidence that six patterns cover 2,202 drawings. |
| Shi et al., *AMSchem*, [arXiv v1, 2026-11-09](https://arxiv.org/html/2611.12333v1), sections III and the benchmark description read. Recent preprint; no independent reproduction here. | A coordinate-free drawing plan precedes geometric output. Typed matching binds device-terminal roles to drawing references. Local repairs are revalidated. Algorithm 1 discards strict-subset matches and caps matches per reference. | Separating facts, intent and actual geometry fits the proposed boundaries. Strict-subset removal and bounded search need additional safeguards for our nested relations and ambiguous owners; copying those policies would not be justified by this paper. |

The following are **our deductions from the repository's examples**, not
findings attributed to these papers:

1. **Retain subordinate relations when selecting a parent.** AG517's inner
   and outer pair relations remain necessary inside its switching group.
   Removing every smaller match would remove useful constraints unless the
   parent explicitly carries their complete relation witnesses. The
   [quad study](quads.md) also has several supported arrangements for the
   same abstract group. Recognition and arrangement therefore need different
   records, even if an implementation uses one bounded owner to consume both.
2. **A match cap must not manufacture uniqueness.** The literal two-source,
   three-drain example has two qualifying quad embeddings sharing devices.
   Keeping only the first would conceal competition. A bounded production
   collector needs an explicit overflow/incomplete outcome; it cannot issue
   a unique-owner certificate after truncation. This follows from
   [the independent quad review](groups_review_quads.json), not a preference
   for any particular graph-matching implementation.
3. **All electrical incidences constrain admission.** A match can preserve
   internal edges yet miss an extra consumer on its interface. Our optional
   BJT-substrate, MOS-body, outer-formal and feedback-capacitor controls require
   the complete external incidence witness. Monomorphic subgraph existence
   alone does not establish a private boundary. See
   [the ownership attacks](cross-review-bodies-to-groups.md) and
   [executed caller fixtures](fourth-ports.md).
4. **A valid plan is not final geometry.** Four frozen quad cases retain an
   honored axis report while I2 ends off the common axis. Final contacts,
   caller placement and relations require their own checks after every
   geometry-changing stage. See [sixth-groups.md](sixth-groups.md). A validator
   that checks only stored intent can accept the same error even if planning
   and rendering are separate modules.
5. **The relevant alternative is not always another route.** AG1080 needs
   local groups and deliberate physical pieces of shared electrical nets.
   Its lower-crossing ablation still loses human organization. AG928 must
   retain a useful single core. Routing changes need both positive continuity
   and negative separation relations, plus target-valid naming; minimizing
   a scalar wire cost cannot choose these by itself. See
   [the actual-ink partition study](../grouping-and-distribution.md).

The actionable next step remains the bounded
[implementation packages](implementation-packages.md): use concrete
collectors and independent witnesses first. A general matcher, learned
scorer or agent in the runtime path would need a second demonstrated use,
measured cost, deterministic fallback and the same final-artifact gates.
The literature check does not supply that evidence.
