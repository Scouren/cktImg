* inverting amplifier from one op-amp block
*@ flow vin -> r1 -> x1 -> vout
.subckt opamp inp inn out
.ends
.subckt inv vin vout gnd
R1 vin sum 10k
Rf sum vout 100k
X1 gnd sum vout opamp
.ends
