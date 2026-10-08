/*
 * SMOKE TEST ONLY - unrelated to the homework.  Checks that an ELF built by
 * scripts/refbuild.sh --elf has its data sections loaded where the code
 * expects them in Ripes: .rodata and .data are initialised, and .bss/.sbss
 * read as zero (crt0 does not clear them; Ripes memory starts zeroed).
 *
 * Expected: main returns 0 ("Program exited with code: 0").  A non-zero
 * exit code tells which check failed (1 = .rodata, 2 = .data, 3 = .bss,
 * 4 = .sbss).
 */
const int ro_tab[8] = {1, 2, 3, 4, 5, 6, 7, 8}; /* .rodata */
int rw_tab[8] = {10, 20, 30, 40, 50, 60, 70, 80}; /* .data */
int zero_tab[64];                                 /* .bss */
int small_zero;                                   /* .sbss */
static volatile int count = 8;                    /* .sdata */

int main(void)
{
    int n = count;
    int a = 0, b = 0, c = 0;
    for (int i = 0; i < n; i++) {
        a += ro_tab[i];
        b += rw_tab[i];
    }
    for (int i = 0; i < 8 * n; i++)
        c |= zero_tab[i];
    if (a != 36)
        return 1;
    if (b != 360)
        return 2;
    if (c != 0)
        return 3;
    if (small_zero != 0)
        return 4;
    return 0;
}
