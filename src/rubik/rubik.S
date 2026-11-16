# rubik_solve_asm: optimal 2x2x2 cube solver, hand-written RV32I.
#
# int rubik_solve_asm(const char *state, char *out, size_t cap)
#                                   a0 = state, a1 = out, a2 = cap; result in a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions, no heap, no recursion. Tests: tests/trubik.c.
    .data
    face_table:     .byte   0, 0, 0, 1, 1, 1, 2, 2, 2
    turns_table:    .byte   1, 2, 3, 1, 2, 3, 1, 2, 3
    move_names:     .byte   'R', 0, 'R', '2', 'R', 39    # 39 = '\''
                    .byte   'B', 0, 'B', '2', 'B', 39
                    .byte   'D', 0, 'D', '2', 'D', 39
                          
    name_len:       .byte 1, 2, 2, 1, 2, 2, 1, 2, 2
    
    .text

    .globl  rubik_solve_asm
    .type   rubik_solve_asm, @function
    .align  2
# ---------- rubik_solve ----------
rubik_solve_asm:
    addi    sp, sp, -144
    sw      s0, 0(sp)
    sw      s1, 4(sp)
    sw      s2, 8(sp)
    sw      s3, 12(sp)
    sw      s4, 16(sp)
    sw      s5, 20(sp)
    sw      s6, 24(sp)
    sw      s7, 28(sp)
    sw      s8, 32(sp)
    sw      s9, 36(sp)
    sw      s10, 112(sp)        # after stack[0..6] (sp+56..sp+111)
    sw      s11, 116(sp)
    
    addi    s0, a0, 0           # s0: a0(state)
    addi    s1, a1, 0           # s1: a1(out)
    addi    s2, a2, 0           # s2: a2(cap)
    addi    s3, ra, 0           # s3: ra
    jal     ra, validate
    beq     a0, x0, rubik_solve_asm_is_valid 
    addi    a0, x0, -1
    beq     x0, x0, rubik_solve_asm_return
rubik_solve_asm_is_valid: 
    addi    a0, s0, 0           # encode(a0, a1, a2)
    addi    a1, x0, 0           # encode(a0, a1, a2)
    addi    a2, x0, 0           # encode(a0, a1, a2)
    jal     ra, encode
    # a1: p_rank, a2: o_rank
    addi    a0, a1, 0
    addi    a1, a2, 0
    addi    a2, sp, 40          # &path[0] = sp + 40
    jal     ra, solve           # a0: depth, path is in stack
    addi    s0, a0, 0
    addi    a2, sp, 40 
    addi    a3, a2, 0
    addi    a2, a0, 0
    addi    a0, s1, 0
    addi    a1, s2, 0
    jal     ra, write_out
    beq     a0, x0, rubik_solve_asm_out_is_valid
    addi    a0, x0, -2
    beq     x0, x0, rubik_solve_asm_return
rubik_solve_asm_out_is_valid:
    addi    a0, s0, 0
rubik_solve_asm_return: 
    addi    ra, s3, 0
    lw      s11, 116(sp)
    lw      s10, 112(sp)
    lw      s9, 36(sp)
    lw      s8, 32(sp)
    lw      s7, 28(sp)
    lw      s6, 24(sp)
    lw      s5, 20(sp)
    lw      s4, 16(sp)
    lw      s3, 12(sp)
    lw      s2, 8(sp)
    lw      s1, 4(sp)
    lw      s0, 0(sp)
    addi    sp, sp, 144
    jalr    x0, ra, 0
# ---------- rubik_solve (end) ----------
# ---------- validate ----------
validate:
    addi    t0, x0, 0   # t0: i
    addi    t1, x0, 0   # t1: seen
validate_loop_1:
    add     t3, a0, t0  # t3: &state[i]
    lbu     t4, 0(t3)   
    addi    t4, t4, -49 # t4: p

    # check 1 (front 7 char): less than 7
    addi    t5, x0, 7
    bgeu    t4, t5, validate_bad

    # check 2 (front 7 char): is unique
    addi    t5, x0, 1   # t5: mask
    sll     t5, t5, t4  # 1 << p[i]
    and     t6, t1, t5
    bne     t6, x0, validate_bad
    or      t1, t1, t5  # update seen
    addi    t0, t0, 1   # increment i
    addi    t3, x0, 7
    blt     t0, t3, validate_loop_1

    addi    t0, x0, 7   # t0: i = 7
    addi    t1, x0, 0   # t1: sum
