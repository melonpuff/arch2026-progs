#include "rubik.h"
#define MAX_DEPTH 11

// state : a 14 digit state, e.g. "12345671111111"
// If the innitial state is invalid, return -1
// out: moves (with a '\0' at the back), e.g. "R2, B "
// cap: check if out is the shortest move, if out > cap, return -2
extern const uint8_t perm_heuristic[5040];
extern const uint8_t ori_heuristic[729];
extern const uint16_t
    perm_transition_flat[24576];  // perm_transition_flat[3][2^13]
extern const uint16_t
    ori_transition_flat[3072];  // ori_transition_flat[3][2^10]


// Lookup tables to eliminate division and modulo for move generation
const uint8_t face_table[9] = {0, 0, 0, 1, 1, 1, 2, 2, 2};
const uint8_t turns_table[9] = {1, 2, 3, 1, 2, 3, 1, 2, 3};

const char *const move_names[9] = {"R",  "R2", "R'", "B", "B2",
                                   "B'", "D",  "D2", "D'"};
const uint8_t name_len[9] = {1, 2, 2, 1, 2, 2, 1, 2, 2};

typedef struct {
    uint16_t p_rank;
    uint16_t o_rank;
    uint8_t g;
    int8_t last_face;
    uint8_t move_index;  // the move that this node is going to try next
} StackNode;

int validate(const char *state)
{
    uint8_t seen = 0, sum = 0;
    for (int i = 0; i < 7; ++i) {
        uint8_t p = (uint8_t) (state[i] - '1');
        if (p >= 7)
            return 1;
        uint8_t mask = (1U << p);
        if (seen & mask)
            return 1;  // duplicate
        seen |= mask;
    }
    for (int i = 7; i < 14; ++i) {
        uint8_t o = (uint8_t) (state[i] - '1');
        if (o >= 3)
            return 1;
        sum += o;
    }
    if (state[14] != '\0')
        return 1;
    while (sum > 2) {
        sum -= 3;
    }

    return sum != 0;
}

void encode(const char *state, uint16_t *p_rank, uint16_t *o_rank)
{
    uint16_t p = 0, o = 0;

    for (int i = 0; i < 6; ++i) {
        uint16_t smaller = 0;
        for (int j = i + 1; j <= 6; ++j) {
            smaller += state[j] < state[i];
        }
        // multiply
        uint16_t prod = 0;
        uint16_t a = p;
        uint16_t b = (uint16_t) 7 - i;
        while (b) {
            if (b & 1)
                prod += a;
            b >>= 1;
            a <<= 1;
        }
        p = prod + smaller;
    }

    for (int i = 0; i < 6; i++) {
        o = (uint16_t) ((o << 1) + o + (state[i + 7] - '1'));  // o * 3 + digit
    }  // i = 6 adds nothing: no cubie to its right, and the multiplier is 1

    *p_rank = p;
    *o_rank = o;
    return;
}

uint8_t get_heuristic(uint16_t p_rank, uint16_t o_rank)
{
    uint8_t p_h = perm_heuristic[p_rank];
    uint8_t o_h = ori_heuristic[o_rank];
    return (p_h > o_h) ? p_h : o_h;
}

int solve_ida_star(uint16_t initial_p_rank,
                   uint16_t initial_o_rank,
                   uint8_t *path)
{
    uint8_t initial_h = get_heuristic(initial_p_rank, initial_o_rank);
    if (initial_h == 0) {
        return 0;
    }

    StackNode stack[MAX_DEPTH + 1];

    for (uint8_t bound = initial_h; bound <= MAX_DEPTH; ++bound) {
        int8_t depth =
            0;  // Index of the top node; also its distance from the start
        stack[0].p_rank = initial_p_rank;
        stack[0].o_rank = initial_o_rank;
        stack[0].g = 0;
        stack[0].last_face = -1;
        stack[0].move_index = 0;

        while (depth >= 0) {
            uint8_t h = get_heuristic(stack[depth].p_rank, stack[depth].o_rank);

            if (h == 0) {  // Goal found
                for (int8_t k = 0; k < depth; k++)
                    path[k] = stack[k].move_index -
                              1;  // move_index is incremented before child is
                                  // push to stack
                return depth;
            }

            if (stack[depth].g + h > bound) {
                depth--;
                continue;
            }

            if (stack[depth].move_index < 9) {
                uint8_t face = face_table[stack[depth].move_index];
                uint8_t turns = turns_table[stack[depth].move_index];

                if (face == stack[depth].last_face) {
                    stack[depth].move_index += 3;
                    continue;
                }

                stack[depth].move_index++;

                uint16_t next_p = stack[depth].p_rank;
                uint16_t next_o = stack[depth].o_rank;
                for (int i = 0; i < turns; ++i) {
                    next_p = perm_transition_flat[(face << 13) + next_p];
                    next_o = ori_transition_flat[(face << 10) + next_o];
                }
                depth++;
                stack[depth].p_rank = next_p;
                stack[depth].o_rank = next_o;
                stack[depth].g =
                    stack[depth - 1].g + 1;  // child is one move deeper
                stack[depth].last_face = face;
                stack[depth].move_index = 0;
            } else {
                depth--;
            }
        }
    }
    return -1;
}

int write_out(char *out, const size_t cap, const int depth, const uint8_t *path)
{
    size_t need = 1;
    for (int i = 0; i < depth; i++) {
        if (i > 0)
            need += 1;
        need += name_len[path[i]];
    }

    if (need > cap) {
        if (cap >= 1)
            out[0] = '\0';
        return 1;
    }

    int pos = 0;
    for (int i = 0; i < depth; i++) {
        if (i > 0) {
            out[pos] = ' ';
            pos++;
        }
        const char *name = move_names[path[i]];
        for (int j = 0; j < name_len[path[i]]; j++) {
            out[pos] = name[j];
            pos++;
        }
    }
    out[pos] = '\0';
    return 0;
}


int rubik_solve(const char *state, char *out, size_t cap)
{
    if (validate(state))
        return -1;
    uint16_t p_rank = 0, o_rank = 0;
    encode(state, &p_rank, &o_rank);
    uint8_t path[MAX_DEPTH];
    int depth = solve_ida_star(p_rank, o_rank, path);
    if (write_out(out, cap, depth, path))
        return -2;
    return depth;
}
