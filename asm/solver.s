# solver.s - RV32I port of c/ida_core.c, written by the student (Suzu1Dev).
# Work in progress at tag hw1-v2: heur, move_face and ida_apply_move are
# written and tested; the IDA* search loop, input parsing and the LED
# renderer are not yet translated. Run with asm/tables.s appended:
#   cat asm/solver.s asm/tables.s > /tmp/full.s

    .data
input_state: .string "21345671111111"   # @STATE
    .align 4
pv:     .zero 8                      # p[0..6], one byte each
fact:   .word 720, 120, 24, 6, 2, 1  # Lehmer weights 6! .. 1!
st_p:   .zero 48         # 12 words
st_o:   .zero 48
st_mv:  .zero 48
st_f:   .zero 48         # face being tried (0..2, 3 = all done)
st_t:   .zero 48         # quarter turns done on that face (0..3)
st_cp:  .zero 48         # running child of the chain
st_co:  .zero 48
st_lf:  .zero 48         # face used to reach this level (3 = none)
path:   .zero 12         # 11 moves (bytes)
msg_pass: .string "PASS\n"
msg_fail: .string "FAIL\n"
msg_bad:  .string "INVALID\n"

    .text
main:
    # ================= ida_parse =================
    # no call here: t and a registers are free
    # a0 = s, a1 = pv, t6 = 7 (loop limit)
    la   a0, input_state
    la   a1, pv
    li   t6, 7

    # --- loop 1: permutation digits s[0..6] ---
    li   t1, 0              # i = 0
    li   t3, 0              # seen = 0
perm_loop:
    add  t0, a0, t1
    lbu  t2, 0(t0)          # t2 = s[i]
    li   t4, 49             # '1'
    bltu t2, t4, bad_input
    li   t4, 55             # '7'
    bgtu t2, t4, bad_input
    addi t2, t2, -49        # p[i] = s[i] - '1'
    add  t0, a1, t1
    sb   t2, 0(t0)          # pv[i] = p[i]
    li   t4, 1
    sll  t4, t4, t2         # bit = 1 << p[i]
    and  t5, t3, t4
    bnez t5, bad_input      # seen & bit -> duplicate
    or   t3, t3, t4         # seen |= bit
    addi t1, t1, 1
    bltu t1, t6, perm_loop

    # --- loop 2: orientation digits s[7..13] ---
    li   t1, 0              # i = 0
    li   a2, 0              # sum = 0
    li   a3, 0              # orr = 0
orient_loop:
    add  t0, a0, t1
    lbu  t2, 7(t0)          # t2 = s[7+i]
    li   t4, 49             # '1'
    bltu t2, t4, bad_input
    li   t4, 51             # '3'
    bgtu t2, t4, bad_input
    addi t2, t2, -49        # o = s[7+i] - '1'
    add  a2, a2, t2         # sum += o
    li   t4, 6
    beq  t1, t4, orient_next   # i == 6: not part of orr
    slli t5, a3, 1
    add  a3, t5, a3         # orr * 3
    add  a3, a3, t2         # orr = orr * 3 + o
orient_next:
    addi t1, t1, 1
    bltu t1, t6, orient_loop

    # --- s[14] must be '\0' ---
    lbu  t2, 14(a0)
    bnez t2, bad_input

    # --- sum % 3 must be 0 (% banned: subtract loop) ---
    li   t4, 3
mod3_loop:
    bltu a2, t4, mod3_done
    addi a2, a2, -3
    j    mod3_loop
mod3_done:
    bnez a2, bad_input

    # --- Lehmer code: pr = sum c[i] * fact[i], i = 0..5 ---
    la   a5, fact
    li   a4, 0              # pr = 0
    li   t1, 0              # i = 0
lehmer_i:
    li   t4, 6
    bgeu t1, t4, lehmer_done
    add  t0, a1, t1
    lbu  t2, 0(t0)          # t2 = p[i]
    li   t3, 0              # c = 0
    addi t5, t1, 1          # j = i + 1
lehmer_j:
    bgeu t5, t6, lehmer_j_done   # j > 6 -> done
    add  t0, a1, t5
    lbu  a6, 0(t0)          # a6 = p[j]
    bgeu a6, t2, lehmer_j_next
    addi t3, t3, 1          # p[j] < p[i] -> c++
lehmer_j_next:
    addi t5, t5, 1
    j    lehmer_j
lehmer_j_done:
    slli t0, t1, 2
    add  t0, a5, t0
    lw   a6, 0(t0)          # a6 = fact[i]
add_c_times:                # pr += c * fact[i] without mul
    beqz t3, add_c_done
    add  a4, a4, a6
    addi t3, t3, -1
    j    add_c_times
