# Bandgap reference: op-amp X1 holds X = Y across the R1/Q1 and R2/R3/Q2 branches and drives their top node Vout
net vb1 vb2 vb3 : bias
net vout : signal
stage core : q1 q2 r1 r2 r3
match q1 q2
match r1 r2
flow core -> x1 -> vout
