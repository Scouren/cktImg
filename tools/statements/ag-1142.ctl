# push-push differential Colpitts VCO: NPN pair Q1 Q2 with a common base line, varactor tuning D1-D4, fundamental outputs at the collectors and a 2f tap at the common emitter node
net vbb vtunep vtunen : bias
match q1 q2
# the varactors are not found as images of the pair, so say them
match d1 d2
match d3 d4
flow r2 -> c5 -> out_2f
