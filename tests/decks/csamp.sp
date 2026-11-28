* common-source stage, AC-coupled, with source degeneration; no statement at all
.model nch nmos
.subckt cs vdd vss vin vout
Vs vin vss ac 1
Cin vin g 1u
Rb1 vdd g 1meg
Rb2 g vss 1meg
M1 d g s vss nch
RD vdd d 10k
RS s vss 1k
Cout d vout 1u
RL vout vss 100k
.ends
