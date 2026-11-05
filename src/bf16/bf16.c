#include "bf16.h"

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
    (void) a;
    (void) b;

    return 0;
}

uint16_t bf16_sqrt(uint16_t a)
{
    (void) a;
    return 0;
}
