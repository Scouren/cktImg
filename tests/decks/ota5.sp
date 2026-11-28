* five-transistor OTA with its bias mirror
*@ net vb : signal
*@ stage in : m1 m2 m3 m4 m5
*@ stage ref : m8 iref
*@ match m1 m2
*@ match m3 m4
*@ match m8 m5
*@ flow ref -> in
*@ flow vinp vinn -> m1 m2 -> vout
.model nch nmos
.model pch pmos
.subckt ota vdd vss vinp vinn vout
M1 n1 vinp tail vss nch
M2 vout vinn tail vss nch
M3 n1 n1 vdd vdd pch
M4 vout n1 vdd vdd pch
M5 tail vb vss vss nch
M8 vb vb vss vss nch
Iref vdd vb 10u
.ends
