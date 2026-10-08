/*
 * SMOKE TEST ONLY - unrelated to the homework.  A negative test:
 * scripts/refbuild.sh MUST reject this file.  Under -march=rv32i, GCC turns
 * '*' between two run-time ints into a call to the libgcc helper __mulsi3.
 */
static volatile int a = 6, b = 7;

int main(void)
{
    return a * b == 42 ? 0 : 1;
}
