#!/bin/sh
# refbuild.sh - build one C file as the GCC RV32I reference, report section
# sizes against the 128 KiB static-data budget, and reject libgcc helpers and
# non-RV32I instructions.  Optionally write an ELF that Ripes can run.
#
# Usage:
#   scripts/refbuild.sh [--elf OUT.elf] [--disasm OUT.txt] [--map OUT.map]
#                       FILE.c [EXTRA_CFLAGS...]
#
#   --elf OUT     keep the linked executable (crt0 + FILE.c), runnable with
#                 Ripes --mode cli --src OUT -t elf --proc RV32_ISS --iret.
#                 Written only when the build passes every check (exit 0);
#                 an existing OUT is left untouched otherwise (with a warning)
#   --disasm OUT  write riscv64-elf-objdump -d of the linked ELF
#   --map OUT     write the GNU ld link map
#                 (--disasm/--map are diagnostics: they are also written when
#                 a post-link check fails, and the output says so)
#   EXTRA_CFLAGS  appended after the base flags, so e.g. -O3 overrides -O2;
#                 also passed to the link step (-Wl,... works)
#   -h, --help    print this text and exit 0
#
# What it does:
#   compile  $CC -O2 -march=rv32i -mabi=ilp32 -ffreestanding -c FILE.c
#            -ffreestanding is required: this GCC has no C library, so the
#            hosted <stdint.h> fails; freestanding headers such as
#            stdint.h, stddef.h, stdbool.h, limits.h still work.
#            It also implies -fno-builtin, which changes code generation
#            compared with the plain flags the assignment names
#            (-O2 -march=rv32i -mabi=ilp32): GCC neither expands explicit
#            memcpy/memset/... calls inline nor turns copy/clear loops into
#            memcpy/memset calls.  Add -fbuiltin (or -fhosted) as an
#            EXTRA_CFLAG to get the hosted behaviour back; with no C library
#            linked, a loop that GCC turns into a memset call then fails.
#   audit    scripts/rv32i-audit.sh on the object: fails on any libgcc helper
#            (__mulsi3, __divsi3, __udivsi3, __modsi3, __umodsi3, __muldi3,
#            ...), undefined memcpy/memset/memmove/memcmp, or non-RV32I
#            instruction
#   link     $CC -march=rv32i -mabi=ilp32 -nostdlib -nostartfiles -static
#            -T tools/rv32/ripes.ld tools/rv32/crt0.S FILE.o
#            (no libgcc, no libc; crt0 sets gp/sp, calls main, then
#            ecall 93 with main's return value; crt0 is placed last in
#            .text so that ecall is the final instruction, see crt0.S)
#   audit    the linked ELF again (covers crt0 as well)
#   report   section sizes from "riscv64-elf-size -A" on the linked ELF
#
# "Linked .text bytes" = the .text row of `riscv64-elf-size -A OUT.elf`,
# linked with tools/rv32/ripes.ld.  That script puts all code (crt0 + every
# .text* input) in the one section .text, and the size is taken after linker
# relaxation.  ripes.ld sets __global_pointer$ with the same formula as GNU
# ld's default RISC-V script, so the gp-relative relaxation (and hence the
# size) of the C part matches a default-script link of the same object; other
# layouts can differ by a few bytes.  The crt0 share is reported separately
# from the __crt0_start/__crt0_end symbols.  Static data = the sum of every
# allocated, non-executable section (.rodata .srodata .data .sdata .sbss
# .bss and any other).  This sum is compared with 131072 bytes.
#
# Exit status: 0 = built, audit clean, within budget; 1 = compile/link error,
# audit failure, or over budget; 2 = usage error or missing tool.
#
# Environment: CC (default riscv64-elf-gcc).  RISCV_PREFIX (binutils prefix,
# default: CC with the trailing "gcc" removed, e.g. riscv64-elf-).

set -eu

prog=refbuild
BUDGET=131072

die() { printf '%s: error: %s\n' "$prog" "$*" >&2; exit 1; }
die2() { printf '%s: error: %s\n' "$prog" "$*" >&2; exit 2; }
# usage [STATUS]: print the header comment; to stdout for --help (status 0),
# to stderr for a usage error (status 2).
usage() {
    if [ "${1:-2}" -eq 0 ]; then
        sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
    else
        sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//' >&2
    fi
    exit "${1:-2}"
}

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd) || die2 "cannot locate script directory"
repo=$(CDPATH='' cd -- "$script_dir/.." && pwd)
crt0=$repo/tools/rv32/crt0.S
ldscript=$repo/tools/rv32/ripes.ld
audit=$script_dir/rv32i-audit.sh

