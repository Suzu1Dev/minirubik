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

static uint32_t move_face(uint32_t move)
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
    return face;
}

static uint32_t st_p[IDA_LEVELS];   
static uint32_t st_o[IDA_LEVELS];  
static uint32_t st_mv[IDA_LEVELS];  
static uint32_t st_nx[IDA_LEVELS];  


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
        st_nx[0] = 0;
#ifdef IDA_STATS
        ida_expanded++;                     /* the root, once per bound */
#endif
        while (1) {
            /* all 9 moves tried at this depth: go back up */
            if (st_nx[d] == 9) {
                if (d == 0) {
                    break;                  /* this bound found nothing */
                }
                d--;
                continue;
            }
            /* take the next move to try */
            uint32_t m = st_nx[d];
            st_nx[d]++;
            /* same-face pruning */
            if (d > 0 && move_face(m) == move_face(st_mv[d])) {
                continue;
            }
            /* child state */
            uint32_t cp = st_p[d];
            uint32_t co = st_o[d];
            ida_apply_move(&cp, &co, m);
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
            st_nx[d] = 0;
#ifdef IDA_STATS
            ida_expanded++;
#endif
            /* solved: copy the moves into path and return the length */
            if (st_p[d] == 0 && st_o[d] == 0) {
                for (uint32_t i = 1; i <= d; i++) {
                    path[i-1] = (uint8_t) st_mv[i];
                }
                return (int) d;
            }
        }
    }
    return IDA_FAIL;
}