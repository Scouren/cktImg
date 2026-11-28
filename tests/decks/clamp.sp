* two collectors clamped by a pair of back-to-back diode-connected devices (a loop of series
* parts: neither stands above the other), each input device over an emitter inductor
.model qn npn
.subckt clamp vcc vee a b
Q1 x a e1 qn
Q2 y b e2 qn
Q3 y y x qn
Q4 x x y qn
L1 e1 vee 1n
L2 e2 vee 1n
R1 vcc x 1k
R2 vcc y 1k
.ends
