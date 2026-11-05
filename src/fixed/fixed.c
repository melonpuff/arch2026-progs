#include "fixed.h"

uint32_t op1(uint32_t a, uint32_t b, int *n)
{
    *n = 0;
    while (b) {
        unsigned c = (a & b) << 1;
        a = a ^ b;
        b = c;
        ++*n;
    }
    return a;
}

uint32_t op2(uint32_t a, uint32_t b)
{
    return a - b;
}

uint32_t op3(uint32_t a, uint32_t b)
{
    return (a >> 1) + (b >> 1) + (a & b & 1);
}

int32_t q_mul(int32_t a, int32_t b)
{
    uint32_t ua = a < 0 ? -(uint32_t) a : (uint32_t) a; /* |a| */
    uint32_t ub = b < 0 ? -(uint32_t) b : (uint32_t) b;
    uint32_t ua_hi = 0, ua_lo = ua, prod_hi = 0, prod_lo = 0;
    while (ub) {
        if (ub & 1) {
            prod_lo += ua_lo;
            /* ua_lo > prod_lo == 1 when overflow */
            prod_hi += ua_hi + (ua_lo > prod_lo);
        }
        ua_hi = (ua_hi << 1) | (ua_lo >> 31);
        ua_lo <<= 1;
        ub >>= 1;
    }
    uint64_t prod = (uint64_t) prod_hi << 32 | prod_lo;
    /* a and b have different sign */
    if ((a < 0) != (b < 0))
        prod = ~prod + 1;
    /* rounding */
    prod += 1 << (Q - 1);
    prod >>= Q;
    return (int32_t) prod;
}