validate_loop_2:
    add     t2, a0, t0  # t2: &state[i]
    lbu     t3, 0(t2)   
    addi    t3, t3, -49 # t3: o
    addi    t4, x0, 3
    bgeu    t3, t4, validate_bad
    add     t1, t1, t3
    addi    t0, t0, 1
    addi    t2, x0, 14
    blt     t0, t2, validate_loop_2

    # (input[14] != '\0')
    lbu     t0, 14(a0)
    bne     t0, x0, validate_bad

    # t1: sum
    addi    t0, x0, 2
    bge     t0, t1, validate_mod3_done
validate_mod3:
    addi    t1, t1, -3
    blt     t0, t1, validate_mod3
validate_mod3_done:
    bne     t1, x0, validate_bad
    addi    a0, x0, 0
    jalr    x0, ra, 0

validate_bad:
    addi    a0, x0, 1
    jalr    x0, ra, 0
    .size   rubik_solve_asm, .-rubik_solve_asm
# ---------- validate (end) ----------
# ---------- encode ----------
encode:                     # encode(a0: state, a1: p_rank, a2: o_rank)
    addi    a3, x0, 0       # a3: i
encode_p_loop: 
    addi    a4, x0, 0       # a4: smaller
    addi    a5, a3, 1       # a5: j = i(a3) + 1
encode_smaller_loop: 
    add     a6, a0, a5      # &state[j]
    lbu     a6, 0(a6)       # a6: state[j]
    add     a7, a0, a3      # &state[i]
    lbu     a7, 0(a7)       # a7: state[i]
    sltu    a6, a6, a7
    add     a4, a4, a6      # smaller += state[j] < state[i];
    addi    a5, a5, 1
    addi    a6, x0, 7
    blt     a5, a6, encode_smaller_loop
# free a5 - a7
    addi    a5, x0, 0       # a5: prod
    addi    a6, a1, 0       # a6: a = p(p_rank)
    addi    a7, x0, 7
    sub     a7, a7, a3      # a7: b = 7 - i

    beq     a7, x0, encode_mul_loop_end
encode_mul_loop:
    andi    t0, a7, 1
    beq     t0, x0, encode_mul_loop_no_add
    add     a5, a5, a6      # prod += a 
encode_mul_loop_no_add: 
    srli    a7, a7, 1
    slli    a6, a6, 1
    bne     a7, x0, encode_mul_loop
encode_mul_loop_end:
    add     a1, a5, a4
# free a5 - a7
    addi    a3, a3, 1
    addi    a5, x0, 6
    blt     a3, a5, encode_p_loop
# free a3 - a7
    addi    a3, x0, 0       # a3: i
encode_o_loop:
    addi    a4, a3, 7
    add     a4, a0, a4      # &state[i]
    lbu     a4, 0(a4)       # a4: state[i] 
    addi    a4, a4, -49
    slli    a5, a2, 1
    add     a2, a5, a2
    add     a2, a2, a4
    addi    a3, a3, 1       # i ++
    addi    a4, x0, 6
    blt     a3, a4, encode_o_loop
# free a3 - a7
# return (a1: p_rank, a2: o_rank)
    jalr    x0, ra, 0
# ---------- encode (end) ----------
# ---------- get_heuristic ----------
# get_heuristic(a0: p_rank, a1: o_rank) -> a0: h
# leaf: uses a0-a1 and t1-t2 only
get_heuristic: 
    # s0: &asm_perm_heuristic[0], s9: &asm_ori_heuristic[0] (set in solve)
    add     t1, s0, a0
    lbu     t1, 0(t1)           # t1: p_h
    add     t2, s9, a1
    lbu     t2, 0(t2)           # t2: o_h
    bgeu    t2, t1, get_heuristic_p_smaller_eq
    addi    a0, t1, 0
    jalr    x0, ra, 0
