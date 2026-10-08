<!-- c/README.md - written with AI assistance (Claude Code); see docs/ai-assistance.md -->
# C reference of the IDA* solver

This directory holds the C version of the search the student designed:
IDA* with `h = max(pdb_p[p], pdb_o[o])`, same-face pruning, quarter-turn
transition tables, and an explicit 12-level stack instead of recursion. It
contains the host table generator, the gate checks, a host CLI, and a
single-file freestanding build for the GCC RV32I reference measurement.
No RISC-V assembly for the solver is generated here. The only assembly file
produced is `asm/tables.s`, which holds data tables generated on the host.

All commands below run from the repository root. On this Mac, prefix them
with `DEVELOPER_DIR=/Library/Developer/CommandLineTools`.

## Files

| File | Role |
| --- | --- |
| `ida_core.h`, `ida_core.c` | Search core: `ida_parse`, `ida_solve`, `ida_apply_move`, `ida_apply_path`. Freestanding (only `<stdint.h>`). It has no libc, heap, recursion or divide, and multiplies only by constants. Tables are `extern const`. |
| `tables.h`, `tables.c` | Host generator. It `#include`s the unmodified `../solver.c` with `main` renamed. It builds `gen_perm_qt`/`gen_orient_qt` using upstream's own `build_table()` loops, and `gen_pdb_p`/`gen_pdb_o` by BFS over each abstraction. It also exposes upstream `quarter_turn`/`apply_move` for cross-checks. |
| `gen_tables.c` | `c/gen_tables [--h FILE] [--asm FILE]` writes `c/tables_data.h` and `asm/tables.s`. |
| `tables_data.h` | Generated. Defines `const` `perm_qt`, `orient_qt`, `pdb_p`, `pdb_o`. Include it in exactly one translation unit. |
| `tables_embed.c` | Host translation unit that defines the tables from `tables_data.h`. |
| `ida_host.c` | `c/ida STATE`, `c/ida --stats STATE`. |
| `gates.c` | `c/gates`: gates P, H1–H4 against `tools/oracle`, and `--dist11`. |
| `ripes_main.c` | Freestanding `main` with the inlined `input_state`. |
| `ripes_ref.c` | Single translation unit for `scripts/refbuild.sh`, which accepts only one `.c` file. It contains `tables_data.h`, `ida_core.c` and `ripes_main.c`. |
| `Makefile` | Targets below. Default flags are `-O2 -std=c99 -Wall -Wextra -Wpedantic`, and the build gives zero warnings. |

## Build and run

```sh
make -C c all        # gen_tables, tables_data.h, asm/tables.s, ida, gates binary (runs nothing)
make -C c tables     # force-regenerate c/tables_data.h and asm/tables.s
make -C c check      # tests/solutions.txt: same solution LENGTH as expected,
                     # each path verified by tools/oracle (upstream apply_move);
                     # exit status 2 for the upstream invalid inputs, 1 for closed stdout
make -C c gates      # ./gates --asm ../asm/tables.s (full P, H1-H4; H3 runs on every state)
make -C c dist11     # ./gates --dist11 ../tests/dist11.txt
make -C c ref        # scripts/refbuild.sh --elf /tmp/ida_ref.elf c/ripes_ref.c
make -C c ref-run    # ref, then Ripes --mode cli ... --proc RV32_ISS --iret on that ELF
make -C c clean
```

CLIs:

```sh
./c/ida 21345671111111          # one optimal solution, upstream format; "" + newline if solved
./c/ida --stats 21345671111111  # same line, then: length=N expanded=E generated=G
./c/gates [--jobs N] [--asm FILE] [--skip-h3]   # default asm file: asm/tables.s, found
                                                # from the binary's location, any cwd
./c/gates --dist11 tests/dist11.txt   # "STATE LEN EXPANDED GENERATED" per state + summary
./c/gen_tables --h c/tables_data.h --asm asm/tables.s
```

`c/ida` uses upstream's exit statuses: 0 means ok, 1 means failure, and 2
means usage error or invalid state. There are two deliberate exceptions.
`./c/ida --self-test` is not implemented and exits 2 (upstream runs its
self-test and exits 0); the table and search checks are in `c/gates`.
`./c/ida --stats STATE` is a host-only diagnostic and exits 0 (upstream
rejects it with 2). `make -C c check` pins both. It replays its own path through the
tables before printing it. `c/ida` and upstream `./solver` can return
different move sequences, but the lengths must be equal, and `make -C c
check` and gate H3 check exactly that.

The statistics counters `ida_expanded` and `ida_generated` exist only when
`ida_core.c` is compiled with `-DIDA_STATS`. The host Makefile sets that
flag. `ripes_ref.c` does not, so the RV32I reference build contains no
counter code.

