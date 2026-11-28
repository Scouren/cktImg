* regenerative latch: an NMOS and a PMOS cross pair on the same two nodes, each with its own
* clocked tail, and two pass switches; no statement at all
.model nch nmos
.model pch pmos
.subckt latch vdd vss en enb a b q qb
MN1 q qb tn vss nch
MN2 qb q tn vss nch
MP1 q qb tp vdd pch
MP2 qb q tp vdd pch
MTN tn en vss vss nch
MTP tp enb vdd vdd pch
MS1 a enb qb vss nch
MS2 b enb q vss nch
.ends
