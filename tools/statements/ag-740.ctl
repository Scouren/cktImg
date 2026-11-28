# Latched comparator: triode input and reference pairs under a cross-coupled NMOS/PMOS latch, Vltch enable and reset switches
# vltch is a clock, but M11/M12 stay upright inside the latch stack, so it is only named at each pin like a bias line
net vltch vref+ vref- : bias
stage latch : m1 m2 m3 m4 m5 m6 m7 m8 m9 m10 m11 m12
match m8 m9
match m3 m6
flow vin+ vin- -> m3 m6
flow m8 m9 -> vout- vout+