* `expanded`: nodes whose children were generated. This counts the root
  once per bound iteration and every node the search descends into.
* `generated`: child states computed. Each costs one `perm_qt` lookup and
  one `orient_qt` lookup.

### Reference build for another state

```sh
scripts/refbuild.sh --elf /tmp/x.elf c/ripes_ref.c '-DINPUT_STATE="12345671111111"'
```

The exit status of `main`, passed to Ripes by crt0, is one of the following.

| Status | Meaning |
| --- | --- |
| 0 | Solved, and the path replayed through the tables reaches the solved state. |
| 2 | Invalid input. |
| 3 | No solution within 11 moves. |
| 4 | The path does not solve the state. |

## What `c/gates` checks

| Gate | Check |
| --- | --- |
| P | `ida_parse` against upstream. Every one of the 3,674,160 canonical strings must parse to its upstream rank (`p_rank * 729 + o_rank`). The upstream Makefile's invalid inputs must be rejected. For 4,000,000 random or one-byte-mutated strings, `ida_parse` must accept and reject the same strings as upstream `parse_state` and return the same rank. |
| H2 | The embedded tables equal freshly generated ones. Every `perm_qt`/`orient_qt` entry is in range, and each face row is a permutation. On every state, the tables agree with upstream `quarter_turn` for each of the 3 faces. On every state, `ida_apply_move` agrees with upstream `apply_move` for each of the 9 moves. Both PDBs have no `0xFF` sentinel left. The PDB maxima are printed, and both solved entries are 0. Each PDB is a valid BFS labelling of its abstract graph, which makes it the exact abstract distance independently of the BFS code. `asm/tables.s` has `.align 2` before `perm_qt` and holds the same values. Without `--asm`, the file is `../asm/tables.s` relative to the directory of the `gates` binary, so the check does not depend on the working directory. A missing file fails H2. |
| H1 | `h <= d` on every state for `pdb_p[p]`, `pdb_o[o]` and their max, using `tools/oracle` distances. Prints the violation count and the number of states with `h == d`. |
| H3 | `ida_solve` on every state. The returned length must equal the oracle distance, and the path must reach solved when replayed through the core tables and through upstream `apply_move`. Runs in `--jobs` forked processes (default: online CPUs) and prints wall-clock seconds, node totals, the maximum, and the maximum per distance. |
| H4 | The tables store one byte per entry and there is no packed accessor, so H4 is vacuous. A trivial check still compares PDB byte reads with the generator's arrays at even and odd indices. |

## Data layout (`asm/tables.s`, also `c/tables_data.h`)

All four tables are in one `.data` block, in this order. Offsets are from
`perm_qt`. Ripes has no `.rodata`/`.section` and no `.include`, so append
`asm/tables.s` to the program source. The file uses only `.data`, one
`.align 2` (just before `perm_qt`), `.half` and `.byte`, with 16 values per
line.

Alignment: in this Ripes build `.align N` pads to a multiple of N bytes
(tested: after one `.byte`, `.align 1` adds nothing, and `.align 2`,
`.align 4` and `.align 8` move the next label to offset 2, 4 and 8). GNU
`as` for RISC-V reads `.align N` as 2^N bytes. The `.align 2` before
`perm_qt` therefore gives at least 2-byte alignment under both, so
`perm_qt` and `orient_qt` stay halfword aligned even when odd-length data,
such as the 15-byte state string, comes before the appended file. Without
it `perm_qt` was observed at `0x1000000f` in that case.

| Label | Directive | C type, shape | Bytes | Offset | Address of element |
| --- | --- | --- | ---: | ---: | --- |
| `perm_qt` | `.half` | `uint16_t [3][5040]` | 30240 | 0 | `perm_qt + face*10080 + p*2` (row stride 5040*2 = 10080 bytes) |
| `orient_qt` | `.half` | `uint16_t [3][729]` | 4374 | 30240 | `orient_qt + face*1458 + o*2` (row stride 729*2 = 1458 bytes) |
| `pdb_p` | `.byte` | `uint8_t [5040]` | 5040 | 34614 | `pdb_p + p` |
| `pdb_o` | `.byte` | `uint8_t [729]` | 729 | 39654 | `pdb_o + o` |
| total | | | 40383 | | ends at an odd offset, so put `.align 2` before `.half` data and `.align 4` before `.word` data placed after it (Ripes N-byte semantics; both are also safe under GNU 2^N) |

The table entries are defined as follows.

* Halfword entries are unsigned (use `lhu`), and byte entries are unsigned
  (use `lbu`).
* `perm_qt[f][p]` is the p_rank after one quarter turn of face `f`, which
  is upstream `quarter_turn(state, f)`, the move `R`, `B` or `D`.
  `orient_qt[f][o]` is the o_rank after the same quarter turn.
