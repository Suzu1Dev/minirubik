/* ida_core.c - written with AI assistance (Claude Code); see docs/ai-assistance.md */
/*
 * IDA* search core (design chosen by the student, see c/README.md):
 *   - bound starts at h(start); each iteration is a depth-first search that
 *     cuts any node with g + h > bound; if nothing is found, bound += 1;
 *   - h(p, o) = max(pdb_p[p], pdb_o[o]);
 *   - same-face pruning only: after the first move, the face of the move
 *     that reached a node is not tried again from that node;
 *   - X, X2, X' of a face are 1, 2, 3 chained applications of the face's
 *     quarter-turn table (as in upstream build_table());
 *   - no recursion: an explicit stack of IDA_LEVELS (12) levels.
 *
 * Freestanding: only <stdint.h>; no libc, no heap, no recursion, no divide
 * or modulo, and every multiply is by a compile-time constant (gcc lowers
 * those to shifts and adds; scripts/refbuild.sh audits for __mulsi3 etc.).
 */
#include "ida_core.h"

#ifdef IDA_STATS
uint32_t ida_expanded;
uint32_t ida_generated;
#define STAT_INC(x) ((x)++)
#else
#define STAT_INC(x) ((void) 0)
#endif

int ida_parse(const char *s, uint32_t *p_rank, uint32_t *o_rank)
{
    uint32_t p[7], o[7], smaller[6];
    uint32_t i, j, sum, pr, orr;

    /* Characters: '1'..'7' for the 7 cubie digits, '1'..'3' for the 7
     * orientation digits (upstream parse_state); stop at the first bad
     * byte, so a short string fails on its NUL and nothing past it is read. */
    for (i = 0; i < 14; ++i) {
        uint32_t c = (uint8_t) s[i];
        uint32_t limit = i < 7 ? '7' : '3';
        if (c < '1' || c > limit)
            return 0;
        if (i < 7)
            p[i] = c - '1';
        else
            o[i - 7] = c - '1';
    }
    if (s[14] != '\0')
        return 0;

    /* Distinct cubies (upstream valid()). */
    for (i = 1; i < 7; ++i)
        for (j = 0; j < i; ++j)
            if (p[j] == p[i])
                return 0;

    /* Orientation sum must be a multiple of 3.  sum <= 14, so reduce it by
     * repeated subtraction instead of a modulo. */
    sum = o[0] + o[1] + o[2] + o[3] + o[4] + o[5] + o[6];
    while (sum >= 3)
        sum -= 3;
    if (sum != 0)
        return 0;

    /* Lehmer code: smaller[i] = number of j > i with p[j] < p[i]
     * (smaller[6] is always 0 and is not needed). */
    for (i = 0; i < 6; ++i) {
        smaller[i] = 0;
        for (j = i + 1; j < 7; ++j)
            if (p[j] < p[i])
                ++smaller[i];
    }
    /* Upstream: p = p * (7 - i) + smaller[i] for i = 0..6.  Unrolled so
     * every multiplier is a constant (the i = 6 step is p * 1 + 0). */
    pr = smaller[0];
    pr = pr * 6 + smaller[1];
    pr = pr * 5 + smaller[2];
    pr = pr * 4 + smaller[3];
    pr = pr * 3 + smaller[4];
    pr = pr * 2 + smaller[5];

    /* Base-3 orientation rank of o[0..5] (o[6] is implied by the sum). */
    orr = o[0];
    for (i = 1; i < 6; ++i)
        orr = orr * 3 + o[i];

    *p_rank = pr;
    *o_rank = orr;
    return 1;
}

int ida_apply_move(uint32_t *p_rank, uint32_t *o_rank, uint32_t move)
{
    uint32_t face = 0, turn = move, p = *p_rank, o = *o_rank;
    if (move >= IDA_MOVES)
        return 0;
    /* face = move / 3, turn = move % 3, by subtraction. */
    while (turn >= 3) {
        turn -= 3;
        ++face;
    }
    /* turn + 1 chained quarter turns of face. */
    for (;;) {
        p = perm_qt[face][p];
        o = orient_qt[face][o];
        if (turn == 0)
            break;
        --turn;
    }
    *p_rank = p;
    *o_rank = o;
    return 1;
}

