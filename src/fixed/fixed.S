# op1, op2, op3 and q_mul: hand-written RV32I.
#
# uint32_t op1_asm(uint32_t a, uint32_t b, int *n)   a0, a1, a2 -> a0
# uint32_t op2_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# uint32_t op3_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# int32_t  q_mul_asm(int32_t a, int32_t b)           a0, a1 -> a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. q_mul forms a 64-bit product in a register pair. Tests:
# tests/tfixed.c.

    .text

    .globl  op1_asm
    .type   op1_asm, @function
    .align  2
op1_asm:
    addi    t1, x0, 0   # t1: n count
    sw      t1, 0(a2)   # *n = 0
    beq     a1, x0, op1_finish
op1_while:
    and     t0, a0, a1  # c = a & b
    slli    t0, t0, 1   # c = (a & b) << 1 
    xor     a0, a0, a1  # a = a ^ b
    addi    a1, t0, 0   # b = c
    addi    t1, t1, 1   # t1 ++
    bne     a1, x0, op1_while
op1_finish:
    sw      t1, 0(a2)
    jalr    x0, ra, 0    # return a
    .size   op1_asm, .-op1_asm

    .globl  op2_asm
    .type   op2_asm, @function
    .align  2
op2_asm:
    sub     a0, a0, a1  # return (a - b)
    jalr    x0, ra, 0 
    .size   op2_asm, .-op2_asm

    .globl  op3_asm
    .type   op3_asm, @function
    .align  2
op3_asm:
    and     t0, a0, a1
    andi    t0, t0, 1
    srli    a0, a0, 1
    srli    a1, a1, 1
    add     a0, a0, a1
    add     a0, a0, t0
    jalr    x0, ra, 0
    .size   op3_asm, .-op3_asm

    .globl  q_mul_asm
    .type   q_mul_asm, @function
    .align  2
q_mul_asm:
    addi    t0, a0, 0           # t0: a 
    addi    t1, a1, 0           # t1: b
    bge     a0, x0, q_mul_pos_a # a0: ua
    sub     a0, x0, a0
q_mul_pos_a:
    bge     a1, x0, q_mul_pos_b # a1: ub
    sub     a1, x0, a1
q_mul_pos_b:
    addi    t2, x0, 0           # t2: ua_hi
    addi    t3, a0, 0           # t3: ua_lo
    addi    t4, x0, 0           # t4: prod_hi
    addi    t5, x0, 0           # t5: prod_lo
    beq     a1, x0, q_mul_end_loop
q_mul_loop: 
    andi    t6, a1, 1           # t6: ub & 1
    beq     t6, x0, q_mul_no_add
    add     t5, t5, t3          # prod_lo += ua_lo
    sltu    t6, t5, t3          # ua_lo > prod_lo
    add     t6, t6, t2          # ua_hi + (ua_lo > prod_lo)
    add     t4, t4, t6          # prod_hi += ua_hi + (ua_lo > prod_lo)
q_mul_no_add: 
    slli    a2, t2, 1           # a2: ua_hi << 1
    srli    a3, t3, 31          # a3: ua_lo >> 31
    or      t2, a2, a3          # ua_hi = (ua_hi << 1) | (ua_lo >> 31);
    slli    t3, t3, 1           # ua_lo <<= 1
    # free (t6, a2, a3 )
    srli    a1, a1, 1           # ub >>= 1
    bne     a1, x0, q_mul_loop
q_mul_end_loop:
    slt     t0, t0, x0
    slt     t1, t1, x0
    beq     t0, t1, q_mul_same_sign
    xor     t4, t4, 0xFFFFFFFF
    xor     t5, t5, 0xFFFFFFFF
    addi    a0, x0, 0xFFFFFFFF
    bne     t5, a0, q_mul_prod_lo_sign_no_OF
    # check if pro_lo overflow after sign changing
    # If so, add 1 to prod_hi
    addi    t4, t4, 1
q_mul_prod_lo_sign_no_OF:
    addi    t5, t5, 1
q_mul_same_sign:
    srli    a1, t5, 19
    andi    a1, a1, 1           # a1: prod_lo[19]
    srli    t5, t5, 20
    add     t5, t5, a1
    # check if pro_lo overflow after rounding
    # Even if prod_lo overflow (t5 = 0x1000)
    # Add it to prod_hi will take care of that 
    slli    t4, t4, 12
    add     a0, t4, t5
    jalr    x0, ra, 0
    .size   q_mul_asm, .-q_mul_asm
