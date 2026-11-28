* folded cascode, drawn as two modules
*@ net vb1 vb2 vb3 vb4 : bias
*@ stage in   : m1 m2 m0
*@ stage casc : m3 m4 m5 m6 m7 m8 m9 m10
*@ match m1 m2
*@ match m3 m4
*@ flow vinp vinn -> in -> casc -> vout
.model nch nmos
.model pch pmos
.subckt folded vdd vss vinp vinn vout vb1 vb2 vb3 vb4
M0 tail vb1 vdd vdd pch
M1 f1 vinp tail vdd pch
M2 f2 vinn tail vdd pch
M3 f1 vb2 vss vss nch
M4 f2 vb2 vss vss nch
M5 m1 vb3 f1 vss nch
M6 vout vb3 f2 vss nch
M7 m1 vb4 p1 vdd pch
M8 vout vb4 p2 vdd pch
M9 p1 m1 vdd vdd pch
M10 p2 m1 vdd vdd pch
.ends
