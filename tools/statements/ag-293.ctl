# Folded-cascode core: PMOS input pair under tail ISS, then NMOS cascodes M3/M4 between ideal current sources
net vb1 : bias
stage in   : m1 m2 iss
stage casc : m3 m4 i1 i2 iss1 iss2
match m1 m2
match m3 m4
flow vin1 vin2 -> in -> casc -> vout1 vout2
