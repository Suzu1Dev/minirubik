/* gates.c - written with AI assistance (Claude Code); see docs/ai-assistance.md */
/*
 * Host correctness gates H1-H4 for the IDA* core, checked against the exact
 * BFS distances of tools/oracle (unmodified upstream solver.c).
 *
 *   gates [--jobs N] [--asm FILE] [--skip-h3]
 *       P   parser: ida_parse agrees with upstream parse_state/rank_state
 *       H2  tables: embedded == regenerated, ranges, bijections, agreement
 *           with upstream quarter_turn/apply_move on every state, PDBs fully
 *           populated (max, solved entry, BFS-labelling property), and the
 *           asm tables file holds the same values after ".align 2"; the
 *           default file is ../asm/tables.s relative to the directory of
 *           this binary (c/), independent of the working directory; a
 *           missing file is a failure, not a skip
 *       H1  h <= d on all 3,674,160 states for pdb_p, pdb_o and their max
 *       H3  ida_solve on every state: length == oracle distance and the
 *           path solves the state (core tables and upstream apply_move);
 *           runs in N forked processes (default: online CPUs), prints
 *           wall-clock seconds
 *       H4  no packed accessor exists (byte tables), so H4 is vacuous; a
 *           trivial even/odd index check of the byte tables is still run
 *   gates --dist11 FILE
 *       solves every state in FILE (blank and # lines skipped), prints
 *       "STATE LEN EXPANDED GENERATED" per state, then max/min/mean and the
 *       line for 21345671111111
 * Exit status: 0 all checks pass, 1 a check failed, 2 usage or setup error.
 */
#define _POSIX_C_SOURCE 200809L
#define _DARWIN_C_SOURCE 1
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#include "ida_core.h"
#include "oracle.h"
#include "tables.h"

#define N_STATES TB_STATES
#define SAMPLE_STATE "21345671111111"

static const char *const move_names[IDA_MOVES] = {"R",  "R2", "R'", "B", "B2",
                                                  "B'", "D",  "D2", "D'"};

static int g_fail; /* set by check() */

static void check(int ok, const char *gate, const char *what)
{
    printf("  %-4s %-62s %s\n", gate, what, ok ? "ok" : "FAIL");
    if (!ok)
        g_fail = 1;
}

static double now_seconds(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double) ts.tv_sec + (double) ts.tv_nsec * 1e-9;
}

static uint32_t h_of(uint32_t p, uint32_t o)
{
    uint32_t hp = pdb_p[p], ho = pdb_o[o];
    return hp > ho ? hp : ho;
}

/* ---------------------------------------------------------------- P */

static uint32_t rng_state = 2463534242u;
static uint32_t xorshift32(void)
{
    rng_state ^= rng_state << 13;
    rng_state ^= rng_state >> 17;
    rng_state ^= rng_state << 5;
    return rng_state;
}

static void gate_parser(void)
{
    char s[ORACLE_STATE_LEN + 2]; /* up to 15 characters + NUL */
    uint32_t p, o, bad_rank = 0, bad_accept = 0, fuzz_bad = 0, fuzz_valid = 0;
    static const char *const invalid[] = {
        "1234567111111",  "123456711111111", "02345671111111",
        "82345671111111", "12345671111110",  "12345671111114",
        "1234567111111a", "11345671111111",  "12345671111112", ""};

    printf("P: parser (ida_parse) against upstream parse_state/rank_state\n");
    for (uint32_t r = 0; r < N_STATES; ++r) {
        oracle_state_at(r, s);
        if (!ida_parse(s, &p, &o)) {
            ++bad_accept;
            continue;
        }
        if (p >= IDA_PERMS || o >= IDA_ORIENTS || p * 729u + o != r)
            ++bad_rank;
    }
    printf("       canonical strings rejected: %lu, rank mismatches: %lu\n",
           (unsigned long) bad_accept, (unsigned long) bad_rank);
    check(bad_accept == 0 && bad_rank == 0, "P",
          "every valid state string parses to its upstream rank");

    int inv_ok = 1;
    for (size_t i = 0; i < sizeof invalid / sizeof invalid[0]; ++i)
        if (ida_parse(invalid[i], &p, &o))
            inv_ok = 0;
    check(inv_ok, "P", "upstream Makefile's invalid inputs (and \"\") rejected");

    /* Random strings over '0'..'9' and 'a' (14 or 15 characters), and
     * valid states with one byte replaced or appended: the accept/reject
     * decision and the rank must match upstream. */
    static const char alphabet[] = "0123456789a";
    for (uint32_t n = 0; n < 4000000u; ++n) {
        if (n & 1u) {
            /* a valid state with one byte replaced (or appended) */
            uint32_t pos = xorshift32() % 15u;
            oracle_state_at(xorshift32() % N_STATES, s);
            s[pos] = alphabet[xorshift32() % 11u];
            s[15] = '\0';
        } else {
            uint32_t len = (n & 30u) == 0 ? 15u : 14u;
            for (uint32_t i = 0; i < len; ++i) {
                uint32_t x = xorshift32() % 100u;
                /* bias towards plausible digits */
                if (i < 7)
                    s[i] = x < 92 ? (char) ('1' + x % 7) : alphabet[x % 11];
                else
                    s[i] = x < 92 ? (char) ('1' + x % 3) : alphabet[x % 11];
            }
            s[len] = '\0';
        }
        int32_t up = oracle_index_of(s);
        int mine = ida_parse(s, &p, &o);
        if ((up >= 0) != (mine != 0) ||
            (mine && (uint32_t) up != p * 729u + o))
            ++fuzz_bad;
        if (up >= 0)
            ++fuzz_valid;
    }
    printf("       fuzz: 4000000 strings, %lu valid, %lu disagreements\n",
           (unsigned long) fuzz_valid, (unsigned long) fuzz_bad);
    check(fuzz_bad == 0, "P", "random strings: same accept/reject and rank");
}

