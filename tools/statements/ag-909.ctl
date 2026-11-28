# Two-stage Miller op-amp: PMOS input pair, NMOS mirror load, NMOS common-source output, RZ-C compensation, M8 bias diode
net ib1 : bias
stage in  : m1 m2 m3 m4 m5
stage out : m6 m7 rz c cl
stage ref : m8
match m1 m2
match m3 m4
match m8 m5 m7
flow vin1 vin2 -> in -> out -> vout1
