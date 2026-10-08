# c/Makefile - written with AI assistance (Claude Code); see docs/ai-assistance.md
#
# C reference of the IDA* solver (host programs + RV32I reference build).
# Run from the repository root as "make -C c TARGET" (on this Mac prefix
# with DEVELOPER_DIR=/Library/Developer/CommandLineTools).
#
#   all     build gen_tables, tables_data.h, ../asm/tables.s, ida and the
#           gates binary (gates-bin); nothing is run
#   tables  force-regenerate tables_data.h and ../asm/tables.s
#   gates   build and run ./gates (P, H1-H4; H3 over all states takes a
#           while; ./gates --skip-h3 for a quick run)
#   dist11  run ./gates --dist11 ../tests/dist11.txt
#   check   ./ida on every vector of ../tests/solutions.txt: same solution
#           LENGTH as the expected one, path verified by the core and by
#           tools/oracle (upstream apply_move); exit codes as upstream,
#           except the two documented ida-only cases (--self-test exits 2,
#           --stats STATE exits 0)
#   ref     scripts/refbuild.sh --elf $(REF_ELF) c/ripes_ref.c
#   ref-run ref, then run $(REF_ELF) in the Ripes CLI on RV32_ISS with --iret
#   clean

CC ?= cc
CFLAGS ?= -O2
override WARN := -std=c99 -Wall -Wextra -Wpedantic
HOST_CFLAGS = $(CFLAGS) $(WARN) -DIDA_STATS -I../tools/oracle

ROOT := ..
VECTORS := $(ROOT)/tests/solutions.txt
DIST11 := $(ROOT)/tests/dist11.txt
ASM_TABLES := $(ROOT)/asm/tables.s
ORACLE_CLI := $(ROOT)/tools/oracle/oracle
REF_ELF ?= /tmp/ida_ref.elf
RIPES ?= $(abspath $(ROOT)/../.tools/Ripes-v2.2.6-106-g5b8a616-mac-universal2.app/Contents/MacOS/Ripes)
SAMPLE_STATE := 21345671111111
# Same rejection cases as the upstream Makefile.
INVALID_STATES := 1234567111111 123456711111111 02345671111111 82345671111111 \
	12345671111110 12345671111114 1234567111111a 11345671111111 12345671111112

.PHONY: all tables gates gates-bin dist11 check ref ref-run clean

all: gen_tables tables_data.h $(ASM_TABLES) ida gates-bin

# --- table generation (host, from upstream solver.c) ---
tables.o: tables.c tables.h $(ROOT)/solver.c
	$(CC) $(HOST_CFLAGS) -c tables.c -o $@

gen_tables.o: gen_tables.c tables.h
	$(CC) $(HOST_CFLAGS) -c gen_tables.c -o $@

gen_tables: gen_tables.o tables.o
	$(CC) $(HOST_CFLAGS) gen_tables.o tables.o -o $@

tables_data.h: gen_tables
	./gen_tables --h $@

$(ASM_TABLES): gen_tables
	./gen_tables --asm $@

tables: gen_tables
	./gen_tables --h tables_data.h --asm $(ASM_TABLES)

# --- host programs ---
ida_core.o: ida_core.c ida_core.h
	$(CC) $(HOST_CFLAGS) -c ida_core.c -o $@

tables_embed.o: tables_embed.c tables_data.h ida_core.h
	$(CC) $(HOST_CFLAGS) -c tables_embed.c -o $@

ida_host.o: ida_host.c ida_core.h
	$(CC) $(HOST_CFLAGS) -c ida_host.c -o $@

ida: ida_host.o ida_core.o tables_embed.o
	$(CC) $(HOST_CFLAGS) ida_host.o ida_core.o tables_embed.o -o $@

oracle_lib.o: $(ROOT)/tools/oracle/oracle.c $(ROOT)/tools/oracle/oracle.h $(ROOT)/solver.c
	$(CC) $(HOST_CFLAGS) -c $(ROOT)/tools/oracle/oracle.c -o $@

gates.o: gates.c ida_core.h tables.h $(ROOT)/tools/oracle/oracle.h
	$(CC) $(HOST_CFLAGS) -c gates.c -o $@