/* --------------------------------------------------------------- H2 */

static int is_bijection16(const uint16_t *a, uint32_t n)
{
    static uint8_t seen[TB_PERMS];
    memset(seen, 0, n);
    for (uint32_t i = 0; i < n; ++i) {
        if (a[i] >= n || seen[a[i]])
            return 0;
        seen[a[i]] = 1;
    }
    return 1;
}

/* PDB check independent of the BFS code: entry 0 is the only 0, and every
 * entry v > 0 has a move to a v-1 entry while no move changes the value by
 * more than 1.  Together these prove dist == exact abstract distance. */
static int pdb_is_bfs_labelling(const uint8_t *pdb, const uint16_t *qt,
                                uint32_t n)
{
    for (uint32_t v = 0; v < n; ++v) {
        int has_parent = 0;
        if ((pdb[v] == 0) != (v == 0))
            return 0;
        for (uint32_t f = 0; f < 3; ++f) {
            uint32_t w = v;
            for (uint32_t t = 0; t < 3; ++t) {
                w = qt[f * n + w];
                int diff = (int) pdb[w] - (int) pdb[v];
                if (diff > 1 || diff < -1)
                    return 0;
                if (diff == -1)
                    has_parent = 1;
            }
        }
        if (v != 0 && !has_parent)
            return 0;
    }
    return 1;
}

/* Parse asm/tables.s and compare it with the embedded tables. The file must
 * be ".data", then ".align 2", then the four labels in order, each followed
 * only by its .half/.byte value lines.
 * Returns 1 match, 0 mismatch, -1 file missing. */
