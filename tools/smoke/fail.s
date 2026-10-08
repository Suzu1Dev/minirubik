# SMOKE TEST ONLY -- not homework code.
# Prints its @STATE string, then "FAIL", then exits with status 1.
# Used to check that scripts/ripes-run.sh / ripes-batch.sh flag a run that
# reports FAIL (and a non-zero exit code).

.equ RENDER, 0

.data
input_state: .string "11111111111111"   # @STATE
nl:          .string "\n"
fail_msg:    .string "FAIL\n"

.text
main:
    la   a0, input_state
    li   a7, 4
    ecall
    la   a0, nl
    li   a7, 4
    ecall
    la   a0, fail_msg
    li   a7, 4
    ecall
    li   a0, 1
    li   a7, 93
    ecall
