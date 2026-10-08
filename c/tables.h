/* tables.h - written with AI assistance (Claude Code); see docs/ai-assistance.md */
/*
 * Host-side generation of the IDA* tables from the unmodified upstream
 * solver.c (included by tables.c with its main() renamed).  The generated
 * arrays use a gen_ prefix so they never clash with the embedded tables
 * (perm_qt, orient_qt, pdb_p, pdb_o) that ida_core.c links against.
 */
#ifndef MINIRUBIK_TABLES_H
#define MINIRUBIK_TABLES_H

#include <stdint.h>

#define TB_FACES 3
#define TB_MOVES 9
#define TB_PERMS 5040
#define TB_ORIENTS 729
#define TB_STATES (5040u * 729u)
#define TB_UNREACHED 0xFFu /* PDB sentinel before BFS reaches an entry */

/* Filled by tables_build(). */
extern uint16_t gen_perm_qt[TB_FACES][TB_PERMS];
extern uint16_t gen_orient_qt[TB_FACES][TB_ORIENTS];
extern uint8_t gen_pdb_p[TB_PERMS];
extern uint8_t gen_pdb_o[TB_ORIENTS];

/*
 * Build all four tables:
 *   gen_perm_qt/gen_orient_qt: exactly the loops of upstream build_table()
 *     (unrank, quarter_turn, rank) for faces R, B, D;
 *   gen_pdb_p: BFS distance from p_rank 0 in the permutation-only graph,
 *     9 HTM moves, each move = 1..3 chained perm_qt steps;
 *   gen_pdb_o: the same over the orientation-only graph.
 * Returns 0 on success, 1 if a BFS leaves an entry unreached.
 */
int tables_build(void);

/* Upstream reference for cross-checks: rank of the state with upstream
 * rank 'rank' after upstream apply_move(move) (move 0..8). */
uint32_t tables_upstream_apply(uint32_t rank, uint32_t move);

/* Upstream reference: rank of a state after one upstream quarter_turn(face). */
uint32_t tables_upstream_quarter(uint32_t rank, uint32_t face);

#endif /* MINIRUBIK_TABLES_H */
