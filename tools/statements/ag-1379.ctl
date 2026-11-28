# switched-inductor power stage (storage VSTO -> MP3/MN1 -> LRX -> MN2/MP2 -> VOUT) whose output switch MP2 is an active diode driven by a folded-cascode amplifier (M5-M15); self-biased reference M16-M25 makes VBP VB3 VB4 VB5
net vb1 vb2 vb3 vb4 vb5 vbp : bias
net vcont1 vcont2 vcont3 : clock
stage pwr : mp3 mn1 lrx mn2 mp2 csto cl
stage amp : m5 m6 m7 m8 m9 m10 m11 m12 m13 m14 m15
stage ref : m16 m17 m18 m19 m20 m21 m22 m23 m24 m25
match m13 m14
match m16 m19 m21 m24
flow vsto -> mp3 -> lrx -> mp2 -> vout
# vg, the amplifier output, is MP2's gate drive; not called a clock because it also gates the amplifier's own input M14
flow amp -> mp2
