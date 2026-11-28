# AC-coupled NMOS source follower M1 (gate biased to VDD through Rin) on a mirror current sink MB -> M2 fed by IB
stage sf  : m1 m2 rin
stage ref : ib mb
match mb m2
flow vin -> cin -> m1 -> vout
