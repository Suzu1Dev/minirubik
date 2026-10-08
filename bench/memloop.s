    .text
    .equ LEN, 0
main:
    li   t0, 0x10000000 # addr = 0x10000000
    li   t1, LEN        # t1 = 1MiB
    add  t1, t1, t0    # t1 = end = 0x10000000 + 1 MiB
loop:
    sw   zero, 0(t0)      # store word in addr
    addi t0, t0, 4      # addr = addr + 4
    bne  t0, t1, loop   # if addr != end, go back to loop

    li   a7, 10         # ecall 10: exit
    ecall