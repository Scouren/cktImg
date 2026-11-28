# Two source-coupled NMOS pairs sharing resistor loads RD1 RD2: cross-coupled M5 M6 on tail device M1 (Vinp) and diode-connected M3 M4 on tail device M2 (Vinn)
stage cross : m5 m6 m1
stage diode : m3 m4 m2
match m5 m6
match m3 m4
match m1 m2
match rd1 rd2
flow vinp vinn -> cross diode -> voutp voutn
