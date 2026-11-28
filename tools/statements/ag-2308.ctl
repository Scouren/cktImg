# NMOS-pass LDO: PMOS-input folded-cascode error amplifier M2-M12 (VREF against FB), class-AB source-follower buffer M13-M21 driving the pass gate, pass device MNP from VIN, divider R2 R1, load CL R3 RL; block X1 makes VBN1 VBN2
net vin : supply
net vb1 vb2 vb4 vbn1 vbn2 : bias
stage ea   : m2 m3 m4 m5 m6 m7 m8 m9 m10 m11 m12
stage buf  : m13 m14 m15 m16 m17 m18 m19 m20 m21
stage div  : r1 r2
stage load : cl r3 rl
match m3 m4
# the two cascode branches are halves of the same amplifier (the shared names VX and net0 hide it from the pair)
match m7 m8
match m9 m10
match m11 m12
flow vref -> ea -> buf -> mnp -> div -> load -> vout
