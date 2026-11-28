* cross-coupled NMOS LC oscillator
*@ net vb : bias
*@ match m1 m2
.model nch nmos
.subckt vco vdd vss outp outn vb
M1 outp outn tail vss nch
M2 outn outp tail vss nch
L1 vdd outp 1n
L2 vdd outn 1n
C1 outp outn 1p
M3 tail vb vss vss nch
.ends
