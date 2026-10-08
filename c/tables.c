/* tables.c - written with AI assistance (Claude Code); see docs/ai-assistance.md */
/*
 * Host-side table generation.  The unmodified upstream solver.c is compiled
 * into this translation unit (main renamed by a macro, as tools/oracle does),
 * so the quarter-turn tables come from upstream's own unrank_state(),
 * quarter_turn() and rank_state().  The pattern databases are breadth-first
 * searches over the two abstractions using those tables.
 */
#include "tables.h"

int tables_upstream_main(int argc, char **argv);
#define main tables_upstream_main
#include "../solver.c"
#undef main

typedef char tb_assert_perms[(PERMUTATIONS == TB_PERMS) ? 1 : -1];
typedef char tb_assert_orients[(ORIENTATIONS == TB_ORIENTS) ? 1 : -1];
typedef char tb_assert_moves[(MOVES == TB_MOVES) ? 1 : -1];

uint16_t gen_perm_qt[TB_FACES][TB_PERMS];
uint16_t gen_orient_qt[TB_FACES][TB_ORIENTS];
uint8_t gen_pdb_p[TB_PERMS];
uint8_t gen_pdb_o[TB_ORIENTS];

/* Same loops as the first part of upstream build_table(). */
static void build_quarter_turn_tables(void)
{
    state_t state;
    for (uint16_t rank = 0; rank < PERMUTATIONS; ++rank) {
        unrank_state((uint32_t) rank * ORIENTATIONS, &state);
        for (uint8_t face = 0; face < 3; ++face) {
            state_t next = quarter_turn(state, face);
            gen_perm_qt[face][rank] =
                (uint16_t) (rank_state(&next) / ORIENTATIONS);
        }
    }
    for (uint16_t rank = 0; rank < ORIENTATIONS; ++rank) {
        unrank_state(rank, &state);
        for (uint8_t face = 0; face < 3; ++face) {
            state_t next = quarter_turn(state, face);
            gen_orient_qt[face][rank] =
                (uint16_t) (rank_state(&next) % ORIENTATIONS);
        }
    }
}

/*
 * BFS from rank 0 over a graph of n vertices whose 9 moves are 1..3 chained
 * steps of qt[face] (qt is row-major [3][n]).  dist[v] = number of moves.
 * Returns 0 if every vertex was reached.
 */
static int bfs_pdb(const uint16_t *qt, uint32_t n, uint8_t *dist)
{
    static uint16_t queue[TB_PERMS]; /* n <= 5040 */
    uint32_t head = 0, tail = 0;
    for (uint32_t v = 0; v < n; ++v)
        dist[v] = TB_UNREACHED;
    dist[0] = 0;
    queue[tail++] = 0;
    while (head < tail) {
        uint32_t v = queue[head++];
        for (uint32_t face = 0; face < TB_FACES; ++face) {
            uint32_t w = v;
            for (uint32_t turn = 0; turn < 3; ++turn) {
                w = qt[face * n + w];
                if (dist[w] == TB_UNREACHED) {
                    dist[w] = (uint8_t) (dist[v] + 1);
                    queue[tail++] = (uint16_t) w;
                }
            }
        }
    }
    return tail == n ? 0 : 1;
}

int tables_build(void)
{
    build_quarter_turn_tables();
    if (bfs_pdb(&gen_perm_qt[0][0], TB_PERMS, gen_pdb_p))
        return 1;
    if (bfs_pdb(&gen_orient_qt[0][0], TB_ORIENTS, gen_pdb_o))
        return 1;
    return 0;
}

uint32_t tables_upstream_apply(uint32_t rank, uint32_t move)
{
    state_t state;
    unrank_state(rank, &state);
    state = apply_move(state, (uint8_t) move);
    return rank_state(&state);
}

uint32_t tables_upstream_quarter(uint32_t rank, uint32_t face)
{
    state_t state;
    unrank_state(rank, &state);
    state = quarter_turn(state, (uint8_t) face);
    return rank_state(&state);
}
