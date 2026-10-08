#!/bin/sh
# rv32i-audit.sh - check that code uses only base RV32I instructions and does
# not depend on libgcc helper routines (__mulsi3, __divsi3, ...).
#
# Usage:
#   scripts/rv32i-audit.sh [-q] [--defsym NAME=VALUE]... FILE
#
#   FILE  .s / .asm  assembly source, assembled first with
#                    riscv64-elf-as -march=rv32i -mabi=ilp32 -g
#         .S         assembly source run through the C preprocessor
#                    (riscv64-elf-gcc -c -march=rv32i -mabi=ilp32 -g)
#         .o / .elf  any RISC-V ELF (object or executable); recognised by its
#                    ELF magic, so the file name does not matter
#   -q               print only problems and the final verdict
#   --defsym N=V     define an assembler symbol before assembling, e.g. a Ripes
#                    peripheral constant: --defsym LED_MATRIX_0_BASE=0xf0000000
#
# Checks (all must pass):
#   1. Every instruction that objdump -d -M no-aliases decodes in an
#      executable section is one of the 40 RV32I base instructions:
#        lui auipc jal jalr beq bne blt bge bltu bgeu lb lh lw lbu lhu
#        sb sh sw addi slti sltiu xori ori andi slli srli srai
#        add sub sll slt sltu xor srl sra or and fence ecall ebreak
#      (fence.tso and pause are accepted as FENCE encodings).  Everything
#      else fails: M (mul/div/rem), C (c.*), RV64 (*w, ld, sd, lwu), F/D,
#      A, Zicsr, Zifencei, B, and raw .word/.insn data in executable sections.
#   2. No symbol (defined or undefined) has a libgcc helper name, and there
#      is no undefined mem* routine (memcpy/memset/memmove/memcmp; no C
#      library is linked).  The helper names are read from the toolchain's
#      own rv32i/ilp32 libgcc.a (nm of `gcc -print-libgcc-file-name`), so
#      every routine libgcc can supply is covered (__mulsi3, __clrsbsi2,
#      __gcc_bcmp, __emutls_get_address, _Unwind_*, ...).  If libgcc.a is
#      not found, a built-in name pattern is used instead (with a note).
#      Every other undefined symbol, including __* names, is listed.
#   3. The ELF is 32-bit RISC-V; the RVC and float-ABI e_flags bits are
#      reported.
#   For an assembly source, the strict -march=rv32i assembly is itself a check:
#   GNU as rejects every extension opcode with "extension `x' required".
#
# NOT AUDITED (exit 2) instead of PASS when a check cannot be done:
#   - no instruction at all is found in an executable section (empty file,
#     or code placed in a data section);
#   - an executable ELF has no symbol table (stripped): linked-in libgcc code
#     cannot be recognised without symbol names.  A relocatable object (.o or
#     assembled source) without symbols is fine: it cannot call anything.
#
# Limitation: Ripes' assembler is not GNU as.  A source that Ripes accepts may
# not assemble with GNU as (e.g. comma-less operands such as "mv t0 a0",
# Ripes-only directives, or Ripes peripheral symbols such as
# LED_MATRIX_0_BASE that Ripes predefines).  The script then says
# "NOT AUDITED" and exits 2 (or exits 1 if it also saw extension opcodes).
# It never reports a pass for a file it could not assemble.  Use --defsym
# for Ripes symbols.
#
# Exit status: 0 = pass, 1 = violations found, 2 = could not audit (bad usage,
# missing tool, file GNU as cannot assemble, not a RISC-V ELF, no
# instructions, stripped executable).  --help prints this text and exits 0.
#
# Environment: RISCV_PREFIX (default "riscv64-elf-"), e.g. set it to
# "riscv64-unknown-elf-" to use that toolchain instead.

set -eu

prog=rv32i-audit
P=${RISCV_PREFIX:-riscv64-elf-}

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

quiet=0
defsyms=""
file=""
while [ $# -gt 0 ]; do
    case $1 in
        -q) quiet=1 ;;
        --defsym)
            [ $# -ge 2 ] || die2 "--defsym needs NAME=VALUE"
            case $2 in *=*) ;; *) die2 "--defsym needs NAME=VALUE, got '$2'" ;; esac
            defsyms="$defsyms
