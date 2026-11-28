* switched-capacitor sampler into an integrator
*@ net phi1 phi2 : clock
*@ flow vin -> m1 -> cs -> m4 -> x1 -> vout
.model nch nmos
.subckt opamp inp inn out
.ends
.subckt sc vin vout phi1 phi2 gnd
M1 vin phi1 a gnd nch
M2 a phi2 gnd gnd nch
CS a b 1p
M3 b phi1 gnd gnd nch
M4 b phi2 sum gnd nch
CI sum vout 1p
X1 gnd sum vout opamp
.ends
