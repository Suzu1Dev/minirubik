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
- Wrote `tools/oracle/` (an exact-distance oracle that includes the unmodified upstream `solver.c`) and generated `tests/dist11.txt` (all 2,644 distance-11 states) as test data for gates H1, H3, and the worst-case check. The H1–H4 gate programs themselves were not written.
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
- 1.3, 1.4, 2.1–2.4, and 2.7: student's Chinese bullets translated into English; flagged items resolved by the student. For 2.2 and 2.3 the tool first explained the baseline code (Cantor expansion, base-3 orientation rank, FIFO argument) before the student wrote the bullets. The 2.4 per-update instruction figure is cited as the assignment's estimate.
