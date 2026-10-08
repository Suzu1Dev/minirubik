# HW1 working plan

This is a preparation checklist and reading guide for the student. The solver design, performance experiments, assembly, and report analysis remain to be developed by the student. This file is not a completed submission.

Sources: [assignment](https://hackmd.io/@sysprog/2026-arch-homework1), [AI guidelines](https://hackmd.io/@sysprog/arch2026-ai-guidelines), and the pinned upstream [report](https://github.com/sysprog21/minirubik/blob/231796cc48868f4ea276f652139b6bebbad0cd02/report.md).

## Dates and submission

- Phase 1: October 8, 2026, **23:59 GMT+8**.
- Phase 2: October 18, 2026, **23:59 GMT+8**.
- [x] Connect the student's [GitHub fork](https://github.com/Suzu1Dev/minirubik). On October 7, `origin` was set to this fork and the teacher's repository retained as `upstream`; local `main` tracks `origin/main` at the same baseline commit.
- [ ] Create an English HackMD note, published so anyone can read it, with write permission set to **Signed-in users** (the assignment requires reviewers to be able to annotate it).
- [ ] Preserve meaningful code commits and at least three substantive note revisions as work develops.
- [ ] Tag the submitted commit and record the tag and HackMD revision URL in the submission form.
- [x] Submission form: https://forms.gle/2ZupDEdJyJkHM8Y6A (listed in the assignment as of October 7). Submission is complete only after an email whose subject ends in "accepted"; do not reply to that email.

## Environment prepared in this session

Upstream commit: `231796cc48868f4ea276f652139b6bebbad0cd02`.

Ripes package: `Ripes-v2.2.6-106-g5b8a616-mac-universal2`, downloaded from the official continuous release. Its archive SHA-256 matched the digest published by GitHub:

```text
e03ffdb0cc698bb6bcf3b4077e2fcd2e83d6559affa9126285f8de518d67c3bd
```

The portable app is in `../.tools/` relative to this repository. Both `RV32_ISS` and `RV32_5S` successfully ran the upstream console example. That example is an installation check, not homework assembly or a performance benchmark. Raw outputs are in [setup-logs](setup-logs/).

The original `make check` passed using the installed Command Line Tools. Default Xcode selection encountered a license prompt, so this session selected Command Line Tools for individual commands without changing the system configuration or accepting any agreement.

From this repository, reproduce the baseline check:

```sh
DEVELOPER_DIR=/Library/Developer/CommandLineTools make check
```

Launch the prepared Ripes app:

```sh
open ../.tools/Ripes-v2.2.6-106-g5b8a616-mac-universal2.app
```

Inspect its available command-line options:

```sh
../.tools/Ripes-v2.2.6-106-g5b8a616-mac-universal2.app/Contents/MacOS/Ripes --help
```

A RISC-V GCC executable was not found on `PATH`. Prepare the reference compiler before the assembly comparison stage. No student performance measurements have been collected, and none of H1–H4 or T5–T7 has been established for a new implementation.

## Stage 1 baseline study

Read `solver.c` in this order: `state_t`, `source` and `twist`, `quarter_turn`, `valid` and `parse_state`, `rank_state` and `unrank_state`, `build_table`, then `main`. Read sections 2, 4, and 7 of `report.md` alongside them.

Use these questions to write your own explanation:

1. What does each position in the 14-character input describe? How does it differ from the internal array value?
2. Which corner is absent from the arrays, and which moves leave it fixed?
3. Which orientation constraint must hold? How many orientation values can be chosen independently?
4. What does `source[face][destination]` mean? Trace one destination by hand.
5. What must ranking and unranking preserve?
6. Why does `build_table` store an inverse move when discovering a state?
7. Which objects dominate memory, and when are they live?
8. Which claims in report section 7 need reconsideration on Ripes?

Then design and run your own memory experiment and instruction-rate experiment. Keep the source, exact command, model, build identifier, raw output, repetitions, and interpretation. Measure `RV32_ISS` and a visual pipeline model. Distinguish guest allocation bytes from host process memory and model execution time from process startup time.

## Stage 2 representation and search

Record your candidate representations and algorithms before implementing them. Explain the target budget, how a move updates your state, why the search terminates, and why its result is shortest. Derive the admissibility argument for each heuristic you choose. Keep rejected ideas and the evidence for rejecting them.

## Stage 3 C implementation and verification

Develop and test the chosen C algorithm before translating it. Keep the upstream implementation available as an oracle. Explain your changes using operation counts and record the actual validation commands and outcomes.

- [ ] H1: compare every heuristic with exact distances throughout the domain.
- [ ] H2: verify table completeness, maxima, and solved entries.
- [ ] H3: verify the returned length for every state and record wall-clock time.
- [ ] H4: compare packed and unpacked accessors, including both index parities.

## Stage 4 RV32I and Ripes

Write the assembly yourself and retain measured intermediate versions. Plan explicit storage and control flow under the no-heap, no-recursion, no-floating-point constraints. Audit the emitted instructions and helper calls for base RV32I compatibility.

- [ ] Accept an arbitrary assembly-time 14-character state.
- [ ] Keep `.data + .bss + .rodata` within 128 KiB.
- [ ] Compare against the final C algorithm compiled with GCC `-O2 -march=rv32i -mabi=ilp32`.
- [ ] Record linked `.text` bytes and Ripes `--iret` with rendering disabled.
- [ ] Check all 2,644 distance-11 states against the 50,000,000-instruction limit on `RV32_ISS`.
- [ ] Report `21345671111111` separately.
- [ ] T5: apply returned moves and check the final state inside the target program.
- [ ] T6: check the named vector has an 11-move solution.
- [ ] T7: run the solved, short-scramble, and distance-11 cases on both required model types; retain support for unseen states.

## Display and explanation

- [ ] Drive a 35 by 25 LED Matrix with symbolic peripheral addresses and row-major indexing.
- [ ] Render a cube net and redraw from the actual returned path after each move.
- [ ] Guard the renderer at assembly time for CLI measurements.
- [ ] Prepare an IF, ID, EX, MEM, and WB walkthrough with register writes, multiplexers, memory updates, and correctness explanations.

## Learning checkpoints

At the end of each stage, explain the work aloud without relying on generated prose. Write the HackMD analysis from that explanation, link to relevant code instead of pasting full listings, and update the [AI assistance log](ai-assistance.md) with the actual division of work.