$2"
            shift ;;
        --defsym=*) defsyms="$defsyms
${1#--defsym=}" ;;
        -h|--help) usage 0 ;;
        -*) die2 "unknown option '$1' (try --help)" ;;
        *) [ -z "$file" ] || die2 "only one FILE may be given"; file=$1 ;;
    esac
    shift
done
[ -n "$file" ] || usage
[ -f "$file" ] || die2 "no such file: $file"
[ -r "$file" ] || die2 "cannot read: $file"

for t in as objdump nm readelf gcc; do
    command -v "${P}$t" >/dev/null 2>&1 ||
        die2 "${P}$t not found on PATH (brew install riscv64-elf-gcc, or set RISCV_PREFIX)"
done

say() { [ "$quiet" -eq 1 ] || printf '%s\n' "$*"; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/rv32i-audit.XXXXXX") || die2 "mktemp failed"
trap 'rm -rf "$tmp"' EXIT
trap 'exit 130' INT TERM

# ---------------------------------------------------------------- input type
magic=$(od -An -tx1 -N4 "$file" | tr -d ' \n')
problems=0
obj=""
kind=""
if [ "$magic" = "7f454c46" ]; then
    obj=$file
    kind=elf
else
    case $file in
        *.s|*.asm) kind=asm ;;
        *.S) kind=cpp-asm ;;
        *) die2 "$file is neither an ELF file nor a .s/.S/.asm source" ;;
    esac
    obj=$tmp/audit.o
    errf=$tmp/as.err
    # Build the argument list in "$@" (POSIX sh has no arrays).
    set --
    oldifs=$IFS
    IFS='
'
    for d in $defsyms; do
        [ -n "$d" ] || continue
        if [ "$kind" = asm ]; then
            set -- "$@" --defsym "$d"
        else
            set -- "$@" "-Wa,--defsym,$d"
        fi
    done
    IFS=$oldifs
    if [ "$kind" = asm ]; then
        asm_cmd="${P}as -march=rv32i -mabi=ilp32 -g"
        if "${P}as" -march=rv32i -mabi=ilp32 -g "$@" -o "$obj" "$file" 2>"$errf"; then
            as_ok=1
        else
            as_ok=0
        fi
    else
        asm_cmd="${P}gcc -c -march=rv32i -mabi=ilp32 -g -x assembler-with-cpp"
        if "${P}gcc" -c -march=rv32i -mabi=ilp32 -g -x assembler-with-cpp \
            "$@" -o "$obj" "$file" 2>"$errf"; then
            as_ok=1
        else
            as_ok=0
        fi
    fi
    if [ "$as_ok" -eq 0 ]; then
        ext_err=$(grep -c "extension \`" "$errf" || true)
        other_err=$(grep -i "error" "$errf" | grep -vc "extension \`" || true)
        printf '%s: %s does not assemble with: %s\n' "$prog" "$file" "$asm_cmd"
        if [ "$ext_err" -gt 0 ]; then
            printf '%s: FAIL: non-RV32I instruction(s) rejected by the assembler:\n' "$prog"
            grep "extension \`" "$errf" | sed 's/^/  FAIL  /'
        fi
        if [ "$other_err" -gt 0 ]; then
            printf '%s: other assembler errors (GNU as cannot parse these lines):\n' "$prog"
            grep -i "error" "$errf" | grep -v "extension \`" | sed 's/^/  ?     /'
            if grep -i "error" "$errf" | grep -v "extension \`" |
                grep -q "illegal operands\|undefined\|bad expression\|unknown pseudo-op\|junk at end"; then
                printf '%s: hint: Ripes accepts things GNU as rejects, e.g. operands\n' "$prog"
                printf '%s:       without commas ("mv t0 a0") and predefined peripheral\n' "$prog"
                printf '%s:       symbols (LED_MATRIX_0_BASE, ...).  Add the commas (also\n' "$prog"
                printf '%s:       valid in Ripes) or pass --defsym NAME=VALUE.\n' "$prog"
            fi
            printf '%s: NOT AUDITED: GNU as cannot assemble %s, so this script cannot\n' "$prog" "$file"
            printf '%s: confirm it is RV32I-only.  This is not a pass.\n' "$prog"
            if [ "$ext_err" -gt 0 ]; then
                printf '%s: FAIL: %d non-RV32I instruction(s) in %s (audit incomplete)\n' "$prog" "$ext_err" "$file"
                exit 1
            fi
            exit 2
        fi
        if [ "$ext_err" -eq 0 ]; then
            sed 's/^/  ?     /' "$errf"
            printf '%s: NOT AUDITED: the assembler failed without a recognisable error.\n' "$prog"
            exit 2
        fi
        printf '%s: FAIL: %d non-RV32I instruction(s) in %s\n' "$prog" "$ext_err" "$file"
        exit 1
    fi