CC=${CC:-riscv64-elf-gcc}
case $CC in
    *gcc) P=${RISCV_PREFIX:-${CC%gcc}} ;;
    *) P=${RISCV_PREFIX:-riscv64-elf-} ;;
esac
export RISCV_PREFIX="$P"

elf_out=""
dis_out=""
map_out=""
src=""
while [ $# -gt 0 ]; do
    case $1 in
        --elf|--disasm|--map)
            [ $# -ge 2 ] || die2 "$1 needs a file argument"
            case $1 in
                --elf) elf_out=$2 ;;
                --disasm) dis_out=$2 ;;
                --map) map_out=$2 ;;
            esac
            shift 2 ;;
        -h|--help) usage 0 ;;
        --) shift; [ $# -gt 0 ] || usage; src=$1; shift; break ;;
        -*) die2 "unknown option '$1' before FILE.c (try --help)" ;;
        *) src=$1; shift; break ;;
    esac
done
[ -n "$src" ] || usage
# Remaining "$@" = extra CFLAGS.
case $src in *.c) ;; *) die2 "expected a .c file, got '$src'" ;; esac
[ -f "$src" ] || die2 "no such file: $src"
for f in "$crt0" "$ldscript" "$audit"; do
    [ -f "$f" ] || die2 "missing support file: $f"
done
command -v "$CC" >/dev/null 2>&1 ||
    die2 "$CC not found (brew install riscv64-elf-gcc, or set CC=...)"
for t in size readelf nm objdump; do
    command -v "${P}$t" >/dev/null 2>&1 ||
        die2 "${P}$t not found (set RISCV_PREFIX to the binutils prefix)"
done

tmp=$(mktemp -d "${TMPDIR:-/tmp}/refbuild.XXXXXX") || die2 "mktemp failed"
trap 'rm -rf "$tmp"' EXIT
trap 'exit 130' INT TERM

base="-O2 -march=rv32i -mabi=ilp32 -ffreestanding"
ldbase="-march=rv32i -mabi=ilp32 -nostdlib -nostartfiles -static"
obj=$tmp/prog.o
elf=$tmp/prog.elf

printf '%s: %s\n' "$prog" "$src"
printf '  compiler : %s\n' "$("$CC" --version | head -n 1)"
printf '  compile  : %s %s %s -c %s\n' "$CC" "$base" "$*" "$src"

# shellcheck disable=SC2086  # $base is a fixed, space-separated flag list
if ! "$CC" $base "$@" -c "$src" -o "$obj" 2>"$tmp/cc.err"; then
    cat "$tmp/cc.err" >&2
    die "compilation failed"
fi
if [ -s "$tmp/cc.err" ]; then cat "$tmp/cc.err" >&2; fi

# Object audit: helper calls show up here as undefined symbols.
if ! sh "$audit" -q "$obj" >"$tmp/audit-obj.txt" 2>&1; then
    printf '  audit of the object compiled from %s (prog.o):\n' "$src"
    cat "$tmp/audit-obj.txt"
    printf '%s: FAIL: %s needs code outside base RV32I or a runtime helper.\n' "$prog" "$src"
    printf '%s:       Nothing is linked from libgcc/libc, so the reference build\n' "$prog"
    printf '%s:       must compile to base RV32I with no helper calls.\n' "$prog"
    if grep -q 'undefined libc routine mem' "$tmp/audit-obj.txt"; then
        printf '%s: hint: -ffreestanding implies -fno-builtin, so an explicit\n' "$prog"
        printf '%s:       memcpy/memset/... call stays a call.  Define the routine in\n' "$prog"
        printf '%s:       %s, or add -fbuiltin so GCC may expand small fixed-size\n' "$prog" "$src"
        printf '%s:       calls inline (it may then also turn loops into calls).\n' "$prog"
    fi
    exit 1
fi

if ! "$CC" -march=rv32i -mabi=ilp32 -c "$crt0" -o "$tmp/crt0.o" 2>"$tmp/crt0.err"; then
    cat "$tmp/crt0.err" >&2
    die "assembling $crt0 failed"
