# Gilbert cell: control pair M5/M6 steers the tail between two input pairs whose drains cross-connect to loads RD1/RD2
stage pa  : m1 m2
stage pb  : m3 m4
stage ctl : m5 m6 iss
match m1 m2
match m3 m4
match m5 m6
flow vin+ vin- -> pa pb -> vout+ vout-
