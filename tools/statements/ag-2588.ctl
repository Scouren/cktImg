# flipped-voltage-follower LDO: block X1 (error amplifier, Vref against fb) sets Vset on the gate of M2; M2 senses Vout, folded through cascode M5 and source M4 onto the gate of pass device M1 (C2 compensates); divider R2 R1
net biasp biascas biasn vb1 vb2 vb3 : bias
stage fvf : m1 m2 m3 m4 m5 c2
stage div : r1 r2
flow vref -> x1 -> fvf -> div -> vout
# inside the follower loop the folded branch drives the pass gate
flow m4 m5 -> m1
