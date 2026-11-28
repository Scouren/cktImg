# fully differential two-stage amplifier with two PMOS input pairs (differential-difference input): two mirrored half cells, each a pair with its tail, a first-stage sink and a Miller-compensated common-source output
stage a : i1 m1 m2 i2 m9 i3 cc rz
stage b : i1r m2x m1x i2r m6 i3r ccr rzr
match a b
match m1 m2
match m1x m2x
# cell b's output; vo2 is its mirror image on cell a and leaves on the other side, so it is not listed
flow b -> vo1
