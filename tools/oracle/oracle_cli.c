/*
 * oracle_cli.c - command-line front end for the host-side distance oracle
 * (oracle.h).  Test tooling only.  Built to tools/oracle/oracle by the
 * Makefile in this directory.
 *
 * Usage:
 *   oracle dist STATE...        exact distance of each STATE, one per line
 *                               (-1 for an invalid STATE)
 *   oracle dist -               read states from stdin, one per line (blank
 *                               and '#' lines skipped); print "STATE DIST"
 *   oracle hist                 "DEPTH COUNT" for depths 0..11, then
 *                               "total COUNT"
 *   oracle list D               every state at distance D, one per line, in
 *                               rank order (= LC_ALL=C sorted order)
 *   oracle verify STATE MOVES.. check that MOVES (upstream notation, one
 *                               quoted argument or several) solve STATE;
 *                               print "ok moves=N distance=D optimal=yes|no"
 *                               or "not-solved"
 *   oracle verify -             read "STATE|MOVES" lines from stdin (the
 *                               tests/solutions.txt format; blank and '#'
 *                               lines skipped); print "STATE <result>"
 *   oracle check-all            exhaustive internal self-consistency check
 *
 * Exit status: 0 success; 1 table build failure, failed check, moves that
 * do not solve, or stdout write error; 2 usage error or invalid input
 * (same convention as upstream ./solver).  In the multi-state modes the
 * worst status over all inputs is returned.  "optimal=no" is not an error
 * for verify; compare moves= with distance= yourself.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "oracle.h"

static const char *prog = "oracle";

static int usage(void)
{
    fprintf(stderr,
            "usage: %s dist STATE...\n"
            "       %s dist -            (states on stdin)\n"
            "       %s hist\n"
            "       %s list D            (0 <= D <= %d)\n"
            "       %s verify STATE MOVES...\n"
            "       %s verify -          (STATE|MOVES lines on stdin)\n"
            "       %s check-all\n"
            "STATE is the 14-character solver input, e.g. 21345671111111\n",
            prog, prog, prog, prog, ORACLE_MAX_DEPTH, prog, prog, prog);
    return 2;
}

/* Flush stdout and turn a write error into exit status 1. */
static int finish(int status)
{
    if (fflush(stdout) != 0 || ferror(stdout)) {
        fprintf(stderr, "%s: error writing standard output\n", prog);
        return 1;
    }
    return status;
}

static int init_or_die(void)
{
    if (oracle_init() != 0) {
        fprintf(stderr, "%s: could not build the upstream BFS table\n", prog);
        return 0;
    }
    return 1;
}

static int cmd_dist_args(int argc, char **argv)
{
    int status = 0;
    if (!init_or_die())
        return 1;
    for (int i = 0; i < argc; ++i) {
        int d = oracle_distance(argv[i]);
        if (d < 0) {
            fprintf(stderr, "%s: invalid state '%s'\n", prog, argv[i]);
            status = 2;
            d = -1;
        }
        printf("%d\n", d);
    }
    return finish(status);
}

static int cmd_dist_stdin(void)
{
    char line[256];
    int status = 0;
    unsigned long lineno = 0;
    if (!init_or_die())
        return 1;
    while (fgets(line, sizeof line, stdin)) {
        size_t len = strlen(line);
        ++lineno;
        if (len > 0 && line[len - 1] != '\n' && !feof(stdin)) {
            int c;
            while ((c = getchar()) != EOF && c != '\n')
                ;
            fprintf(stderr, "%s: stdin line %lu too long\n", prog, lineno);
            status = 2;
            continue;
        }
        while (len > 0 && (line[len - 1] == '\n' || line[len - 1] == '\r'))
            line[--len] = '\0';
        if (len == 0 || line[0] == '#')
            continue;
        int d = oracle_distance(line);
        if (d < 0) {
            fprintf(stderr, "%s: stdin line %lu: invalid state '%s'\n", prog,
                    lineno, line);
            status = 2;
            d = -1;
        }
        printf("%s %d\n", line, d);
    }
    if (ferror(stdin)) {
        fprintf(stderr, "%s: error reading standard input\n", prog);
        status = 1;
    }
    return finish(status);
}

static int cmd_hist(void)
{
    uint32_t hist[ORACLE_MAX_DEPTH + 1];
    unsigned long total = 0;
    if (oracle_histogram(hist) < 0) {
        fprintf(stderr, "%s: could not build the upstream BFS table\n", prog);
        return 1;
    }
    for (int d = 0; d <= ORACLE_MAX_DEPTH; ++d) {
        printf("%d %lu\n", d, (unsigned long) hist[d]);
        total += hist[d];
    }
    printf("total %lu\n", total);
    return finish(total == oracle_count() ? 0 : 1);
}