get_heuristic_p_smaller_eq: 
    addi    a0, t2, 0
    jalr    x0, ra, 0
# ---------- get_heuristic (end) ----------
# ---------- solve ----------
solve: 
    addi    s4, ra, 0           # s4: ra
    addi    s5, a0, 0           # s5: p_rank (initial)
    addi    s6, a1, 0           # s6: o_rank (initial)
    addi    s7, sp, 56          # s7: &stack[0]
    addi    s8, a2, 0           # s8: &path[0]
    # table addresses, loaded once for get_heuristic and apply_move
1:  auipc   s0, %pcrel_hi(asm_perm_heuristic)
    addi    s0, s0, %pcrel_lo(1b)       # s0: &asm_perm_heuristic[0]
1:  auipc   s9, %pcrel_hi(asm_ori_heuristic)
    addi    s9, s9, %pcrel_lo(1b)       # s9: &asm_ori_heuristic[0]
1:  auipc   s10, %pcrel_hi(asm_perm_transition_flat)
    addi    s10, s10, %pcrel_lo(1b)     # s10: &asm_perm_transition_flat[0]
1:  auipc   s11, %pcrel_hi(asm_ori_transition_flat)
    addi    s11, s11, %pcrel_lo(1b)     # s11: &asm_ori_transition_flat[0]

    slli    a0, s5, 10
    or      a0, a0, s6          # a0: rank

1:  auipc   a1, %pcrel_hi(asm_in_step_5)
    addi    a1, a1, %pcrel_lo(1b)
    lui     a2, %hi(12224)
    addi    a2, a2, %lo(12224)
    # dont touch: 
    jal     ra, binary_search
    addi    a1, x0, 255
    beq     a0, a1, solve_not_found
    addi    a0, s5, 0
    addi    a1, s6, 0
    addi    a2, s8, 0
    # dont touch: 
    jal     ra, follow_table
    jalr    x0, s4, 0           # return: follow_table(p_rank, o_rank, path)
solve_not_found:
    addi    a3, x0, 0           # a3: bound
    addi    a0, s5, 0
    addi    a1, s6, 0
    # dont touch: 
    jal     ra, get_heuristic
    addi    a3, a0, 0
    addi    a1, x0, 6
    bgeu    a3, a1, solve_not_bound_smaller_then_6 
    addi    a3, x0, 6
solve_not_bound_smaller_then_6:
    addi    a4, x0, 0           # a4: first
    addi    a5, x0, -1          # a5: first_face

    slli    a0, s5, 10
    or      a0, a0, s6          # a0: rank
1:  auipc   a1, %pcrel_hi(asm_step_11)
    addi    a1, a1, %pcrel_lo(1b)
    lui     a2, %hi(2644)
    addi    a2, a2, %lo(2644)
    # binary_search: uses a0-a2 and t1-t6 only
    jal     ra, binary_search

    addi    a1, x0, 255
    beq     a0, a1, solve_move_not_found
    sb      a0, 0(s8)           # path[0] = move
    addi    a4, x0, 1           # a4: first = 1
1:  auipc   t1, %pcrel_hi(face_table)
    addi    t1, t1, %pcrel_lo(1b)
    add     t1, t1, a0
    lbu     a5, 0(t1)           # a5: first_face = face_table[move]

    addi    a2, a0, 0           # a2: move
    addi    a0, s5, 0           # a0: p_rank
    addi    a1, s6, 0           # a1: o_rank
    # apply_move: uses a0-a2 and t1-t6 only, a3-a5 are kept
    jal     ra, apply_move
    addi    s5, a0, 0           # s5: p_rank after the move
    addi    s6, a1, 0           # s6: o_rank after the move
    addi    a3, x0, 10          # a3: bound = 10
solve_move_not_found:
    # a3: bound
    # a4: first
    # a5: first_face
    # a6: depth
    # a7: &stack[depth]
    # t0: kept across calls (callees use a0-a2 and t1-t6 only)
