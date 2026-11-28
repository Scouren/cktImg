# Folded-cascode OTA: NMOS pair M1 M2 on tail M5, PMOS sources M3 M4, PMOS cascodes M6 M7, NMOS cascode mirror M8-M11, bias branch I1 M12-M15, load cap C1
stage ref : m14 i1 m12 m15 m13
stage in : m1 m2 m5
stage casc : m3 m4 m6 m7 m8 m9 m10 m11
match m1 m2
match m3 m4
match m6 m7
match m8 m9
match m10 m11
flow ref -> in -> casc -> vout
flow v1 v2 -> in