* `pdb_p[p]` is the exact distance of `p` in the permutation-only graph,
  and `pdb_o[o]` is the exact distance of `o` in the orientation-only
  graph. Both graphs use the 9 HTM moves.

Face numbering is R = 0, B = 1, D = 2. A move is `3*face + turn`, where
turn 0, 1, 2 means 1, 2, 3 quarter turns, so the moves 0..8 are
`R R2 R' B B2 B' D D2 D'`, the same as upstream. Move `3f+t` is `t+1`
chained lookups in row `f`.

The state ranks are the same as upstream `rank_state`. `p_rank` is the
Lehmer/Cantor rank of `p[0..6]`. `o_rank` is the base-3 number formed by
`o[0..5]`, with `o[0]` as the most significant digit. The upstream rank is
`p_rank*729 + o_rank`. `ida_parse` computes `p_rank` with the Horner steps
unrolled, so every multiplier is a constant:
`((((s0*6 + s1)*5 + s2)*4 + s3)*3 + s4)*2 + s5`, where `si` is the number
of `j > i` with `p[j] < p[i]`.

## Search stack (`ida_core.c`)

The search keeps 12 levels, k = 0..11, which is depth 0..11. In the C
code these are file-scope static arrays (`.bss`, 84 bytes).

| Array | Type | Meaning at level k |
| --- | --- | --- |
| `lv_p[k]`, `lv_o[k]` | `uint16_t[12]` | Ranks of the node at depth k on the current path. |
| `lv_move[k]` | `uint8_t[12]` | Move (0..8) that produced depth k from depth k−1, for k ≥ 1. It equals `path[k-1]` when a solution is found. |
| `lv_face[k]` | `uint8_t[12]` | Face currently being tried from depth k: 0..2, or 3 when every face has been tried. |
| `lv_turn[k]` | `uint8_t[12]` | Quarter turns of `lv_face[k]` already applied: 0..3. The next child is move `3*lv_face[k] + lv_turn[k]`. |

The child of depth k is always written to `lv_p[k+1]`/`lv_o[k+1]`, even
when it is cut off. The next turn of the same face chains from that slot,
because deeper levels never overwrite it. The face of the move that reached
depth k is `lv_face[k-1]`, and same-face pruning compares against it.

```
ida_solve(p0, o0, path):
    if p0 == 0 and o0 == 0: return 0
    lv_p[0] = p0; lv_o[0] = o0
    for bound = h(p0, o0) .. 11:                 # h(p,o) = max(pdb_p[p], pdb_o[o])
        k = 0; lv_face[0] = 0; lv_turn[0] = 0
        loop:
            f = lv_face[k]; t = lv_turn[k]
            if t == 3: f = f + 1; t = 0          # this face's three turns done
            if t == 0 and k != 0 and f == lv_face[k-1]:
                f = f + 1                        # same-face pruning
            if f == 3:                           # all children of depth k tried
                if k == 0: break loop            # iteration exhausted -> bound + 1
                k = k - 1; continue loop         # backtrack
            if t == 0: (sp, so) = (lv_p[k],   lv_o[k])      # first quarter turn
            else:      (sp, so) = (lv_p[k+1], lv_o[k+1])    # chain from previous turn
            cp = perm_qt[f][sp]; co = orient_qt[f][so]
            lv_p[k+1] = cp; lv_o[k+1] = co
            lv_face[k] = f; lv_turn[k] = t + 1
            g = k + 1
            if g + h(cp, co) > bound: continue loop          # cut off
            lv_move[g] = 3*f + t
            if cp == 0 and co == 0:                          # solved
                path[i] = lv_move[i+1] for i = 0 .. g-1
                return g
            k = g; lv_face[k] = 0; lv_turn[k] = 0            # descend
    return -1                                    # unreachable for a valid state
```

The 12 levels are enough for the following reason. A non-solved node has
`h >= 1`, so a node is descended into only when `g <= bound - 1`.
Therefore `k + 1 <= bound <= 11`.

`ida_apply_move` gets `face` and `turn` from the move by repeated
subtraction of 3, so no divide is needed. It then applies `turn + 1`
chained lookups. `ida_apply_path` does this for every move and then tests
`(p, o) == (0, 0)`.

## Notes

* `scripts/refbuild.sh` must report `audit: PASS`, which means no
  `__mulsi3`, `__divsi3`, `__udivsi3`, `__modsi3` and no non-RV32I
  instruction. GCC lowers every constant multiply, including the 2-D
  table indexing, to shifts and adds.
* `tools/oracle` and `solver.c` are not modified. `gates` and `gen_tables`
  compile `solver.c` into their own translation units.
* The numbers these tools print are diagnostics from this C reference.
  Figures for the write-up must come from the student's own runs.
