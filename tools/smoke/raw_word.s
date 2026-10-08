# SMOKE TEST ONLY -- not homework code.
# Shows that Ripes does not check raw instruction encodings: the '.word'
# below is the encoding of 'mul a0, a0, a0' (M extension), which the Ripes
# assembler would reject as a mnemonic without --isaexts.
#   RV32_ISS executes it   -> prints 36, exit 0, ripes-run.sh status ok
#   RV32_5S  retires a NOP -> prints 6,  exit 0, ripes-run.sh status ok
# The runners cannot see this; scripts/rv32i-audit.sh must reject the file
# (raw .word data in an executable section) with exit status 1.

.text
main:
    li    a0, 6
    .word 0x02A50533        # mul a0, a0, a0 (raw encoding)
    li    a7, 1
    ecall
    li    a0, 0
    li    a7, 93
    ecall