solve_bound_loop:
    add     t0, a3, a4
    addi    t1, x0, 11
    blt     t1, t0, solve_fail  # bound + first > MAX_DEPTH
    addi    a6, x0, 0           # a6: depth = 0
    addi    a7, s7, 0           # a7: &stack[0]
    sh      s5, 0(a7)           # stack[0].p_rank = p_rank
    sh      s6, 2(a7)           # stack[0].o_rank = o_rank
    sb      x0, 4(a7)           # stack[0].g = 0
    sb      a5, 5(a7)           # stack[0].last_face = first_face
    sb      x0, 6(a7)           # stack[0].move_index = 0
solve_stack_loop:
    blt     a6, x0, solve_next_bound    # while (depth >= 0)
    slli    a7, a6, 3
    add     a7, s7, a7          # a7: &stack[depth]
    lbu     t0, 4(a7)
    sub     t0, a3, t0          # t0: remaining = bound - g

    # remaining == 5: look the node up in in_step_5
    addi    t1, x0, 5
    bne     t0, t1, solve_not_remaining_5
    lhu     a0, 0(a7)
    lhu     a1, 2(a7)
    jal     ra, get_heuristic   # a0: h
    bltu    t0, a0, solve_pop_5 # h > 5: not within 5 moves
    lhu     a0, 0(a7)
    slli    a0, a0, 10
    lhu     t1, 2(a7)
    or      a0, a0, t1          # a0: node_rank
1:  auipc   a1, %pcrel_hi(asm_in_step_5)
    addi    a1, a1, %pcrel_lo(1b)
    lui     a2, %hi(12224)
    addi    a2, a2, %lo(12224)
    jal     ra, binary_search
    addi    t1, x0, 255
    bne     a0, t1, solve_found
solve_pop_5:
    addi    a6, a6, -1          # depth--
    beq     x0, x0, solve_stack_loop

solve_not_remaining_5:
    lhu     a0, 0(a7)
    lhu     a1, 2(a7)
    jal     ra, get_heuristic   # a0: h
    bgeu    t0, a0, solve_try_move      # h <= remaining
    addi    a6, a6, -1          # depth--
    beq     x0, x0, solve_stack_loop

solve_try_move:
    lbu     t0, 6(a7)           # t0: move_index
solve_check_move_index_over_9:
    addi    t1, x0, 9
    bgeu    t0, t1, solve_all_moves_tried
1:  auipc   t1, %pcrel_hi(face_table)
    addi    t1, t1, %pcrel_lo(1b)
    add     t1, t1, t0
    lbu     t1, 0(t1)           # t1: face
    lb      t2, 5(a7)           # t2: last_face
    bne     t1, t2, solve_not_same_face
    addi    t0, t0, 3
    sb      t0, 6(a7)           # move_index += 3
    beq     x0, x0, solve_check_move_index_over_9

solve_not_same_face:
    addi    a2, t0, 0           # a2: next_move
    addi    t2, t0, 1
    sb      t2, 6(a7)           # move_index++
    addi    t0, t1, 0           # t0: face (kept across apply_move)
    lhu     a0, 0(a7)
    lhu     a1, 2(a7)
    jal     ra, apply_move      # a0: next_p, a1: next_o
    addi    a6, a6, 1           # depth++
    lbu     t2, 4(a7)
    addi    t2, t2, 1           # t2: stack[depth].g + 1
    addi    a7, a7, 8           # a7: &stack[depth]
    sh      a0, 0(a7)           # stack[depth].p_rank = next_p
    sh      a1, 2(a7)           # stack[depth].o_rank = next_o
    sb      t2, 4(a7)           # stack[depth].g
    sb      t0, 5(a7)           # stack[depth].last_face = face
    sb      x0, 6(a7)           # stack[depth].move_index = 0
    beq     x0, x0, solve_stack_loop

solve_all_moves_tried:
    addi    a6, a6, -1          # depth--
    beq     x0, x0, solve_stack_loop

solve_next_bound:
    addi    a3, a3, 1           # bound++
    beq     x0, x0, solve_bound_loop