fi

# ---------------------------------------------------------------- ELF header
hdr=$tmp/hdr
"${P}readelf" -h "$obj" >"$hdr" 2>/dev/null || die2 "readelf cannot read $obj"
class=$(awk -F: '/^ *Class:/ {gsub(/^[ \t]+/, "", $2); print $2}' "$hdr")
machine=$(awk -F: '/^ *Machine:/ {gsub(/^[ \t]+/, "", $2); print $2}' "$hdr")
etype=$(awk -F: '/^ *Type:/ {gsub(/^[ \t]+/, "", $2); print $2}' "$hdr")
flags=$(awk -F: '/^ *Flags:/ {gsub(/^[ \t]+/, "", $2); print $2}' "$hdr")
[ "$machine" = "RISC-V" ] || die2 "$obj is not a RISC-V ELF (Machine: $machine)"
arch=$("${P}readelf" -A "$obj" 2>/dev/null |
    awk -F'"' '/Tag_RISCV_arch/ {print $2; exit}')
[ -n "$arch" ] || arch="(no Tag_RISCV_arch attribute)"
say "$prog: $file"
say "  ELF: $class, $etype, e_flags $flags, Tag_RISCV_arch \"$arch\""
if [ "$class" != "ELF32" ]; then
    printf '  FAIL  ELF class is %s; RV32I code must be ELF32\n' "$class"
    problems=$((problems + 1))
fi
# e_flags: bit 0 = RVC, bits 1-2 = float ABI.  "0x0" is plain ilp32, no RVC.
fl=$(printf '%s\n' "$flags" | awk '{print $1}' | sed 's/,.*//')
case $fl in
    0x*) flv=$(printf '%d' "$fl" 2>/dev/null || echo 0) ;;
    *) flv=0 ;;
esac
if [ $((flv & 1)) -ne 0 ]; then
    say "  note  e_flags has RVC set (compressed code allowed by the build)"
fi
if [ $((flv & 6)) -ne 0 ]; then
    say "  note  e_flags float ABI is not soft-float ilp32"
fi
case $arch in
    rv32i2p[0-9]|rv32i2p[0-9]_zicsr*|rv32i2p[0-9]_zifencei*) ;;
    "(no Tag_RISCV_arch attribute)") ;;
    *) say "  note  arch attribute lists extensions beyond RV32I (it records the -march used, not the instructions actually emitted)" ;;
esac

# ---------------------------------------------------------- instruction scan
dis=$tmp/dis
"${P}objdump" -d -l -M no-aliases "$obj" >"$dis" 2>"$tmp/objdump.err" ||
    die2 "objdump failed on $obj: $(cat "$tmp/objdump.err")"