int ida_apply_path(uint32_t p_rank, uint32_t o_rank, const uint8_t *path,
                   uint32_t len)
{
    uint32_t i;
    for (i = 0; i < len; ++i)
        if (!ida_apply_move(&p_rank, &o_rank, path[i]))
            return 0;
    return p_rank == 0 && o_rank == 0;
}

/*
 * Explicit search stack, one entry per depth k = 0..IDA_MAX_DEPTH.
 *   lv_p[k], lv_o[k]  ranks of the node at depth k on the current path
 *   lv_move[k]        move (0..8) that produced depth k from depth k-1
 *                     (k >= 1; this is path[k-1] when a solution is found)
 *   lv_face[k]        face currently being tried from depth k (0..2);
 *                     3 = every face tried
 *   lv_turn[k]        quarter turns of lv_face[k] already applied (0..3);
 *                     the next child to try is move 3 * lv_face[k] +
 *                     lv_turn[k], i.e. one more quarter turn
 * The child of depth k is always written to lv_p[k+1]/lv_o[k+1], also when
 * it is cut off, so the next turn of the same face chains from it.
 * The face of the move that reached depth k (k >= 1) is lv_face[k-1];
 * same-face pruning compares against it.
 */
static uint16_t lv_p[IDA_LEVELS];
static uint16_t lv_o[IDA_LEVELS];
static uint8_t lv_move[IDA_LEVELS];
static uint8_t lv_face[IDA_LEVELS];
static uint8_t lv_turn[IDA_LEVELS];

static uint32_t heuristic(uint32_t p, uint32_t o)
{
    uint32_t hp = pdb_p[p], ho = pdb_o[o];
    return hp > ho ? hp : ho;
}

int ida_solve(uint32_t p_rank, uint32_t o_rank, uint8_t path[IDA_MAX_DEPTH])
{
    uint32_t bound, k, f, t, cp, co, g, h, i;

#ifdef IDA_STATS
    ida_expanded = 0;
    ida_generated = 0;
#endif
    if (p_rank == 0 && o_rank == 0)
        return 0; /* already solved: empty solution */

    lv_p[0] = (uint16_t) p_rank;
    lv_o[0] = (uint16_t) o_rank;
    for (bound = heuristic(p_rank, o_rank); bound <= IDA_MAX_DEPTH; ++bound) {
        /* One depth-first iteration under this bound, from the root. */
        k = 0;
        lv_face[0] = 0;
        lv_turn[0] = 0;
        STAT_INC(ida_expanded);
        for (;;) {
            /* Pick the next child of depth k. */
            f = lv_face[k];
            t = lv_turn[k];
            if (t == 3) { /* all three turns of face f done: next face */
                ++f;
                t = 0;
            }
            if (t == 0 && k != 0 && f == lv_face[k - 1])
                ++f; /* same-face pruning */
            if (f == 3) { /* every child of depth k tried: backtrack */
                if (k == 0)
                    break; /* iteration exhausted, raise the bound */
                --k;
                continue;
            }

            /* Child = one more quarter turn of face f: from depth k for the
             * first turn, else from the previous turn's child at k+1. */
            if (t == 0) {
                cp = lv_p[k];
                co = lv_o[k];
            } else {
                cp = lv_p[k + 1];
                co = lv_o[k + 1];
            }
            cp = perm_qt[f][cp];
            co = orient_qt[f][co];
            lv_p[k + 1] = (uint16_t) cp;
            lv_o[k + 1] = (uint16_t) co;
            lv_face[k] = (uint8_t) f;
            lv_turn[k] = (uint8_t) (t + 1);
            STAT_INC(ida_generated);

            g = k + 1;
            h = heuristic(cp, co);
            if (g + h > bound)
                continue; /* cut off */
            lv_move[g] = (uint8_t) (3 * f + t);
            if (cp == 0 && co == 0) { /* solved: path = lv_move[1..g] */
                for (i = 0; i < g; ++i)
                    path[i] = lv_move[i + 1];
                return (int) g;
            }

            /* Descend into the child. */
            k = g;
            lv_face[k] = 0;
            lv_turn[k] = 0;
            STAT_INC(ida_expanded);
        }
    }
    return IDA_FAIL;
}
