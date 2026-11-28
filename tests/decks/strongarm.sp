* StrongARM latch
*@ net clk : clock
*@ match m1 m2
*@ flow inp inn -> m1 m2 -> outn outp
.model nch nmos
.model pch pmos
.subckt sa vdd vss clk inp inn outp outn
M0 tail clk vss vss nch
M1 x inp tail vss nch
M2 y inn tail vss nch
M3 outn outp x vss nch
M4 outp outn y vss nch
M5 outn outp vdd vdd pch
M6 outp outn vdd vdd pch
M7 outn clk vdd vdd pch
M8 outp clk vdd vdd pch
.ends
