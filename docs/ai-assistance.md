# AI assistance log

This log records material assistance provided during development. It does not claim that the student has reviewed, independently reproduced, or adopted the output unless that has actually happened. Add the student's decisions and checks as work proceeds.

## October 5 2026 preparation

Tool: OpenAI Codex.

Request: help the student work through HW1.

Assistance performed:

- Retrieved and read the assignment, its linked AI guidelines, and upstream source material.
- Cloned `sysprog21/minirubik` locally at commit `231796cc48868f4ea276f652139b6bebbad0cd02`.
- Checked the local tools and downloaded an official Ripes continuous package into the project tools directory. Verified the downloaded archive against GitHub's published SHA-256 digest.
- Ran the unchanged upstream C checks and the unchanged upstream Ripes console example on `RV32_ISS` and `RV32_5S` as environment checks.
- Resolved a local build configuration issue by selecting the already-installed Command Line Tools for the command.
- Drafted an English working checklist and baseline reading questions in `hw1-plan.md`.

Output status: source files for the student's algorithm and assembly have not been written or modified. No student performance experiments, optimization conclusions, or submission analysis have been produced. No GitHub fork, remote push, HackMD publication, form submission, or message to the instructor was performed.

Student review and decisions: pending; record the actual review, independent checks, and decisions here as they occur.

## October 7 2026 fork connection and source walkthrough

The student reported that they had created a fork and requested an explanation of the original program before implementation.

Codex found `Suzu1Dev/minirubik`, fetched it, connected it as `origin`, retained the teacher's repository as `upstream`, and set local `main` to track `origin/main`. The fork and checkout both pointed to the same baseline commit. Existing local documentation was preserved.

For the source walkthrough, Codex read the original `solver.c` and ran its existing binary on the solved state, a state obtained by applying one R turn to solved, and the assignment's distance-11 example. These were illustrative functional runs, not performance measurements or validation of a new implementation. Explanations in this chat cover the upstream state representation, moves, ranking, BFS construction, and solution lookup.

The student's solver implementation and understanding have not yet been assessed. No solver source changes or remote pushes were made in this step.

## October 7 2026 tooling, test data, and concept tutoring

Tool: Claude Code (Claude Opus 5.5), including background subagents.

At the start of the session, the course boundary was restated to the student: the state representation, search design and admissibility argument, every reported measurement, the optimization reasoning, the RV32I assembly, and the analysis in the note are to be the student's own and were not produced by the tool. The student chose to have the tool do tooling, test data, concept tutoring, and later review of the student's own code.

Assistance performed:

- Corrected `hw1-plan.md`: the Phase 1 deadline is 23:59 (not 11:59), the submission form link is recorded, and the HackMD note must allow editing by signed-in users.
- Installed the GNU RISC-V toolchain via Homebrew (`riscv64-elf-gcc` 16.2.0, binutils 2.47) for the `-O2 -march=rv32i -mabi=ilp32` reference build.
- Wrote `scripts/refbuild.sh` (reference build, linked `.text` and static-data sizes, freestanding crt0 and linker script in `tools/rv32/`) and `scripts/rv32i-audit.sh` (flags non-RV32I instructions and libgcc helpers).
- Wrote `scripts/ripes-prep.sh`, `ripes-run.sh`, `ripes-batch.sh`, and `ripes-rate.sh` to automate Ripes CLI runs. They only run programs and collect numbers; no homework program was run or measured.
- Wrote `tools/oracle/` (an exact-distance oracle that includes the unmodified upstream `solver.c`) and generated `tests/dist11.txt` (all 2,644 distance-11 states) as test data for gates H1, H3, and the worst-case check. The H1–H4 gate programs themselves were not written in this session. They were written on October 8 as `c/gates.c`; see "October 8 2026 C reference implementation of the student's design" below.
- Every tool was smoke-tested only with throwaway programs under `tools/smoke/`, then checked by an independent verifier agent and fixed.
- Concept tutoring in chat, in question-and-answer form: the fixed corner and the order 7!·3^6, the meaning of `p`, `o`, and `twist`, permutation composition, and odd and even permutations. The student's answers and the write-up are the student's own.

