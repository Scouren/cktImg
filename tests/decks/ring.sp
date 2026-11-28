* three-inverter ring oscillator
*@ stage s1 : mp1 mn1
*@ stage s2 : mp2 mn2
*@ stage s3 : mp3 mn3
*@ match s1 s2 s3
*@ flow s1 -> s2 -> s3 -> out
*@ net out : signal
.model nch nmos
.model pch pmos
.subckt ring vdd vss out
MP1 a out vdd vdd pch
MN1 a out vss vss nch
MP2 b a vdd vdd pch
MN2 b a vss vss nch
MP3 out b vdd vdd pch
MN3 out b vss vss nch
.ends
