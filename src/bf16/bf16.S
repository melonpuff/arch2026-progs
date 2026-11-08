# BFloat16 routines: hand-written RV32I.
#
# uint16_t bf16_from_f32_asm(uint32_t f32bits)   a0 -> a0
# uint16_t bf16_mul_asm(uint16_t a, uint16_t b)  a0, a1 -> a0
# uint16_t bf16_sqrt_asm(uint16_t a)             a0 -> a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. Tests: tests/tbf16.c.

    .text

    .globl  bf16_from_f32_asm
    .type   bf16_from_f32_asm, @function
    .align  2
bf16_from_f32_asm:
    lui     t0, 0x7f800
    and     t1, a0, t0
    bne     t1, t0, bf16_from_f32_asm_not_speical
    srli    a0, a0, 16
    jalr    x0, ra, 0
bf16_from_f32_asm_not_speical:
    srli    t0, a0, 16      # f32bits >> 16
    andi    t0, t0, 1       # a0: (f32bits >> 16) & 1
    lui     a1, 0x00008     
    addi    a1, a1, -1      # a1: 0x00008000 + 0xFFF
    add     a0, a0, t0
    add     a0, a0, a1      
    srli    a0, a0, 16
    jalr    x0, ra, 0
    .size   bf16_from_f32_asm, .-bf16_from_f32_asm

    .globl  bf16_mul_asm
    .type   bf16_mul_asm, @function
    .align  2
bf16_mul_asm:
    srli    a2, a0, 15      # a2: sign_a
    srli    a3, a1, 15      # a3: sign_b

    srli    a4, a0, 7
    andi    a4, a4, 0xFF    # a4: exp_a
    srli    a5, a1, 7
    andi    a5, a5, 0xFF    # a5: exp_b

    andi    a6, a0, 0x7F    # a6: mant_a
    andi    a7, a1, 0x7F    # a7: mant_b 

    # t0: NaN (0x7FC0)
    lui   t0, %hi(0x7FC0)
    addi  t0, t0, %lo(0x7FC0)

    xor     a2, a2, a3      # a2: result_sign
    # free: a3
    # a0: a, a1: b
    # a speical case
    addi    a3, x0, 0xFF
    bne     a4, a3, bf16_mul_asm_a_not_special
    beq     a6, x0, bf16_mul_asm_a_is_inf
    jalr    x0, ra, 0       # return a
bf16_mul_asm_a_is_inf:
    bne     a5, x0, bf16_mul_asm_a_is_special_ret_inf
    bne     a7, x0, bf16_mul_asm_a_is_special_ret_inf
    addi    a0, t0, 0
    jalr    x0, ra, 0       # return NaN
bf16_mul_asm_a_is_special_ret_inf: 
    slli    a0, a2, 15
    lui     t0, %hi(0x7F80)
    addi    t0, t0, %lo(0x7F80)
    or      a0, a0, t0
    jalr    x0, ra, 0       # return result_sign << 15 | 0x7F80
bf16_mul_asm_a_not_special: 
    # b speical case
    bne     a5, a3, bf16_mul_asm_b_not_special
    beq     a7, x0, bf16_mul_asm_b_is_inf
    addi    a0, a1, 0
    jalr    x0, ra, 0
bf16_mul_asm_b_is_inf:
    bne     a4, x0, bf16_mul_asm_b_is_special_ret_inf
    bne     a6, x0, bf16_mul_asm_b_is_special_ret_inf
    addi    a0, t0, 0
    jalr    x0, ra, 0       # return NaN
bf16_mul_asm_b_is_special_ret_inf:    
    slli    a0, a2, 15
    lui     t0, %hi(0x7F80)
    addi    t0, t0, %lo(0x7F80)
    or      a0, a0, t0
    jalr    x0, ra, 0       # return result_sign << 15 | 0x7F80
bf16_mul_asm_b_not_special: 

    # free: a3
    # a is +- 0 or b is +- 0
    or      a3, a4, a6
    beq     a3, x0, bf16_mul_asm_ab_is_zero
    or      a3, a5, a7
    beq     a3, x0, bf16_mul_asm_ab_is_zero
    beq     x0, x0, bf16_mul_asm_ab_not_zero
bf16_mul_asm_ab_is_zero: 
    slli    a0, a2, 15
    jalr    x0, ra, 0
