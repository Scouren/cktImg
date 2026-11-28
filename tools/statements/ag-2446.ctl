# Flipped-voltage-follower LDO: reference amp sets net4, replica branch M1-M3 makes the control-gate bias, MRES/MCTRL/MBIAS output loop, sense-and-inject branch, bias generator
net vin : supply
net nb pb vb1 vb2 vbn : bias
stage bgen : m13 m14 m15 m16 m17 m18 m19 m20
stage amp  : m8 m11 m12 m4 m7 m5 m6 m9 m10
stage rep  : m1 m2 m3
stage inj  : mchg msen mgen minj
stage out  : mres mctrl mbias
match m8 m11
match m9 m10
# the replica branch is a copy of the output branch, device for device
match rep out
flow bgen -> amp
flow vref -> amp -> rep -> out -> vout
flow amp -> inj -> out
