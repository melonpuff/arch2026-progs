#include "rubik.h"
#define MAX_DEPTH 11

// state : a 14 digit state, e.g. "12345671111111"
// uint32_t rank = ((uint32_t) p_rank << 10) | o_rank (o_rank uses 10 bits)
extern const uint8_t perm_heuristic[5040];
extern const uint8_t ori_heuristic[729];
extern const uint16_t
    perm_transition_flat[24576];  // perm_transition_flat[3][2^13]
extern const uint16_t
    ori_transition_flat[3072];  // ori_transition_flat[3][2^10]
extern const uint32_t in_step_5[12224];
extern const uint32_t step_11[2644];


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


#define NOT_FOUND 255
#define SOLVED_MOVE 15  // the move stored for the solved state

uint8_t binary_search(uint32_t rank, const uint32_t *table, int size)
{
    int low = 0;
    int high = size - 1;
    while (low <= high) {
        int mid = (low + high) >> 1;
        uint32_t entry = table[mid];
        uint32_t entry_rank = entry & 0x7FFFFF;  // low 23 bits
        if (entry_rank == rank)
            return (uint8_t) ((entry >> 23) & 0xF);  // bits 26..23: move
        if (entry_rank < rank)
            low = mid + 1;
        else
            high = mid - 1;
    }
    return NOT_FOUND;
}

// Turn the cube by one move: update p_rank and o_rank.
void apply_move(uint16_t *p_rank, uint16_t *o_rank, uint8_t move)
{
    uint8_t face = face_table[move];
    uint8_t turns = turns_table[move];
    for (int i = 0; i < turns; ++i) {
        *p_rank = perm_transition_flat[(face << 13) + *p_rank];
        *o_rank = ori_transition_flat[(face << 10) + *o_rank];
    }
}

// The state is within 5 moves: follow the moves of in_step_5 until the
// solved state, writing them to path. Return the number of moves.
int follow_table(uint16_t p_rank, uint16_t o_rank, uint8_t *path)
{
    int count = 0;
    uint32_t rank = ((uint32_t) p_rank << 10) | o_rank;
    uint8_t move = binary_search(rank, in_step_5, 12224);
    while (move != SOLVED_MOVE) {
        path[count] = move;
        count++;
        apply_move(&p_rank, &o_rank, move);
        rank = ((uint32_t) p_rank << 10) | o_rank;
        move = binary_search(rank, in_step_5, 12224);
    }
    return count;
}

int solve(uint16_t p_rank, uint16_t o_rank, uint8_t *path)
{
    // 1. Within 5 moves: the table gives the whole solution.
    uint32_t rank = ((uint32_t) p_rank << 10) | o_rank;
    if (binary_search(rank, in_step_5, 12224) != NOT_FOUND)
        return follow_table(p_rank, o_rank, path);

    // Not within 5 moves, so the distance is at least 6.
    uint8_t bound = get_heuristic(p_rank, o_rank);
    if (bound < 6)
        bound = 6;

    // 2. Distance 11: the table gives the first move, to a distance-10 state.
    int first = 0;  // moves fixed before the search: 0 or 1
    int8_t first_face = -1;
    uint8_t move = binary_search(rank, step_11, 2644);
    if (move != NOT_FOUND) {  // is distance 11
        path[0] = move;
        first = 1;
        first_face = (int8_t) face_table[move];
        apply_move(&p_rank, &o_rank, move);
        bound = 10;  // the distance is now exactly 10
    }

    // 3. IDA*: expand a node while more than 5 moves remain; with exactly 5
    // left, look it up in in_step_5 instead.
    StackNode stack[MAX_DEPTH + 1];

    for (; bound + first <= MAX_DEPTH; ++bound) {
        int8_t depth = 0;
        stack[0].p_rank = p_rank;
        stack[0].o_rank = o_rank;
        stack[0].g = 0;
        stack[0].last_face = first_face;
        stack[0].move_index = 0;

        while (depth >= 0) {
            uint8_t remaining = bound - stack[depth].g;

            if (remaining == 5) {
                if (get_heuristic(stack[depth].p_rank, stack[depth].o_rank) >
                    5) {
                    depth--;
                    continue;
                }
                uint32_t node_rank = ((uint32_t) stack[depth].p_rank << 10) |
                                     stack[depth].o_rank;
                if (binary_search(node_rank, in_step_5, 12224) != NOT_FOUND) {
                    // Found: the moves on the stack, then the table's moves.
                    for (int8_t k = 0; k < depth; k++)
                        path[first + k] = stack[k].move_index - 1;
                    int tail =
                        follow_table(stack[depth].p_rank, stack[depth].o_rank,
                                     path + first + depth);
                    return first + depth + tail;
                }
                depth--;  // more than 5 moves away: no solution within bound
                continue;
            }

            uint8_t h = get_heuristic(stack[depth].p_rank, stack[depth].o_rank);
            if (h > remaining) {
                depth--;
                continue;
            }

            if (stack[depth].move_index < 9) {
                uint8_t face = face_table[stack[depth].move_index];
                if (face == stack[depth].last_face) {
                    stack[depth].move_index += 3;
                    continue;
                }
                uint8_t next_move = stack[depth].move_index;
                stack[depth].move_index++;

                uint16_t next_p = stack[depth].p_rank;
                uint16_t next_o = stack[depth].o_rank;
                apply_move(&next_p, &next_o, next_move);
                depth++;
                stack[depth].p_rank = next_p;
                stack[depth].o_rank = next_o;
                stack[depth].g = stack[depth - 1].g + 1;
                stack[depth].last_face = (int8_t) face;
                stack[depth].move_index = 0;
            } else {
                depth--;
            }
        }
    }
    return -1;  // not reached: every valid state is within 11 moves
}

int rubik_solve(const char *state, char *out, size_t cap)
{
    if (validate(state))
        return -1;
    uint16_t p_rank = 0, o_rank = 0;
    encode(state, &p_rank, &o_rank);
    uint8_t path[MAX_DEPTH];
    int depth = solve(p_rank, o_rank, path);
    if (write_out(out, cap, depth, path))
        return -2;
    return depth;
}
