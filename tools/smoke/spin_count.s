# SMOKE TEST ONLY -- not homework code.
# Counts a register down from 1,000,000 (about 2 million retired
# instructions) and exits with status 0. Used only to check that
# scripts/ripes-rate.sh parses Ripes' --iret/--exectime report.

.text
main:
    li   t0, 1000000
loop:
    addi t0, t0, -1
    bnez t0, loop
    li   a0, 0
    li   a7, 93
    ecall