static int asm_matches(const char *path, char *why, size_t whylen)
{
    static uint32_t vals[4][3 * TB_PERMS];
    static const char *const labels[4] = {"perm_qt", "orient_qt", "pdb_p",
                                          "pdb_o"};
    static const char *const dirs[4] = {".half", ".half", ".byte", ".byte"};
    static const uint32_t want[4] = {3 * TB_PERMS, 3 * TB_ORIENTS, TB_PERMS,
                                     TB_ORIENTS};
    uint32_t count[4] = {0, 0, 0, 0};
    int cur = -1, next_label = 0, saw_data = 0, saw_align = 0;
    char line[4096];
    FILE *f = fopen(path, "r");
    if (!f)
        return -1;
    while (fgets(line, sizeof line, f)) {
        char *hash = strchr(line, '#'), *s = line;
        if (hash)
            *hash = '\0';
        while (*s == ' ' || *s == '\t')
            ++s;
        size_t len = strlen(s);
        while (len && (s[len - 1] == '\n' || s[len - 1] == ' ' ||
                       s[len - 1] == '\t' || s[len - 1] == '\r'))
            s[--len] = '\0';
        if (!len)
            continue;
        if (!strcmp(s, ".data")) {
            saw_data = 1;
            continue;
        }
        if (!strncmp(s, ".align", 6) && (s[6] == ' ' || s[6] == '\t')) {
            const char *a = s + 6;
            while (*a == ' ' || *a == '\t')
                ++a;
            if (!saw_data || saw_align || cur >= 0 || strcmp(a, "2")) {
                snprintf(why, whylen,
                         "expected one '.align 2' between .data and perm_qt");
                fclose(f);
                return 0;
            }
            saw_align = 1;
            continue;
        }
        if (s[len - 1] == ':') {
            s[len - 1] = '\0';
            if (next_label > 3 || strcmp(s, labels[next_label])) {
                snprintf(why, whylen, "unexpected label '%s'", s);
                fclose(f);
                return 0;
            }
            cur = next_label++;
            continue;
        }
        if (cur < 0 || strncmp(s, dirs[cur], 5) || (s[5] != ' ' && s[5] != '\t')) {
            snprintf(why, whylen, "unexpected line '%.40s'", s);
            fclose(f);
            return 0;
        }
        char *q = s + 5;
        for (;;) {
            char *end;
            errno = 0;
            unsigned long v = strtoul(q, &end, 10);
            if (end == q || errno || count[cur] >= want[cur]) {
                snprintf(why, whylen, "bad value list under %s", labels[cur]);
                fclose(f);
                return 0;
            }
            vals[cur][count[cur]++] = (uint32_t) v;
            q = end;
            while (*q == ' ' || *q == '\t')
                ++q;
            if (*q == '\0')
                break;
            if (*q != ',') {
                snprintf(why, whylen, "bad separator under %s", labels[cur]);
                fclose(f);
                return 0;
            }
            ++q;
        }
    }
    fclose(f);
    if (!saw_data || !saw_align || next_label != 4) {
        snprintf(why, whylen, "missing .data, '.align 2' or labels");
        return 0;
    }
    for (int t = 0; t < 4; ++t)
        if (count[t] != want[t]) {
            snprintf(why, whylen, "%s has %lu values, want %lu", labels[t],
                     (unsigned long) count[t], (unsigned long) want[t]);
            return 0;
        }
    for (uint32_t i = 0; i < 3 * TB_PERMS; ++i)
        if (vals[0][i] != perm_qt[i / TB_PERMS][i % TB_PERMS])
            return snprintf(why, whylen, "perm_qt differs at %lu",
                            (unsigned long) i),
                   0;
    for (uint32_t i = 0; i < 3 * TB_ORIENTS; ++i)
        if (vals[1][i] != orient_qt[i / TB_ORIENTS][i % TB_ORIENTS])
            return snprintf(why, whylen, "orient_qt differs at %lu",
                            (unsigned long) i),
                   0;
    for (uint32_t i = 0; i < TB_PERMS; ++i)
        if (vals[2][i] != pdb_p[i])
            return snprintf(why, whylen, "pdb_p differs at %lu",
                            (unsigned long) i),
                   0;
    for (uint32_t i = 0; i < TB_ORIENTS; ++i)
        if (vals[3][i] != pdb_o[i])
            return snprintf(why, whylen, "pdb_o differs at %lu",
                            (unsigned long) i),
                   0;
    return 1;
}

static unsigned pdb_max(const uint8_t *a, uint32_t n, uint32_t *unreached)
{
    unsigned m = 0;
    *unreached = 0;
    for (uint32_t i = 0; i < n; ++i) {
        if (a[i] == TB_UNREACHED)
            ++*unreached;
        else if (a[i] > m)
            m = a[i];
    }
    return m;
}

