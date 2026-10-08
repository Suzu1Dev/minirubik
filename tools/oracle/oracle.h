/*
 * oracle.h - host-side exact-distance test oracle for minirubik (2x2x2 cube,
 * half-turn metric, moves R R2 R' B B2 B' D D2 D').
 *
 * TEST TOOLING ONLY.  This library answers "what is the exact distance of
 * state s?" so that host-side gate checks (for example: a heuristic never
 * exceeds the true distance; a search returns a path of exactly the true
 * length) have something trustworthy to compare against.  It is not a
 * solver for the homework and contains no search or heuristic of its own.
 *
 * Every distance comes from the UNMODIFIED upstream breadth-first search
 * build_table() in ../../solver.c (sysprog21/minirubik commit
 * 231796cc48868f4ea276f652139b6bebbad0cd02), which oracle.c compiles in
 * verbatim with #include; only upstream main() is renamed.  The distance of
 * a state is the number of moves obtained by following upstream's
 * toward_solved[] table to the solved state, i.e. exactly the length of the
 * solution the upstream ./solver prints for that state.
 *
 * State strings use exactly the upstream command-line format
 * "PPPPPPPOOOOOOO": 7 permutation digits '1'..'7' (distinct) followed by 7
 * orientation digits '1'..'3' whose (digit - 1) sum is a multiple of 3.
 * A string is accepted iff upstream parse_state() accepts it, so any string
 * accepted here is also accepted by ./solver and vice versa.
 *
 * Link:  cc -O2 -std=c99 -I tools/oracle my_check.c tools/oracle/oracle.c
 * (from the repository root), or link tools/oracle/oracle.o built by
 * "make -C tools/oracle".  Memory: about 7 MiB resident after
 * oracle_init() (upstream table + one depth byte per state) and a transient
 * 14 MiB queue inside build_table().  Not thread-safe.
 */
#ifndef MINIRUBIK_ORACLE_H
#define MINIRUBIK_ORACLE_H

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

/* Characters in a state string, excluding the terminating NUL. */
#define ORACLE_STATE_LEN 14
/* Number of valid states, 7! * 3^6; also the value of oracle_count(). */
#define ORACLE_NUM_STATES 3674160u
/* Diameter of the half-turn-metric graph; oracle_init() fails otherwise. */
#define ORACLE_MAX_DEPTH 11

/* Negative return codes.  Values are distinct across the whole API. */
#define ORACLE_E_STATE (-1)    /* invalid state string or index out of range */
#define ORACLE_E_INIT (-2)     /* the BFS table could not be built */
#define ORACLE_E_MOVES (-3)    /* move list contains an unknown token */
#define ORACLE_E_UNSOLVED (-4) /* move list parsed but does not solve */

/*
 * Build the upstream BFS table once and derive the per-state depth array.
 * Returns 0 on success (also on every later call), ORACLE_E_INIT on
 * allocation failure or if any internal consistency condition fails
 * (incomplete BFS, diameter != 11, broken toward-solved chain).
 * Calling it is optional: every function that needs the table calls it.
 */
int oracle_init(void);

/* Release the table; a later call to any function rebuilds it. */
void oracle_fini(void);

/* Number of valid states (3674160).  Valid indices are 0 .. count-1. */
uint32_t oracle_count(void);

/*
 * Exact distance (0..11) of the state named by the NUL-terminated string
 * state14, ORACLE_E_STATE if upstream parse_state() rejects it (wrong
 * length, bad digit, repeated cubie, orientation parity), ORACLE_E_INIT if
 * the table cannot be built.
 *
 * state14 MUST be NUL-terminated.  Upstream parse_state() reads input[0..13]
 * and then input[14], which has to be '\0' (that is how it rejects strings
 * longer than 14 characters); it stops at the first byte that is not a
 * valid digit, so it reads at most 15 bytes and never past the first NUL.
 * Passing an unterminated 14-byte buffer therefore reads one byte past its
 * end (undefined behaviour).  Writing the parameter as const char[14] would
 * not prevent that: a C array parameter is just a pointer.  For a 14-byte
 * buffer without a NUL, use oracle_distance_n().
 */
int oracle_distance(const char *state14);

/*
 * Same as oracle_distance() for a buffer that need not be NUL-terminated:
 * reads exactly len bytes of buf (none unless len == ORACLE_STATE_LEN),
 * copies them into a local NUL-terminated string and looks that up.
 * Returns ORACLE_E_STATE if buf is NULL, len != 14, or the 14 bytes are not
 * a valid state (an embedded NUL is invalid).  Example:
 *     char s[14]; memcpy(s, "21345671111111", 14);
 *     int d = oracle_distance_n(s, sizeof s);      d == 11
 */
int oracle_distance_n(const char *buf, size_t len);

/* Exact distance of the state with the given index (= upstream rank). */
int oracle_distance_at(uint32_t index);

/*
 * Write the canonical 14-character string of state number index, plus a
 * terminating NUL, to out14.  Index order is upstream rank order, which is
 * also strictly increasing byte (LC_ALL=C) order of the strings.  Returns 0,
 * or ORACLE_E_STATE if index >= oracle_count().  Does not need the table.
 */
int oracle_state_at(uint32_t index, char out14[ORACLE_STATE_LEN + 1]);

/* Index (upstream rank) of a state string, or ORACLE_E_STATE if invalid. */
int32_t oracle_index_of(const char *state14);

/*
 * Depth histogram: hist[d] = number of states at exact distance d, for
 * d = 0 .. ORACLE_MAX_DEPTH.  Returns the diameter (11) on success, or
 * ORACLE_E_INIT.
 */
int oracle_histogram(uint32_t hist[ORACLE_MAX_DEPTH + 1]);

/* Diameter reported by upstream build_table() (11), or ORACLE_E_INIT. */
int oracle_diameter(void);

/*
 * Apply a move list written in upstream output notation (tokens R R2 R' B
 * B2 B' D D2 D' separated by spaces, tabs or newlines; empty string = no
 * moves) to state14 using upstream apply_move().  Returns the number of
 * moves if the result is the solved state, ORACLE_E_STATE for an invalid
 * state, ORACLE_E_MOVES for an unknown token, ORACLE_E_UNSOLVED if the
 * moves do not solve the state.  Optimality is NOT checked here; compare
 * the return value with oracle_distance().  Does not need the table.
 */
int oracle_verify(const char *state14, const char *moves);

/*
 * Exhaustive self-consistency check over all 3674160 states; progress and
 * failures are written to log (may be NULL).  Returns 0 if every check
 * passes, 1 otherwise (ORACLE_E_INIT if the table cannot be built).
 * Checks: upstream self_test(); for every index, state_at -> parse ->
 * rank round-trips and matches unrank, strings are strictly increasing,
 * oracle_distance(string) and oracle_distance_n(string, 14) equal the
 * depth array; the depth array is a BFS labelling (solved is the only
 * depth-0 state, the stored move lowers depth by exactly 1, every one of
 * the 9 moves changes depth by at most 1 and is undone by its inverse),
 * which proves depth == true distance; every histogram bucket equals a
 * fresh per-depth recount of the depth array, no level is empty, the
 * buckets sum to oracle_count() and the diameter is 11.
 * Takes a few seconds.
 */
int oracle_check_all(FILE *log);

#endif /* MINIRUBIK_ORACLE_H */
