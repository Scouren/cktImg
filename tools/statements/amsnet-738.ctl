# Fully differential two-stage op-amp drawn about one axis: telescopic-cascode first stage M1-M8 on tail ISS, PMOS common-source second stage M10/M9 on loads I1/I2 outside it, cascode compensation CC1/CC2
net vb1 vb2 vb3 : bias
stage amp : m1 m2 m3 m4 m5 m6 m7 m8 m9 m10 iss i1 i2 cc1 cc2 cl1 cl2
match m1 m2
flow vin1 vin2 -> m1 m2 -> vout1 vout2
flow m2 -> m9
