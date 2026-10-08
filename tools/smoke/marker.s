# SMOKE TEST ONLY -- not homework code.
# Trivial program used to check the Ripes CLI runners in scripts/:
#   - the RENDER switch, both guard styles that scripts/ripes-prep.sh handles
#     ('.if RENDER/.else/.endif' and the '@RENDER-BEGIN/-END' comment markers),
#   - the marker line that the runner rewrites with the requested state,
#   - console output (ecall a7=4 string, a7=1 int) and exit (a7=93, a0=status).
# It prints the marker string, a RENDER-ON/OFF line, the sum 1..10, "PASS",
# then exits with status 0.
# Note: Ripes itself has no .if/.endif, so this file only assembles after
# scripts/ripes-prep.sh (which scripts/ripes-run.sh calls) has rewritten it.

.equ RENDER, 1                 # the runner forces this to 0

.data
input_state: .string "21345671111111"   # @STATE
label_sum:   .string "sum="
nl:          .string "\n"
pass_msg:    .string "PASS\n"
.if RENDER
render_msg:  .string "RENDER-ON\n"
.else
render_msg:  .string "RENDER-OFF\n"
.endif
# @RENDER-BEGIN
block_msg:   .string "MARKER-BLOCK-ON\n"
# @RENDER-END

.text
main:
    la   a0, input_state       # print the (possibly rewritten) marker string
    li   a7, 4
    ecall
    la   a0, nl
    li   a7, 4
    ecall
    la   a0, render_msg        # RENDER-ON or RENDER-OFF
    li   a7, 4
    ecall
# @RENDER-BEGIN
    la   a0, block_msg         # only kept when RENDER != 0
    li   a7, 4
    ecall
# @RENDER-END
    li   t0, 0                 # sum 1..10
    li   t1, 1
    li   t2, 11
loop:
    add  t0, t0, t1
    addi t1, t1, 1
    blt  t1, t2, loop
    la   a0, label_sum
    li   a7, 4
    ecall
    mv   a0, t0
    li   a7, 1
    ecall
    la   a0, nl
    li   a7, 4
    ecall
    la   a0, pass_msg
    li   a7, 4
    ecall
    li   a0, 0                 # exit status 0
    li   a7, 93
    ecall