fi

printf '  link     : %s %s %s -T %s crt0.o prog.o\n' "$CC" "$ldbase" "$*" "$ldscript"
# shellcheck disable=SC2086
if ! "$CC" $ldbase "$@" -T "$ldscript" -Wl,-Map="$tmp/prog.map" \
    "$tmp/crt0.o" "$obj" -o "$elf" 2>"$tmp/ld.err"; then
    cat "$tmp/ld.err" >&2
    if grep -q "undefined reference" "$tmp/ld.err"; then
        printf '%s: hint: no C library or libgcc is linked (-nostdlib).  Every\n' "$prog" >&2
        printf '%s:       function must be defined in %s itself.  Use Ripes\n' "$prog" "$src" >&2
        printf '%s:       ecalls (inline asm) for output.\n' "$prog" >&2
    fi
    die "link failed"
fi
if [ -s "$tmp/ld.err" ]; then cat "$tmp/ld.err" >&2; fi

# ------------------------------------------------------------ section table
# readelf: name and flags (to classify); size -A: the reported byte counts.
"${P}readelf" -S -W "$elf" | awk '
/^ *\[ *[0-9]+\]/ {
    sub(/^ *\[ *[0-9]+\] */, "")
    if (NF >= 10) flg = $7; else flg = ""
    if ($1 != "" && $2 != "NULL") print $1, flg
}' >"$tmp/flags"
"${P}size" -A "$elf" >"$tmp/size.txt" || die "size -A failed"

awk -v budget="$BUDGET" -v flagsfile="$tmp/flags" '
BEGIN {
    while ((getline line < flagsfile) > 0) {
        split(line, kv, " "); fl[kv[1]] = kv[2]
    }
    order = ".text .rodata .srodata .data .sdata .sbss .bss"
    nk = split(order, known, " ")
    for (i = 1; i <= nk; i++) isknown[known[i]] = 1
}
NF == 3 && $2 ~ /^[0-9]+$/ { sz[$1] = $2; ad[$1] = $3; names[++n] = $1 }
END {
    for (i = 1; i <= n; i++) {
        s = names[i]; f = fl[s]
        if (f ~ /X/ && s != ".text") badx = badx " " s
        if (f ~ /A/ && f !~ /X/) {
            data += sz[s]
            if (!(s in isknown)) extra = extra " " s
        }
    }
    printf "#text %d\n#textend %d\n#data %d\n#badx %s\n#extra %s\n", sz[".text"], ad[".text"] + sz[".text"], data, badx, extra
    for (i = 1; i <= nk; i++) printf "%s %d\n", known[i], (known[i] in sz ? sz[known[i]] : 0)
    for (i = 1; i <= n; i++) {
        s = names[i]
        if ((fl[s] ~ /A/) && !(s in isknown)) printf "%s %d\n", s, sz[s]
    }
}' "$tmp/size.txt" >"$tmp/report"

textend=$(awk '/^#textend/ {print $2}' "$tmp/report")
data=$(awk '/^#data/ {print $2}' "$tmp/report")
badx=$(awk '/^#badx/ {$1 = ""; sub(/^ /, ""); print}' "$tmp/report")
extra=$(awk '/^#extra/ {$1 = ""; sub(/^ /, ""); print}' "$tmp/report")

# "<bytes> <end address>" of the crt0 code, both decimal; "? ?" if missing.
crt0_info=$("${P}nm" "$elf" | awk '
$3 == "__crt0_start" {s = $1} $3 == "__crt0_end" {e = $1}
END {
    if (s == "" || e == "") { print "? ?"; exit }
    hex = "0123456789abcdef"; vs = 0; ve = 0
    for (i = 1; i <= length(s); i++) vs = vs * 16 + index(hex, substr(tolower(s), i, 1)) - 1
    for (i = 1; i <= length(e); i++) ve = ve * 16 + index(hex, substr(tolower(e), i, 1)) - 1
    print ve - vs, ve
}')
crt0_bytes=${crt0_info% *}
crt0_end=${crt0_info#* }
entry=$("${P}readelf" -h "$elf" | awk -F: '/Entry point/ {gsub(/[ \t]/, "", $2); print $2}')

printf '  sizes    : %s -A <linked ELF>   (bytes)\n' "${P}size"
grep -v '^#' "$tmp/report" | while read -r name bytes; do
    case $name in
        .text)
            if [ "$crt0_bytes" = "?" ]; then
                printf '    %-18s %8d   linked .text\n' "$name" "$bytes"
            else
                printf '    %-18s %8d   linked .text = %d crt0 + %d compiled from %s\n' \
                    "$name" "$bytes" "$crt0_bytes" "$((bytes - crt0_bytes))" "$src"
            fi ;;
        *) printf '    %-18s %8d\n' "$name" "$bytes" ;;
    esac
