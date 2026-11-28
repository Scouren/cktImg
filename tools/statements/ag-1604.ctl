# Bandgap reference: op-amp X1 holds X = Y across the R1/Q1 and R2/R3/Q2 branches and drives Vout
net vb1 vb2 vb3 : bias
match r1 r2
match q1 q2
flow x1 -> vout
