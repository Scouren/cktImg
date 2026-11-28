# Fully differential gain-boosted folded-cascode OTA: PMOS input pair, CMFB sinks M3/M4, common-source boosters on all four cascodes
net vbias3 vbias4 vbias5 vbias6 vcmfb : bias
# one stage, so both folded branches and their boosters mirror about the input pair's axis
stage ota : m1 m2 mb1 m3 m4 m5 m6 m7 m8 m9 m10 md1 md2 mb4 mb5 mu1 mu2 mb2 mb3
match m1 m2
flow vin+ vin- -> m1 m2
flow m5 m6 -> vout- vout+
