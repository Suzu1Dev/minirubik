# SMOKE TEST ONLY -- not homework code.
# Prints one line, then spins forever. Used to check how the Ripes CLI and
# scripts/ripes-run.sh behave when --timeout expires (run with a short -t).

.data
input_state: .string "00000000000000"   # @STATE
msg:         .string "spinning\n"

.text
main:
    la   a0, msg
    li   a7, 4
    ecall
spin:
    j    spin
