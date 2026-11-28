# NMOS-pass LDO: error amp X1 compares the R1/R2 tap FB with Vref and drives pass device MNP from VIN to VOUT; CL-R3 branch on the output
net vin : supply
net fb : signal
stage div : r1 r2
stage load : cl r3
flow vref -> x1 -> mnp -> div -> load -> vout