# "gates" is the run target, so the binary c/gates is linked by the phony
# gates-bin (relinked on every call; it takes well under a second).
GATES_OBJS := gates.o ida_core.o tables_embed.o tables.o oracle_lib.o
gates-bin: $(GATES_OBJS)
	$(CC) $(HOST_CFLAGS) $(GATES_OBJS) -o gates

gates: gates-bin $(ASM_TABLES)
	./gates --asm $(ASM_TABLES)

dist11: gates-bin
	./gates --dist11 $(DIST11)

$(ORACLE_CLI):
	$(MAKE) -C $(ROOT)/tools/oracle oracle

# --- vectors: equal solution length, verified path, upstream exit codes ---
check: ida $(ORACLE_CLI) $(VECTORS)
	@count=0; \
	while IFS='|' read -r state solution; do \
		case "$$state" in ""|\#*) continue ;; esac; \
		got=$$(./ida "$$state"); status=$$?; \
		test $$status -eq 0 || { echo "ida $$state: exit status $$status"; exit 1; }; \
		want_len=$$(printf '%s\n' "$$solution" | wc -w | tr -d ' '); \
		got_len=$$(printf '%s\n' "$$got" | wc -w | tr -d ' '); \
		test "$$got_len" -eq "$$want_len" || { \
			echo "ida $$state: length $$got_len, expected $$want_len"; \
			echo "  expected: $$solution"; echo "  got:      $$got"; exit 1; }; \
		verdict=$$($(ORACLE_CLI) verify "$$state" $$got); \
		case "$$verdict" in "ok moves=$$want_len distance=$$want_len optimal=yes") ;; \
			*) echo "ida $$state: oracle verify says '$$verdict'"; exit 1 ;; esac; \
		printf '  %s  %2s moves  %s\n' "$$state" "$$got_len" "$$got"; \
		count=$$((count + 1)); \
	done <$(VECTORS); \
	echo "$$count vectors: ida length == expected length, paths verified by oracle (upstream apply_move)"
	@for bad in $(INVALID_STATES); do \
		./ida "$$bad" >/dev/null 2>&1; status=$$?; \
		test $$status -eq 2 || { echo "ida $$bad: expected status 2, got $$status"; exit 1; }; \
	done; \
	./ida >/dev/null 2>&1; status=$$?; \
	test $$status -eq 2 || { echo "ida with no argument: expected 2, got $$status"; exit 1; }; \
	./ida $(SAMPLE_STATE) $(SAMPLE_STATE) >/dev/null 2>&1; status=$$?; \
	test $$status -eq 2 || { echo "ida with two states: expected 2, got $$status"; exit 1; }; \
	./ida $(SAMPLE_STATE) >&- 2>/dev/null; status=$$?; \
	test $$status -eq 1 || { echo "ida with stdout closed: expected 1, got $$status"; exit 1; }; \
	echo "invalid input rejected with status 2, unwritable stdout with status 1"
	@# The two documented differences from upstream ./solver (see ida_host.c).
	@./ida --self-test >/dev/null 2>&1; status=$$?; \
	test $$status -eq 2 || { echo "ida --self-test: expected 2, got $$status"; exit 1; }; \
	plain=$$(./ida $(SAMPLE_STATE)) && stats=$$(./ida --stats $(SAMPLE_STATE)) || \
		{ echo "ida --stats $(SAMPLE_STATE): nonzero exit status"; exit 1; }; \
	test "$$(printf '%s\n' "$$stats" | sed -n 1p)" = "$$plain" || \
		{ echo "ida --stats: first line differs from plain output"; exit 1; }; \
	printf '%s\n' "$$stats" | sed -n 2p | grep -q '^length=11 expanded=[0-9]* generated=[0-9]*$$' || \
		{ echo "ida --stats: bad statistics line"; exit 1; }; \
	echo "ida-only CLI: --self-test status 2 (use gates), --stats status 0 with the statistics line"

# --- RV32I reference build (single translation unit) ---
ref: tables_data.h
	cd $(ROOT) && scripts/refbuild.sh --elf $(REF_ELF) c/ripes_ref.c

ref-run: ref
	"$(RIPES)" --mode cli --src $(REF_ELF) -t elf --proc RV32_ISS --iret --timeout 600000

clean:
	$(RM) *.o gen_tables ida gates
