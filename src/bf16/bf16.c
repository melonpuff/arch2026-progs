#include "bf16.h"

#define BF16_NAN 0x7FC0
#define BF16_ZERO 0x0000
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
    uint16_t sign = (a >> 15) & 1;
    int16_t exp = ((a >> 7) & 0xFF);
    uint16_t mant = a & 0x7F;

    /* Handle special cases */
    if (exp == 0xFF) {
        if (mant)
            return a; /* NaN propagation */
        if (sign)
            return BF16_NAN; /* sqrt(-Inf) = NaN */
        return a;            /* sqrt(+Inf) = +Inf */
    }
    /* sqrt(0) = 0 (handle both +0 and -0) */
    if (!exp && !mant)
        return BF16_ZERO;

    /* sqrt of negative number is NaN */
    if (sign)
        return BF16_NAN;

    /* Flush denormals to zero */
    if (!exp)
        return BF16_ZERO;

    /* Direct bit manipulation square root algorithm */
    /* For sqrt: new_exp = (old_exp - bias) / 2 + bias */
    int32_t e = exp - BF16_EXP_BIAS;
    int32_t new_exp;

    /* Get full mantissa with implicit 1 */
    uint32_t m = 0x80 | mant; /* Range [128, 256) representing [1.0, 2.0) */

    /* Adjust for odd exponents: sqrt(2^odd * m) = 2^((odd-1)/2) * sqrt(2*m) */
    if (e & 1) {
        m <<= 1; /* Double mantissa for odd exponent */
        new_exp = ((e - 1) >> 1) + BF16_EXP_BIAS;
    } else {
        new_exp = (e >> 1) + BF16_EXP_BIAS;
    }

    /* Now m is in range [128, 256) or [256, 512) if exponent was odd */
    /* Binary search for integer square root */
    /* We want result where result^2 = m * 128 (since 128 represents 1.0) */

    uint32_t low = 128;    /* Min sqrt (sqrt(128 * 128)) */
    uint32_t high = 256;   /* Max sqrt (sqrt(512 * 128)) */
    uint32_t result = 128; /* Default */

    /* Binary search for square root of m */
    while (low <= high) {
        uint32_t mid = (low + high) >> 1;
        uint32_t sq = (mid * mid) / 128; /* Square and scale */

        if (sq <= m) {
            result = mid; /* This could be our answer */
            low = mid + 1;
        } else {
            high = mid - 1;
        }
    }


    /* Since m is scaled where 128=1.0, result should also be scaled same way */

    /* Normalize to ensure result is in [128, 256) */
    if (result >= 256) {
        result >>= 1;
        new_exp++;
    } else if (result < 128) {
        while (result < 128 && new_exp > 1) {
            result <<= 1;
            new_exp--;
        }
    }

    /* Extract 7-bit mantissa (remove implicit 1) */
    uint16_t new_mant = result & 0x7F;

    /* Check for overflow/underflow */
    if (new_exp >= 0xFF)
        return (uint16_t) 0x7F80; /* +Inf */
    if (new_exp <= 0)
        return BF16_ZERO;

    return (uint16_t) ((new_exp & 0xFF) << 7) | new_mant;
}
