# telescopic-cascode fully differential amplifier: NMOS pair M1 M2, cascodes M3-M6, PMOS sources M7 M8, tail M9; mirror references Mb1 (tail) and Mb2 (PMOS sources)
net vb1 vb2 vb3 : bias
stage amp : m1 m2 m3 m4 m5 m6 m7 m8 m9
match m1 m2
match mb1 m9
match mb2 m7 m8
# vin2 and vout1 are the other half of the pair: the same input and output, mirrored. They are left off the flow
# because the read-back takes every listed input to enter from the left and every output to leave to the right.
flow vin1 -> amp -> vout2
