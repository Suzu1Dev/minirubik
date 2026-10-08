#!/bin/sh
# refbuild-smoke.sh - SMOKE TESTS ONLY (unrelated to the homework): check that
# the RV32I reference toolchain, scripts/refbuild.sh, scripts/rv32i-audit.sh
# and Ripes ELF loading still work.  Uses only the throwaway programs in
# tools/smoke/ (sum.c, datasec.c, mul.c, ext-mul.s).
#
# Usage:  tools/smoke/refbuild-smoke.sh
# Env:    RIPES  path to the Ripes binary (default: the portable app in
#                ../.tools/ next to the repository)
#         CC, RISCV_PREFIX  passed through to refbuild.sh / rv32i-audit.sh
#
# Checks:
#   1. refbuild.sh builds sum.c and datasec.c (exit 0) and Ripes RV32_ISS
#      prints "Program exited with code: 0" for each ELF (iret is shown)
#   2. refbuild.sh rejects mul.c (exit 1, __mulsi3 reported)
#   3. rv32i-audit.sh rejects ext-mul.s (exit 1, M extension reported)
#   Regression checks (throwaway one-line inputs generated in a temp dir):
#   4. rv32i-audit.sh flags __clrsbsi2 (a libgcc helper outside the old
#      fixed name list) with exit 1
#   5. rv32i-audit.sh says NOT AUDITED (exit 2) for an empty .s and for a
#      stripped executable
#   6. refbuild.sh --elf does not write the ELF when the build fails (over
#      the static-data budget); --help exits 0
#   7. datasec.c: the C part of .text under tools/rv32/ripes.ld equals the
#      .text of a default-linker-script link (same gp relaxation)
# Exit status: 0 if every check passed, 1 otherwise, 2 on setup errors.

