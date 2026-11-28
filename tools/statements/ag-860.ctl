# Widlar bandgap reference: Q1-Q2 delta-Vbe pair with R1 R2 R3, gain transistor Q3 on current source I, emitter follower Q4 returning VOUT to the resistors
net vout : signal
stage cell : q1 q2 r1 r2 r3
match q1 q2
match r1 r2
flow cell -> q3 -> q4 -> vout
