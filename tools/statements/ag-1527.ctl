# bandgap reference: core R1 Q1 (node X) and R2 R3 Q2 (node Y) hung on Vout, symmetric OTA M1-M9 that senses X and Y and drives Vout to hold X = Y, self-biased current reference M10-M17 R4 making VB1 VB2 VB3
net vb1 vb2 vb3 : bias
stage core : r1 q1 r2 r3 q2
stage amp  : m1 m2 m3 m4 m5 m6 m7 m8 m9
stage ref  : m10 m11 m12 m13 m14 m15 m16 m17 r4
match m5 m6
match m8 m9
match q1 q2
match m14 m15 m16
# the amplifier is written after the nodes it senses; its output Vout returns to the top of the core
flow core -> amp -> vout
