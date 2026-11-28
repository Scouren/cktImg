# Single-balanced passive mixer (LO switches M1/M2) into PMOS differential pair M3/M4 with tail I1 and loads R1/R2; MG1-MG3 are gain switches across the pair's inputs A-B
net vlo vlo_bar d1 d2 d3 : clock
stage amp : m3 m4 i1 r1 r2
match m3 m4
match mg1 mg2 mg3
flow vin -> m1 m2 -> mg1 mg2 mg3 -> amp -> voutn voutp
