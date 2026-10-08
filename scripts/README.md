## tools/oracle and tests/dist11.txt

Host-side **test oracle** (not a solver): the exact half-turn-metric distance
of any state, taken from the unmodified upstream breadth-first search
`build_table()` in `solver.c` (sysprog21/minirubik
`231796cc48868f4ea276f652139b6bebbad0cd02`). `tools/oracle/oracle.c` does
`#include "../../solver.c"` with upstream `main` renamed by a macro;
`solver.c` itself is not edited. A state's distance is the number of moves
obtained by following upstream's `toward_solved[]` table home, i.e. exactly
the length of the line `./solver STATE` prints. It contains no search or
heuristic of its own; use it as the reference for host gate checks such as
H1 (h(s) <= d(s)) and H3 (returned length == d(s)) that you write yourself.

Build (on this Mac prefix with `DEVELOPER_DIR=/Library/Developer/CommandLineTools`):

```sh
make -C tools/oracle              # tools/oracle/oracle (CLI) and tools/oracle/oracle.o
make -C tools/oracle check        # oracle check-all, then oracle hist (about 4 s)
make -C tools/oracle dist11       # regenerate tests/dist11.txt (sh tools/oracle/gen_dist11.sh)
make -C tools/oracle crosscheck   # sh tools/oracle/crosscheck.sh (about 15 s)
```

`CFLAGS` (default `-O2`) can be overridden, e.g. `make -C tools/oracle
CFLAGS='-O0 -g'`; `-std=c99 -Wall -Wextra -Wpedantic` are kept in a
separate `WARN` variable that is always added, and the build is expected to
give zero warnings.

CLI (`STATE` = the 14-character solver input, e.g. `21345671111111`):

| Command | Prints |
| --- | --- |
| `oracle dist STATE...` | one distance (0..11) per argument; `-1` for an invalid state |
| `oracle dist -` | `STATE DIST` for each stdin line (blank and `#` lines skipped) |
| `oracle hist` | `DEPTH COUNT` for depths 0..11, then `total 3674160` |
| `oracle list D` | every state at distance `D`, one per line, rank order (= `LC_ALL=C` sorted) |
| `oracle verify STATE MOVES...` | `ok moves=N distance=D optimal=yes\|no` if the moves (upstream notation `R R2 R' B B2 B' D D2 D'`) solve `STATE`, else `not-solved` |
| `oracle verify -` | same for `STATE\|MOVES` stdin lines (the `tests/solutions.txt` format), prefixed by `STATE` |
| `oracle check-all` | exhaustive self-consistency report, `check-all: OK (0 failures)` |

Exit status follows upstream `./solver`: 0 success, 1 failure (table build,
failed check, moves that do not solve, stdout write error), 2 usage error
or invalid input. `optimal=no` is not an error for `verify`; compare
`moves=` with `distance=` yourself.

Library (`tools/oracle/oracle.h`, C99, documented there): `oracle_init`,
`oracle_fini`, `oracle_count` (3674160), `oracle_distance(state)` (0..11,
`ORACLE_E_STATE` = -1 if invalid; `state` must be NUL-terminated because
upstream `parse_state()` reads byte 14), `oracle_distance_n(buf, len)` (same,
for a buffer without a NUL; reads exactly `len` bytes, valid only when
`len == 14`), `oracle_distance_at(index)`,
`oracle_state_at(index, out)` (canonical string; index = upstream rank, rank
order = byte-sorted order), `oracle_index_of(state)`,
`oracle_histogram(hist[12])`, `oracle_diameter`, `oracle_verify(state,
moves)`, `oracle_check_all(FILE *)`. Strings are accepted exactly when
upstream `parse_state()` accepts them, so they round-trip into `./solver`
and into your own program. Link from the repository root with, for example,
`cc -O2 -std=c99 -I tools/oracle your_check.c tools/oracle/oracle.c`
(about 7 MiB resident after `oracle_init`; not thread-safe).

`oracle check-all` verifies, over all 3674160 indices: upstream
`self_test()`; `state_at -> parse_state -> rank_state` round-trips and
agrees with `unrank_state`; strings strictly increase with the index;
`oracle_distance(state_at(i))` and `oracle_distance_n(state_at(i), 14)`
equal the depth array; only the solved state has depth 0; the stored
upstream move lowers depth by exactly 1; each of the 9 moves changes depth
by at most 1 and is undone by its inverse; every histogram bucket equals a
fresh recount of the depth array, no level is empty, and the buckets sum
to 3674160 with diameter 11. The depth-0,
stored-move and at-most-1-per-move properties together prove that the
depth array equals the true graph distance (the stored moves give a path
of that length, and no path can be shorter because each move lowers depth
by at most 1).