solve_found:
    # path[first + k] = stack[k].move_index - 1, for k < depth
    addi    t0, x0, 0           # t0: k
    bge     t0, a6, solve_copy_end
solve_copy_loop:
    slli    t1, t0, 3
    add     t1, s7, t1          # t1: &stack[k]
    lbu     t1, 6(t1)
    addi    t1, t1, -1          # t1: stack[k].move_index - 1
    add     t2, s8, a4
    add     t2, t2, t0          # t2: &path[first + k]
    sb      t1, 0(t2)
    addi    t0, t0, 1
    blt     t0, a6, solve_copy_loop
solve_copy_end:
    add     s9, a4, a6          # s9: first + depth (follow_table uses a3-a7)
    lhu     a0, 0(a7)
    lhu     a1, 2(a7)
    add     a2, s8, s9          # a2: path + first + depth
    jal     ra, follow_table    # a0: tail
    add     a0, a0, s9          # return first + depth + tail
    jalr    x0, s4, 0

solve_fail:
    addi    a0, x0, -1          # not reached: every state is within 11 moves
    jalr    x0, s4, 0
# ---------- solve (end) ----------

# ---------- binary_search ----------
# binary_search(a0: rank, a1: &table[0], a2: size) -> a0: move, 255 if not found
# leaf: uses a0-a2 and t1-t6 only
binary_search:
    addi    t6, x0, 0           # t6: low
    addi    t5, a2, -1          # t5: high
    lui     t1, %hi(0x7FFFFF)
    addi    t1, t1, %lo(0x7FFFFF)   # t1: rank mask, loaded once
binary_search_while: 
    add     t4, t6, t5
    srli    t4, t4, 1           # t4: mid
    slli    t3, t4, 2
    add     t3, t3, a1          # &table[mid]
    lw      t3, 0(t3)           # t3: entry
    and     t2, t3, t1          # t2: entry_rank
    bne     t2, a0, binary_search_not_found
    srli    a0, t3, 23
    andi    a0, a0, 0xF
    jalr    x0, ra, 0 
binary_search_not_found:
    bgeu    t2, a0, binary_search_high_side
    addi    t6, t4, 1
    bge     t5, t6, binary_search_while
    beq     x0, x0, binary_search_while_end 
binary_search_high_side:
    addi    t5, t4, -1
    bge     t5, t6, binary_search_while
binary_search_while_end:
    addi    a0, x0, 255
    jalr    x0, ra, 0
# ---------- binary_search (end) ----------

# ---------- apply_move ----------
apply_move:
    # dont use a3- a7
    # used: t1 - t6
1:  auipc   t2, %pcrel_hi(face_table)
    addi    t2, t2, %pcrel_lo(1b)
    add     t2, t2, a2
    lbu     t2, 0(t2)           # t2: face

1:  auipc   t3, %pcrel_hi(turns_table)
    addi    t3, t3, %pcrel_lo(1b)
    add     t3, t3, a2
    lbu     t3, 0(t3)           # t3: turns
    addi    t4, x0, 0           # t4: i
    # s10: &asm_perm_transition_flat[0], s11: &asm_ori_transition_flat[0]
    # (set in solve)
apply_move_for_loop:
    slli    t5, t2, 13
    add     t5, t5, a0
    slli    t5, t5, 1
    add     t5, t5, s10
    lhu     a0, 0(t5)

    slli    t6, t2, 10
    add     t6, t6, a1
    slli    t6, t6, 1
    add     t6, t6, s11
    lhu     a1, 0(t6)

    addi    t4, t4, 1
    bltu    t4, t3, apply_move_for_loop
    
    jalr    x0, ra, 0
# ---------- apply_move (end) ----------

# ---------- follow_table ----------
follow_table:
    # follow_table(a0: p_rank, a1: o_rank, a2: *path)
    addi    a3, a0, 0           # a3: p_rank
    addi    a4, a1, 0           # a4: o_rank
    addi    a5, a2, 0           # a5: &path[0]
    addi    a7, ra, 0           # a7: ra

    addi    a6, x0, 0           # a6: count
    slli    a0, a3, 10
    or      a0, a0, a4