add_c_done:
    addi t1, t1, 1
    j    lehmer_i
lehmer_done:
    mv   s5, a4             # p_rank
    mv   s6, a3             # o_rank
    # ================= end ida_parse =================

    # if (p == 0 && o == 0) -> solved, length 0
    or   t0, s5, s6
    beqz t0, found0

    # bound = heur(p, o)
    mv   a0, s5
    mv   a1, s6
    call heur
    mv   s1, a0

    # table base addresses, kept in s registers for the whole search
    # (s8 is reused as i in verify_loop, after the search is done)
    la   s8, perm_qt
    la   s9, orient_qt
    la   s10, pdb_p
    la   s11, pdb_o

bound_loop:
    # if (bound > 11) -> fail
    li   t0, 11
    bgtu s1, t0, fail

    # d = 0
    li   s0, 0

    # root: st_p[0] = p; st_o[0] = o; st_lf[0] = 3 (no previous face)
    #       st_f[0] = 0; st_t[0] = 0; st_cp[0] = p; st_co[0] = o
    la   t0, st_p
    sw   s5, 0(t0)
    la   t0, st_o
    sw   s6, 0(t0)
    la   t0, st_lf
    li   t1, 3
    sw   t1, 0(t0)
    la   t0, st_f
    sw   zero, 0(t0)
    la   t0, st_t
    sw   zero, 0(t0)
    la   t0, st_cp
    sw   s5, 0(t0)
    la   t0, st_co
    sw   s6, 0(t0)

    # registers in the loop:
    #   s0 = d, s1 = bound, s2 = m, s3 = cp, s4 = co, s7 = f
    #   t6 = d * 4 (valid until call heur; no call before that)
dfs_loop:
    slli t6, s0, 2          # t6 = d * 4

    # (1) if (st_t[d] == 3): next face, restart the chain from the parent
    la   t0, st_t
    add  t0, t0, t6
    lw   t1, 0(t0)          # t1 = st_t[d]
    li   t2, 3
    bne  t1, t2, chk_all_done
    sw   zero, 0(t0)        # st_t[d] = 0
    la   t0, st_f
    add  t0, t0, t6
    lw   t1, 0(t0)
    addi t1, t1, 1
    sw   t1, 0(t0)          # st_f[d]++
    la   t0, st_p
    add  t0, t0, t6
    lw   t1, 0(t0)
    la   t0, st_cp
    add  t0, t0, t6
    sw   t1, 0(t0)          # st_cp[d] = st_p[d]
    la   t0, st_o
    add  t0, t0, t6
    lw   t1, 0(t0)
    la   t0, st_co
    add  t0, t0, t6
    sw   t1, 0(t0)          # st_co[d] = st_o[d]

chk_all_done:
    # (2) if (st_f[d] == 3): all faces done, go back up
    #     (before same-face check: at the root st_lf = 3)
    la   t0, st_f
    add  t0, t0, t6
    lw   s7, 0(t0)          # s7 = f = st_f[d]
    li   t2, 3
    bne  s7, t2, chk_same_face
    beqz s0, next_bound     # d == 0 -> next bound
    addi s0, s0, -1         # d--
    j    dfs_loop

chk_same_face:
    # (3) if (st_f[d] == st_lf[d]): skip the whole face
    la   t0, st_lf
    add  t0, t0, t6
    lw   t1, 0(t0)          # t1 = st_lf[d]
    bne  s7, t1, do_turn
    la   t0, st_t
    add  t0, t0, t6
    li   t1, 3
    sw   t1, 0(t0)          # st_t[d] = 3
    j    dfs_loop

do_turn:
    # (4) one quarter turn of face f on the running child
    #     row start: t3 = perm_qt[f], t4 = orient_qt[f]
    mv   t3, s8             # perm_qt
    mv   t4, s9             # orient_qt
    beqz s7, row_ready      # f == 0
    li   t1, 1
    beq  s7, t1, row_one    # f == 1
    li   t1, 20160          # f == 2
    add  t3, t3, t1
    li   t1, 2916
    add  t4, t4, t1
    j    row_ready
row_one:
    li   t1, 10080
    add  t3, t3, t1
    li   t1, 1458
    add  t4, t4, t1