static void gate_h2(const char *asm_path)
{
    uint32_t bad_qt = 0, bad_move = 0, unreached_p, unreached_o;
    char why[128] = "";

    printf("H2: every table fully populated, max and solved entry verified\n");
    check(!memcmp(perm_qt, gen_perm_qt, sizeof gen_perm_qt) &&
              !memcmp(orient_qt, gen_orient_qt, sizeof gen_orient_qt) &&
              !memcmp(pdb_p, gen_pdb_p, sizeof gen_pdb_p) &&
              !memcmp(pdb_o, gen_pdb_o, sizeof gen_pdb_o),
          "H2", "embedded tables (tables_data.h) == regenerated tables");

    int perm_ok = 1, orient_ok = 1;
    for (uint32_t f = 0; f < IDA_FACES; ++f) {
        perm_ok &= is_bijection16(perm_qt[f], IDA_PERMS);
        orient_ok &= is_bijection16(orient_qt[f], IDA_ORIENTS);
    }
    check(perm_ok, "H2",
          "perm_qt: 3x5040 entries < 5040, each face a permutation");
    check(orient_ok, "H2",
          "orient_qt: 3x729 entries < 729, each face a permutation");
    check(perm_qt[0][0] != 0 && perm_qt[1][0] != 0 && perm_qt[2][0] != 0,
          "H2", "perm_qt: a quarter turn moves the solved permutation");

    /* Every state, every face: tables == upstream quarter_turn; every
     * move: ida_apply_move == upstream apply_move. */
    for (uint32_t r = 0; r < N_STATES; ++r) {
        uint32_t p0 = r / 729u, o0 = r % 729u;
        for (uint32_t f = 0; f < IDA_FACES; ++f)
            if (tables_upstream_quarter(r, f) !=
                (uint32_t) perm_qt[f][p0] * 729u + orient_qt[f][o0])
                ++bad_qt;
        for (uint32_t m = 0; m < IDA_MOVES; ++m) {
            uint32_t p = p0, o = o0;
            ida_apply_move(&p, &o, m);
            if (tables_upstream_apply(r, m) != p * 729u + o)
                ++bad_move;
        }
    }
    printf("       quarter-turn mismatches: %lu (of %lu), move mismatches: "
           "%lu (of %lu)\n",
           (unsigned long) bad_qt, (unsigned long) (3u * N_STATES),
           (unsigned long) bad_move, (unsigned long) (9u * N_STATES));
    check(bad_qt == 0, "H2",
          "tables == upstream quarter_turn, all states x 3 faces");
    check(bad_move == 0, "H2",
          "ida_apply_move == upstream apply_move, all states x 9 moves");

    unsigned mp = pdb_max(pdb_p, IDA_PERMS, &unreached_p);
    unsigned mo = pdb_max(pdb_o, IDA_ORIENTS, &unreached_o);
    printf("       pdb_p: max %u, solved entry %u, unreached %lu;  pdb_o: max "
           "%u, solved entry %u, unreached %lu\n",
           mp, pdb_p[0], (unsigned long) unreached_p, mo, pdb_o[0],
           (unsigned long) unreached_o);
    check(unreached_p == 0 && unreached_o == 0, "H2",
          "pdb_p and pdb_o fully populated (no 0xFF sentinel)");
    check(pdb_p[0] == 0 && pdb_o[0] == 0, "H2", "solved entries == 0");
    check(mp <= IDA_MAX_DEPTH && mo <= IDA_MAX_DEPTH, "H2",
          "PDB maxima <= 11");
    check(pdb_is_bfs_labelling(pdb_p, &perm_qt[0][0], IDA_PERMS) &&
              pdb_is_bfs_labelling(pdb_o, &orient_qt[0][0], IDA_ORIENTS),
          "H2", "PDBs are exact abstract distances (BFS labelling)");

    int am = asm_matches(asm_path, why, sizeof why);
    printf("       asm tables file: %s\n", asm_path);
    if (am < 0)
        printf("       not found (pass --asm FILE)\n");
    else if (am == 0)
        printf("       %s\n", why);
    check(am == 1, "H2", "asm tables file == embedded tables, after .align 2");
}

/* --------------------------------------------------------------- H1 */

static void gate_h1(void)
{
    uint32_t viol[3] = {0, 0, 0}, equal[3] = {0, 0, 0}, bad_oracle = 0;
    printf("H1: admissibility h(s) <= d(s) over all %lu states\n",
           (unsigned long) N_STATES);
    for (uint32_t r = 0; r < N_STATES; ++r) {
        uint32_t p = r / 729u, o = r % 729u;
        int d = oracle_distance_at(r);
        uint32_t h[3];
        if (d < 0) {
            ++bad_oracle;
            continue;
        }
        h[0] = pdb_p[p];
        h[1] = pdb_o[o];
        h[2] = h_of(p, o);
        for (int i = 0; i < 3; ++i) {
            if (h[i] > (uint32_t) d)
                ++viol[i];
            if (h[i] == (uint32_t) d)
                ++equal[i];
        }
    }
    static const char *const names[3] = {"pdb_p[p]", "pdb_o[o]",
                                         "max(pdb_p[p], pdb_o[o])"};
    for (int i = 0; i < 3; ++i)
        printf("       h = %-24s violations %lu, states with h == d %lu\n",
               names[i], (unsigned long) viol[i], (unsigned long) equal[i]);
    check(bad_oracle == 0, "H1", "oracle distance available for every state");
    check(viol[0] == 0 && viol[1] == 0 && viol[2] == 0, "H1",
          "no state with h > d (all three heuristics)");
}

