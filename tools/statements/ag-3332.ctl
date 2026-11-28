# Parasitic-insensitive switched-capacitor integrator: switches M1-M4 around series cap C1, OTA M5-M10 M16 with integrating cap C2, resistor-referenced bias chain R1 M11-M15
net phi1 phi2 : clock
net vb1 : bias
stage ota : m5 m6 m7 m8 m9 m10 m16 c2
stage ref : r1 m11 m12 m13 m14 m15
match m5 m6
match m7 m8 m9
match m11 m12
match m13 m14
flow vci -> m1 -> c1 -> m4 -> ota -> vco
flow r1 m11 -> m12 m13 -> m14 m15
