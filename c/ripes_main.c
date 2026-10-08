/* ripes_main.c - written with AI assistance (Claude Code); see docs/ai-assistance.md */
/*
 * Freestanding main for the GCC RV32I reference build of the IDA* core.
 * tools/rv32/crt0.S calls main() and passes its return value to the exit
 * ecall, so Ripes prints "Program exited with code: N".
 *   0  solved, and the returned path was replayed through the tables and
 *      reaches the solved state
 *   2  input_state is not a valid state
 *   3  the search found no solution within 11 moves
 *   4  the returned path does not solve the state
 * Built as one translation unit through ripes_ref.c (scripts/refbuild.sh
 * takes a single .c file).  Change input_state to run another vector, or
 * pass it as an extra compiler flag:
 *   scripts/refbuild.sh --elf OUT.elf c/ripes_ref.c '-DINPUT_STATE="12345671111111"'
 */
#include "ida_core.h"

#ifdef INPUT_STATE
static const char input_state[] = INPUT_STATE;
#else
static const char input_state[] = "21345671111111";
#endif

int main(void)
{
    uint32_t p, o;
    uint8_t path[IDA_MAX_DEPTH];
    int len;

    if (!ida_parse(input_state, &p, &o))
        return 2;
    len = ida_solve(p, o, path);
    if (len < 0)
        return 3;
    if (!ida_apply_path(p, o, path, (uint32_t) len))
        return 4;
    return 0;
}
