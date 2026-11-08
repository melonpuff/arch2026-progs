#include "bf16.h"

#define BF16_NAN 0x7FC0
#define BF16_EXP_BIAS 127

uint16_t bf16_from_f32(uint32_t f32bits)
{
    if (((f32bits >> 23) & 0xFF) == 0xFF) {
        return (uint16_t) (f32bits >> 16);
    }
    f32bits += ((f32bits >> 16) & 1) + 0x7FFF;
    return (uint16_t) (f32bits >> 16);
}

uint16_t bf16_mul(uint16_t a, uint16_t b)
{
    uint16_t sign_a = a >> 15 & 1;
    uint16_t sign_b = b >> 15 & 1;
    int16_t exp_a = a >> 7 & 0xFF;
    int16_t exp_b = b >> 7 & 0xFF;
    uint16_t mant_a = a & 0x7F;
    uint16_t mant_b = b & 0x7F;

    uint16_t result_sign = sign_a ^ sign_b;

    if (exp_a == 0xFF) {
        if (mant_a) /* a = NaN */
            return a;
        /* a = Inf */
        if (!exp_b && !mant_b) /* b = +-0 */
            return BF16_NAN;
        return result_sign << 15 | 0x7F80;
    }
    if (exp_b == 0xFF) {
        if (mant_b) /* b = NaN */
            return b;
        /* b = Inf */
        if (!exp_a && !mant_a) /* a = +-0 */
            return BF16_NAN;
        return result_sign << 15 | 0x7F80;
    }
    /* a = +-0 or b = +-0 */
    if ((!exp_a && !mant_a) || (!exp_b && !mant_b))
        return result_sign << 15;

    int32_t exp_adjust = 0;
    /* If a is a denormal, normalize it */
    if (!exp_a) {
        while (!(mant_a & 0x80)) { /* until mant_a[7] == 1 */
            mant_a <<= 1;
            exp_adjust--;
        }
        exp_a = 1; /* biased 1: exponent -126 */
    } else {
        mant_a |= 0x80; /* normal a: restore the hidden 1 in mant_a[7] */
    }

    /* If b is a denormal, normalize it */
    if (!exp_b) {
        while (!(mant_b & 0x80)) { /* until mant_b[7] == 1 */
            mant_b <<= 1;
            exp_adjust--;
        }
        exp_b = 1; /* biased 1: exponent -126 */
    } else {
        mant_b |= 0x80; /* normal b: restore the hidden 1 in mant_b[7] */
    }

    /* result_mant = mant_a * mant_b */
    uint32_t result_mant = 0;
    while (mant_b) {
        if (mant_b & 1)
            result_mant += (uint32_t) mant_a;
        mant_b >>= 1;
        mant_a <<= 1;
    }
    int32_t result_exp = (int32_t) exp_a + exp_b - BF16_EXP_BIAS + exp_adjust;

    /* product >= 2.0: shift one more bit, exponent + 1 */
    if (result_mant & 0x8000) {
        result_mant = (result_mant >> 8) & 0x7F;
        result_exp++;
    } else
        result_mant = (result_mant >> 7) & 0x7F;

    /* overflow: +-Inf */
    if (result_exp >= 0xFF)
        return (uint16_t) (result_sign << 15) | 0x7F80;

    if (result_exp <= 0) {
        if (result_exp < -6)
            return (uint16_t) result_sign << 15;
        result_mant >>= (1 - result_exp);
        result_exp = 0;
    }
    return (uint16_t) (result_sign << 15) | ((result_exp & 0xFF) << 7) |
           (result_mant & 0x7F);
}

uint16_t bf16_sqrt(uint16_t a)
{
    (void) a;
    return 0;
}
