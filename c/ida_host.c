/* ida_host.c - written with AI assistance (Claude Code); see docs/ai-assistance.md */
/*
 * Host CLI for the IDA* core.
 *   ida STATE            print an optimal solution in upstream ./solver's
 *                        format (moves separated by one space, newline;
 *                        an empty line for the solved state)
 *   ida --stats STATE    the same line, then
 *                        "length=N expanded=E generated=G"
 * Exit status as upstream: 0 ok, 1 failure (search failed, returned path
 * does not solve the state, stdout write error), 2 usage or invalid state.
 *
 * Two deliberate differences from upstream ./solver's argument handling
 * (otherwise the exit statuses are upstream's):
 *   --self-test         not implemented: exit 2 with a note to run c/gates
 *                       (upstream runs its self-test and exits 0)
 *   --stats STATE       host-only diagnostic: exit 0 with the extra line
 *                       (upstream treats it as a usage error, exit 2)
 */
#include <stdio.h>
#include <string.h>

#include "ida_core.h"

static const char *const move_names[IDA_MOVES] = {"R",  "R2", "R'", "B", "B2",
                                                  "B'", "D",  "D2", "D'"};

static int output_failed(void)
{
    return fflush(stdout) != 0 || ferror(stdout);
}

int main(int argc, char **argv)
{
    const char *state = NULL;
    int stats = 0, len;
    uint32_t p, o;
    uint8_t path[IDA_MAX_DEPTH];

    if (argc == 2 && !strcmp(argv[1], "--self-test")) {
        fputs("ida: --self-test is not implemented; the table and search "
              "checks are in c/gates\n",
              stderr);
        return 2;
    }
    if (argc == 2) {
        state = argv[1];
    } else if (argc == 3 && !strcmp(argv[1], "--stats")) {
        stats = 1;
        state = argv[2];
    }
    if (!state || !ida_parse(state, &p, &o)) {
        fprintf(stderr, "usage: %s [--stats] PPPPPPPOOOOOOO\n",
                argc > 0 && argv[0] ? argv[0] : "ida");
        return 2;
    }
    len = ida_solve(p, o, path);
    if (len < 0 || !ida_apply_path(p, o, path, (uint32_t) len)) {
        fputs("ida: no valid solution found\n", stderr);
        return 1;
    }
    for (int i = 0; i < len; ++i)
        printf("%s%s", i ? " " : "", move_names[path[i]]);
    putchar('\n');
    if (stats)
        printf("length=%d expanded=%lu generated=%lu\n", len,
               (unsigned long) ida_expanded, (unsigned long) ida_generated);
    return output_failed();
}
