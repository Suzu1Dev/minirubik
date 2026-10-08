/* tables_embed.c - written with AI assistance (Claude Code); see docs/ai-assistance.md */
/*
 * Host translation unit that defines the embedded tables (perm_qt,
 * orient_qt, pdb_p, pdb_o) from the generated tables_data.h, so the host
 * programs link exactly the data the freestanding reference build uses.
 * Including ida_core.h first checks that the definitions match the extern
 * declarations the core uses.
 */
#include "ida_core.h"
#include "tables_data.h"
