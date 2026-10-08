/* ripes_ref.c - written with AI assistance (Claude Code); see docs/ai-assistance.md */
/*
 * Single translation unit for scripts/refbuild.sh, which compiles exactly
 * one .c file:  scripts/refbuild.sh --elf /tmp/ida_ref.elf c/ripes_ref.c
 * The tables become .rodata; ida_core.c is compiled without -DIDA_STATS,
 * so the statistics counters are not part of the reference build.
 */
#include "tables_data.h"
#include "ida_core.c"
#include "ripes_main.c"
