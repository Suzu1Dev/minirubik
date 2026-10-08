    .text
    .equ N, 3000000
main:
    li   t0, 0x10000000 # addr = 0x10000000
    li   t1, N          # t1 = N (loop count)
loop:
    sw   zero, 0(t0)    # store word in addr
    addi t1, t1, -1     # t1 = t1 - 1
    bne  t1, zero, loop # if N != 0, go back to loop

    li   a7, 10         # ecall 10: exit
    ecall