`tests/dist11.txt`: all 2644 states at distance 11, one 14-character
string per line, `LC_ALL=C` sorted, after a 2-line `#` header that names
the generating command and upstream commit. Skip the header when reading
it, e.g. `grep -v '^#' tests/dist11.txt`. `gen_dist11.sh [OUTPUT]` (`-h`
for usage) refuses to run if `solver.c` is not the upstream blob or if
`tools/oracle/oracle` is older than `oracle.c`, `oracle.h`, `oracle_cli.c`
or `solver.c`, and asserts 2644 well-formed, unique, sorted strings, all at
oracle distance 11, including `21345671111111`. `OUTPUT` must be a regular
file (or not exist yet) in an existing directory; a directory, an extra
argument, or an argument starting with `-` is a usage error (exit 2; write
`./-name` for such a file).

`crosscheck.sh` checks: `oracle hist` equals the depth table in
`report.md` and Jaap Scherphuis' face-turn-metric totals
(<https://www.jaapsch.net/puzzles/cube2.htm>, embedded in the script);
for every vector in `tests/solutions.txt`, the oracle distance equals the
word count of the expected solution and the solution solves the state;
`tests/dist11.txt` equals `oracle list 11`; and every `SAMPLE_STRIDE`-th
dist11 state (an integer 1..2644, default 13, i.e. 204 states;
`SAMPLE_STRIDE=1` runs all 2644 in a few minutes) is solved by the upstream
`./solver` (override with `SOLVER=`) in exactly 11 moves that `oracle
verify` confirms. A bad `SAMPLE_STRIDE` (such as `0`, `00`, `abc`, `2645`)
or any argument other than `-h` exits 2 before any check runs; a stale
`tools/oracle/oracle` is refused as in `gen_dist11.sh`.

## Ripes runners

Scripts that drive the Ripes command-line simulator for the homework's
instruction-count checks. They only automate runs and collect numbers. The
assembly program, its validation and every measurement belong to the student.
All four scripts are POSIX `sh` + `awk`, print a usage text when given `-h` or
bad arguments, and exit with status 2 for usage or setup errors.

| Script | Purpose |
|---|---|
| `ripes-prep.sh` | Rewrites a source for one CLI run: inserts the requested state, forces `RENDER` and removes guarded render code. |
| `ripes-run.sh` | Runs one simulation and prints one CSV line. |
| `ripes-batch.sh` | Runs many states in parallel and writes CSV output, a summary and one log per state. |
| `ripes-rate.sh` | Wraps `--iret --exectime` for a program you supply and prints instructions/s. |

Ripes executable: by default the scripts use
`../.tools/Ripes-v2.2.6-106-g5b8a616-mac-universal2.app/Contents/MacOS/Ripes`
(absolute path built into the scripts). Override it with `RIPES=/path/to/Ripes`.

### Source conventions

1. **State line.** Put exactly one quoted 14-digit string on a code line whose
   trailing comment contains `@STATE`:

   ```
   input_state: .string "21345671111111"   # @STATE
   ```

   When `ripes-run.sh` is given a state, it replaces those 14 digits in a
   temporary copy. Without a state, it uses the value already in the file. It
   is an error to have more than one `@STATE` line, or to pass a state when
   the file has none.
2. **Render switch.** Every `.equ RENDER, <x>` line (spacing does not matter)
   is rewritten to `.equ RENDER, 0`. Use `-R 1` to keep render code instead.
3. **Render guards.** The Ripes assembler (commit 5b8a616) supports only these directives:
   `.text .data .bss .string .asciz .zero .byte .half .short .2byte .word
   .4byte .long .dword .equ .align .global .globl`.
   **It has no `.if/.else/.endif` and no macros.** Any `.if` makes the CLI
   fail with `Unknown directive '.if'`. There are two ways to guard
   renderer code:
   - Comment markers, which the Ripes assembler ignores, so the raw file still
     assembles in Ripes. This is the recommended form:

     ```
     # @RENDER-BEGIN
     ...renderer code and data...
     # @RENDER-END
     ```

   - GNU-style `.if RENDER` / `.else` / `.endif`. `ripes-prep.sh` evaluates
     these blocks when the condition is an integer literal or one symbol set by
     an earlier `.equ NAME, <integer literal>`. A raw file that uses them will
     not assemble in Ripes. To load a GUI copy with rendering enabled, generate
     one with
     `scripts/ripes-prep.sh -R 1 solver.s /tmp/solver-gui.s`.

   Guards can be nested. Inactive lines and directive lines become
   `#ripes-prep: ...` comments, so line numbers stay the same as in the
   original file. In CLI mode Ripes defines no peripheral symbols:
   `la a0, LED_MATRIX_0_BASE` fails with `Unknown symbol`, and `li` with an
   unknown symbol fails with the misleading message `Unknown opcode 'li'`.
   Render code must therefore be fully removed from CLI builds.
4. **End of program.** Exit with `li a7, 93` and `ecall`, with the status in `a0`.
   Ripes prints `Program exited with code: N`. The runners read the exit code
   from that line, because the Ripes process itself exits with 0.
5. **Self-check tokens (batch).** After validating its answer, the program
   prints a line whose first word is `PASS` or `FAIL`. Change the tokens with
   `PASS_TOKEN=...` / `FAIL_TOKEN=...`.

### Usage

```sh
# one run (CSV on stdout, program console on stderr)
scripts/ripes-run.sh -H solver.s 21345671111111
#   state,proc,iret,cycles,status,exit_code
#   21345671111111,RV32_ISS,<iret>,<cycles>,ok,0
scripts/ripes-run.sh -p RV32_5S -l run.log solver.s 21345671111111

# all distance-11 states, 10 parallel Ripes processes
scripts/ripes-batch.sh -j 10 -o build/dist11-iss.csv solver.s tests/dist11.txt
#   progress lines "[k/n] <csv line>" on stderr, then the summary on stdout

# simulator speed for your own measurement program
scripts/ripes-rate.sh -H -n 3 my_rate_test.s
#   proc,iret,exectime_ms,iret_per_s

# see exactly what Ripes will assemble
scripts/ripes-prep.sh -s 21345671111111 solver.s /tmp/solver-cli.s
```

Options for `ripes-run.sh`:

- `-p PROC`: processor model (default `RV32_ISS`).
- `-t MS`: timeout in ms (default 300000).
- `-R VALUE`: value for `RENDER` (default 0).
- `-l LOG`: write the console output to LOG instead of stderr.
- `-H`: print the CSV header.
- `-k`: keep the temporary directory.

`ripes-batch.sh` takes `-p`, `-t` and `-R` with the same meanings. It also takes:

- `-j JOBS`: number of parallel runs (default: CPU count minus 2).
- `-o out.csv`: CSV output file (default `./<src>-<PROC>-batch.csv`). The
  failure list goes next to it as `<out>.failures.csv`.
- `-L logdir`: directory for per-state logs (default `<out>.logs/`).

`ripes-rate.sh` takes `-p`, `-t`, `-n REPEAT` and `-H`. It runs the file
unmodified. A run gives a rate only if Ripes wrote a report *and* printed
`Program exited with code: N`, so the program must end with an exit ecall
(a7=10 or 93). A silent stop (see below) is reported as a failure with exit
status 1, not as a rate.

**`ripes-run.sh` CSV** `state,proc,iret,cycles,status,exit_code`:

- `status=ok`: Ripes finished, wrote a report and printed `Program exited with code`.
- `timeout`: Ripes printed `Simulation did not finish within the specified timeout`. No iret is available.
- `asm_error`: Ripes printed `Error during assembly`. This includes non-RV32I *mnemonics* such as `mul`, because no `--isaexts` flag is passed and the Ripes assembler then accepts only RV32I mnemonics.
- `sim_error`: Ripes exited with a non-zero status, no report was written, or the program stopped without an exit ecall. Ripes stops *silently* (exit status 0, report written) on a jump to an unmapped PC, on an unknown ecall number, or when it runs off the end of `.text`.
- `exit_code` is `none` when no exit line was seen.

The script exits with 0 only for `status=ok` with `exit_code=0`.

**Not detected by the runners: raw encodings.** The RV32I-only check in Ripes
applies to mnemonics at assembly time, not to what runs. A `.word` placed in
`.text` is executed without any message:

- An illegal or unknown word (`0xffffffff`, `0x00000000`, `0x0000007f` were
  tried) does **not** stop the run. It is retired as a no-op, counted in
  iret, and the program continues. This happens on both `RV32_ISS` and `RV32_5S`.
- An M-extension encoding (e.g. `.word 0x02A50533`, `mul a0, a0, a0`) is
  **executed** on `RV32_ISS` even without `--isaexts`. On `RV32_5S` the same
  word is a no-op. See `tools/smoke/raw_word.s`: it prints 36 on `RV32_ISS`
  and 6 on `RV32_5S`, and `ripes-run.sh` reports `ok` for both.

Use `scripts/rv32i-audit.sh` for the RV32I check. It flags raw `.word`/`.insn`
data in executable sections (`raw_word.s` fails it with exit status 1).

**`ripes-batch.sh`** reads the states file and skips blank lines and lines
starting with `#`. The first token of each line, up to whitespace, `,` or `|`,
must be 14 digits, so `tests/solutions.txt` also works as input. Before
starting the batch, it checks two things:

1. A two-instruction program runs on the chosen processor.
2. The source prepares and assembles. This uses a 1 ms run, so a broken source
   stops the batch before any state runs.

The CSV adds a `check` column: `pass`, `fail` or `none` (neither token
printed). A run counts as a failure when any of these holds:

- `status` is not `ok`;
- `check` is `fail`;
- `exit_code` is not 0;
- `check` is `none` and `REQUIRE_PASS=1` (the default; set `REQUIRE_PASS=0`
  to relax this).

The summary reports:

- the number of runs and the counts per status and per check;
- the failures, with the first 20 listed along with their log paths;
- min, mean and max iret over runs that passed, and the state with the
  maximum;
- the number of finished runs with `iret > IRET_LIMIT` (default 50000000).

Every failing run and every run over the limit is also written to
`<out without .csv>.failures.csv`, with the columns
`state,iret,status,check,exit_code,reason,log`. `reason` joins the causes with
`;`, for example `status=timeout;no_PASS;exit_code=none` or `iret>50000000`.
The file always has its header, so an old list is never left behind.

The batch exits with 1 if there was any failure or any run over the limit.
Rows keep the order of the input file. Logs are named `NNNNNN-<state>.log`.

The CSV and the failures list are written only after all runs have finished.
A batch that stops early leaves an existing CSV at the `-o` path unchanged.
Early stops include a bad states line, an empty states file, a failed
pre-flight check or Ctrl-C. The log directory is created after the pre-flight
checks. Old logs in it are not deleted, but every state that runs overwrites
its own log.

The progress counter `[k/n]` on stderr counts finished runs. Workers update
it under a lock, so each finished run gets its own `k`. Lines appear in
completion order, not input order.

Output files are not gitignored, so write them somewhere outside the commit
(for example `/tmp` or an ignored `build/`) unless you mean to keep them.

### Timeouts

`-t` is Ripes' `--timeout` for the simulation of one state. The default is
300000 ms. A timed-out run has no iret, because Ripes writes no report.

- **Pipelined models need a larger `-t`.** On this Mac, the trivial loop
  `tools/smoke/spin_count.s` (2,000,005 instructions) ran at:

  | Model | Processes | instr/s |
  |---|---|---|
  | `RV32_ISS` | 1 | about 2.9e7 |
  | `RV32_5S` | 1 | about 2.7e5 |
  | `RV32_5S` | 10 parallel | about 1.8e5 |

  At 1.8e5 instr/s, a 5e7-instruction run on `RV32_5S` needs about 280 s,
  which is very close to the 300000 ms default. For `RV32_5S` and the other
  pipelined models, pass a larger `-t` (for example `-t 1200000`), lower
  `-j`, or both. `ripes-batch.sh` prints a reminder when `-p` is not
  `RV32_ISS` and no `-t` was given. These rates come from a smoke loop.
  Measure your own program with `ripes-rate.sh`.
- **Tiny timeouts race.** With `--timeout` of 1, 5 or 20 ms, Ripes often
  printed `Program exited with code: 0` for a 2-instruction program and
  *then* the timeout error. It then exited with 1 and wrote no report (about
  8 of 10 runs). At 100 ms and above this was not seen. `ripes-run.sh`
  classifies such a run as `timeout`, with an empty iret. Its `exit_code`
  column shows the code that was printed, and a note is added to the log.
  This matters only for very small `-t`. The batch pre-flight assembly check
  uses `-t 1` on purpose and accepts either outcome.

### Ripes CLI facts (observed with v2.2.6-106-g5b8a616 on macOS)

- Program console output goes to **stdout**. So do the Ripes messages for
  assembly errors, timeouts and a missing input file (`ERROR: ...`,
  `INFO: ...`). The one exception seen: an invalid `--proc` writes
  `ERROR: Invalid processor model specified '...' (--proc).` to **stderr** and
  the usage text to stdout. `ripes-run.sh` keeps both streams in the console
  log, and `ripes-rate.sh` merges them. Without `--output`, the report is
  printed to stdout *after* the console output and the
  `Program exited with code: N` line. With `--output FILE`, only the report
  goes to FILE. The runners always use `--json --output`.
- `print_string` (a7=4) also writes the string's terminating NUL byte to
  stdout. The runners strip NUL bytes from logs. Ripes adds a newline before
  `Program exited with code: N`.
- The JSON keys are `"# instructions retired"`, `"cycles"` and
  `"execution time (ms)"`. Each is a plain integer.
- The process exit status is 1 for assembly errors, timeouts and a missing
  input file. It is **0** in all of these cases:
  - normal runs, whatever exit code the program passes;
  - silent stops: a jump to an unmapped PC, an unknown ecall number, or
    running off the end of `.text`. Ripes writes a report but prints no exit
    line;
  - an invalid `--proc`, where Ripes prints usage and writes no report.
- Illegal or extension instruction words do **not** stop a run. They are
  retired as no-ops, or executed on `RV32_ISS` in the M-extension case. See
  "Not detected by the runners: raw encodings" above.
- On a timeout Ripes prints
  `ERROR: Simulation did not finish within the specified timeout (N ms)`,
  exits with 1 and writes no report. According to `src/cli/clirunner.cpp`
  (not tested here), the timer starts after assembly, so `--timeout` covers
  only the model run, and `--timeout 0` disables the limit.
- Assembly errors give the message only, with no line number. Example:
  `ERROR: Error during assembly:` followed by `INFO: Unknown symbol 'foo'`.
- `#` comments after directives and instructions are accepted. `#` inside a
  `.string` literal is kept as text. `.equ NAME,1` and `.equ  NAME , 1` both
  work.
- Loads from unmapped addresses return 0 and misaligned loads succeed. Neither
  is reported.
- On `RV32_ISS`, an exit ecall that is followed by another instruction is
  reported with one extra retired instruction (for example 4 instead of 3).
  `RV32_5S` reports 3 in both layouts.
- One Ripes CLI process used about 75 MB maximum RSS on a trivial program.
- Every Ripes process writes `ripes_system.h` into `$TMPDIR`. The runners
  start Ripes with `TMPDIR` set to the run's own temporary directory, so
  parallel runs share no files and nothing is left behind.

### Smoke tests (`tools/smoke/`, not homework code)

| File | Expected result |
|---|---|
| `marker.s` | Echoes its `@STATE` string and prints `RENDER-ON`/`RENDER-OFF`, `sum=55` and `PASS`. Exits with 0. Covers both guard styles. |
| `fail.s` | Prints `FAIL`, exits with 1. |
| `forever.s` | Spins forever. Use a short `-t` to test the timeout path. |
| `asm_error.s` | Uses `mul`, so the result is `asm_error` (RV32I only). |
| `no_exit.s` | Runs off the end of `.text`, so the result is `sim_error` with `exit_code=none`. |
| `varied.s` + `states_mixed.txt` | The first state digit selects the outcome: pass, `FAIL`, no token, or timeout. The iret grows with the digit. |
| `states5.txt` | Five arbitrary states with comment lines, blank lines and `state|solution` suffixes. |
| `spin_count.s` | About 2,000,000 retired instructions. Input for `ripes-rate.sh`. |
| `raw_word.s` | Contains a raw `.word` `mul` encoding. `ripes-run.sh` reports `ok` and prints 36 on `RV32_ISS` and 6 on `RV32_5S`. `rv32i-audit.sh` must fail it (exit 1). Shows what the runners cannot detect. |

```sh
scripts/ripes-run.sh tools/smoke/marker.s 12345671111111
scripts/ripes-run.sh -t 2000 tools/smoke/forever.s
scripts/ripes-batch.sh -j 2 -o /tmp/smoke/marker.csv tools/smoke/marker.s tools/smoke/states5.txt
IRET_LIMIT=10000 scripts/ripes-batch.sh -j 2 -t 3000 -o /tmp/smoke/varied.csv \
    tools/smoke/varied.s tools/smoke/states_mixed.txt   # expect 3 failures, 1 over limit, exit 1
scripts/ripes-rate.sh -H -p RV32_5S tools/smoke/spin_count.s
scripts/ripes-rate.sh tools/smoke/no_exit.s        # expect a failure message, exit 1
scripts/ripes-run.sh tools/smoke/raw_word.s        # ok, prints 36 (RV32_ISS)
scripts/rv32i-audit.sh -q tools/smoke/raw_word.s   # expect FAIL, exit 1
```

## refbuild.sh and rv32i-audit.sh

These two scripts are toolchain helpers. They build a C file as the GCC RV32I
reference, report its section sizes, and check object code for anything that
is not base RV32I. They do not contain or generate homework code. Which C file
to build, and what the numbers mean, are the student's job.

### Toolchain

- Homebrew `riscv64-elf-gcc` 16.2.0 and `riscv64-elf-binutils` 2.47
  (`riscv64-elf-as --version`: `GNU assembler (GNU Binutils) 2.47.20260726`),
  installed with `brew install riscv64-elf-gcc` into `/opt/homebrew/bin`.
- The assignment's `riscv64-unknown-elf-gcc` is the same GNU toolchain
  (GCC + binutils for bare-metal RISC-V ELF). Only the target triplet in the
  name differs: Homebrew configures `--target=riscv64-elf` and riscv-gnu-toolchain
  defaults to `riscv64-unknown-elf`. Both produce RV32 code with
  `-march=rv32i -mabi=ilp32`. This build ships an `rv32i/ilp32` multilib
  (`riscv64-elf-gcc -print-multi-lib`), so libgcc exists for rv32i, but the
  scripts never link it.
- This Homebrew build is configured `--without-headers`, so it has no C
  library (no newlib, no `printf`). Even `#include <stdint.h>` fails unless
  `-ffreestanding` is given. With it, GCC's own freestanding headers
  (`stdint.h`, `stddef.h`, `stdbool.h`, `limits.h`) work.
- `-ffreestanding` also implies `-fno-builtin`, so code generation is not
  identical to the plain `-O2 -march=rv32i -mabi=ilp32` named by the
  assignment. Two differences were seen with throwaway files:
  - With plain flags, a zeroing loop over an array became a `memset` call.
    With `-ffreestanding`, the loop stays a loop.
  - With plain flags, an explicit 8-byte `memcpy(dst, src, 8)` was expanded
    inline. With `-ffreestanding`, it stays a call, which then fails because
    no C library is linked.

  Code that never names `memcpy`/`memset`/... and has no such loops compiles
  to the same instructions either way (`sum.c`, `datasec.c`). Adding
  `-fbuiltin` (or `-fhosted`) as an extra flag restores both behaviours.
- To use another installation, set `CC=riscv64-unknown-elf-gcc` (binutils
  prefix derived from it) or `RISCV_PREFIX=...`.

Checks that were run:

```sh
riscv64-elf-gcc -O2 -march=rv32i -mabi=ilp32 -ffreestanding -c x.c      # ok; e_flags 0x0, Tag_RISCV_arch "rv32i2p1"
riscv64-elf-gcc -O2 -march=rv32i -mabi=ilp32 -c x.c                     # fails if x.c includes <stdint.h>
riscv64-elf-gcc -O2 -march=rv32i -mabi=ilp32 -ffreestanding -nostdlib s.c -o s.elf   # ok
```

### refbuild.sh

```sh
scripts/refbuild.sh [--elf OUT.elf] [--disasm OUT.txt] [--map OUT.map] FILE.c [EXTRA_CFLAGS...]
```

Steps:

1. Compile with `riscv64-elf-gcc -O2 -march=rv32i -mabi=ilp32 -ffreestanding -c FILE.c`.
   Extra flags are appended, so `-Os`/`-O3` override `-O2`, and `-fbuiltin`
   undoes the `-fno-builtin` implied by `-ffreestanding` (see Toolchain).
2. Run `rv32i-audit.sh` on the object.
3. Link with `-nostdlib -nostartfiles -static -T tools/rv32/ripes.ld` together
   with `tools/rv32/crt0.S`. No libgcc and no libc are linked.
4. Audit the linked ELF.
5. Print the sizes.

Exit status: 0 = OK, 1 = compile/link error, audit failure, crt0 placement
error, or static data over budget, 2 = usage error or missing tool.
`--help` prints the usage and exits 0.

Output files:

- `--elf` is written only when the exit status is 0, so a rejected ELF is
  never left behind for a runner. If a file from an earlier run already
  exists at that path, it is left unchanged and a warning says so.
- `--disasm` and `--map` are diagnostics. They are also written when a
  post-link check fails (over budget, crt0 placement, ELF audit), and the
  output then marks them `(written for diagnosis; the build FAILED)`.
- The `--disasm` header names the `--elf` file, or
  `(linked from FILE.c by refbuild.sh; ELF not saved)` when `--elf` is not
  given. It never names a deleted temporary path.

The output shows the exact compile and link commands. Example (smoke program;
the compiler/compile/link lines are omitted here):

```
$ scripts/refbuild.sh --elf /tmp/sum.elf tools/smoke/sum.c
  sizes    : riscv64-elf-size -A <linked ELF>   (bytes)
    .text                    92   linked .text = 28 crt0 + 64 compiled from tools/smoke/sum.c
    .rodata                   0
    .srodata                  0
    .data                     0
    .sdata                    4
    .sbss                     0
    .bss                      0
    static data total         4 / 131072 bytes (all allocated non-code sections)
  audit    : PASS (rv32i-audit.sh on object and linked ELF)
  elf      : /tmp/sum.elf (entry 0x40)
refbuild: OK
```

**How "linked .text bytes" is measured.** It is the `.text` row of
`riscv64-elf-size -A` on the ELF linked with `tools/rv32/ripes.ld`:

- `ripes.ld` gathers every code input section (`.text`, `.text.*`, including
  `.text.startup`, where GCC places `main` at -O2) plus crt0 into that one
  section.
- The number is taken after linker relaxation, so a `call` may become a
  single `jal`, and small-data accesses may become gp-relative.
- The number depends on the layout. Relaxation turns `lui` + `lw`/`sw`/`addi`
  into one gp-relative instruction only when the target is within ±2 KiB of
  gp, so the gp value changes both the size and the instruction count.
  - `ripes.ld` sets `__global_pointer$` with exactly the formula of GNU ld's
    default RISC-V script:
    `MIN(__SDATA_BEGIN__ + 0x800, MAX(__DATA_BEGIN__ + 0x800, __BSS_END__ - 0x800))`.
    The C part of `.text` therefore matches a link of the same object with the
    default script.
  - This was checked on the smoke programs and three throwaway files (large
    `.bss`, no small data, a zeroing loop). `.text` and the number of
    gp-relative accesses were equal in every case, e.g. `datasec.c` main is
    160 B both ways.
  - An earlier `ripes.ld` used `gp = start of small data + 0x800`. It relaxed
    fewer accesses: `datasec.c` main was 168 B.
  - Any other linker script or memory map can still differ by a few bytes.
    Quote the number as "linked with tools/rv32/ripes.ld".
- crt0 contributes 28 bytes (7 instructions), computed from
  `__crt0_start`/`__crt0_end`. The script prints it separately, so you can
  quote the total or the C-only part, but say which one you quote.
- `riscv64-elf-size` without `-A` (Berkeley format) would merge `.rodata`
  into "text", so do not use it for this number. For `datasec.c`, Berkeley
  "text" is 220 = 188 `.text` + 32 `.rodata`.

**Static data.** This is the sum of all allocated, non-executable sections
(`.rodata .srodata .data .sdata .sbss .bss`, plus any other allocated section,
which is listed). The script fails above 131072 bytes. GCC puts objects of
8 bytes or less in `.sdata`/`.sbss`/`.srodata` (`-msmall-data-limit=8`), so
those sections belong to the budget too.

Link-time failures:

- Any libgcc helper (`__mulsi3 __divsi3 __udivsi3 __modsi3 __umodsi3 __muldi3
  __popcountsi2 __clrsbsi2 ...`; see rv32i-audit.sh) fails the build.
- So does an undefined `memcpy`/`memset`/`memmove`/`memcmp`. Two sources
  are possible:
  - an explicit call in the source, which stays a call under `-fno-builtin`;
  - a call GCC emits itself. With `-fbuiltin`, a copy or clear loop can
    become `memcpy`/`memset`. Under the default `-ffreestanding`, struct
    copies of 256 B, 4 KiB and 32 KiB were still expanded inline, and no such
    call was seen.

  The failure message prints a hint about `-fbuiltin`.
- Any other undefined function (e.g. `putchar`) fails at link time, with a hint.

### crt0 and linker script (`tools/rv32/`)

- `crt0.S` does `gp = __global_pointer$`, `sp = 0x7ffffff0` (Ripes' default),
  `call main`, `a7 = 93`, `ecall`. Ripes prints `Program exited with code: <main's return value>`.
  It does **not** clear `.bss`: Ripes memory reads 0 until written and is
  cleared on reset, which `tools/smoke/datasec.c` checks.
- Memory map, mirroring the Ripes assembler defaults: `.text` at
  `0x00000000`, then `.rodata .data .srodata .sdata .sbss .bss` from
  `0x10000000`, stack top `0x7ffffff0`.
- `__global_pointer$` uses the GNU ld default formula (see "How linked
  .text bytes is measured"). The script defines `__DATA_BEGIN__` (start of
  `.data`), `__SDATA_BEGIN__` (start of `.srodata`, followed by `.sdata`)
  and `__BSS_END__` for it. `.rodata` sits just below `.data`, but the
  formula never places gp within reach of it, the same as in the default
  layout.
- crt0 is placed **last** in `.text`, and Ripes starts at `e_entry`
  (`_start`), not at address 0. The reason is that on `RV32_ISS` an exit ecall
  followed by another instruction in `.text` makes Ripes *execute* and count
  that next instruction (`rviss.h` finishes "in the next cycle"). Two
  throwaway checks confirmed this:
  - `li a0,3; li a7,93; ecall; addi a1,a1,7` gives iret 4 and `a1 = 7` on
    RV32_ISS, but 3 and `a1 = 0` on RV32_SS/RV32_5S. `a7 = 10` behaves the
    same.
  - The first crt0 layout, with `j .` after the ecall, gave 319 on RV32_ISS
    and 318 on RV32_SS/RV32_5S for `sum.c`.

  With the ecall last, all three models report 318. `refbuild.sh` fails if
  anything ends up after the crt0 ecall. The same quirk applies to
  hand-written assembly: an exit ecall that is not the last instruction of
  `.text` costs one extra instruction on RV32_ISS, and that instruction
  actually runs.
- Ripes ELF loading (`src/cli/programutilities.cpp` at 5b8a616):
  - Ripes copies **every** non-`.debug` section to its `sh_addr`, including
    non-allocated ones (`.symtab`, `.strtab`, `.comment`, `.riscv.attributes`
    at address 0).
  - It applies them in alphabetical name order, so `.text` (at 0) is written
    last and survives. Keep data away from low addresses.
  - It requires a section literally named `.text`. Only `.text` counts as
    executable, and the run also ends when the PC leaves it.
  - It accepts only ELF32 `ET_EXEC` with the RISC-V machine type.

### rv32i-audit.sh

```sh
scripts/rv32i-audit.sh [-q] [--defsym NAME=VALUE]... FILE   # FILE: .s/.asm, .S, .o or ELF
```

- **Assembly sources** are assembled with `riscv64-elf-as -march=rv32i -mabi=ilp32 -g`.
  `.S` files go through `riscv64-elf-gcc -c -x assembler-with-cpp`. GNU as
  already rejects every extension opcode and reports its line, e.g.
  `ext-mul.s:7: ... mul a0,a0,a1', extension 'm' or 'zmmul' required`. These
  are reported as FAIL.
- **Assembled code** (and every ELF) is disassembled with
  `riscv64-elf-objdump -d -l -M no-aliases`. Every mnemonic in an executable
  section must be one of the 40 RV32I instructions (`fence.tso`/`pause` are
  accepted as FENCE encodings). The rest is flagged by category:
  - M (`mul*/div*/rem*`)
  - C (`c.*` or 16-bit encodings)
  - RV64 (`*w`, `ld`, `sd`, `lwu`)
  - F/D, A, Zicsr, Zifencei
  - raw `.word`/`.insn` data in code

  Each finding shows the section, address, function and, for sources, `file:line`.
- **Symbols.** Any libgcc helper name is flagged, whether defined or
  undefined, and so is an undefined `mem*`. ELF class, `e_flags` (RVC,
  float ABI) and `Tag_RISCV_arch` are printed.
  - The helper names come from the toolchain itself: every global symbol
    defined in `$(riscv64-elf-gcc -march=rv32i -mabi=ilp32 -print-libgcc-file-name)`.
    That is 225 names for GCC 16.2.0, including `__clrsbsi2`,
    `__clrsbdi2`, `__gcc_bcmp`, `__udiv_w_sdiv`, `__emutls_get_address`
    and `_Unwind_*`.
  - If that `libgcc.a` cannot be found, a built-in name pattern is used and a
    note says so. The pattern matches all 225 names as well.
  - Every other undefined symbol, including `__*` names such as
    `__global_pointer$`, is listed in a note and never hidden.
  - A *defined* helper name is reported as "libgcc code linked in, or an own
    routine using a libgcc name". If you wrote the routine yourself, rename
    it.
- **NOT AUDITED instead of PASS.** The script exits 2, never 0, when it
  could not check the file:
  - no instruction was found in any executable section (an empty file, or
    code placed in a data section);
  - an executable ELF has no symbol table (stripped), so libgcc code linked
    into it cannot be recognised by name. Audit the unstripped ELF instead.

  A relocatable object (`.o` or assembled source) without symbols is fine:
  it cannot call anything.
- **Exit status:** 0 = pass, 1 = violations, 2 = not audited (usage, missing
  tool, GNU as cannot assemble the file, no instructions, or a stripped
  executable). `--help` prints the usage and exits 0.
- **Limitation: GNU as is not the Ripes assembler.** Ripes accepts some
  syntax that GNU as rejects. Two examples were seen: comma-less operands
  (`mv t0 a0`, as in Ripes' own `consolePrinting.s`), and Ripes peripheral
  symbols such as `LED_MATRIX_0_BASE`. In those cases the script prints
  `NOT AUDITED` and exits 2. It never reports a pass for such a file. It exits
  1 if it also saw extension opcodes. To fix:
  - add the commas, which Ripes accepts too;
  - pass `--defsym LED_MATRIX_0_BASE=0xf0000000` (any value) for each symbol;
  - or audit a preprocessed copy, e.g. the output of `scripts/ripes-prep.sh`.

  Ripes itself, without `--isaexts`, also refuses `mul` at assembly time
  (`ext-mul.s`: `Unknown opcode 'mul'`, exit 1). With `--isaexts M` it
  accepts the instruction and runs it, so never pass `--isaexts` for
  homework runs. The audit adds checks for helper calls and for GCC output.

### Smoke tests (`tools/smoke/`, not homework code)

| File | Expected result |
|---|---|
| `sum.c` | Sums 1..100 (bound is `volatile`), returns 0 if the sum is 5050. Builds, and Ripes prints `Program exited with code: 0`. Observed iret: 318 on RV32_ISS, RV32_SS and RV32_5S. |
| `datasec.c` | Reads `.rodata`/`.data` and checks that `.bss`/`.sbss` are zero. Exits with 0. Observed iret: 342 on RV32_ISS, RV32_SS and RV32_5S. It was 344 before the gp fix, when two small-data loads were not relaxed. |
| `mul.c` | `a * b` of two run-time ints. `refbuild.sh` must fail with `__mulsi3` (exit 1). |
| `ext-mul.s` | Contains `mul`. `rv32i-audit.sh` must fail (exit 1). |

```sh
tools/smoke/refbuild-smoke.sh      # 8 checks: the four files above, plus regression checks
                                   # on throwaway one-liners generated in a temp dir
                                   # (__clrsbsi2 flagged; NOT AUDITED for an empty .s and a
                                   # stripped ELF; no --elf on a failed build, --help exits 0;
                                   # datasec.c .text equal to a default-script link)
scripts/refbuild.sh --elf /tmp/sum.elf tools/smoke/sum.c
../.tools/Ripes-v2.2.6-106-g5b8a616-mac-universal2.app/Contents/MacOS/Ripes \
    --mode cli --src /tmp/sum.elf -t elf --proc RV32_ISS --iret --timeout 60000
#   Program exited with code: 0
#   ===== instructions retired
#   318
```
