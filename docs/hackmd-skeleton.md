---
tags: computer-arch
---

# Assignment 1: minirubik on RV32I

contributed by < [`Suzu1Dev`](https://github.com/Suzu1Dev) >

<!-- HackMD settings (spec: Documentation): published, Read = Everyone, Write = Signed-in users. All prose in English. Fill section by section and keep at least three substantive revisions. No complete listings: link to the fork and quote a few lines at a time, each with what it does and why. Links into the fork resolve only after the linked files are committed and pushed to `main`. Delete TODO bullets as they are filled. This comment and the checklist at the end may be deleted before tagging; they stay in the revision history either way. -->

[TOC]

## Result

<!-- Opening summary, modelled on the "Result" section of report.md (spec: Documentation). Fill last. -->

- TODO: short summary of what was built and what it achieves (spec: Documentation)

| Figure | Requirement (given by the assignment) | Result | Section |
| :--- | :--- | ---: | :--- |
| Worst-case `--iret` over all 2,644 distance-11 states, `RV32_ISS`, renderer compiled out | at most $5 \times 10^7$ | — | 8 |
| `.data` + `.bss` + `.rodata` | at most 128 KiB | — | 6 |
| `--iret` for `21345671111111` | reported, not graded | — | 8.1 |
| Assembly against the GCC `-O2` reference: `.text` bytes and `--iret` | assembly expected to beat it | — | 5.5 |
| H3: returned length equals exact distance for every state | required | — | 7.1 |

## Links and environment

| Item | Value |
| :--- | :--- |
| Fork (all Phase 1 work on `main`) | https://github.com/Suzu1Dev/minirubik |
| Submitted tag | <!-- TODO --> |
| Upstream and forked commit | [sysprog21/minirubik](https://github.com/sysprog21/minirubik) at `231796cc48868f4ea276f652139b6bebbad0cd02` |
| Ripes build (pinned) | `v2.2.6-106-g5b8a616`, `continuous` prerelease, asset `Ripes-v2.2.6-106-g5b8a616-mac-universal2.zip` (SHA-256 `e03ffdb0cc698bb6bcf3b4077e2fcd2e83d6559affa9126285f8de518d67c3bd`) |
| Reference toolchain | `riscv64-elf-gcc (GCC) 16.2.0`, GNU Binutils 2.47, Homebrew |
| Host machine and OS | <!-- TODO --> |
| Measurement and test tooling | `scripts/README.md` in the fork <!-- TODO: link once committed and pushed to main --> |

<!-- TODO: scripts/, tools/, tests/dist11.txt and docs/ are not on the fork's main yet; commit and push them before linking to them. The HackMD revision URL goes on the submission form only, not in this note (spec: Scope, Submission). -->

## Disclosure of AI use

:::info
This assignment is AI-assisted (AI guidelines Section 3); disclosure follows Section 4.1. Full use log: `docs/ai-assistance.md` in the fork. <!-- TODO: link once committed and pushed to main -->
:::

Named by the assignment as the student's own work: the choice of state representation, the search design and its admissibility argument, every measurement reported, the optimization reasoning, the RV32I assembly, and the analysis in this note.

### Tools used and for what

<!-- TODO: check against docs/ai-assistance.md and add anything missing -->

| Tool | Used for | Portion of work affected |
| :--- | :--- | :--- |
| OpenAI Codex | Environment setup checks, fork remote setup, walkthrough of upstream `solver.c`, working checklist | `docs/setup-logs/`, `docs/hw1-plan.md` |
| Claude Code (Claude Opus 5.5) | Checklist corrections, toolchain install, build, audit and Ripes runner scripts, exact-distance oracle and distance-11 test data, concept tutoring, skeleton of this note | `docs/hw1-plan.md`, `scripts/`, `tools/`, `tests/dist11.txt`, this note's headings, TODO prompts, empty tables and environment facts |

### What I decided that the tools did not

- TODO (guidelines 4.1: decisions, rejected suggestions and why, results verified independently)

### Use log

- TODO: summary below; full entries in `docs/ai-assistance.md`
- TODO: add the 2026-10-08 note-skeleton entry to `docs/ai-assistance.md`
- TODO: any fact a tool supplied is cited to its underlying source, not to the tool (guidelines 4.1); this includes the Ripes behaviors noted in 5.1, 7.2 and 10.4

| Date | Tool | Task | Portion affected | What happened to the output |
| :--- | :--- | :--- | :--- | :--- |
| 2026-10-05 | OpenAI Codex | Environment setup and checks | `docs/setup-logs/`, `docs/hw1-plan.md` | — |
| 2026-10-07 | OpenAI Codex | Fork remote setup, upstream source walkthrough | local checkout | — |
| 2026-10-07 | Claude Code | Tooling, test data, concept tutoring | `scripts/`, `tools/`, `tests/dist11.txt` | — |
| 2026-10-08 | Claude Code | Note skeleton | this note | — |

## 1. The state space

### 1.1 The group $\langle R, B, D \rangle$ and its order

- TODO: define the group and its generators (spec: Documentation)
- TODO: derive its order; the assignment gives $7! \cdot 3^6 = 3{,}674{,}160$

### 1.2 Cayley graph and generators

- TODO: vertices, edges, the nine HTM generators `R R2 R' B B2 B' D D2 D'` (spec: Preparation, half-turn metric)
- TODO: why this is a Cayley graph and not a Schreier coset graph (spec: References, Cayley Graph)

### 1.3 Diameter 11 by exhaustive BFS

- TODO: how BFS shows a state at depth 11 exists
- TODO: how BFS shows no state is deeper
- TODO: HTM 11 versus QTM 14 (spec: Preparation)

| Depth (HTM) | States (own run) | Jaap Scherphuis | `report.md` |
| ---: | ---: | ---: | ---: |
| 0 | — | — | — |
| 1 | — | — | — |
| 2 | — | — | — |
| 3 | — | — | — |
| 4 | — | — | — |
| 5 | — | — | — |
| 6 | — | — | — |
| 7 | — | — | — |
| 8 | — | — | — |
| 9 | — | — | — |
| 10 | — | — | — |
| 11 | — | — | — |
| Total | — | — | — |

### 1.4 The orientation-sum invariant

- TODO: the invariant $\sum o_i \equiv 0 \pmod 3$ and what it rules out; a modulo-3 invariant, not a parity (spec: Documentation)

### 1.5 Cross-check with an independent source

- TODO: corroborate the diameter in both metrics with [Jaap Scherphuis, Pocket Cube](https://www.jaapsch.net/puzzles/cube2.htm), rather than asserting it from one source (spec: References)

| Metric | Diameter (own result) | Jaap Scherphuis | `report.md` |
| :--- | ---: | ---: | ---: |
| HTM | — | — | — |
| QTM | — | — | — |

| Depth (QTM) | States (Jaap Scherphuis) | Second source |
| ---: | ---: | ---: |
| 0 | — | — |
| 1 | — | — |
| 2 | — | — |
| 3 | — | — |
| 4 | — | — |
| 5 | — | — |
| 6 | — | — |
| 7 | — | — |
| 8 | — | — |
| 9 | — | — |
| 10 | — | — |
| 11 | — | — |
| 12 | — | — |
| 13 | — | — |
| 14 | — | — |
| Total | — | — |

## 2. Stage 1: Characterizing the baseline

### 2.1 What the program computes

- TODO (spec: Stages 1)

### 2.2 How it represents a cube

- TODO (spec: Stages 1)

### 2.3 Invariants it relies on

- TODO (spec: Stages 1)

### 2.4 Where its cost lies

- TODO: memory and instruction cost (spec: Stages 1)

Dominant allocations, given by the assignment:

| Allocation | Storage | Bytes (given by the assignment) | Checked against `solver.c` |
| :--- | :--- | ---: | :--- |
| One move toward solved per state | heap | 3,674,160 | — |
| BFS queue of 32-bit ranks | heap | 14,696,640 | — |
| Factored quarter-turn transitions | automatic | 34,614 | — |
| Peak | | 18,405,414 | — |

- TODO: the assignment's ~$10^9$ instruction figure is an estimate, not a measurement; explain where it comes from

### 2.5 Measurement A: host bytes per guest byte

- TODO: read the VSRTL address-space container before measuring (spec: References)

Methodology:

- Measurement program: <!-- TODO link -->
- Ripes command and processor: <!-- TODO -->
- Loop region size and control size: <!-- TODO -->
- Host memory metric and how it was read: <!-- TODO -->
- Repetitions: <!-- TODO -->
- Raw output: <!-- TODO link -->

| Run | Guest bytes written | Host memory | Notes |
| :--- | ---: | ---: | :--- |
| Control | — | — | — |
| Large region | — | — | — |
| Ratio (host bytes per guest byte) | | — | |

- TODO: project the 18,405,414-byte baseline peak onto this machine (spec: Why the target changes the answer)

### 2.6 Measurement B: retired instructions per second

Methodology:

- Measurement program: <!-- TODO link -->
- Ripes command: <!-- TODO -->
- Repetitions: <!-- TODO -->
- Raw output: <!-- TODO link -->

| Processor | Retired | Exec time (ms) | iret/s (measured) | iret/s (given by the assignment) | Time for $10^9$ at measured rate |
| :--- | ---: | ---: | ---: | ---: | ---: |
| `RV32_ISS` | — | — | — | 1.09 million | — |
| `RV32_SS` | — | — | — | 86 thousand | — |
| `RV32_5S` | — | — | — | 20.5 thousand | — |
| `RV32_6S_DUAL` | — | — | — | 6.2 thousand | — |

- TODO: at least `RV32_ISS` and one pipelined model (spec: Stages 1); drop unmeasured rows

### 2.7 Reading `report.md` section 7 critically

- TODO: the section 7 argument for keeping the full table
- TODO: why it does not survive the move to Ripes (spec: The starting point)

### 2.8 From Stage 1 to Stage 2

- TODO: what the Stage 1 numbers require of Stage 2 (spec: Stages)

## 3. Stage 2: Representation and algorithm for the target

### 3.1 Budget

:::info
Given by the assignment: `.data` + `.bss` + `.rodata` at or under 128 KiB; no distance-11 state above $5 \times 10^7$ retired instructions on `RV32_ISS` with the renderer compiled out; transition and heuristic tables may be generated on the host and linked as read-only data; the search runs on the target; a complete distance table over all 3,674,160 states is not accepted.
:::

| Item | Entries | Size per entry | Bytes | Section | Justification (link) |
| :--- | ---: | ---: | ---: | :--- | :--- |
| — | — | — | — | — | — |
| Total | | | — | | |
| Remaining of 131,072 | | | — | | |

- TODO: justify each choice against Stage 1 numbers and this budget (spec: Stages 2)

### 3.2 State representation

- TODO: representation and how a move updates it

### 3.3 Search algorithm

- TODO: algorithm and why it terminates

### 3.4 Heuristics and admissibility argument

- TODO: each heuristic the search uses and its admissibility argument (spec: Stages 2; gate H1 in 7.1)

### 3.5 Optimality argument

- TODO: why the returned solution is always a shortest one (spec: Stages 2)

### 3.6 Pruning and its measured worth

| Rule | Kept | Measured effect | Evidence (link) |
| :--- | :--- | ---: | :--- |
| — | — | — | — |

### 3.7 Rejected ideas and negative results

| Idea | Expected | Measured | Decision | Evidence (link) |
| :--- | :--- | ---: | :--- | :--- |
| — | — | — | — | — |

### 3.8 From Stage 2 to Stage 3

- TODO

## 4. Stage 3: Efficiency in C

### 4.1 Changes and operation counts

Counts per <!-- TODO: unit of work -->.

| Step | Commit | Change | Branches | Memory accesses | mul / div / mod | Other ALU |
| :--- | :--- | :--- | ---: | ---: | ---: | ---: |
| — | — | — | — | — | — | — |

- TODO: argue each effect from the counts (spec: Stages 3)

### 4.2 Host verification of the C version

- TODO: see [7.1](#71-Host-gates)

### 4.3 From Stage 3 to Stage 4

- TODO

## 5. Stage 4: RV32I assembly

### 5.1 Measurement conventions

- Code size: bytes of linked `.text`, renderer compiled out (spec: Constraints)
- Retired instructions: Ripes `--iret`, CLI mode, pinned build `v2.2.6-106-g5b8a616`, same input across steps (spec: Constraints)
- Processor: <!-- TODO -->
- Input used for step-to-step comparison: <!-- TODO -->

:::warning
Recorded in `scripts/README.md` from AI-assisted tooling experiments (see Disclosure): on `RV32_ISS`, when the exit `ecall` is followed by another instruction in `.text`, that instruction is also executed and counted, one more retired instruction than `RV32_SS` and `RV32_5S` report. With the exit `ecall` as the last instruction of `.text`, the three models report the same count.
:::

- TODO: reproduce this or attribute it, citing the Ripes source at `5b8a616` (`rviss.h`) rather than the tool (guidelines 4.1)
- TODO: state how reported figures account for this

### 5.2 Constraint compliance

| Requirement (spec: Constraints; Precomputation rule) | How satisfied | Evidence (link) |
| :--- | :--- | :--- |
| RV32I only, no extensions | — | — |
| No `__mulsi3`, `__divsi3` or other compiler routines | — | — |
| No heap | — | — |
| No recursion | — | — |
| No floating point | — | — |
| Everything sized at assembly time | — | — |
| Arbitrary state as a 14-character string inlined at assembly time | — | — |
| Not a line-by-line translation of the C source | — | — |
| Host-generated tables linked only as read-only data; search runs on the target; no complete distance table over all 3,674,160 states | — | — |

### 5.3 Program structure and data layout

- TODO: link to source; registers, control flow, data layout (no listing)

### 5.4 Iterative refinement

| Step | Commit | Change | `.text` bytes | `--iret` | Change vs previous | Why |
| :--- | :--- | :--- | ---: | ---: | ---: | :--- |
| — | — | — | — | — | — | — |

### 5.5 Comparison with the GCC reference build

- TODO: exact command; the assignment names `riscv64-unknown-elf-gcc -O2 -march=rv32i -mabi=ilp32`, this note uses `riscv64-elf-gcc` 16.2.0; record any flag differences (see `scripts/README.md`, Toolchain)
- TODO: C source compiled (the final C algorithm), link
- TODO: how the reference build was run on Ripes for `--iret`

| Build | `.text` bytes | Static data bytes | `--iret` (same input) | Notes |
| :--- | ---: | ---: | ---: | :--- |
| GCC `-O2 -march=rv32i -mabi=ilp32` | — | — | — | — |
| Hand-written RV32I | — | — | — | — |

- TODO: explain any case where the assembly does not win (spec: Constraints)

### 5.6 RV32I-specific instruction sequences

| Operation | Where (link) | Instructions | Why base RV32I forces it | Alternative measured |
| :--- | :--- | ---: | :--- | :--- |
| — | — | — | — | — |

- TODO: short fragments only, each with what it does and why (spec: Documentation)

## 6. Memory quantified

| Object | Section | Entries | Bytes | How obtained |
| :--- | :--- | ---: | ---: | :--- |
| — | — | — | — | — |
| `.data` + `.bss` + `.rodata` total | | | — | — |
| Budget | | | 131,072 | given by the assignment |

- TODO: peak working set and how it was obtained (spec: Documentation)
- TODO: compliance with the precomputation rule: how any host-generated table enters the program, that the search runs on the target, and that no complete distance table is linked (spec: Precomputation rule)
- TODO: comparison with the baseline's 18,405,414-byte peak (given by the assignment)

## 7. Correctness gates

### 7.1 Host gates

- TODO: the exact reference the gates are checked against, and how it was obtained (spec: Correctness gates)

| Gate | Check (spec: Correctness gates) | Program / command | Result | Wall-clock | Commit |
| :--- | :--- | :--- | :--- | ---: | :--- |
| H1 | Every heuristic: $h(s) \le d(s)$ over all 3,674,160 states | — | — | — | — |
| H2 | Every table fully populated; maximum and solved entry verified | — | — | — | — |
| H3 | Returned length equals exact distance for every state | — | — | — (required) | — |
| H4 | Any packed accessor agrees with unpacked reference at even and odd indices | — | — | — | — |

### 7.2 Target gates

:::info
Recorded in `scripts/README.md` from AI-assisted tooling experiments (see Disclosure): the Ripes CLI reports the program's exit code only as the console line `Program exited with code: N`. The Ripes process exits 0 for a normal run, whatever exit code the program passes; it exits 1 on assembly errors, timeouts and a missing input file.
:::

- TODO: reproduce this or attribute it, citing the Ripes source at `5b8a616` rather than the tool (guidelines 4.1)
- TODO: how the program reports pass or fail

| Gate | Check (spec: Correctness gates) | How | Result |
| :--- | :--- | :--- | :--- |
| T5 | Applying every returned path reaches solved | — | — |
| T6 | `21345671111111` returns an optimal 11-move solution | — | — |
| T7 | Own test cases and grader states reproduce on `RV32_ISS` and a visual pipeline model | see [9](#9-Test-cases) | — |

## 8. Worst case over all distance-11 states

- Inputs: all 2,644 distance-11 states (count given by the assignment); source and how it was checked: <!-- TODO -->
- Setup: `RV32_ISS`, renderer compiled out, Ripes `v2.2.6-106-g5b8a616`; command <!-- TODO -->

| Quantity | Value |
| :--- | ---: |
| States run | — |
| Maximum `--iret` (pass: at most $5 \times 10^7$) | — |
| State at the maximum | — |
| Minimum `--iret` | — |
| States above $5 \times 10^7$ | — |
| Raw results (link) | — |

### 8.1 Reference vector `21345671111111`

Reported separately, not graded against a threshold (spec: What counts as done).

| Processor | `--iret` | Returned solution | Length |
| :--- | ---: | :--- | ---: |
| `RV32_ISS` | — | — | — |

## 9. Test cases

| Case | 14-character input | Exact distance | Returned path | In-program check | `RV32_ISS` | Pipelined model: <!-- TODO --> | `--iret` (`RV32_ISS`) |
| :--- | :--- | ---: | :--- | :--- | :--- | :--- | ---: |
| Solved | — | — | — | — | — | — | — |
| Short scramble | — | — | — | — | — | — | — |
| Distance 11 | — | — | — | — | — | — | — |
| Grader-supplied | — | — | — | — | — | — | — |

- TODO: how results are validated inside the program (spec: Constraints)
- TODO: where the input string lives in the source (link)

## 10. LED matrix visualization

### 10.1 Peripheral setup

- Given by the assignment: Width 35, Height 25; Ripes lists Height above Width
- TODO: screenshot of the I/O tab

### 10.2 Net layout

- Given by the assignment: six faces in a 4 by 3 slot box, 8 by 6 facelets, 4 by 3 pixels per facelet, separators give 35 by 20
- TODO: own layout diagram (face placement, facelet order)
- TODO: show that the six face colors remain distinguishable throughout (spec: Visualization)

| Face | Color (24-bit RGB) |
| :--- | :--- |
| — | — |

### 10.3 Address mapping derivation

- Given by the assignment: one 32-bit word per LED, row-major `y * WIDTH + x`; use `LED_MATRIX_0_BASE`, `LED_MATRIX_0_WIDTH`, `LED_MATRIX_0_HEIGHT`; the in-GUI column-major formula is wrong
- TODO: derive the address of a facelet pixel and its RV32I computation

### 10.4 Renderer switch

:::warning
Recorded in `scripts/README.md` from AI-assisted tooling experiments (see Disclosure): the assembler in this Ripes build has no `.if` / `.else` / `.endif` (`Unknown directive '.if'`), and in CLI mode the `LED_MATRIX_0_*` symbols are undefined.
:::

- TODO: reproduce this or attribute it, citing the Ripes source at `5b8a616` rather than the tool (guidelines 4.1)
- TODO: the switch used and why
- TODO: state that the GUI and CLI builds differ only in the renderer, and how that is ensured (spec: Visualization)

### 10.5 Redraw after every move

- TODO: how each redraw is driven by the solver's actual output (spec: Visualization)
- TODO: screenshots or animation

## 11. Instruction-level walkthrough

- Processor model: <!-- TODO -->
- Instruction(s) traced: <!-- TODO link -->

| Stage | Instruction in stage | Signals (register write enable, mux selects, ...) | Screenshot |
| :--- | :--- | :--- | :--- |
| IF | — | — | — |
| ID | — | — | — |
| EX | — | — | — |
| MEM | — | — | — |
| WB | — | — | — |

- TODO: program behavior around the traced instruction(s)
- TODO: how memory is updated and why the result is correct (spec: Instruction-level walkthrough)

## 12. Reflection and development process

### 12.1 Development timeline

| Date | Commit or HackMD revision | What changed |
| :--- | :--- | :--- |
| — | — | — |

### 12.2 Research process and outline

- TODO: research process and how the outline of this note developed (guidelines 4.2, written work)

### 12.3 Key difficulties, debugging, and resolutions

- TODO: debugging, alongside the testing and validation in 7 and 9 (guidelines 4.2, code projects)

| Difficulty | How it was found and debugged | Resolution | Evidence (link) |
| :--- | :--- | :--- | :--- |
| — | — | — | — |

### 12.4 Revisions and process evidence

- TODO: links to at least three substantive note revisions (spec: Documentation; guidelines 4.2)
- TODO: problem-solving across iterations, shown in commits (guidelines 4.2, code projects)
- TODO: if evidence is thin for a legitimate reason, say so and point to equivalent evidence

### 12.5 Reflection on the development process

- TODO: short reflection on the development process (guidelines 4.2, all major assignments)

## Changes after the submitted tag (optional)

- TODO: if work continues after the tag, what changed and why (spec: Scope)

| Date | Commit | What changed | Why | Measured effect |
| :--- | :--- | :--- | :--- | ---: |
| — | — | — | — | — |

## Bonus (optional)

- TODO if attempted (spec: BONUS)

## References

1. sysprog21/minirubik, [`report.md`](https://github.com/sysprog21/minirubik/blob/231796cc48868f4ea276f652139b6bebbad0cd02/report.md) at `231796cc48868f4ea276f652139b6bebbad0cd02`.
2. Jaap Scherphuis, [Pocket Cube](https://www.jaapsch.net/puzzles/cube2.htm).
3. Eric W. Weisstein, [Cayley Graph](https://mathworld.wolfram.com/CayleyGraph.html), MathWorld.
4. Morten Borup Petersen, [Ripes](https://github.com/mortbopet/Ripes) and its [documentation](https://github.com/mortbopet/Ripes/tree/master/docs).
5. [VSRTL sparse address space](https://github.com/mortbopet/VSRTL/blob/master/include/VSRTL/core/vsrtl_addressspace.h).
6. Andrew Waterman and Krste Asanović, eds., [The RISC-V Instruction Set Manual, Volume I](https://github.com/riscv/riscv-isa-manual/releases/latest).
7. RISC-V International, [RISC-V Assembly Programmer's Manual](https://github.com/riscv-non-isa/riscv-asm-manual).

<!-- TODO: add the sources actually relied on; cite underlying sources, never an AI tool (guidelines 4.1) -->

<!-- REQUIREMENTS CHECKLIST (may be deleted before tagging)
Structure
- [ ] report.md as the model for register and structure, opening summary of results -> Result

Preparation
- [ ] Ripes build with RV32_ISS; version recorded -> Links and environment
- [ ] Forked commit recorded -> Links and environment
- [ ] All Phase 1 work committed and pushed to main of the fork, meaningful messages -> Links and environment; 12.1 Development timeline
- [ ] Files linked from the note (scripts/, tools/, tests/dist11.txt, docs/) committed and pushed so links resolve -> Links and environment; Disclosure of AI use
- [ ] Moves counted in HTM -> 1.2 Cayley graph and generators

Stages
- [ ] Each stage its own section, with reasoning into the next -> 2.8, 3.8, 4.3
- [ ] Stage 1: what it computes, representation, invariants, cost -> 2.1 to 2.4
- [ ] Stage 1: host bytes per guest byte, tight loop vs control, projected 18,405,414-byte peak -> 2.5 Measurement A
- [ ] Stage 1: iret per second on RV32_ISS and at least one pipelined model -> 2.6 Measurement B
- [ ] Stage 1: why the report.md section 7 argument fails on Ripes -> 2.7 Reading report.md section 7 critically
- [ ] Stage 2: representation and algorithm fit the target -> 3.2, 3.3
- [ ] Stage 2: optimal solution, and shown to be -> 3.5 Optimality argument
- [ ] Stage 2: choices justified against Stage 1 numbers and the budget -> 3.1 Budget
- [ ] Stage 2: admissibility argument -> 3.4 Heuristics and admissibility argument
- [ ] Prunings measured before being kept -> 3.6 Pruning and its measured worth
- [ ] Negative results reported -> 3.7 Rejected ideas and negative results
- [ ] Stage 3: branches, memory traffic, expensive arithmetic removed; argued from operation counts -> 4.1 Changes and operation counts
- [ ] Stage 4: RV32I translation with its test data; measured with the Ripes iret flag -> 5. Stage 4; 9. Test cases

What counts as done
- [ ] .data + .bss + .rodata at or under 128 KiB -> 6. Memory quantified; Result
- [ ] No distance-11 state above 5e7 iret on RV32_ISS, renderer compiled out, pinned build -> 8. Worst case; Result
- [ ] 21345671111111 count reported separately -> 8.1 Reference vector; Result
- [ ] Precomputation rule: host-generated tables only as read-only data, search on target, no complete distance table -> 5.2 Constraint compliance; 6. Memory quantified

Constraints
- [ ] RV32I only, no compiler helper routines -> 5.2 Constraint compliance
- [ ] No heap, no recursion, no floating point, sized at assembly time -> 5.2 Constraint compliance
- [ ] Arbitrary 14-character state inlined at assembly time -> 5.2 Constraint compliance; 9. Test cases
- [ ] At least three own test cases: solved, short scramble, distance 11 -> 9. Test cases
- [ ] Results validated inside the program -> 9. Test cases; 7.2 Target gates
- [ ] Not a line-by-line translation -> 5.2 Constraint compliance
- [ ] Beats GCC -O2 rv32i reference in iret and code size; reference reported; losses explained -> 5.5 Comparison with the GCC reference build; Result
- [ ] Iterative refinement with measurements at each step -> 5.4 Iterative refinement
- [ ] Code size and iret conventions stated -> 5.1 Measurement conventions
- [ ] Runs correctly on Ripes -> 7.2 Target gates

Correctness gates
- [ ] H1 admissibility over all states -> 7.1 Host gates
- [ ] H2 tables fully populated, maximum and solved entry -> 7.1 Host gates
- [ ] H3 exact length for every state, wall-clock reported -> 7.1 Host gates; Result
- [ ] H4 packed vs unpacked accessor, even and odd indices -> 7.1 Host gates
- [ ] T5 returned paths reach solved -> 7.2 Target gates
- [ ] T6 21345671111111 optimal 11 moves -> 7.2 Target gates; 8.1 Reference vector
- [ ] T7 test cases and grader states on RV32_ISS and a visual pipeline model -> 7.2 Target gates; 9. Test cases

LED matrix
- [ ] 35 wide by 25 tall LED Matrix -> 10.1 Peripheral setup
- [ ] Row-major addressing through LED_MATRIX_0 symbols, no literal address -> 10.3 Address mapping derivation
- [ ] Unfolded net -> 10.2 Net layout
- [ ] Six face colors distinguishable throughout -> 10.2 Net layout; 10.5 Redraw after every move
- [ ] Redraw after every move, driven by actual solver output -> 10.5 Redraw after every move
- [ ] Assemble-time renderer switch; builds differ only in the renderer, stated -> 10.4 Renderer switch

Instruction-level walkthrough
- [ ] Signals such as register write enable and mux selection -> 11. Instruction-level walkthrough
- [ ] IF, ID, EX, MEM, WB -> 11. Instruction-level walkthrough
- [ ] Memory update and why the result is correct -> 11. Instruction-level walkthrough

Documentation
- [ ] Group <R, B, D> and its order -> 1.1
- [ ] Cayley graph and generators -> 1.2
- [ ] BFS diameter 11: depth-11 state exists and none deeper -> 1.3
- [ ] Orientation-sum mod-3 invariant and what it rules out -> 1.4
- [ ] Diameter corroborated with Jaap Scherphuis: 11 in HTM and 14 in QTM -> 1.5
- [ ] Optimization argument across the four stages -> 2 to 5
- [ ] Memory: bytes per table, peak working set, how obtained -> 6. Memory quantified
- [ ] RV32I-specific sequences and why the base ISA forces them -> 5.6 RV32I-specific instruction sequences
- [ ] Analysis of code, LED mapping, pipeline walkthrough -> 5.3, 10.3, 11
- [ ] No complete listings; short quoted fragments with explanation -> whole note
- [ ] At least three substantive revisions; thin history explained -> 12.4 Revisions and process evidence
- [ ] Published, readable by anyone, write permission Signed-in users -> HackMD settings (outside the text)
- [ ] All writing in English -> whole note

AI guidelines
- [ ] 4.1 tools and purposes, decisions not made by the tools, use log -> Disclosure of AI use
- [ ] 4.1 tool-supplied facts cited to underlying sources; Ripes behaviors reproduced or attributed -> 5.1, 7.2, 10.4; References
- [ ] 4.2 written work: research process, outline, revisions -> 12.2; 12.4
- [ ] 4.2 code projects: problem-solving across iterations; testing, validation, debugging -> 12.4; 7, 9; 12.3
- [ ] 4.2 all major assignments: short reflection -> 12.5; key difficulties and resolutions -> 12.3; thin evidence explained -> 12.4

Scope
- [ ] Changes after the submitted tag accounted for, what and why -> Changes after the submitted tag

Submission (outside the note)
- [ ] Tag and HackMD revision URL recorded on the form; the revision URL goes on the form only, not in the note -> Links and environment (tag)
- [ ] Note and fork submitted through the form by Oct 8, 2026, 23:59 (GMT+8)
- [ ] Automatic result email: do not reply; complete only when the subject ends in "accepted"
- [ ] Subject ends in "action required": fix the listed issues and submit the form again
-->