set -eu

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd) || exit 2
repo=$(CDPATH='' cd -- "$here/../.." && pwd) || exit 2
RIPES=${RIPES:-$repo/../.tools/Ripes-v2.2.6-106-g5b8a616-mac-universal2.app/Contents/MacOS/Ripes}
[ -x "$RIPES" ] || { echo "refbuild-smoke: Ripes not found at $RIPES (set RIPES=...)" >&2; exit 2; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/refbuild-smoke.XXXXXX") || exit 2
trap 'rm -rf "$tmp"' EXIT
trap 'exit 130' INT TERM

fails=0
pass() { printf 'PASS  %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*"; fails=$((fails + 1)); }

for t in sum datasec; do
    if sh "$repo/scripts/refbuild.sh" --elf "$tmp/$t.elf" "$here/$t.c" >"$tmp/$t.build" 2>&1; then
        "$RIPES" --mode cli --src "$tmp/$t.elf" -t elf --proc RV32_ISS --iret \
            --timeout 60000 >"$tmp/$t.run" 2>&1 || true
        iret=$(awk 'f {print; exit} /instructions retired/ {f = 1}' "$tmp/$t.run")
        if grep -q "Program exited with code: 0" "$tmp/$t.run"; then
            pass "$t.c: built, ran on RV32_ISS, exit code 0, iret ${iret:-?}"
        else
            fail "$t.c: Ripes did not report exit code 0:"; cat "$tmp/$t.run"
        fi
    else
        fail "$t.c: refbuild.sh failed:"; cat "$tmp/$t.build"
    fi
done

st=0
sh "$repo/scripts/refbuild.sh" "$here/mul.c" >"$tmp/mul.build" 2>&1 || st=$?
if [ "$st" -eq 1 ] && grep -q "__mulsi3" "$tmp/mul.build"; then
    pass "mul.c: rejected by refbuild.sh (__mulsi3)"
else
    fail "mul.c: expected exit 1 mentioning __mulsi3, got exit $st:"; cat "$tmp/mul.build"
fi

st=0
sh "$repo/scripts/rv32i-audit.sh" "$here/ext-mul.s" >"$tmp/ext.audit" 2>&1 || st=$?
if [ "$st" -eq 1 ] && grep -q "mul a0,a0,a1" "$tmp/ext.audit"; then
    pass "ext-mul.s: rejected by rv32i-audit.sh (mul)"
else
    fail "ext-mul.s: expected exit 1 mentioning mul, got exit $st:"; cat "$tmp/ext.audit"
fi

# ---- regression checks; inputs are throwaway one-liners, not homework code
P=${RISCV_PREFIX:-riscv64-elf-}
CCX=${CC:-${P}gcc}

printf 'int f(int x) { return __builtin_clrsb(x); }\n' >"$tmp/clrsb.c"
st=0
if "$CCX" -O2 -march=rv32i -mabi=ilp32 -ffreestanding -c "$tmp/clrsb.c" -o "$tmp/clrsb.o"; then
    sh "$repo/scripts/rv32i-audit.sh" "$tmp/clrsb.o" >"$tmp/clrsb.audit" 2>&1 || st=$?
    if [ "$st" -eq 1 ] && grep -q "__clrsbsi2" "$tmp/clrsb.audit"; then
        pass "clrsb.o: rv32i-audit.sh flags libgcc helper __clrsbsi2"
    else
        fail "clrsb.o: expected exit 1 mentioning __clrsbsi2, got exit $st:"; cat "$tmp/clrsb.audit"
    fi
else
    fail "clrsb.c: compile failed"
fi

: >"$tmp/empty.s"
st=0
sh "$repo/scripts/rv32i-audit.sh" "$tmp/empty.s" >"$tmp/empty.audit" 2>&1 || st=$?
printf 'int f(int a, int b) { return a + b; }\n' >"$tmp/add.c"
st2=0
if "$CCX" -O2 -march=rv32i -mabi=ilp32 -ffreestanding -nostdlib -Wl,-e,f \
        "$tmp/add.c" -o "$tmp/add.elf" &&
    "${P}strip" -o "$tmp/add-stripped.elf" "$tmp/add.elf"; then
    sh "$repo/scripts/rv32i-audit.sh" "$tmp/add-stripped.elf" >"$tmp/strip.audit" 2>&1 || st2=$?
else
    st2=99
fi
if [ "$st" -eq 2 ] && [ "$st2" -eq 2 ] &&
    grep -q "NOT AUDITED" "$tmp/empty.audit" && grep -q "NOT AUDITED" "$tmp/strip.audit"; then
    pass "rv32i-audit.sh: NOT AUDITED (exit 2) for an empty .s and a stripped ELF"
else
    fail "rv32i-audit.sh: expected exit 2 for empty.s and stripped ELF, got $st and $st2:"
    cat "$tmp/empty.audit" "$tmp/strip.audit" 2>/dev/null || true
fi

printf 'static char big[131080]; static volatile int i = 5;\nint main(void) { big[i] = 1; return big[i] - 1; }\n' >"$tmp/big.c"
st=0
sh "$repo/scripts/refbuild.sh" --elf "$tmp/big.elf" "$tmp/big.c" >"$tmp/big.build" 2>&1 || st=$?
hst=0
sh "$repo/scripts/refbuild.sh" --help >/dev/null 2>&1 || hst=$?
if [ "$st" -eq 1 ] && [ ! -e "$tmp/big.elf" ] && grep -q "exceeds the 131072-byte budget" "$tmp/big.build" &&
    [ "$hst" -eq 0 ]; then
    pass "refbuild.sh: over-budget build exits 1 without writing --elf; --help exits 0"
else
    fail "refbuild.sh: over-budget exit $st (want 1), ELF written: $([ -e "$tmp/big.elf" ] && echo yes || echo no), --help exit $hst (want 0)"
    cat "$tmp/big.build"
fi

st=0
if "$CCX" -O2 -march=rv32i -mabi=ilp32 -ffreestanding -c "$here/datasec.c" -o "$tmp/ds.o" &&
    "$CCX" -march=rv32i -mabi=ilp32 -nostdlib -nostartfiles -static -Wl,-e,main \
        "$tmp/ds.o" -o "$tmp/ds-default.elf"; then
    def=$("${P}size" -A "$tmp/ds-default.elf" | awk '$1 == ".text" {print $2}')
    rb=$(sed -n 's/.*linked \.text = [0-9]* crt0 + \([0-9]*\) compiled from.*/\1/p' "$tmp/datasec.build")
    if [ -n "$def" ] && [ "$def" = "$rb" ]; then
        pass "datasec.c: C part of .text $rb B under ripes.ld = default-script link $def B"
    else
        fail "datasec.c: C part of .text under ripes.ld '${rb:-?}' != default-script link '${def:-?}'"
    fi
else
    fail "datasec.c: default-script link failed"
fi

if [ "$fails" -eq 0 ]; then
    echo "refbuild-smoke: all checks passed"
    exit 0
fi
echo "refbuild-smoke: $fails check(s) failed"
exit 1
