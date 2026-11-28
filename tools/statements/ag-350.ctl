# Fully differential two-stage op-amp: telescopic cascode first stage, PMOS common-source second stages M10/M9, cascode compensation
net vb1 vb2 vb3 : bias
# one stage, so the second stages and their loads mirror about the input pair's axis too
stage amp : m1 m2 m3 m4 m5 m6 m7 m8 iss m10 m9 i1 i2 cc1 cc2 cl1 cl2
match m1 m2
flow vin1 vin2 -> m1 m2
flow m10 m9 -> vout1 vout2
