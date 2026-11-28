# FVF-style LDO: error amp X1 (biased by X2) sets replica branch M1-M2-M3, follower MCTRL on sink MBIAS drives pass device MRES, MCHG-MSEN-MGEN-MINJ injects current into VERR
net vin : supply
net pb nb vb1 : bias
stage core : m1 m2 m3 mres mctrl mbias
stage inj : mchg msen mgen minj
match m2 mctrl
match mgen minj
flow vref -> x1 -> core -> vout
flow x1 -> inj
