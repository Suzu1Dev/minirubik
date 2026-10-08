/*
 * oracle.c - host-side exact-distance test oracle for minirubik.  API and
 * usage are documented in oracle.h; build with the Makefile next to it.
 *
 * The upstream program ../../solver.c (sysprog21/minirubik commit
 * 231796cc48868f4ea276f652139b6bebbad0cd02) is compiled into this
 * translation unit verbatim.  Its main() is renamed with a macro so it
 * does not collide with the caller's main(); nothing in solver.c is
 * edited.  All upstream identifiers (state_t, rank_state, unrank_state,
 * parse_state, apply_move, build_table, self_test, ...) are static there,
 * so they stay private to this file; this file's own globals use a g_
 * prefix and its exported symbols an oracle_ prefix to avoid clashes.
 *
 * Test tooling only: no search, heuristic or solver of its own.
 */
#include "oracle.h"

/* The renamed upstream main() is an external function (unused here);
 * declare it first so stricter warning sets stay quiet. */
int minirubik_upstream_main(int argc, char **argv);
#define main minirubik_upstream_main
#include "../../solver.c"
#undef main

/* Compile-time agreement between oracle.h and upstream constants. */
typedef char oracle_assert_states[(STATES == ORACLE_NUM_STATES) ? 1 : -1];
typedef char oracle_assert_moves[(MOVES == 9) ? 1 : -1];
typedef char oracle_assert_len[(2 * CUBIES == ORACLE_STATE_LEN) ? 1 : -1];

static uint8_t *g_table; /* upstream toward_solved[]: move toward solved */
static uint8_t *g_depth; /* exact distance per rank, derived from g_table */
static uint32_t g_hist[ORACLE_MAX_DEPTH + 1];
static int g_diameter = -1;
static int g_ready;

static void format_state(const state_t *state, char out[ORACLE_STATE_LEN + 1])
{
    for (int i = 0; i < CUBIES; ++i) {
        out[i] = (char) ('1' + state->p[i]);
        out[i + CUBIES] = (char) ('1' + state->o[i]);
    }
    out[ORACLE_STATE_LEN] = '\0';
}

static uint32_t neighbour_rank(uint32_t rank, uint8_t move)
{
    state_t state;
    unrank_state(rank, &state);
    state = apply_move(state, move);
    return rank_state(&state);
}

/*
 * depth[r] = number of moves needed to reach rank 0 by repeatedly applying
 * the upstream table move, i.e. the length of upstream's printed solution.
 * Chains are memoised, so each state is unranked/moved/ranked once.
 */
static int derive_depths(void)
{
    memset(g_depth, UINT8_MAX, STATES);
    memset(g_hist, 0, sizeof g_hist);
    g_depth[0] = 0;
    for (uint32_t rank = 0; rank < STATES; ++rank) {
        uint32_t path[ORACLE_MAX_DEPTH];
        unsigned n = 0, depth;
        uint32_t here = rank;
        while (g_depth[here] == UINT8_MAX) {
            if (n == ORACLE_MAX_DEPTH || g_table[here] >= MOVES)
                return -1; /* chain longer than the diameter, or bad move */
            path[n++] = here;
            here = neighbour_rank(here, g_table[here]);
        }
        depth = g_depth[here];
        while (n > 0) {
            if (++depth > ORACLE_MAX_DEPTH)
                return -1;
            g_depth[path[--n]] = (uint8_t) depth;
        }
    }
    for (uint32_t rank = 0; rank < STATES; ++rank)
        ++g_hist[g_depth[rank]];
    return g_hist[ORACLE_MAX_DEPTH] ? 0 : -1;
}

int oracle_init(void)
{
    uint8_t diameter = 0;
    if (g_ready)
        return 0;
    g_table = build_table(&diameter); /* NULL if malloc fails or BFS short */
    if (!g_table)
        return ORACLE_E_INIT;
    if (diameter != ORACLE_MAX_DEPTH)
        goto fail;
    g_depth = malloc(STATES);
    if (!g_depth || derive_depths() != 0)
        goto fail;
    g_diameter = diameter;
    g_ready = 1;
    return 0;
fail:
    oracle_fini();
    return ORACLE_E_INIT;
}

