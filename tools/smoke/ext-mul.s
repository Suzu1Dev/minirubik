# SMOKE TEST ONLY - unrelated to the homework.  A negative test:
# scripts/rv32i-audit.sh MUST reject this file because 'mul' belongs to the
# M extension, not to base RV32I.
        .text
        li      a0, 6
        li      a1, 7
        mul     a0, a0, a1
        li      a7, 10
        ecall
