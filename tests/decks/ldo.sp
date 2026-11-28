* LDO: error amplifier block, PMOS pass device, divider, load
*@ net vb : bias
*@ stage div : r1 r2
*@ flow vref -> x1 -> mp -> div -> cl -> vout
.model pch pmos
.subckt opamp vdd vss inp inn out vb
.ends
.subckt ldo vin vss vref vout vb
X1 vin vss fb vref gate vb opamp
MP vout gate vin vin pch
R1 vout fb 100k
R2 fb vss 100k
CL vout vss 1u
.ends
*@ net vin : supply