/* --------------------------------------------------------------- H3 */

typedef struct {
    uint64_t states, expanded, generated;
    uint32_t wrong_len, unsolved, upstream_unsolved, fails;
    uint32_t max_expanded, max_index, first_bad;
    uint32_t max_expanded_d[IDA_MAX_DEPTH + 1];
} h3_result_t;

static void h3_range(uint32_t start, uint32_t step, h3_result_t *res)
{
    uint8_t path[IDA_MAX_DEPTH];
    memset(res, 0, sizeof *res);
    res->first_bad = UINT32_MAX;
    for (uint32_t r = start; r < N_STATES; r += step) {
        uint32_t p = r / 729u, o = r % 729u;
        int d = oracle_distance_at(r);
        int len = ida_solve(p, o, path);
        int bad = 0;
        ++res->states;
        res->expanded += ida_expanded;
        res->generated += ida_generated;
        if (ida_expanded > res->max_expanded) {
            res->max_expanded = ida_expanded;
            res->max_index = r;
        }
        if (d >= 0 && d <= IDA_MAX_DEPTH &&
            ida_expanded > res->max_expanded_d[d])
            res->max_expanded_d[d] = ida_expanded;
        if (len < 0) {
            ++res->fails;
            bad = 1;
        } else {
            if (len != d) {
                ++res->wrong_len;
                bad = 1;
            }
            if (!ida_apply_path(p, o, path, (uint32_t) len)) {
                ++res->unsolved;
                bad = 1;
            }
            uint32_t q = r;
            for (int i = 0; i < len; ++i)
                q = tables_upstream_apply(q, path[i]);
            if (q != 0) {
                ++res->upstream_unsolved;
                bad = 1;
            }
        }
        if (bad && res->first_bad == UINT32_MAX)
            res->first_bad = r;
    }
}

static int read_full(int fd, void *buf, size_t n)
{
    char *p = buf;
    while (n) {
        ssize_t k = read(fd, p, n);
        if (k < 0 && errno == EINTR)
            continue;
        if (k <= 0)
            return -1;
        p += k;
        n -= (size_t) k;
    }
    return 0;
}

static int write_full(int fd, const void *buf, size_t n)
{
    const char *p = buf;
    while (n) {
        ssize_t k = write(fd, p, n);
        if (k < 0 && errno == EINTR)
            continue;
        if (k <= 0)
            return -1;
        p += k;
        n -= (size_t) k;
    }
    return 0;
}

