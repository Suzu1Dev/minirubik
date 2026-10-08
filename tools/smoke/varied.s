# SMOKE TEST ONLY -- not homework code.
# Exercises every outcome scripts/ripes-batch.sh has to classify. Only the
# FIRST digit d of the @STATE string matters:
#   d = 0      spin forever            -> status timeout
#   d = 8      print nothing, exit 0   -> check none
#   d = 9      print FAIL, exit 1      -> check fail
#   otherwise  count down d*1000 times, print PASS, exit 0
# so the retired-instruction count grows with d (for min/mean/max/argmax).

.data
input_state: .string "50000000000000"   # @STATE
pass_msg:    .string "PASS\n"
fail_msg:    .string "FAIL\n"

.text
main:
    la   t0, input_state
    lbu  t1, 0(t0)
    addi t1, t1, -48           # d = first digit
    beqz t1, spin
    li   t2, 9
    beq  t1, t2, fail
    li   t2, 8
    beq  t1, t2, quiet
    li   t3, 1000
    li   t4, 0
times:                         # t4 = d * 1000 by repeated addition
    add  t4, t4, t3
    addi t1, t1, -1
    bnez t1, times
countdown:
    addi t4, t4, -1
    bnez t4, countdown
    la   a0, pass_msg
    li   a7, 4
    ecall
    li   a0, 0
    li   a7, 93
    ecall
fail:
    la   a0, fail_msg
    li   a7, 4
    ecall
    li   a0, 1
    li   a7, 93
    ecall
quiet:
    li   a0, 0
    li   a7, 93
    ecall
spin:
    j    spin
