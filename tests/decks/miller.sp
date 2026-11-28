* two-stage Miller op-amp
*@ stage in  : m1 m2 m3 m4 m5
*@ stage out : m6 m7 cc rz
*@ stage ref : m8 iref
*@ match m1 m2
*@ match m3 m4
*@ match m8 m5 m7
*@ flow ref -> in
*@ flow vinn vinp -> in -> out -> vout
.model nch nmos
.model pch pmos
.subckt miller vdd vss vinp vinn vout
M1 n1 vinn tail vss nch
M2 n2 vinp tail vss nch
M3 n1 n1 vdd vdd pch
M4 n2 n1 vdd vdd pch
M5 tail vb vss vss nch
M6 vout n2 vdd vdd pch
M7 vout vb vss vss nch
M8 vb vb vss vss nch
Iref vdd vb 10u
Cc n2 nz 1p
Rz nz vout 1k
.ends
