# Clapp (series-tuned Colpitts) BJT VCO between VSS (top rail) and VEE: varactor Q2 tuned by VB1, series tank C3-L1, oscillator Q1, output through LTRL1
net vss : supply
stage tune : q2 r5 c4
stage osc : q1 r1 r2 r3 r4 c1 c2
flow vb1 -> r6 -> tune -> c3 -> l1 -> osc -> ltrl1 -> vout1