1:  auipc   a1, %pcrel_hi(asm_in_step_5)
    addi    a1, a1, %pcrel_lo(1b)
    lui     a2, %hi(12224)
    addi    a2, a2, %lo(12224)
    # dont touch: a3-a7
    # binary_search(a0: rank, a1: *table, a2: size)
    jal     ra, binary_search
    
    addi    a1, x0, 15
    beq     a0, a1, follow_table_while_end 
follow_table_while:
    add     a1, a6, a5
    sb      a0, 0(a1)
    addi    a6, a6, 1

    addi    a2, a0, 0
    addi    a1, a4, 0
    addi    a0, a3, 0
    # dont touch: a3 - a7
    # apply_move(a0: p_rank, a1: o_rank, a2: move)
    jal     ra, apply_move
    addi    a3, a0, 0
    addi    a4, a1, 0

    slli    a0, a3, 10
    or      a0, a0, a4
1:  auipc   a1, %pcrel_hi(asm_in_step_5)
    addi    a1, a1, %pcrel_lo(1b)
    lui     a2, %hi(12224)
    addi    a2, a2, %lo(12224)
    # dont touch: a3-a7
    # binary_search(a0: rank, a1: *table, a2: size)
    jal     ra, binary_search

    addi    a1, x0, 15
    bne     a0, a1, follow_table_while
follow_table_while_end:
    addi    a0, a6, 0
    jalr    x0, a7, 0
# ---------- follow_table (end) ----------

# ---------- write_out ----------
write_out:
    addi    a4, x0, 1           # a4: need = 1
    addi    a5, x0, 0           # a5: i
    bgeu    a5, a2, write_out_need_loop_end
write_out_need_loop:
    bgeu    x0, a5, write_out_no_add
    addi    a4, a4, 1 
write_out_no_add: 
    add     a6, a3, a5
    lbu     a6, 0(a6)
1:  auipc   a7, %pcrel_hi(name_len)
    addi    a7, a7, %pcrel_lo(1b)
    add     a7, a7, a6
    lbu     a7, 0(a7)
    add     a4, a4, a7
    addi    a5, a5, 1
    blt     a5, a2, write_out_need_loop
write_out_need_loop_end:
    bgeu    a1, a4, write_out_greater_than_cap
    addi    a5, x0, 1
    blt     a1, a5, write_out_cap_smaller_than_one
    sb      x0, 0(a0)           # out[0] = '\0';
write_out_cap_smaller_than_one:
    addi    a0, x0, 1
    jalr    x0, ra, 0           # return 1
write_out_greater_than_cap:
# free a4 - a7
    addi    a4, x0, 0           # a4: pos
    addi    a5, x0, 0           # a5: i
    bgeu    a5, a2, write_out_loop_end  # depth == 0: no moves
write_out_loop:
    bgeu    x0, a5, write_out_i_smaller_eq_than_one
    add     a6, a0, a4
    addi    a7, x0, 32          # 32 == ' '
    sb      a7, 0(a6)
    addi    a4, a4, 1
write_out_i_smaller_eq_than_one:
    add     a6, a3, a5
    lbu     a6, 0(a6)           # a6: path[i] 
    slli    a6, a6, 1           
1:  auipc   a7, %pcrel_hi(move_names)
    addi    a7, a7, %pcrel_lo(1b)
    add     a6, a6, a7
    lbu     t0, 0(a6)           # t0: name[0]
    lbu     t1, 1(a6)           # t1: name[1]
    add     a6, a4, a0
    sb      t0, 0(a6)
    beq     t1, x0, write_out_no_store_sec_char
    sb      t1, 1(a6)
    addi    a4, a4, 1           # second char: pos++
write_out_no_store_sec_char:
    addi    a4, a4, 1           

    addi    a5, a5, 1
    blt     a5, a2, write_out_loop
write_out_loop_end:
    add     t0, a4, a0
    sb      x0, 0(t0)
    addi    a0, x0, 0
    jalr    x0, ra, 0           # return 0
# ---------- write_out (end) ----------