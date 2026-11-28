# Buck-boost power stage around coil LRX: storage VSTO -> MP3 -> LRX -> active diode MP2 (gate net1 driven by comparator X1) -> VOUT, with low-side switches MN1/MN2
net vcont1 vcont2 vcont3 net1 : clock
match mn1 mn2
flow vsto -> mp3 -> lrx -> mp2 -> vout
flow lrx -> x1