Facts found by experiment that affect the student's design: the Ripes build in use rejects `.if`/`.endif` (`Unknown directive '.if'`), so the renderer switch needs comment markers or the `ripes-prep.sh` preprocessor; and on `RV32_ISS` the instruction after an exit `ecall` is also retired (iret +1 compared with `RV32_SS`/`RV32_5S`).

Output status: nothing committed or pushed. The student should review `scripts/`, `tools/`, and `tests/dist11.txt` before committing them.

Student review and decisions: pending.

## October 8 2026 note skeleton and continued tutoring

Tool: Claude Code (Claude Opus 5.5), including background subagents.

- Generated `docs/hackmd-skeleton.md`: English section headings, TODO bullets that paraphrase the assignment's requirements, empty tables, and verifiable environment facts (upstream commit, Ripes build, toolchain version). An independent subagent checked it against the specification for missing requirements and for any analysis or design content. Flagged items were removed or turned into TODOs. The skeleton contains no analysis, design choices, or measured numbers.
- Continued concept tutoring in chat: iterative deepening, admissible heuristics, IDA* optimality, pattern databases as abstractions, max versus sum of heuristics, pruning, and how the baseline's transition tables are sized. The student answered the guided questions. The design questions (which abstractions, table formats, how to use the remaining budget) were left to the student.

Student review and decisions: pending.

## October 8 2026 English wording of note sections

Tool: Claude Code (Claude Opus 5.5).

The student asked the tool to write the note directly. This was declined because the assignment names the note's analysis as the student's own work. Instead, the student writes each section's reasoning as Chinese bullet points, and the tool translates and polishes them into English without adding content. Where the bullets were wrong or incomplete, the tool flagged the problem and the student supplied the correction. Sections handled this way are listed below as they are done.

- 1.1 and 1.2: drafted in English by the student; the tool corrected grammar and terminology and flagged gaps, which the student filled.
- 1.3, 1.4, 2.1–2.7: student's Chinese bullets translated into English; flagged items resolved by the student. For 2.2 and 2.3 the tool first explained the baseline code (Cantor expansion, base-3 orientation rank, FIFO argument) before the student wrote the bullets. The 2.4 per-update instruction figure is cited as the assignment's estimate.

## October 8 2026 Stage 1 measurements

The student wrote `bench/memloop.s` and `bench/rate.s` and ran every measurement, after the tool explained the method (`/usr/bin/time -l`, control group, `ripes-rate.sh`) and the RV32I instructions needed, using an unrelated sum loop as the worked example. The tool reviewed the student's drafts and pointed out bugs (a fixed store address, a loop that compared against the length instead of the end address, and a do-while loop that never ends for LEN = 0) without rewriting them. The tool saved the student's pasted terminal output verbatim to `bench/results/`, and once wrote the student's pasted `rate.s` to disk verbatim when the file on disk still held the old program. It also computed means and ratios from the student's raw numbers as an arithmetic check, and fixed a zsh word-splitting bug in a command it had supplied.

## October 8 2026 Section 3 design write-up

The student chose IDA* with pattern databases. The tool explained IDA* and pattern databases and laid out the trade-offs (quarter-turn versus nine-move tables, byte versus nibble entries, same-face pruning) as questions, citing the assignment's own figures. The student answered each question and made each decision: quarter-turn tables, byte entries, same-face pruning, and h = max of a permutation PDB and an orientation PDB. The tool then assembled the English text of Sections 3.1–3.6 from the student's answers to the tutoring questions and the design questions. The student reviewed and confirmed it. The second half of the optimality argument in 3.5 (no state on a shortest path is cut off when the bound equals D) follows the tool's earlier explanation of Korf's argument.

