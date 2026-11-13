.model rt_sample_n nmos level=1 vto=0.7 kp=20u
* Round-trip regression: the top exports model declarations but no devices.
* Compare the populated dut cell with the exported model context intact.
.subckt dut vin ck vout vss
M1 vin ck vout vss rt_sample_n w=2u l=1u
CH vout vss 1p
.ends dut
