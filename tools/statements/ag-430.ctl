# differential delay cell with variable negative resistance: input pair M1 M2 and cross-coupled pair M3 M4 on shared loads R1 R2, tail current IT steered between the two pairs by M5 M6
net vcont1 vcont2 : bias
stage in    : m1 m2 r1 r2
stage latch : m3 m4
stage steer : m5 m6 it
match m1 m2
match m3 m4
match m5 m6
# vin2 is the mirrored input, on M2's outward-facing gate: left off the flow because the read-back takes a listed input to enter from the left
flow vin1 -> in -> latch -> vout1 vout2