bf16_mul_asm_ab_not_zero:

    # denormal a
    addi    a3, x0, 0       # a3: exp_adjust
    bne     a4, x0, bf16_mul_asm_exp_a_not_zero
    andi    t0, a6, 0x80
    bne     t0, x0, bf16_mul_asm_denorm_a_end_loop
bf16_mul_asm_denorm_a_loop:
    slli    a6, a6, 1
    addi    a3, a3, -1
    andi    t0, a6, 0x80
    beq     t0, x0, bf16_mul_asm_denorm_a_loop
bf16_mul_asm_denorm_a_end_loop:
    addi    a4, a4, 1
bf16_mul_asm_exp_a_not_zero:
    ori     a6, a6, 0x80

    # denormal b
    bne     a5, x0, bf16_mul_asm_exp_b_not_zero
    andi    t0, a7, 0x80
    bne     t0, x0, bf16_mul_asm_denorm_b_end_loop
bf16_mul_asm_denorm_b_loop:
    slli    a7, a7, 1
    addi    a3, a3, -1
    andi    t0, a7, 0x80
    beq     t0, x0, bf16_mul_asm_denorm_b_loop
bf16_mul_asm_denorm_b_end_loop:
    addi    a5, a5, 1
bf16_mul_asm_exp_b_not_zero:
    ori     a7, a7, 0x80

 # result_mant = mant_a * mant_b 
 # a0: result_mant
    addi    a0, x0, 0
    beq     a7, x0, bf16_mul_asm_mul_end_loop
bf16_mul_asm_mul_loop:
    andi    t0, a7, 1
    beq     t0, x0, bf16_mul_asm_mul_iter_no_add
    add     a0, a0, a6          # result_mant += mant_a
bf16_mul_asm_mul_iter_no_add:    
    srli    a7, a7, 1
    slli    a6, a6, 1
    bne  a7, x0, bf16_mul_asm_mul_loop
bf16_mul_asm_mul_end_loop:
    # a3: result_exp (from exp_adjust)
    add     a3, a3, a4          # exp_adjust + exp_a
    add     a3, a3, a5          # exp_adjust + exp_b
    addi    a3, a3, -127        # - bias

# product >= 2.0: shift one more bit, exponent + 1
# (a0: result_mant)
    lui     t0, 0x8
    and     t0, a0, t0
    beq     t0, x0, bf16_mul_asm_result_mant_less_than_2    
    srli    a0, a0, 8
    andi    a0, a0, 0x7F
    addi    a3, a3, 1           # result_exp ++
    beq     x0, x0, bf16_mul_asm_mant_greater_eq_than_2
bf16_mul_asm_result_mant_less_than_2:
    srli    a0, a0, 7
    andi    a0, a0, 0x7F
bf16_mul_asm_mant_greater_eq_than_2:

# overflow: +-Inf
    addi    t0, x0, 0xFF
    blt     a3, t0, bf16_mul_asm_no_OF_inf
    lui     t0, %hi(0x7F80)
    addi    t0, t0, %lo(0x7F80)
    slli    a0, a2, 15
    or      a0, a0, t0
    jalr    x0, ra, 0       # return result_sign << 15 | 0x7F80
bf16_mul_asm_no_OF_inf:
    blt     x0, a3, bf16_mul_asm_result_exp_greater_then_zero
    addi    t0, x0, -6
    bge     a3, t0, bf16_mul_asm_result_exp_no_to_zero   
    slli    a0, a2, 15
    jalr    x0, ra, 0       # return +- 0
bf16_mul_asm_result_exp_no_to_zero:
    addi    t0, x0, 1
    sub     t0, t0, a3      # 1 - result_exp
    srl     a0, a0, t0      # result_mant >>= (1 - result_exp)
    addi    a3, x0, 0       # result_exp = 0
bf16_mul_asm_result_exp_greater_then_zero: 
    slli    a2, a2, 15      # result_sign << 15
    slli    a3, a3, 7       # result_exp << 7
    or      a0, a0, a2
    or      a0, a0, a3
    jalr    x0, ra, 0
    .size   bf16_mul_asm, .-bf16_mul_asm

    .globl  bf16_sqrt_asm
    .type   bf16_sqrt_asm, @function
    .align  2
bf16_sqrt_asm:
    li      a0, 0
    ret
    .size   bf16_sqrt_asm, .-bf16_sqrt_asm
