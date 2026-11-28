# Three-stage differential ring oscillator: resistor-loaded NMOS pairs M1-M2, M3-M4, M5-M6, each on its own tail current source
net net4 net5 : signal
stage s1 : m1 m2 r1 r2 iss1
stage s2 : m3 m4 r3 r4 iss2
stage s3 : m5 m6 r5 r6 iss3
match m1 m2
match m3 m4
match m5 m6
match s1 s2 s3
flow s1 -> s2 -> s3
