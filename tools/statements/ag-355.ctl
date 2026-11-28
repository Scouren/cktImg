# Fully differential folded-cascode amplifier: NMOS input pair M1/M2 (tail ISS) folded into PMOS sources M7/M8 and cascodes M5/M6 over NMOS cascodes M3/M4 and sources M9/M10
net x y vb2 vb3 vb4 : bias
stage in : m1 m2 iss
stage casc : m3 m4 m5 m6 m7 m8 m9 m10
match m1 m2
match m5 m6
flow vin1 vin2 -> in -> casc -> vout1 vout2
