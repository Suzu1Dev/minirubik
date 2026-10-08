# solver.s - RV32I port of c/ida_core.c, written by the student (Suzu1Dev).
# Work in progress at tag hw1-v2: heur, move_face and ida_apply_move are
# written and tested; the IDA* search loop, input parsing and the LED
# renderer are not yet translated. Run with asm/tables.s appended:
#   cat asm/solver.s asm/tables.s > /tmp/full.s

    .text

# heur: a0 = p_rank, a1 = o_rank -> a0 = max(pdb_p[p], pdb_o[o])
heur:
    la t0, pdb_p
    add t0, t0, a0
    lbu t1, 0(t0)
    la t0, pdb_o
    add t0, t0, a1
    lbu a0, 0(t0)
    bgeu a0, t1, ida_heur_return
    mv a0, t1
ida_heur_return:
    ret

# move_face: a0 = move (0..8) -> a0 = face (0 = R, 1 = B, 2 = D)
move_face:
    li   t0, 6
    bgeu a0, t0, face_two
    li   t0, 3
    bgeu a0, t0, face_one
    li   a0, 0
    ret
face_one:
    li   a0, 1
    ret
face_two:
    li   a0, 2
    ret

# ida_apply_move: a0 = p_rank, a1 = o_rank, a2 = move (0..8)
#                 -> a0 = new p_rank, a1 = new o_rank
ida_apply_move:
    li t2, 0
    li t0, 3
    bltu a2, t0, ida_move_face_ready
    li t2, 1
    li t0, 6
    bltu a2, t0, ida_move_face_ready
    li t2, 2
ida_move_face_ready:
    slli t3, t2, 1
    add t3, t3, t2
    sub a2, a2, t3
    addi a2, a2, 1
    la t0, perm_qt
    la t1, orient_qt
    li t3, 10080
    li t4, 1458
ida_move_row_loop:
    beqz t2, ida_move_qt_loop
    add t0, t0, t3
    add t1, t1, t4
    addi t2, t2, -1
    j ida_move_row_loop
ida_move_qt_loop:
    slli t2, a0, 1
    add t2, t0, t2
    lhu a0, 0(t2)
    slli t2, a1, 1
    add t2, t1, t2
    lhu a1, 0(t2)
    addi a2, a2, -1
    bnez a2, ida_move_qt_loop
    ret
