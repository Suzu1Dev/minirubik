/* ida_core.c - search core, written by the student (Suzu1Dev).
 * API: see ida_core.h. The skeleton (signatures and stubs) was set up with
 * AI assistance (Claude Code); the function bodies are the student's own.
 */
#include "ida_core.h"

#ifdef IDA_STATS
uint32_t ida_expanded;
uint32_t ida_generated;
#endif

int ida_parse(const char *s, uint32_t *p_rank, uint32_t *o_rank)
{
    uint32_t p[7], o[7];
    uint32_t seen = 0;
    uint32_t sum = 0;

    for (uint32_t i = 0; i < 7; i++) {
        if( s[i]<'1' || s[i]>'7' ){
            return 0;
        }
        p[i] = s[i] - '1';

        uint32_t bit = 1u << p[i];

        if(seen & bit){
            return 0;
        }
        seen = seen | bit;
    }

    for (uint32_t i = 0; i < 7; i++) {
        if( s[7+i]<'1' || s[7+i]>'3'){
            return 0;
        }
        o[i] = s[7+i] - '1';
        sum += o[i];
    }

    if(s[14] != '\0'){
        return 0;
    }

    // % is banned so we use while loop to do it.
    while(sum>=3){
        sum -= 3;
    }
    if(sum != 0){
        return 0;
    }

    uint32_t c[6];
    for (uint32_t i = 0; i < 6; i++) {
        c[i] = 0;
        for (uint32_t j = i+1; j <= 6; j++) {
            if(p[j] < p[i]){
                c[i] ++;
            }
        }
    }
    uint32_t pr = c[0]*720 + c[1]*120 + c[2]*24 + c[3]*6 + c[4]*2 + c[5];

    uint32_t orr = 0;
    for (uint32_t i = 0; i < 6; i++) {
        orr = orr * 3 + o[i];
    }

    *p_rank = pr;
    *o_rank = orr;
    return 1;

}

int ida_apply_move(uint32_t *p_rank, uint32_t *o_rank, uint32_t move)
{
    uint32_t face;
    if (move > 8){
        return 0;
    }else if(move >= 6){
        face = 2;
    }else if(move >= 3){
        face = 1;
    }else{
        face = 0;
    }
    uint32_t turn = move - 3 * face;
    for (uint32_t i = 0; i <= turn; i++){
        *p_rank = perm_qt[face][*p_rank];
        *o_rank = orient_qt[face][*o_rank];
    }

    return 1;
}

int ida_apply_path(uint32_t p_rank, uint32_t o_rank, const uint8_t *path,
                   uint32_t len)
{
    for(uint32_t i = 0; i < len; i++){
        if(!ida_apply_move(&p_rank, &o_rank, path[i])){
            return 0;
        }
    }
    return (p_rank == 0 && o_rank == 0);
}

// return the bigger table of the 2
static uint32_t heur(uint32_t p, uint32_t o)
{
    uint32_t a = pdb_p[p];
    uint32_t b = pdb_o[o];
    if(a>b){return a;}
    else{return b;}
}

/* per-level search state (optimization A: per-face chaining) */
static uint32_t st_p[IDA_LEVELS];   /* state at this level (the parent)      */
static uint32_t st_o[IDA_LEVELS];
static uint32_t st_mv[IDA_LEVELS];  /* move that led to this level           */
static uint32_t st_f[IDA_LEVELS];   /* face being tried (0..2, 3 = all done) */
static uint32_t st_t[IDA_LEVELS];   /* quarter turns done on that face (0..3)*/
static uint32_t st_cp[IDA_LEVELS];  /* running child of the chain            */
static uint32_t st_co[IDA_LEVELS];
static uint32_t st_lf[IDA_LEVELS];  /* face used to reach this level (3: none)*/


int ida_solve(uint32_t p_rank, uint32_t o_rank, uint8_t path[IDA_MAX_DEPTH])
{
#ifdef IDA_STATS
    ida_expanded = 0;
    ida_generated = 0;
#endif
    if (p_rank == 0 && o_rank == 0) {
        return 0;
    }
    for (uint32_t bound = heur(p_rank, o_rank); bound <= IDA_MAX_DEPTH; bound++) {
        uint32_t d = 0;
        st_p[0] = p_rank;
        st_o[0] = o_rank;
        st_lf[0] = 3;                       /* root: no previous face */
        st_f[0] = 0;
        st_t[0] = 0;
        st_cp[0] = p_rank;
        st_co[0] = o_rank;
#ifdef IDA_STATS
        ida_expanded++;                     /* the root, once per bound */
#endif
        while (1) {
            /* this face's X, X2, X' all done: next face, restart the chain */
            if (st_t[d] == 3) {
                st_f[d]++;
                st_t[d] = 0;
                st_cp[d] = st_p[d];
                st_co[d] = st_o[d];
            }
            /* all faces done: go back up
             * (checked BEFORE same-face pruning: at the root st_lf = 3,
             *  so st_f == 3 would otherwise be "pruned" and run past 3) */
            if (st_f[d] == 3) {
                if (d == 0) {
                    break;                  /* this bound found nothing */
                }
                d--;
                continue;
            }
            /* same-face pruning: skip the whole face */
            if (st_f[d] == st_lf[d]) {
                st_t[d] = 3;
                continue;
            }
            /* one more quarter turn of face f on the running child */
            uint32_t f = st_f[d];
            st_cp[d] = perm_qt[f][st_cp[d]];
            st_co[d] = orient_qt[f][st_co[d]];
            st_t[d]++;
            uint32_t m = 3 * f + st_t[d] - 1;
            uint32_t cp = st_cp[d];
            uint32_t co = st_co[d];
#ifdef IDA_STATS
            ida_generated++;
#endif
            /* IDA* cut: the child is at depth g = d + 1 */
            if (d+1 + heur(cp, co) > bound) {
                continue;
            }
            /* go down to the child */
            d++;
            st_p[d] = cp;
            st_o[d] = co;
            st_mv[d] = m;
            st_lf[d] = f;
            st_f[d] = 0;
            st_t[d] = 0;
            st_cp[d] = cp;
            st_co[d] = co;
#ifdef IDA_STATS
            ida_expanded++;
#endif
            /* solved: copy the moves into path and return the length */
            if (cp == 0 && co == 0) {
                for (uint32_t i = 1; i <= d; i++) {
                    path[i-1] = (uint8_t) st_mv[i];
                }
                return (int) d;
            }
        }
    }
    return IDA_FAIL;
}
