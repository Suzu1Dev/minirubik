# tools/oracle/Makefile - host-side exact-distance oracle (test tooling).
#
# Usage, from the repository root (on this Mac prefix every command with
# DEVELOPER_DIR=/Library/Developer/CommandLineTools to avoid the Xcode
# license prompt):
#   make -C tools/oracle              build tools/oracle/oracle and oracle.o
#   make -C tools/oracle check        run "oracle check-all" and "oracle hist"
#   make -C tools/oracle dist11       regenerate tests/dist11.txt
#   make -C tools/oracle crosscheck   cross-check vs report.md, Jaap's table,
#                                     tests/solutions.txt, upstream ./solver
#   make -C tools/oracle clean
#
# oracle.c #includes ../../solver.c unmodified, so editing solver.c (which
# you should not do) would rebuild the oracle.
#
# CFLAGS (default -O2) may be overridden from the environment or command
# line, e.g. "make CFLAGS='-O0 -g'".  The language standard and warning
# flags in WARN are always added after CFLAGS and cannot be overridden, so
# every build is checked with -std=c99 -Wall -Wextra -Wpedantic (expected:
# zero warnings).

CC ?= cc
CFLAGS ?= -O2
override WARN := -std=c99 -Wall -Wextra -Wpedantic
UPSTREAM := ../../solver.c

.PHONY: all check dist11 crosscheck clean

all: oracle

oracle.o: oracle.c oracle.h $(UPSTREAM) Makefile
	$(CC) $(CFLAGS) $(WARN) -c oracle.c -o $@

oracle_cli.o: oracle_cli.c oracle.h Makefile
	$(CC) $(CFLAGS) $(WARN) -c oracle_cli.c -o $@

oracle: oracle.o oracle_cli.o
	$(CC) $(CFLAGS) $(WARN) $(LDFLAGS) oracle.o oracle_cli.o -o $@

check: oracle
	./oracle check-all
	./oracle hist

dist11: oracle
	sh ./gen_dist11.sh

crosscheck: oracle
	sh ./crosscheck.sh

clean:
	$(RM) oracle oracle.o oracle_cli.o