void oracle_fini(void)
{
    free(g_table);
    free(g_depth);
    g_table = NULL;
    g_depth = NULL;
    g_diameter = -1;
    g_ready = 0;
}

uint32_t oracle_count(void)
{
    return STATES;
}

int oracle_distance(const char *state14)
{
    state_t state;
    if (!state14 || !parse_state(state14, &state))
        return ORACLE_E_STATE;
    if (oracle_init() != 0)
        return ORACLE_E_INIT;
    return g_depth[rank_state(&state)];
}

int oracle_distance_n(const char *buf, size_t len)
{
    char text[ORACLE_STATE_LEN + 1];
    if (!buf || len != ORACLE_STATE_LEN)
        return ORACLE_E_STATE;
    memcpy(text, buf, ORACLE_STATE_LEN); /* reads exactly 14 bytes */
    text[ORACLE_STATE_LEN] = '\0';       /* an embedded NUL fails parsing */
    return oracle_distance(text);
}

int oracle_distance_at(uint32_t index)
{
    if (index >= STATES)
        return ORACLE_E_STATE;
    if (oracle_init() != 0)
        return ORACLE_E_INIT;
    return g_depth[index];
}

int oracle_state_at(uint32_t index, char out14[ORACLE_STATE_LEN + 1])
{
    state_t state;
    if (!out14 || index >= STATES)
        return ORACLE_E_STATE;
    unrank_state(index, &state);
    format_state(&state, out14);
    return 0;
}

int32_t oracle_index_of(const char *state14)
{
    state_t state;
    if (!state14 || !parse_state(state14, &state))
        return ORACLE_E_STATE;
    return (int32_t) rank_state(&state);
}

int oracle_histogram(uint32_t hist[ORACLE_MAX_DEPTH + 1])
{
    if (oracle_init() != 0)
        return ORACLE_E_INIT;
    if (hist)
        memcpy(hist, g_hist, sizeof g_hist);
    return g_diameter;
}

int oracle_diameter(void)
{
    return oracle_init() != 0 ? ORACLE_E_INIT : g_diameter;
}

static int is_blank(char c)
{
    return c == ' ' || c == '\t' || c == '\n' || c == '\r';
}

int oracle_verify(const char *state14, const char *moves)
{
    state_t state;
    int count = 0;
    if (!state14 || !parse_state(state14, &state))
        return ORACLE_E_STATE;
    if (!moves)
        return ORACLE_E_MOVES;
    for (const char *p = moves;;) {
        while (is_blank(*p))
            ++p;
        if (!*p)
            break;
        const char *start = p;
        while (*p && !is_blank(*p))
            ++p;
        size_t len = (size_t) (p - start);
        uint8_t move = 0;
        while (move < MOVES && !(strlen(move_names[move]) == len &&
                                 !strncmp(move_names[move], start, len)))
            ++move;
        if (move == MOVES || count == 1000000)
            return ORACLE_E_MOVES; /* unknown token, or absurdly long list */
        state = apply_move(state, move);
        ++count;
    }
    return rank_state(&state) == 0 ? count : ORACLE_E_UNSOLVED;
}

/* Report one failed check, printing at most a few examples per check. */
static void fail_note(FILE *log, unsigned long *failures, const char *what,
                      uint32_t rank)
{
    if (log && *failures < 5)
        fprintf(log, "check-all: FAIL %s at index %lu\n", what,
                (unsigned long) rank);
    ++*failures;
}