/* Strict decimal parse of a depth 0..ORACLE_MAX_DEPTH; -1 if malformed. */
static int parse_depth(const char *s)
{
    int value = 0;
    if (!*s || strlen(s) > 2)
        return -1;
    for (; *s; ++s) {
        if (*s < '0' || *s > '9')
            return -1;
        value = value * 10 + (*s - '0');
    }
    return value <= ORACLE_MAX_DEPTH ? value : -1;
}

static int cmd_list(const char *arg)
{
    char text[ORACLE_STATE_LEN + 1];
    int depth = parse_depth(arg);
    if (depth < 0) {
        fprintf(stderr, "%s: depth must be an integer 0..%d, got '%s'\n",
                prog, ORACLE_MAX_DEPTH, arg);
        return 2;
    }
    if (!init_or_die())
        return 1;
    for (uint32_t i = 0, n = oracle_count(); i < n; ++i) {
        if (oracle_distance_at(i) != depth)
            continue;
        oracle_state_at(i, text);
        fputs(text, stdout);
        putchar('\n');
    }
    return finish(0);
}

/* Format one verify result; returns the exit status it implies. */
static int report_verify(const char *state, int n)
{
    int d;
    if (n == ORACLE_E_STATE || n == ORACLE_E_MOVES) {
        fprintf(stderr, "%s: %s '%s'\n", prog,
                n == ORACLE_E_STATE ? "invalid state"
                                    : "unknown move token (expected R R2 R' "
                                      "B B2 B' D D2 D') for state",
                state);
        printf("invalid\n");
        return 2;
    }
    if (n == ORACLE_E_UNSOLVED) {
        printf("not-solved\n");
        return 1;
    }
    d = oracle_distance(state);
    if (d < 0) {
        fprintf(stderr, "%s: could not build the upstream BFS table\n", prog);
        printf("error\n");
        return 1;
    }
    printf("ok moves=%d distance=%d optimal=%s\n", n, d,
           n == d ? "yes" : "no");
    return 0;
}

/* Lines "STATE|MOVES" (tests/solutions.txt format); '#'/blank skipped. */
static int cmd_verify_stdin(void)
{
    char line[1024];
    int status = 0;
    unsigned long lineno = 0;
    while (fgets(line, sizeof line, stdin)) {
        size_t len = strlen(line);
        char *bar;
        int rc;
        ++lineno;
        if (len > 0 && line[len - 1] != '\n' && !feof(stdin)) {
            int c;
            while ((c = getchar()) != EOF && c != '\n')
                ;
            fprintf(stderr, "%s: stdin line %lu too long\n", prog, lineno);
            status = 2;
            continue;
        }
        while (len > 0 && (line[len - 1] == '\n' || line[len - 1] == '\r'))
            line[--len] = '\0';
        if (len == 0 || line[0] == '#')
            continue;
        bar = strchr(line, '|');
        if (!bar) {
            fprintf(stderr, "%s: stdin line %lu: expected STATE|MOVES\n",
                    prog, lineno);
            status = 2;
            continue;
        }
        *bar = '\0';
        printf("%s ", line);
        rc = report_verify(line, oracle_verify(line, bar + 1));
        if (rc > status)
            status = rc;
    }
    if (ferror(stdin)) {
        fprintf(stderr, "%s: error reading standard input\n", prog);
        status = 1;
    }
    return finish(status);
}

static int cmd_verify(int argc, char **argv)
{
    size_t size = 1;
    char *moves;
    int n;
    for (int i = 1; i < argc; ++i)
        size += strlen(argv[i]) + 1;
    moves = malloc(size);
    if (!moves) {
        fprintf(stderr, "%s: out of memory\n", prog);
        return 1;
    }
    moves[0] = '\0';
    for (int i = 1; i < argc; ++i) {
        strcat(moves, argv[i]);
        strcat(moves, " ");
    }
    n = oracle_verify(argv[0], moves);
    free(moves);
    return finish(report_verify(argv[0], n));
}

int main(int argc, char **argv)
{
    if (argc > 0 && argv[0] && argv[0][0])
        prog = argv[0];
    if (argc < 2)
        return usage();
    const char *cmd = argv[1];
    if (!strcmp(cmd, "dist") && argc == 3 && !strcmp(argv[2], "-"))
        return cmd_dist_stdin();
    if (!strcmp(cmd, "dist") && argc >= 3)
        return cmd_dist_args(argc - 2, argv + 2);
    if (!strcmp(cmd, "hist") && argc == 2)
        return cmd_hist();
    if (!strcmp(cmd, "list") && argc == 3)
        return cmd_list(argv[2]);
    if (!strcmp(cmd, "verify") && argc == 3 && !strcmp(argv[2], "-"))
        return cmd_verify_stdin();
    if (!strcmp(cmd, "verify") && argc >= 3)
        return cmd_verify(argc - 2, argv + 2);
    if (!strcmp(cmd, "check-all") && argc == 2) {
        int rc = oracle_check_all(stdout);
        return finish(rc == 0 ? 0 : 1);
    }
    return usage();
}