The tool also reset the default `.equ LEN` in `bench/memloop.s` from 0, which never terminates, to 0x100000. The measurement command overrides LEN, so the recorded results are unaffected.

## October 8 2026 C reference implementation of the student's design

Tool: Claude Code (Claude Opus 5.5), run as a workflow of subagents: one wrote the code, independent verifier agents reviewed it and reproduced each reported issue, and a further agent fixed the issues.

The student made the design decisions recorded in the Section 3 entry above and asked the tool to write the C version of that design: IDA* with the bound starting at h(start); an explicit 12-level stack instead of recursion; upstream's `rank_state` ranks; quarter-turn tables `perm_qt[3][5040]` and `orient_qt[3][729]` chained 1, 2 or 3 times per move; h = max(`pdb_p`, `pdb_o`) with one byte per entry; same-face pruning only; and upstream's output format. The tool added no other heuristic or optimization.

Files written by the tool, all new and each with a header line that points to this log:

- `c/ida_core.h`, `c/ida_core.c`: the search core (parser, explicit-stack IDA*, move and path replay).
- `c/tables.h`, `c/tables.c`, `c/gen_tables.c`: host table generator. It includes the unmodified `solver.c` and uses upstream's own `build_table()` loop for the quarter-turn tables and a BFS over each abstraction for the PDBs.
- `c/tables_data.h` and `asm/tables.s`: generated by `c/gen_tables` on the host, as the precomputation rule allows. `asm/tables.s` contains only data directives (`.data`, `.align`, `.half`, `.byte`) and comments.
- `c/tables_embed.c`, `c/ida_host.c` (host CLI `c/ida`), `c/gates.c` (gates P and H1–H4 against `tools/oracle`, plus the `--dist11` run), `c/ripes_main.c` and `c/ripes_ref.c` (freestanding single file for the `-O2 -march=rv32i -mabi=ilp32` reference build by `scripts/refbuild.sh`), `c/Makefile`, `c/README.md`, `c/.gitignore`.

The tool wrote no RISC-V assembly for the solver, search, renderer or LED code. The RV32I reference ELF is GCC output from `scripts/refbuild.sh`. The tool ran `make -C c all check`, the full `c/gates`, `c/gates --dist11 tests/dist11.txt`, the reference build and a Ripes CLI run of the ELF, and short Ripes runs of throwaway programs that load `asm/tables.s`, to check the code. The numbers printed by these runs are diagnostics from the tool's own runs of the C reference. They are not the student's measurements and must not be reported as such.

Issues reported by the last independent review and fixed after each was reproduced:

- `asm/tables.s` had no alignment directive before `perm_qt`, so odd-length data placed before the appended file (for example the 15-byte state string) put `perm_qt` at an odd address (`0x1000000f`). Ripes still read the tables correctly. The generator now emits `.align 2` before `perm_qt`. In the Ripes build in use, `.align N` pads to N bytes, while GNU `as` pads to 2^N bytes. `.align 2` therefore gives at least halfword alignment under both. `c/gates` requires the directive.
- Without `--asm`, `c/gates` looked for `asm/tables.s` relative to the working directory, and when run from inside `c/` it skipped the comparison yet still printed PASS. The default path is now taken relative to the `gates` binary, and a missing file fails gate H2.
- `c/ida` differs from upstream `./solver` in two argument cases: `--self-test` exits 2 (upstream runs its self-test and exits 0), and `--stats STATE` exits 0 with an extra statistics line (upstream exits 2). Both are kept on purpose and are now documented in `c/ida_host.c` and `c/README.md`, and `make -C c check` tests them. `--self-test` now prints a note that points to `c/gates`.
- This log had no entry for the work above. This entry adds it, and the October 7 entry now says when the gate programs were written.

Output status: nothing committed or pushed. The student should review `c/` and `asm/tables.s` before committing them.

Student review and decisions: pending.
