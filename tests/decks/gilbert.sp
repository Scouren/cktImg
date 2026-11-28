* Gilbert cell
*@ net vb : bias
*@ stage quad : q1 q2 q3 q4 rl1 rl2
*@ stage rf : q5 q6 itail
*@ match q5 q6
*@ match q1 q2
*@ match q3 q4
*@ match rl1 rl2
.model qn npn
.subckt gilbert vcc vee lop lon rfp rfn ifp ifn
RL1 vcc ifp 1k
RL2 vcc ifn 1k
Q1 ifp lop e1 qn
Q2 ifn lon e1 qn
Q3 ifp lon e2 qn
Q4 ifn lop e2 qn
Q5 e1 rfp tail qn
Q6 e2 rfn tail qn
Itail tail vee 1m
.ends
*@ net vee : ground