done
printf '    %-18s %8d / %d bytes (all allocated non-code sections)\n' \
    "static data total" "$data" "$BUDGET"
if [ -n "$extra" ]; then
    printf '  note     : other allocated sections counted as data: %s\n' "$extra"
fi

status=0
if [ "$crt0_end" = "?" ]; then
    printf '%s: FAIL: __crt0_start/__crt0_end not found in the linked ELF\n' "$prog"
    status=1
elif [ "$crt0_end" -ne "$textend" ]; then
    printf '%s: FAIL: crt0 exit ecall is not the last instruction of .text\n' "$prog"
    printf '%s:       (crt0 ends at %d, .text ends at %d).  Ripes RV32_ISS would\n' "$prog" "$crt0_end" "$textend"
    printf '%s:       execute and count one extra instruction after the exit.\n' "$prog"
    status=1
fi
if [ -n "$badx" ]; then
    printf '%s: FAIL: executable section(s) other than .text: %s.\n' "$prog" "$badx"
    printf '%s:       Ripes only executes .text; fix tools/rv32/ripes.ld.\n' "$prog"
    status=1
fi
if [ "$data" -gt "$BUDGET" ]; then
    printf '%s: FAIL: static data %d bytes exceeds the %d-byte budget by %d\n' \
        "$prog" "$data" "$BUDGET" "$((data - BUDGET))"
    status=1
fi

if sh "$audit" -q "$elf" >"$tmp/audit-elf.txt" 2>&1; then
    printf '  audit    : PASS (rv32i-audit.sh on object and linked ELF)\n'
else
    printf '  audit of the linked ELF (prog.elf):\n'
    cat "$tmp/audit-elf.txt"
    status=1
fi

# Outputs.  The ELF is written only for a build that passed every check, so
# a rejected ELF is never left where a runner could pick it up.  The listing
# and the map are diagnostics and are written either way (labelled).
if [ "$status" -eq 0 ]; then
    failnote=""
else
    failnote="  (written for diagnosis; the build FAILED)"
fi
elf_saved=""
if [ -n "$elf_out" ]; then
    if [ "$status" -eq 0 ]; then
        cp "$elf" "$elf_out" || die "cannot write $elf_out"
        elf_saved=$elf_out
        printf '  elf      : %s (entry %s)\n' "$elf_out" "$entry"
    else
        printf '  elf      : NOT written to %s (the build failed)\n' "$elf_out"
        if [ -e "$elf_out" ]; then
            printf '%s: warning: %s already exists from an earlier run and was\n' "$prog" "$elf_out"
            printf '%s:          left unchanged; it does not match %s\n' "$prog" "$src"
        fi
    fi
fi
if [ -n "$dis_out" ]; then
    if [ -n "$elf_saved" ]; then
        # The listing header then names the saved ELF.
        "${P}objdump" -d "$elf_saved" >"$dis_out" || die "cannot write $dis_out"
    else
        # No saved ELF: replace the temporary path in the header line.
        "${P}objdump" -d "$elf" >"$tmp/dis.txt" || die "objdump -d failed"
        awk -v tmpelf="$elf" -v label="(linked from $src by refbuild.sh; ELF not saved)" '
            !done && index($0, tmpelf ":") == 1 {
                $0 = label substr($0, length(tmpelf) + 1); done = 1
            }
            { print }' "$tmp/dis.txt" >"$dis_out" || die "cannot write $dis_out"
    fi
    printf '  disasm   : %s%s\n' "$dis_out" "$failnote"
fi
if [ -n "$map_out" ]; then
    cp "$tmp/prog.map" "$map_out" || die "cannot write $map_out"
    printf '  map      : %s%s\n' "$map_out" "$failnote"
fi

if [ "$status" -ne 0 ]; then
    printf '%s: FAIL\n' "$prog"
    exit 1
fi
printf '%s: OK\n' "$prog"
