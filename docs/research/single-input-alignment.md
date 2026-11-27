# Single-input alignment: a rejected generalization

The 47 previously studied single-input source glyphs all place their input
off the output/apex axis. AEA in AG2423 centers its sole negative input.
That one observation does **not** justify centering every single-input
amplifier. This study changes no engine behavior.

The [script](figures/single_input_alignment.py) scans the complete 2,202 AG
and 734 AMS paired corpora, checks both cohorts by exact instance name,
and retains 48 actual lead certificates in the
[inventory](figures/single_input_alignment_cases.json). All selected cases
are AG. It independently reads each instance's transformed SVG outline,
external leads and polarity strokes; cached input coordinates never choose
a lead.

```sh
python3 -B docs/research/figures/single_input_alignment.py external/examples /tmp/single-input-alignment.json --check
```

| Source cohort | Instances | Input endpoint on output axis | Input attachment on apex axis |
|---|---:|---:|---:|
| Previously supported single-input contracts | 47 | 0 | 0 |
| Added complete AEA contract, AG2423:x1 | 1 | 1 | 1 |

The old cohort contains 35 negative, one positive and 11 unsigned inputs.
All 47 have a negative transverse offset in the triangle's own frame:
5 at −10, 27 at −20, 13 at −30, one at −40 and one at −50 source units.
The forward axis points from base midpoint to apex; its perpendicular
defines the transverse axis. Rotation therefore cannot turn an input's
left/right offset in an upward triangle into apparent row alignment.
Both the actual endpoint and the attachment to the body are measured.

A signed input is identified by its matching actual polarity stroke and
unique base lead. An unsigned input is the sole base lead when that is
unambiguous. Where bias leads also enter the base, the named input's
declared net must reach its actual lead through source conductor ink from
a named marker or independently verified outside device pin. These
certificates retain the marker/pin, declared net and connecting wire tree.
Labels alone cannot connect separate pieces of ink.

AG1363 illustrates an upward triangle whose negative input is left of
the apex, beside two bias leads on the base. AG1368 has an unsigned input
left of three bias leads. AG2418 has a right-facing negative input above
the apex row. All three source sheets were visually checked. AG2423's
centered source input remains a named difference from the native signed
input default; it is not an instance-specific production exception.
The native unsigned default also centers the old cohort's 11 unsigned
inputs, so their source offsets remain a separate limitation.

Twelve named method checks cover centered and offset leads of either
polarity, unsigned input, rotation/reflection, missing or incorrect marks,
missing output, ambiguous leads and the required connectivity certificate
for an unsigned input sharing its base with bias leads. Every source triple
and audit dependency is hashed. The study proves these finite source
relations, not a universal glyph rule, native layout parity, or full
textbook equivalence.
