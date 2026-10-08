# SMOKE TEST ONLY -- not homework code.
# Prints "7" and then runs off the end of .text without an exit ecall.
# Ripes stops silently in that case; scripts/ripes-run.sh reports sim_error.

.text
main:
    li   a0, 7
    li   a7, 1
    ecall