scan=$tmp/scan
awk -F '\t' -v quiet="$quiet" '
BEGIN {
    n = split("lui auipc jal jalr beq bne blt bge bltu bgeu lb lh lw lbu lhu " \
              "sb sh sw addi slti sltiu xori ori andi slli srli srai add sub " \
              "sll slt sltu xor srl sra or and fence fence.tso pause ecall ebreak", a, " ")
    for (i = 1; i <= n; i++) ok[a[i]] = 1
    split("mul mulh mulhsu mulhu div divu rem remu", m, " ")
    for (i in m) mext[m[i]] = 1
    split("addiw slliw srliw sraiw addw subw sllw srlw sraw mulw divw divuw remw remuw ld sd lwu", r, " ")
    for (i in r) rv64[r[i]] = 1
    count = 0; bad = 0; sec = ""; fn = ""; src = ""
}
/^Disassembly of section / { sec = $0; sub(/^Disassembly of section /, "", sec); sub(/:$/, "", sec); next }
/^[0-9a-f]+ <.*>:$/ { fn = $0; sub(/^[0-9a-f]+ </, "", fn); sub(/>:$/, "", fn); next }
/^[^ \t].*:[0-9]+( \(discriminator [0-9]+\))?$/ { src = $0; sub(/ \(discriminator.*$/, "", src); next }
/^ *[0-9a-f]+:\t/ {
    addr = $1; sub(/^ +/, "", addr); sub(/:$/, "", addr)
    enc = $2; gsub(/ +/, "", enc)
    mn = $3; gsub(/^ +| +$/, "", mn)
    ops = $4; sub(/[ \t]+#.*$/, "", ops)
    if (mn == "") next
    count++
    if (mn in ok) next
    if (mn ~ /^c\./ || length(enc) == 4)              why = "C extension (compressed)"
    else if (mn in mext)                              why = "M extension (multiply/divide)"
    else if (mn in rv64)                              why = "RV64-only"
    else if (mn ~ /^(lr|sc)\./ || mn ~ /^amo/)        why = "A extension (atomics)"
    else if (mn ~ /^csrr|^csrw|^csrs|^csrc|^rd(cycle|time|instret)/) why = "Zicsr (CSR access)"
    else if (mn == "fence.i")                         why = "Zifencei"
    else if (mn ~ /^f/)                               why = "F/D (floating point)"
    else if (mn ~ /^\./ || mn == "unimp" || mn ~ /bad/) why = "raw data / undecodable encoding in executable section"
    else                                              why = "not in RV32I"
    bad++
    printf "  FAIL  %s 0x%s <%s>  %s  %s %s  [%s]%s\n", sec, addr, fn, enc, mn, ops, why, (src != "" ? "  at " src : "")
}
END { printf "#count %d\n#bad %d\n", count, bad }
' "$dis" >"$scan"

ninsn=$(awk '/^#count/ {print $2}' "$scan")
nbad=$(awk '/^#bad/ {print $2}' "$scan")
grep -v '^#' "$scan" || true
say "  instructions decoded in executable sections: $ninsn"
problems=$((problems + nbad))
# Reasons the audit is incomplete; any of them turns a PASS into NOT AUDITED.
unaudited=""
if [ "$ninsn" -eq 0 ]; then
    printf '  ?     no instructions found in any executable section (empty input, or\n'
    printf '        code placed in a data section): nothing was checked\n'
    unaudited="$unaudited no-instructions"
fi

# --------------------------------------------------------- helper symbols
# Helper names: every global symbol defined in the toolchain's rv32i/ilp32
# libgcc.a.  Fallback: a fixed name pattern (kept in the awk program below).
helper_list=$tmp/libgcc-names
: >"$helper_list"
libgcc=$("${P}gcc" -march=rv32i -mabi=ilp32 -print-libgcc-file-name 2>/dev/null || true)
if [ -n "$libgcc" ] && [ -f "$libgcc" ] &&
    "${P}nm" -g --defined-only "$libgcc" 2>/dev/null |
        awk 'NF >= 3 {print $NF}' | sort -u >"$helper_list" &&
    [ -s "$helper_list" ]; then
    say "  helper names: $(wc -l <"$helper_list" | tr -d ' ') global symbols of $libgcc"
else
    : >"$helper_list"
    say "  note  libgcc.a for rv32i/ilp32 not found (${P}gcc -print-libgcc-file-name);"
    say "        using the built-in helper name pattern only"
fi

syms=$tmp/syms
"${P}nm" "$obj" >"$syms" 2>/dev/null || : >"$syms"
has_symtab=0
"${P}readelf" -S -W "$obj" 2>/dev/null | grep -q '[[:space:]]\.symtab[[:space:]]' && has_symtab=1
if [ ! -s "$syms" ]; then
    case $etype in
        REL*)
            say "  note  no symbols: a relocatable object without symbols cannot call any"
            say "        external routine, so there is no helper call to find" ;;
        *)
            if [ "$has_symtab" -eq 0 ]; then
                printf '  ?     executable has no symbol table (stripped): linked-in libgcc\n'
            else
                printf '  ?     executable has an empty symbol table: linked-in libgcc\n'
            fi
            printf '        helpers cannot be recognised by name; audit the unstripped ELF\n'
            unaudited="$unaudited no-symbols" ;;
    esac