static void gate_h3(int jobs)
{
    h3_result_t total, part;
    int ok_ipc = 1;
    double t0 = now_seconds(), t1;
    memset(&total, 0, sizeof total);
    total.first_bad = UINT32_MAX;

    printf("H3: ida_solve on every state, length == exact distance "
           "(%d process%s)\n",
           jobs, jobs == 1 ? "" : "es");
    fflush(stdout);
    if (jobs == 1) {
        h3_range(0, 1, &total);
    } else {
        int fds[64];
        pid_t pids[64];
        for (int j = 0; j < jobs; ++j) {
            int pfd[2];
            if (pipe(pfd) != 0) {
                perror("pipe");
                exit(2);
            }
            pids[j] = fork();
            if (pids[j] < 0) {
                perror("fork");
                exit(2);
            }
            if (pids[j] == 0) {
                close(pfd[0]);
                h3_range((uint32_t) j, (uint32_t) jobs, &part);
                _exit(write_full(pfd[1], &part, sizeof part) ? 1 : 0);
            }
            close(pfd[1]);
            fds[j] = pfd[0];
        }
        for (int j = 0; j < jobs; ++j) {
            int status;
            if (read_full(fds[j], &part, sizeof part) != 0) {
                ok_ipc = 0;
            } else {
                total.states += part.states;
                total.expanded += part.expanded;
                total.generated += part.generated;
                total.wrong_len += part.wrong_len;
                total.unsolved += part.unsolved;
                total.upstream_unsolved += part.upstream_unsolved;
                total.fails += part.fails;
                if (part.max_expanded > total.max_expanded) {
                    total.max_expanded = part.max_expanded;
                    total.max_index = part.max_index;
                }
                for (int d = 0; d <= IDA_MAX_DEPTH; ++d)
                    if (part.max_expanded_d[d] > total.max_expanded_d[d])
                        total.max_expanded_d[d] = part.max_expanded_d[d];
                if (part.first_bad < total.first_bad)
                    total.first_bad = part.first_bad;
            }
            close(fds[j]);
            if (waitpid(pids[j], &status, 0) < 0 || !WIFEXITED(status) ||
                WEXITSTATUS(status) != 0)
                ok_ipc = 0;
        }
    }
    t1 = now_seconds();

    char s[ORACLE_STATE_LEN + 1];
    oracle_state_at(total.max_index, s);
    printf("       states %llu, wrong length %lu, path not solving (core) %lu, "
           "(upstream) %lu, search failures %lu\n",
           (unsigned long long) total.states, (unsigned long) total.wrong_len,
           (unsigned long) total.unsolved,
           (unsigned long) total.upstream_unsolved, (unsigned long) total.fails);
    printf("       nodes expanded: total %llu, mean %.1f, max %lu (state %s)\n",
           (unsigned long long) total.expanded,
           total.states ? (double) total.expanded / (double) total.states : 0.0,
           (unsigned long) total.max_expanded, s);
    printf("       nodes generated: total %llu\n",
           (unsigned long long) total.generated);
    printf("       max expanded by distance:");
    for (int d = 0; d <= IDA_MAX_DEPTH; ++d)
        printf(" %d:%lu", d, (unsigned long) total.max_expanded_d[d]);
    printf("\n       wall-clock %.2f s\n", t1 - t0);
    if (total.first_bad != UINT32_MAX) {
        oracle_state_at(total.first_bad, s);
        printf("       first failing state: %s\n", s);
    }
    check(ok_ipc, "H3", "all worker processes reported");
    check(total.states == N_STATES, "H3", "every state searched");
    check(total.fails == 0 && total.wrong_len == 0, "H3",
          "returned length == oracle distance for every state");
    check(total.unsolved == 0 && total.upstream_unsolved == 0, "H3",
          "every returned path solves its state (core and upstream)");
}

/* --------------------------------------------------------------- H4 */

static void gate_h4(void)
{
    uint32_t even = 0, odd = 0, bad = 0;
    printf("H4: packed accessors agree with an unpacked reference\n");
    printf("       no packed accessor exists: pdb_p and pdb_o hold one byte "
           "per entry,\n"
           "       so H4 is vacuous. Trivial check of byte reads at even and "
           "odd indices:\n");
    for (uint32_t i = 0; i < IDA_PERMS; ++i) {
        if (pdb_p[i] != gen_pdb_p[i])
            ++bad;
        (i & 1u) ? ++odd : ++even;
    }
    for (uint32_t i = 0; i < IDA_ORIENTS; ++i) {
        if (pdb_o[i] != gen_pdb_o[i])
            ++bad;
        (i & 1u) ? ++odd : ++even;
    }
    printf("       %lu even and %lu odd indices compared, %lu mismatches\n",
           (unsigned long) even, (unsigned long) odd, (unsigned long) bad);
    check(bad == 0, "H4", "pdb byte reads == generator arrays (even and odd)");
}

/* ----------------------------------------------------------- dist11 */

