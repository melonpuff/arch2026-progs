#include "gcd.h"

uint32_t gcd_u32(uint32_t a, uint32_t b)
{
    int shared_twos = 0;
    /* gdc (a, b) */
    while (a != 0 && b != 0) {
        /* 1. a is even, b is even */
        int e = a | b;
        if (!(e & 1)) {
            a >>= 1;
            b >>= 1;
            shared_twos++;
            continue;
        }
        /* 2. a is even, b is odd */
        if (!(a & 1)) {
            a >>= 1;
            continue;
        }
        /* 3. a is odd, b is even */
        if (!(b & 1)) {
            b >>= 1;
            continue;
        }
        /* 4. a is odd, b is odd */
        if (a >= b) {
            a -= b;
        } else {
            b -= a;
        }
    }
    if (a == 0)
        return (b << shared_twos);
    return a << shared_twos;
}
