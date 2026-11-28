* fully differential telescopic cascode
*@ net vb1 vb2 vb3 : bias
*@ match m1 m2
*@ flow vinp vinn -> m1 m2 -> voutn voutp
.model nch nmos
.model pch pmos
.subckt tele vdd vss vinp vinn voutp voutn vb1 vb2 vb3
M1 x1 vinp tail vss nch
M2 x2 vinn tail vss nch
M3 voutn vb1 x1 vss nch
M4 voutp vb1 x2 vss nch
M5 voutn vb2 y1 vdd pch
M6 voutp vb2 y2 vdd pch
M7 y1 vb3 vdd vdd pch
M8 y2 vb3 vdd vdd pch
Iss tail vss 100u
.ends
