# Switched-capacitor integrator: clocked switches M1 M2 with sampling cap C1, mirror OTA M3-M11 with integrating cap C2, self-biased reference M12-M17
net phi1 phi2 : clock
net vb1 vb2 : bias
stage samp : m1 c1 m2
stage ota : m3 m4 m5 m6 m7 m8 m9 m10 m11 c2
stage ref : m12 m13 m14 m15 m16 m17
match m3 m4
match m10 m6
match m7 m8
match m11 m9
match m12 m14 m16
flow vci -> m1 -> m2 -> ota -> vco
