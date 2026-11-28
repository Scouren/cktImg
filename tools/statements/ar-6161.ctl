# loop-gain test bench (small-signal) of a two-stage feedback amplifier: common-gate M1 then common-source M2, divider R2 R1 from M2's drain back to M1's source; the loop is cut at M2's gate, where test source Vt drives it, and the returned voltage Vr is read at M1's drain
# stage order of the amplifier: M1's drain drove M2's gate before the cut
flow m1 -> m2
flow vt -> m2