row_ready:
    la   t0, st_cp
    add  t0, t0, t6
    lw   t1, 0(t0)          # t1 = st_cp[d]
    slli t1, t1, 1
    add  t1, t3, t1
    lhu  s3, 0(t1)          # cp = perm_qt[f][st_cp[d]]
    sw   s3, 0(t0)          # st_cp[d] = cp
    la   t0, st_co
    add  t0, t0, t6
    lw   t1, 0(t0)          # t1 = st_co[d]
    slli t1, t1, 1
    add  t1, t4, t1
    lhu  s4, 0(t1)          # co = orient_qt[f][st_co[d]]
    sw   s4, 0(t0)          # st_co[d] = co
    la   t0, st_t
    add  t0, t0, t6
    lw   t1, 0(t0)
    addi t1, t1, 1
    sw   t1, 0(t0)          # st_t[d]++ (t1 = new t)

    # (5) m = 3 * f + t - 1
    slli t2, s7, 1
    add  t2, t2, s7         # 3 * f
    add  t2, t2, t1
    addi s2, t2, -1         # s2 = m

    # (6) if (d + 1 + heur(cp, co) > bound) -> skip
    #     heur inlined: h = max(pdb_p[cp], pdb_o[co]), no call
    add  t0, s10, s3
    lbu  t1, 0(t0)          # t1 = pdb_p[cp]
    add  t0, s11, s4
    lbu  t2, 0(t0)          # t2 = pdb_o[co]
    bgeu t1, t2, h_ready
    mv   t1, t2             # t1 = max
h_ready:
    add  t1, t1, s0
    addi t1, t1, 1          # t1 = d + 1 + h
    bgtu t1, s1, dfs_loop

    # (7) d++; st_p = cp; st_o = co; st_mv = m; st_lf = f;
    #     st_f = 0; st_t = 0; st_cp = cp; st_co = co
    addi s0, s0, 1
    slli t1, s0, 2          # new d * 4
    la   t0, st_p
    add  t0, t0, t1
    sw   s3, 0(t0)
    la   t0, st_o
    add  t0, t0, t1
    sw   s4, 0(t0)
    la   t0, st_mv
    add  t0, t0, t1
    sw   s2, 0(t0)
    la   t0, st_lf
    add  t0, t0, t1
    sw   s7, 0(t0)
    la   t0, st_f
    add  t0, t0, t1
    sw   zero, 0(t0)
    la   t0, st_t
    add  t0, t0, t1
    sw   zero, 0(t0)
    la   t0, st_cp
    add  t0, t0, t1
    sw   s3, 0(t0)
    la   t0, st_co
    add  t0, t0, t1
    sw   s4, 0(t0)

    # (8) if (cp == 0 && co == 0) -> found
    or   t0, s3, s4
    beqz t0, found
    j    dfs_loop

next_bound:
    # bound++
    addi s1, s1, 1
    j    bound_loop

found:
    # --- copy path: for (i = 1; i <= d; i++) path[i-1] = st_mv[i] ---
    # no call in this loop, so t registers are safe; d >= 1 here
    li   t1, 1              # i = 1
copy_loop:
    la   t0, st_mv
    slli t2, t1, 2          # i * 4
    add  t0, t0, t2
    lw   t3, 0(t0)          # t3 = st_mv[i]
    la   t0, path
    add  t0, t0, t1         # t0 = path + i
    sb   t3, -1(t0)         # path[i-1] = st_mv[i]
    addi t1, t1, 1          # i++
    bleu t1, s0, copy_loop  # i <= d -> continue

    # --- verify (ida_apply_path): apply path from start, expect (0, 0) ---
    # loop calls ida_apply_move, so p, o, i live in s registers
    # li   s5, 1            # TEST: uncomment to force FAIL
    mv   s3, s5             # p = start p
    mv   s4, s6             # o = start o
    li   s8, 0              # i = 0
verify_loop:
    bgeu s8, s0, verify_done   # i >= d -> done (d = 0: no steps)
    la   t0, path
    add  t0, t0, s8
    lbu  a2, 0(t0)          # a2 = path[i]
    mv   a0, s3
    mv   a1, s4
    call ida_apply_move
    mv   s3, a0
    mv   s4, a1
    addi s8, s8, 1          # i++
    j    verify_loop
verify_done:
    or   t0, s3, s4
    beqz t0, print_pass

print_fail:
    la   a0, msg_fail
    li   a7, 4              # print string
    ecall
    j    print_len

print_pass:
    la   a0, msg_pass
    li   a7, 4              # print string
    ecall

print_len:
    # print solution length d, then exit
    mv   a0, s0
    li   a7, 1              # print int
    ecall
    j    exit

found0:
    # input is already solved: PASS, length 0
    li   s0, 0
    j    print_pass

bad_input:
    la   a0, msg_bad
    li   a7, 4              # print string
    ecall
    j    exit

fail:
    li   a0, -1
    li   a7, 1              # print int
    ecall

exit:
    li   a7, 10             # exit
    ecall

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
