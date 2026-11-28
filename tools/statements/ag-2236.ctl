# LDO: current-mirror OTA drives NMOS pass device MNP, R1/R2 divider returns FB, self-biased current reference, CL-R4 series branch on the output
net vin : supply
net vb1 vb2 : bias
net fb : signal
stage ref : m10 m11 m12 m13 m14 m15 r3
stage ota : m1 m2 m3 m4 m5 m6 m7 m8 m9
stage div : r1 r2
stage rc  : cl r4
match m1 m2
match m10 m11 m12
flow ref -> ota
flow vref -> ota -> mnp -> div -> rc -> vout
