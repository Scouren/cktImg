# Two cascaded resistor-loaded NMOS differential pairs: M3/M4 (tail M5) drive X/Y into M1/M2 (tail M6 at P)
net vb : bias
net x y : signal
stage first : m3 m4 m5 rp1 rp2
stage second : m1 m2 m6 rp3 rp4
match m3 m4
match m1 m2
flow vin1 vin2 -> first -> second
