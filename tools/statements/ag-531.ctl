# Cross-coupled LC VCO tuned by AC-coupled MOS varactors Mv1/Mv2 that are biased through R1/R2
net vb : bias
# one stage, so the coupling caps, varactors and bias resistors mirror about the pair's axis too
stage vco : m1 m2 l1 l2 iss cs1 cs2 mv1 mv2 r1 r2
match m1 m2