fi
# Output: one "  FAIL ..." line per helper / mem* symbol, and "#other NAME"
# for every other undefined symbol (including __* names that are not libgcc
# helpers, e.g. linker-script symbols such as __global_pointer$).
awk -v listfile="$helper_list" '
BEGIN { while ((getline n < listfile) > 0) lg[n] = 1 }
{
    name = $NF; type = (NF >= 3 ? $2 : $1)
    if ((name in lg) ||
        name ~ /^__(mul|div|mod|udiv|umod|udivmod|divmod|ashl|ashr|lshr|neg|cmp|ucmp|clz|ctz|clrsb|ffs|popcount|parity|bswap|abs|absv|addv|subv|mulv|negv|add|sub|fix|fixuns|float|floatun|extend|trunc|eq|ne|lt|le|gt|ge|unord|pow)[a-z]*[0-9]$/ ||
        name ~ /^__(fix|fixuns|float|floatun)[a-z]+$/ ||
        name ~ /^__riscv_(save|restore)_[0-9]+$/ ||
        name ~ /^__(clear_cache|gcc_personality_v0|gcc_bcmp|udiv_w_sdiv|clz_tab|popcount_tab|enable_execute_stack|hardcfr_check|frame_state_for|CTOR_LIST__|DTOR_LIST__)$/ ||
        name ~ /^__(riscv_cpu_model|riscv_feature_bits|init_riscv_feature_bits)$/ ||
        name ~ /^__(register_frame|deregister_frame)(_|$)/ ||
        name ~ /^__(emutls|strub|hidden)_/ ||
        name ~ /^_Unwind_/ ||
        name ~ /^__(sync|atomic)_/)
        printf "  FAIL  libgcc helper symbol %s (%s)\n", name, (type == "U" ? "undefined: called but not provided" : "defined: libgcc code linked in, or an own routine using a libgcc name")
    else if (type == "U" && name ~ /^(memcpy|memset|memmove|memcmp)$/)
        printf "  FAIL  undefined libc routine %s (called explicitly in the source, or emitted by GCC for a block copy/clear/compare; no C library is linked)\n", name
    else if (type == "U")
        print "#other " name
}' "$syms" >"$tmp/symcheck"
helpers=$(grep -v '^#other ' "$tmp/symcheck" || true)
if [ -n "$helpers" ]; then
    printf '%s\n' "$helpers"
    problems=$((problems + $(printf '%s\n' "$helpers" | grep -c .)))
fi
others=$(awk '$1 == "#other" {printf "%s ", $2}' "$tmp/symcheck")
if [ -n "$others" ]; then
    say "  note  other undefined symbols (must be resolved at link time): $others"
fi

if [ "$problems" -gt 0 ]; then
    if [ -n "$unaudited" ]; then
        printf '%s: note: the audit was also incomplete (%s)\n' "$prog" "${unaudited# }"
    fi
    printf '%s: FAIL: %d problem(s) in %s\n' "$prog" "$problems" "$file"
    exit 1
fi
if [ -n "$unaudited" ]; then
    printf '%s: NOT AUDITED: %s could not be fully checked (%s).  This is not a pass.\n' \
        "$prog" "$file" "${unaudited# }"
    exit 2
fi
printf '%s: PASS: %s uses only RV32I base instructions and no libgcc helpers\n' "$prog" "$file"
exit 0
