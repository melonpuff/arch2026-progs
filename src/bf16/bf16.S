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
    srli    a1, a0, 15      # a1: sign

    srli    a2, a0, 7       
    andi    a2, a2, 0xFF    # a2: exp

    andi    a3, a0, 0x7F    # a3: mant

    lui     a4, %hi(0x7FC0)
    addi    a4, a4, %lo(0x7FC0) # a4: BF16_NAN
# Handle special cases         
    addi    a6, x0, 0xFF
    bne     a2, a6, bf16_sqrt_asm_not_special_num
    beq     a3, x0, bf16_sqrt_asm_a_is_neg_inf
    jalr    x0, ra, 0       # return a (NaN propagation)
bf16_sqrt_asm_a_is_neg_inf: 
    beq     a1, x0, bf16_sqrt_asm_a_is_pos_inf
    addi    a0, a4, 0
    jalr    x0, ra, 0       # return NaN (sqrt(-Inf) = NaN)
bf16_sqrt_asm_a_is_pos_inf:
    jalr    x0, ra, 0       # return a (sqrt(+Inf) = +Inf)
bf16_sqrt_asm_not_special_num:

 # free: a6
 #  sqrt(0) = 0 (handle both +0 and -0)
    bne     a2, x0, bf16_sqrt_asm_a_not_zero
    bne     a3, x0, bf16_sqrt_asm_a_not_zero 
    addi    a0, x0, 0
    jalr    x0, ra, 0       # return BF16_ZERO
bf16_sqrt_asm_a_not_zero:

# sqrt of negative number is NaN 
    beq     a1, x0, bf16_sqrt_asm_a_is_pos
    addi    a0, a4, 0
    jalr    x0, ra, 0       # return BF16_NAN
bf16_sqrt_asm_a_is_pos:

# Flush denormals to zero
    bne     a2, x0, bf16_sqrt_asm_a_not_dnorm
    addi    a0, x0, 0
    jalr    x0, ra, 0       # return BF16_ZERO
bf16_sqrt_asm_a_not_dnorm:

# free: a0, a4, a6
# For sqrt: new_exp = (old_exp - bias) / 2 + bias 
    addi    a2, a2, -127    # a2: e (exp -> e)
    ori     a3, a3, 0x80    # a3: m (mant -> m)
    andi    a0, a2, 1
    beq     a0, x0, bf16_sqrt_asm_even_exp
    slli    a3, a3, 1
    addi    a2, a2, -1
    srai    a2, a2, 1
    addi    a2, a2, 127
    beq     x0, x0, bf16_sqrt_asm_odd_exp
bf16_sqrt_asm_even_exp:
    srai    a2, a2, 1       
    addi    a2, a2, 127     # a2: nex_exp (e -> nex_exp)
bf16_sqrt_asm_odd_exp:

# free: a0, a4, a6
# Binary search for integer square root
    addi    a4, x0, 128     # a4: low
    addi    a6, x0, 256     # a6: high 
    addi    a0, x0, 128     # a0: result
bf16_sqrt_asm_binary_search_loop:
    add     a7, a4, a6      # a7: mid
    srli    a7, a7, 1
    addi    t0, a7, 0       # t0: a = mid
    addi    t1, a7, 0       # t1: b = mid

    beq     t1, x0, bf16_sqrt_asm_mul_end_loop
    addi    t2, x0, 0       # t2: sq
bf16_sqrt_asm_mul_loop: 
    andi    t3, t1, 1
    beq     t3, x0, bf16_sqrt_asm_mul_no_add
    add     t2, t2, t0
bf16_sqrt_asm_mul_no_add:     
    slli    t0, t0, 1
    srli    t1, t1, 1
    bne     t1, x0, bf16_sqrt_asm_mul_loop
bf16_sqrt_asm_mul_end_loop: 
    srli    t2, t2, 7       # sq / 128
#free: t0, t1
    blt     a3, t2, bf16_sqrt_asm_sq_greater_m
    addi    a0, a7, 0
    addi    a4, a7, 1
    beq     x0, x0, bf16_sqrt_asm_sq_less_equal_m
bf16_sqrt_asm_sq_greater_m:
    addi    a6, a7, -1
bf16_sqrt_asm_sq_less_equal_m:
    bge     a6, a4, bf16_sqrt_asm_binary_search_loop 

# free: a3-a7
# Normalize to ensure result is in [128, 256) 
    addi    a3, x0, 256
    blt     a0, a3, bf16_sqrt_asm_result_no_greater_eq_then_256
    srli    a0, a0, 1
    addi    a2, a2, 1 
bf16_sqrt_asm_result_no_greater_eq_then_256:
    addi    a3, x0, 128
    addi    a4, x0, 1
    bgeu    a2, a3, bf16_sqrt_asm_result_no_smaller_then_256
    bge     a0, a3, bf16_sqrt_asm_result_norm_end_loop
    bge     a4, a2, bf16_sqrt_asm_result_norm_end_loop
bf16_sqrt_asm_result_norm_loop:
    slli    a0, a0, 1
    addi    a2, a2, -1
    bge     a0, a3, bf16_sqrt_asm_result_norm_end_loop
    bge     a4, a2, bf16_sqrt_asm_result_norm_end_loop
    beq     x0, x0, bf16_sqrt_asm_result_norm_loop
bf16_sqrt_asm_result_norm_end_loop:
bf16_sqrt_asm_result_no_smaller_then_256:

# free: a3 - a7
# Extract 7-bit mantissa (remove implicit 1) 
    andi    a0, a0, 0x7f        # a0: new_mant

# Check for overflow/underflow
    addi    a3, x0, 0xFF
    blt     a2, a3, bf16_sqrt_asm_result_no_overflow
    lui     a0, %hi(0x7F80) 
    addi    a0, a0, %lo(0x7F80)
    jalr    x0, ra, 0           # return inf
bf16_sqrt_asm_result_no_overflow:
    blt     x0, a2, bf16_sqrt_asm_result_no_underflow
    addi    a0, x0, 0
    jalr    x0, ra, 0           # return BF16_ZERO
bf16_sqrt_asm_result_no_underflow:
    andi    a2, a2, 0xFF
    slli    a2, a2, 7
    or      a0, a0, a2
    jalr    x0, ra, 0           # return ((new_exp & 0xFF) << 7) | new_mant
.size   bf16_sqrt_asm, .-bf16_sqrt_asm
