# SMOKE TEST ONLY -- not homework code.
# Uses 'mul' (RV32M). Ripes CLI is run without --isaexts, i.e. plain RV32I,
# so this must be reported as asm_error by scripts/ripes-run.sh, and
# scripts/ripes-batch.sh must stop at its pre-flight check.

.data
input_state: .string "00000000000000"   # @STATE

.text
main:
    li   a0, 6
    mul  a0, a0, a0
    li   a7, 93
    ecall
