# Singly balanced BJT mixer: RF enters at Q1's base and runs on through a two-section LC ladder to Q2's base, LO enters at the ladder's middle node; Q1 and Q2 are AC-coupled to the differential IF amplifier Q3 Q4
stage front : q1 q2 rl1 rl2 l1 c1 l2 c2 l3 l4 c3 c4 c5 c6
stage ifamp : q3 q4 rc1 rc2 re
match q3 q4
flow rf lo -> front -> cblock2 cblock1 -> ifamp -> ifn ifp
flow l1 c1 -> l3 -> l4 -> q2