int oracle_check_all(FILE *log)
{
    unsigned long failures = 0;
    char text[ORACLE_STATE_LEN + 1], prev[ORACLE_STATE_LEN + 1] = "";
    uint32_t sum = 0, recount[ORACLE_MAX_DEPTH + 1] = {0};

    if (oracle_init() != 0) {
        if (log)
            fputs("check-all: FAIL could not build the BFS table\n", log);
        return ORACLE_E_INIT;
    }

    /* 1. Upstream's own self test, unchanged. */
    if (!self_test())
        fail_note(log, &failures, "upstream self_test()", 0);
    else if (log)
        fputs("check-all: upstream self_test() passed\n", log);

    /* 2. String / rank round trip and distance lookup for every index. */
    for (uint32_t rank = 0; rank < STATES; ++rank) {
        state_t unranked, parsed;
        unrank_state(rank, &unranked);
        if (oracle_state_at(rank, text) != 0 ||
            strlen(text) != ORACLE_STATE_LEN) {
            fail_note(log, &failures, "state_at", rank);
            continue;
        }
        if (!parse_state(text, &parsed) || rank_state(&parsed) != rank ||
            memcmp(&parsed, &unranked, sizeof parsed) != 0 ||
            oracle_index_of(text) != (int32_t) rank)
            fail_note(log, &failures, "string/rank round trip", rank);
        if (oracle_distance(text) != g_depth[rank] ||
            oracle_distance_n(text, ORACLE_STATE_LEN) != g_depth[rank])
            fail_note(log, &failures, "oracle_distance(state_at(i))", rank);
        if (rank > 0 && strcmp(prev, text) >= 0)
            fail_note(log, &failures, "strings not strictly increasing", rank);
        memcpy(prev, text, sizeof prev);
    }
    if (log)
        fprintf(log,
                "check-all: %lu indices: state_at -> parse -> rank "
                "round-trips, distance(state_at(i)) == distance_n(...) == "
                "depth[i], strings strictly increasing\n",
                (unsigned long) STATES);

    /* 3. The depth array is a BFS labelling of the move graph. */
    for (uint32_t rank = 0; rank < STATES; ++rank) {
        unsigned depth = g_depth[rank];
        if ((rank == 0) != (depth == 0) || depth > ORACLE_MAX_DEPTH) {
            fail_note(log, &failures, "depth 0 iff solved", rank);
            continue;
        }
        ++recount[depth];
        if (rank > 0 &&
            g_depth[neighbour_rank(rank, g_table[rank])] + 1U != depth)
            fail_note(log, &failures, "table move does not lower depth by 1",
                      rank);
        for (uint8_t move = 0; move < MOVES; ++move) {
            uint32_t next = neighbour_rank(rank, move);
            unsigned there = g_depth[next];
            if (there + 1U < depth || depth + 1U < there)
                fail_note(log, &failures, "edge changes depth by more than 1",
                          rank);
            if (neighbour_rank(next, inverse_move[move]) != rank)
                fail_note(log, &failures, "inverse move does not undo move",
                          rank);
        }
    }
    if (log)
        fprintf(log,
                "check-all: %lu states x %d moves: only solved has depth 0, "
                "table move lowers depth by 1, every edge changes depth by "
                "<= 1, inverse undoes move\n",
                (unsigned long) STATES, MOVES);

    /* 4. The histogram is exactly a recount of the depth array (catches
     *    swapped or shifted buckets that keep the total), every level is
     *    non-empty, the total is STATES and the diameter is 11. */
    for (int d = 0; d <= ORACLE_MAX_DEPTH; ++d) {
        if (g_hist[d] != recount[d])
            fail_note(log, &failures,
                      "histogram bucket != recount of depth array "
                      "(index = depth)",
                      (uint32_t) d);
        if (g_hist[d] == 0)
            fail_note(log, &failures, "empty depth level (index = depth)",
                      (uint32_t) d);
        sum += g_hist[d];
    }
    if (sum != STATES || g_diameter != ORACLE_MAX_DEPTH)
        fail_note(log, &failures, "histogram total / diameter", 0);
    if (log)
        fprintf(log,
                "check-all: histogram == per-depth recount of depth array, "
                "total %lu, diameter %d\n",
                (unsigned long) sum, g_diameter);

    if (log)
        fprintf(log, "check-all: %s (%lu failure%s)\n",
                failures ? "FAILED" : "OK", failures,
                failures == 1 ? "" : "s");
    return failures ? 1 : 0;
}
