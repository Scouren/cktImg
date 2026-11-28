# quadrature receiver front end: source Vin with RS, inverter LNA M1 M2 (self-biased by R1), follower M3 with RM C2 matching feedback to the input, passive mixer switches M4 M5 (I) and M8 M9 (Q) on node VRF, PMOS baseband pairs M6 M7 and M10 M11 with resistor loads
net vb : bias
net vlo_i vlo_i_bar vlo_q vlo_q_bar : clock
stage lna : m1 m2 r1 i1 c1
stage buf : m3 i2
stage bbi : m6 m7 r3 r4 i3
stage bbq : m10 m11 r5 r6 i4
match m6 m7
match m10 m11
flow vin -> rs -> c3 -> lna -> buf -> c4 -> m4 m5 -> bbi -> vbbin vbbip
flow c4 -> m8 m9 -> bbq -> vbbqn vbbqp
