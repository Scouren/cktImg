# Bandgap reference: op-amp X1 holds X = Y on the Q1/Q2 core and drives Vout; M12-M21 generate X1's cascode bias VC
net vb1 vb2 vb3 : bias
net vout : signal
stage core : q1 q2 r1 r2 r3
stage bias : m12 m13 m14 m15 m16 m17 m18 m19 m20 m21
match q1 q2
match r1 r2
match m15 m18 m20 m12
flow core -> x1 -> vout
