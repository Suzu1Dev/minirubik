---
tags: computer-arch
---

# Assignment 1: Optimizations and RISC-V Assembly

contributed by < [`Suzu1Dev`](https://github.com/Suzu1Dev) >

## Links and environment

| Item | Value |
| :--- | :--- |
| Fork | https://github.com/Suzu1Dev/minirubik |
| Submitted tag | `hw1-v2` |
| Forked from | [sysprog21/minirubik](https://github.com/sysprog21/minirubik) at commit `231796cc48868f4ea276f652139b6bebbad0cd02` |
| Ripes build | `v2.2.6-106-g5b8a616` (`continuous` prerelease, macOS universal2) |
| Reference toolchain | `riscv64-elf-gcc` 16.2.0, GNU Binutils 2.47 (Homebrew) |
| Host | MacBook Pro, Apple M3 Pro, 18 GB RAM, macOS 27.2 |

## Disclosure of AI use

This assignment is AI-assisted under Section 3 of the course AI guidelines. The full use log is [`docs/ai-assistance.md`](https://github.com/Suzu1Dev/minirubik/blob/main/docs/ai-assistance.md).

| Tool | Used for |
| :--- | :--- |
| OpenAI Codex | Environment setup checks (Ripes download and smoke test, baseline build), fork remote setup, a walkthrough of the upstream `solver.c` |
| Claude Code (Claude Opus 5.5) | Installing the RISC-V toolchain and writing the tooling in `scripts/` and `tools/` (reference build, RV32I audit, Ripes runners, exact-distance oracle, `tests/dist11.txt`); concept tutoring in question-and-answer form; the section outline of this note; English wording |
| Claude Code (C and assembly stage) | A first C implementation of my design, which I replaced with my own search core `c/ida_core.c`; the table generator `c/gen_tables.c` and its output `asm/tables.s`; the gate checker `c/gates.c`, the host CLI `c/ida_host.c`, and `c/Makefile`; explanations of RV32I instructions and calling conventions; review of my C and assembly drafts |

How the English text was produced: I drafted Sections 1.1 and 1.2 in English, and Claude corrected the grammar and terminology. I wrote Sections 1.3 to 2.7 as Chinese notes, and Claude translated them into English without adding content; where my notes were wrong or incomplete, Claude flagged the problem and I supplied the correction. Claude assembled Sections 3.1 to 3.6 in English from my answers to the tutoring and design questions, and I reviewed the result. The status lines and result tables in Sections 4 to 8 were formatted by Claude from the output of runs I made. The second half of the optimality argument in 3.5 follows Claude's explanation of Korf's argument.

What I decided and did myself:

- Wrote the measurement programs `bench/memloop.s` and `bench/rate.s` and ran every measurement in Sections 2.5 and 2.6. Claude pointed out bugs in my drafts without rewriting them.
- Chose the search design: IDA* with $h = \max(h_p, h_o)$ over a permutation pattern database and an orientation pattern database.
- Kept the quarter-turn transition tables after counting that nine-move tables save no lookups, chose one byte per table entry because memory is not the bottleneck, and kept same-face pruning.
- Wrote every function body of the C search core `c/ida_core.c` (`ida_parse`, `ida_apply_move`, `ida_apply_path`, `heur`, `move_face`, `ida_solve`) from a skeleton of signatures; Claude reviewed each draft and named bugs without rewriting the code. I did not read the earlier Claude-written core while writing mine.
- Wrote the RV32I functions `heur`, `move_face`, and `ida_apply_move` in `asm/solver.s`. After Claude estimated the cost of my first, pointer-based `ida_apply_move`, I changed it to pass and return the ranks in registers.

## 1. The state space

### 1.1 The group $\langle R, B, D \rangle$ and its order

We fix one corner cubie, FUL, so only the remaining seven cubies move. We can still reach every configuration, up to a whole-cube rotation, without moving it: for example, a U turn is equivalent to a D turn followed by a 90° rotation of the whole cube. Arranging seven cubies in seven positions gives $7!$ possible permutations $p$. For the orientation $o$, FUL is fixed, and the twists of the other seven cubies must sum to 0 mod 3: the twists added by every quarter turn sum to 0 mod 3, and the solved state has sum 0, so the sum is always 0 mod 3. Therefore, the twist of the last cubie is determined by the other six, so it suffices to count the twists of the first six cubies, which gives $3^6$ possibilities. Since a state consists of both a permutation and an orientation, we multiply the two counts: $7! \times 3^6 = 3{,}674{,}160$. As a cross-check, without fixing a corner there are $8!$ permutations of the eight corner cubies and $3^7$ orientations, since the eighth twist is determined by the other seven; dividing by 24, the number of orientations of the whole cube, gives the same number. Multiplying is valid because, unlike the 3x3x3 cube, the 2x2x2 cube has no parity constraint, so every combination is reachable. Running `./solver --self-test` confirms this: the exhaustive BFS from the solved state reaches exactly 3,674,160 distinct states (output: `3674160 states; diameter 11`).

### 1.2 Cayley graph and generators

$\langle R, B, D \rangle$ is the group generated by R, B, and D; each of its elements corresponds to exactly one state, and its order is 3,674,160 (Section 1.1). In its Cayley graph, each vertex is an element of the group, that is, a reachable state. For each generator $s$, there is an edge from $g$ to $g \cdot s$. The generators are the nine HTM moves R, R2, R', B, B2, B', D, D2, D'. Since every vertex has 9 outgoing edges, the graph has 3,674,160 × 9 = 33,067,440 directed edges. The generator set is closed under inverses: the inverse of R is R', the inverse of R2 is R2 itself, and the inverse of B' is B. Therefore, for every edge from $g$ to $g \cdot s$, there is also an edge from $g \cdot s$ back to $g$, labeled $s^{-1}$, so the graph can be treated as undirected. The table `inverse_move` in `solver.c` records this pairing. In a Cayley graph, each vertex is one group element, whereas in a Schreier coset graph each vertex is a coset, a set of elements regarded as the same. For example, if we use all six faces (18 face turns) and regard the 24 whole-cube rotations of a configuration as the same, each vertex stands for 24 configurations. Fixing FUL picks exactly one of these 24, so $\langle R, B, D \rangle$ is a group in its own right, and the graph we get is a Cayley graph.

### 1.3 Diameter 11 by exhaustive BFS

A state at distance 11 exists: for example, `21345671111111`, which only swaps two corners, needs 11 moves (see `tests/solutions.txt`). To show that no state is deeper than 11, we enumerate the whole state space by brute force. Since the number of enumerated states equals the group order, no state is missed, so the deepest level the enumeration reaches is the true maximum. Running `./solver --self-test` prints `3674160 states; diameter 11`.

### 1.4 The orientation-sum invariant

Every quarter turn of R or B twists two corners by +1 (120°) and two corners by +2 (240°). Each +1 pairs with a +2 to make 360°, a full turn, which is the same as no twist. A D turn twists no corner. Therefore every quarter turn leaves the twist sum modulo 3 unchanged, and since the solved state has sum 0, every reachable state satisfies $\sum o_i \equiv 0 \pmod 3$.

This invariant rules out every state whose twist sum is not 0 mod 3. For example, a state in which a single corner is twisted by +1 and everything else is solved cannot be reached, because a turn always twists other corners together with it. Only one third of the orientation assignments satisfy the invariant ($3^6$ of the $3^7$ assignments for the seven moving corners), so the other two thirds are ruled out.

This is a modulo-3 invariant, not a parity. On the 2x2x2 cube, the corners can be understood purely as cycles, with no edge cubies moving along with them, so the only constraint is the orientation sum modulo 3. Section 1.1 confirms that all $7!$ permutations are reachable.

## 2. Stage 1: Characterizing the baseline

### 2.1 What the program computes

The program reads a 14-digit state, seven permutation digits followed by seven orientation digits, and prints a shortest solution. It first builds `toward_solved`, a table that stores, for each of the 3,674,160 states, the next move on a shortest path toward the solved state. A query simply follows these stored moves until it reaches the solved state, so no comparison between moves is needed.

### 2.2 How it represents a cube

`p[i]` records which cubie sits at position $i$, and `o[i]` records the twist of that cubie. To index a state, the permutation is ranked by its Cantor expansion (Lehmer code): for each position, count how many entries to its right are smaller, and use these counts as the digits of a factorial-base number, which gives a rank from 0 to 5039. The orientation is ranked as the base-3 number formed by the first six twists, which gives a rank from 0 to 728; the seventh twist is determined by the other six (Section 1.1). The two parts are combined as $p \times 3^6 + o$, so every state maps to a unique integer from 0 to 3,674,159.

### 2.3 Invariants it relies on

Input is rejected if it is not exactly 14 digits, if a cubie digit is outside 1–7 or an orientation digit is outside 1–3, if a cubie appears twice, or if the orientation sum is not 0 mod 3. The BFS uses a FIFO queue, so it processes states level by level: a state first discovered from a parent at distance $k$ is at distance $k+1$. The table stores the inverse of the move that discovered it, so following the stored move returns to the parent, going from $k+1$ back to $k$, and the distance always decreases by exactly 1.

### 2.4 Where its cost lies

The three dominant allocations are given by the assignment: the move-per-state table (3,674,160 bytes), the BFS queue of 32-bit ranks (14,696,640 bytes), and the factored transition tables (34,614 bytes), for a peak of 18,405,414 bytes. The BFS queue is the largest, at 79.85% of the peak; the BFS needs it to know which states to traverse next. For time, the BFS expands 33,067,440 edges (3,674,160 states × 9 moves), and each edge updates two tables, `permutation[face][…]` and `orientation[face][…]`, which gives 66,134,880 updates. At roughly 15 instructions per update, an estimate given by the assignment rather than a measurement, this is about $9.9 \times 10^8$ retired instructions.

### 2.5 Measurement A: host bytes per guest byte

**Method.** The program [`bench/memloop.s`](https://github.com/Suzu1Dev/minirubik/blob/main/bench/memloop.s) stores one word at a time over a region of LEN bytes starting at `0x10000000`, then exits; the loop body is `sw`, `addi`, `bne`. I ran it on `RV32_ISS` (Ripes `v2.2.6-106-g5b8a616`, CLI mode) with LEN = 1 MiB, 2 MiB, and 4 MiB, plus a control with LEN = 4. The control writes one word rather than none, because the loop tests its condition after the store, so LEN = 0 would never terminate. The versions differ only in the `.equ LEN` line. Each was run three times under `/usr/bin/time -l` on the host listed above, recording the peak memory footprint, with the maximum resident set size as a cross-check. Raw output: [`bench/results/mem-ratio-2026-10-08.txt`](https://github.com/Suzu1Dev/minirubik/blob/main/bench/results/mem-ratio-2026-10-08.txt).

| LEN (bytes) | Peak footprint, mean of 3 (bytes) | Increase over control | ÷ (LEN − 4) |
| ---: | ---: | ---: | ---: |
| 4 (control) | 12,873,275 | — | — |
| 1,048,576 | 73,166,443 | 60,293,168 | 57.50 |
| 2,097,152 | 133,186,520 | 120,313,245 | 57.37 |
| 4,194,304 | 253,303,189 | 240,429,915 | 57.32 |

Using the maximum resident set size instead gives 56.93 for LEN = 4 MiB.

**Result.** Every guest byte written costs about 57 host bytes, and the three sizes confirm that the relation is linear. Each newly written guest byte needs its own hash-map entry of fixed size: besides the 1-byte value, the entry stores the key (the address, 4–8 bytes), a pointer to the next entry in the same bucket (8 bytes), possibly a cached hash (8 bytes), plus malloc overhead and alignment padding, and the bucket array itself. Projected onto the baseline's peak of 18,405,414 guest bytes, running the baseline on Ripes would take about 1.05 GB of host memory, so memory would blow up.

### 2.6 Measurement B: retired instructions per second

**Method.** Two loops were timed with [`scripts/ripes-rate.sh`](https://github.com/Suzu1Dev/minirubik/blob/main/scripts/ripes-rate.sh), which divides `--iret` by Ripes' own `--exectime`, the wall-clock time of the model run only, excluding process start-up and assembly. [`bench/rate.s`](https://github.com/Suzu1Dev/minirubik/blob/main/bench/rate.s) stores to the same address N times, so guest memory does not grow; N = 3,000,000 on `RV32_ISS` and 300,000 on `RV32_5S`. `bench/memloop.s` writes 4 MiB to new addresses. Each was run three times; the retired-instruction counts matched the hand-predicted values (9,000,005, 900,005, and 3,145,733). Raw output is in [`bench/results/`](https://github.com/Suzu1Dev/minirubik/tree/main/bench/results).

| Program | Model | Retired instructions/s (mean of 3) |
| :--- | :--- | ---: |
| `rate.s` (same address) | `RV32_ISS` | 25.6 million |
| `rate.s` (same address) | `RV32_5S` | 0.329 million |
| `memloop.s` (new addresses) | `RV32_ISS` | 17.4 million |

**Result.** Both models run much faster than the assignment's table (1.09 million and 20.5 thousand instructions/s), which I attribute to the performance difference of the host computer. Writing to new addresses is about 32% slower than rewriting one address, consistent with the hash-map insertion cost found in Section 2.5. `RV32_ISS` only computes the result of each instruction, whereas `RV32_5S` simulates the actual circuit and models every step in detail, which makes it better suited for observing the intermediate execution than for long runs. At these rates the baseline's roughly $9.9 \times 10^8$ instructions would take about 39 s on `RV32_ISS` and about 50 minutes on `RV32_5S`, while the budget of $5 \times 10^7$ instructions corresponds to about 2 s and 2.5 minutes.

### 2.7 Reading `report.md` section 7 critically

Section 7 of `report.md` argues for keeping the full table because building it is the verification artifact. That argument does not survive the move to Ripes. First, memory would blow up: Ripes stores guest memory as a hash map with one entry per byte, so the 18.4 MB peak would cost about 57 times that, about 1.05 GB of host memory (Section 2.5). Second, building the table takes about $10^9$ instructions, about 20 times the per-query budget of $5 \times 10^7$. Third, the precomputation rule does not allow the full table to be brought in directly: a complete distance table over all 3,674,160 states is not accepted even if it is computed on the host, and even packed at 4 bits per state it would take 1,794 KiB (the assignment's figure), 14 times the 128 KiB budget. Finally, verification does not have to run on the target: it can be done on the host, where gates H1–H4 check against the exact BFS table.

## 3. Stage 2: Representation and algorithm for the target

### 3.1 Budget

| Item | Entries | Size per entry | Bytes |
| :--- | ---: | ---: | ---: |
| Permutation transitions | 3 × 5,040 | 2 B | 30,240 |
| Orientation transitions | 3 × 729 | 2 B | 4,374 |
| Permutation PDB | 5,040 | 1 B | 5,040 |
| Orientation PDB | 729 | 1 B | 729 |
| **Total** | | | **40,383 (30.8%)** |
| Remaining of 131,072 | | | 90,689 |

The input string, the solution path, and the search stack add a few dozen bytes; their exact sizes will be given once the assembly is written.

### 3.2 State representation

A state is the pair (`p_rank`, `o_rank`), as in the baseline. A quarter turn of face $f$ is two table lookups, `permutation[f][p]` and `orientation[f][o]`, and X2 and X' are obtained by applying the quarter-turn tables again. I kept the baseline's quarter-turn tables instead of storing all nine moves: when the three children X, X2, X' of one face are generated by chaining, it takes three lookups either way, so nine-move tables would triple the memory without saving a single lookup. My current implementation does not chain yet: it applies each move from the parent, which takes 1 + 2 + 3 = 6 lookups per face instead of 3. Chaining is the next optimization to measure.

### 3.3 Search algorithm

The search is IDA*. The bound starts at $h$ of the input state. Each iteration is a depth-first search that cuts off any path with $g + h > \text{bound}$, where $g$ is the number of moves made so far; if no solution is found, the bound increases by 1. Since recursion is not allowed, the depth-first search uses an explicit stack with one entry per depth, from the input state at depth 0 down to depth 11. The search terminates because the diameter is 11, so the bound never needs to exceed 11.

### 3.4 Heuristics and admissibility

Two pattern databases are built on the host by BFS over abstractions of the state space: one over the permutation alone (5,040 entries), ignoring orientation, and one over the orientation alone (729 entries), ignoring permutation. Each is admissible: every real move projects to a move in the abstract space, so any real solution projects to an abstract path of the same length, and the abstract distance can only be shorter or equal. The heuristic is $h = \max(h_p, h_o)$, which stays admissible because both values are at most the true distance. Their sum is not admissible, because one move advances both the permutation and the orientation: for a state one R turn from solved, $h_p = 1$ and $h_o = 1$, so the sum 2 exceeds the true distance 1.

### 3.5 Optimality argument

To find a solution, the search must reach the solved state within $g \le \text{bound}$ moves. Any solution has length at least $D$, since $D$ is the shortest. With $\text{bound} < D$, every path reaching solved has $g \ge D > \text{bound}$, so it is cut off. When the bound reaches $D$, no state on a shortest path is cut off, because admissibility gives $g + h \le g + (D - g) = D$, so the first solution found has length $D$.

### 3.6 Pruning

A move of a face followed by another move of the same face either cancels or composes into a single move, so after the first move only 6 of the 9 moves are tried. At depth 11 this reduces the tree from $9^{11} \approx 3.1 \times 10^{10}$ to $9 \cdot 6^{10} \approx 5.4 \times 10^{8}$ nodes, about 58 times fewer. The opposite-face pruning used for the 3x3x3 does not apply here, because R, B, and D are pairwise adjacent faces, so no two of them commute.

## 4. Stage 3: Efficiency in C

The C version of the design is [`c/ida_core.c`](https://github.com/Suzu1Dev/minirubik/blob/main/c/ida_core.c). It uses no division, no modulo, and no multiply by a variable, so it builds for RV32I without library helpers: the face of a move is found by comparison, and the permutation rank uses constant factorial weights. The operation-count analysis of this stage is still to be written.

## 5. Stage 4: RV32I assembly

Status at tag `hw1-v2`: [`asm/solver.s`](https://github.com/Suzu1Dev/minirubik/blob/main/asm/solver.s) contains `heur`, `move_face`, and `ida_apply_move`. `ida_apply_move` was checked in Ripes in a throwaway harness that Claude ran on my unchanged function: from the solved state it gives p = 3294 for R2 and o = 16 for B', matching the C tables. `heur` and `move_face` have not yet been run on the target. The IDA* search loop, input parsing, path validation, and the LED renderer are not yet translated, so no retired-instruction count of the assembly is reported yet. The tables are generated on the host into [`asm/tables.s`](https://github.com/Suzu1Dev/minirubik/blob/main/asm/tables.s) and appended to the source, because the Ripes assembler has no `.include`.

## 7. Correctness gates

### 7.1 Host gates

Run with `make -C c gates` against the exact BFS distances from `tools/oracle`. Raw output: [`bench/results/gates-2026-10-08.txt`](https://github.com/Suzu1Dev/minirubik/blob/main/bench/results/gates-2026-10-08.txt).

| Gate | Result |
| :--- | :--- |
| Parser | Every one of the 3,674,160 valid strings parses to its upstream rank; 4,000,000 random strings, 0 disagreements with upstream |
| H1 | 0 states with $h > d$; $h = d$ for 17,108 states |
| H2 | Both PDBs fully populated, maxima 7 (`pdb_p`) and 6 (`pdb_o`), solved entries 0; the transition tables equal upstream's quarter turns |
| H3 | 3,674,160 states, 0 wrong lengths, 0 paths that fail to solve; wall-clock 31.36 s with 12 processes |
| H4 | Vacuous, since both PDBs use one byte per entry; byte reads at even and odd indices agree |

## 8. Worst case over all distance-11 states

Host run of the C search over all 2,644 distance-11 states (`./c/gates --dist11 tests/dist11.txt`). Raw output: [`bench/results/dist11-host-2026-10-08.txt`](https://github.com/Suzu1Dev/minirubik/blob/main/bench/results/dist11-host-2026-10-08.txt).

| Figure | Value |
| :--- | ---: |
| States with a wrong length or a failing path | 0 |
| Nodes expanded, maximum | 106,636 (`54721631111111`) |
| Nodes expanded, minimum | 23,486 (`15746322313112`) |
| Nodes expanded, mean | 34,439.9 |
| `21345671111111` | 38,999 expanded, 11 moves |

The retired-instruction counts on `RV32_ISS` will be measured once the assembly search loop is complete.