static int run_dist11(const char *path)
{
    FILE *f = fopen(path, "r");
    char line[256];
    uint32_t n = 0, bad = 0, max_e = 0, min_e = UINT32_MAX;
    uint64_t sum_e = 0, sum_g = 0;
    char max_s[16] = "", min_s[16] = "", sample[160] = "(not in file)";
    uint8_t mv[IDA_MAX_DEPTH];
    if (!f) {
        perror(path);
        return 2;
    }
    printf("# state len expanded generated\n");
    while (fgets(line, sizeof line, f)) {
        uint32_t p, o;
        size_t len = strcspn(line, " \t\r\n,|");
        if (line[0] == '#' || len == 0)
            continue;
        line[len] = '\0';
        if (!ida_parse(line, &p, &o)) {
            fprintf(stderr, "invalid state '%s'\n", line);
            fclose(f);
            return 2;
        }
        int d = oracle_distance(line);
        int sl = ida_solve(p, o, mv);
        int ok = sl == d && sl >= 0 &&
                 ida_apply_path(p, o, mv, (uint32_t) sl);
        printf("%s %d %lu %lu%s\n", line, sl, (unsigned long) ida_expanded,
               (unsigned long) ida_generated, ok ? "" : " FAIL");
        if (!ok)
            ++bad;
        ++n;
        sum_e += ida_expanded;
        sum_g += ida_generated;
        if (ida_expanded > max_e) {
            max_e = ida_expanded;
            snprintf(max_s, sizeof max_s, "%s", line);
        }
        if (ida_expanded < min_e) {
            min_e = ida_expanded;
            snprintf(min_s, sizeof min_s, "%s", line);
        }
        if (!strcmp(line, SAMPLE_STATE)) {
            int pos = snprintf(sample, sizeof sample,
                               "len %d, expanded %lu, generated %lu, solution",
                               sl, (unsigned long) ida_expanded,
                               (unsigned long) ida_generated);
            for (int i = 0; i < sl && pos < (int) sizeof sample; ++i)
                pos += snprintf(sample + pos, sizeof sample - (size_t) pos,
                                " %s", move_names[mv[i]]);
        }
    }
    fclose(f);
    if (n == 0) {
        fprintf(stderr, "no states in %s\n", path);
        return 2;
    }
    printf("# summary over %lu states from %s\n", (unsigned long) n, path);
    printf("#   failures (length != oracle distance or path not solving): %lu\n",
           (unsigned long) bad);
    printf("#   expanded: max %lu (%s), min %lu (%s), mean %.1f\n",
           (unsigned long) max_e, max_s, (unsigned long) min_e, min_s,
           (double) sum_e / (double) n);
    printf("#   generated: mean %.1f\n", (double) sum_g / (double) n);
    printf("#   %s: %s\n", SAMPLE_STATE, sample);
    return bad ? 1 : 0;
}

/* ------------------------------------------------------------- main */

static int usage(void)
{
    fputs("usage: gates [--jobs N] [--asm FILE] [--skip-h3]\n"
          "       gates --dist11 FILE\n",
          stderr);
    return 2;
}

/* Default asm tables path: the binary is c/gates, so the file is
 * <directory of argv[0]>/../asm/tables.s whatever the working directory.
 * Without a '/' in argv[0] (found through PATH) fall back to the
 * repository-root-relative "asm/tables.s"; a missing file fails H2. */
static const char *default_asm_path(int argc, char **argv)
{
    static char buf[4096];
    const char *slash =
        argc > 0 && argv[0] ? strrchr(argv[0], '/') : NULL;
    if (!slash)
        return "asm/tables.s";
    int n = snprintf(buf, sizeof buf, "%.*s/../asm/tables.s",
                     (int) (slash - argv[0]), argv[0]);
    return n > 0 && (size_t) n < sizeof buf ? buf : "asm/tables.s";
}

int main(int argc, char **argv)
{
    const char *dist11 = NULL, *asm_path = default_asm_path(argc, argv);
    int skip_h3 = 0, jobs = 0;
    for (int i = 1; i < argc; ++i) {
        if (!strcmp(argv[i], "--dist11") && i + 1 < argc)
            dist11 = argv[++i];
        else if (!strcmp(argv[i], "--asm") && i + 1 < argc) {
            asm_path = argv[++i];
        } else if (!strcmp(argv[i], "--jobs") && i + 1 < argc) {
            jobs = atoi(argv[++i]);
            if (jobs < 1 || jobs > 64)
                return usage();
        } else if (!strcmp(argv[i], "--skip-h3"))
            skip_h3 = 1;
        else
            return usage();
    }
    if (tables_build()) {
        fputs("gates: table generation failed\n", stderr);
        return 2;
    }
    if (oracle_init() != 0) {
        fputs("gates: oracle_init failed\n", stderr);
        return 2;
    }
    if (dist11)
        return run_dist11(dist11);

    if (jobs == 0) {
#ifdef _SC_NPROCESSORS_ONLN
        long c = sysconf(_SC_NPROCESSORS_ONLN);
        jobs = c < 1 ? 1 : c > 64 ? 64 : (int) c;
#else
        jobs = 1;
#endif
    }
    gate_parser();
    gate_h2(asm_path);
    gate_h1();
    if (skip_h3)
        printf("H3: skipped (--skip-h3)\n");
    else
        gate_h3(jobs);
    gate_h4();
    printf("gates: %s\n", g_fail ? "FAIL" : (skip_h3 ? "PASS (H3 skipped)" : "PASS"));
    return g_fail ? 1 : 0;
}
