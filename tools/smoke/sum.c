/*
 * SMOKE TEST ONLY - unrelated to the homework.  Checks that
 * scripts/refbuild.sh --elf produces an ELF that Ripes runs to completion and
 * that the exit status reaches Ripes' console.
 *
 * Sums 1..100; main returns 0 if the sum is 5050, otherwise 1 (crt0 passes
 * the value to ecall 93, and Ripes prints "Program exited with code: N").
 * The limit is volatile so that -O2 cannot constant-fold the loop away.
 */
static volatile int limit = 100;

int main(void)
{
    int n = limit;
    int sum = 0;
    for (int i = 1; i <= n; i++)
        sum += i;
    return sum == 5050 ? 0 : 1;
}
