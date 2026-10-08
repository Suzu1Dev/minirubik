#!/bin/sh
# ripes-run.sh -- run one Ripes CLI simulation of an assembly source.
#
# Usage: scripts/ripes-run.sh [-p PROC] [-t TIMEOUT_MS] [-R VALUE] [-l LOG] [-H] [-k]
#                             <file.s> [state14]
#
#   -p PROC      Ripes processor model (default RV32_ISS; e.g. RV32_5S)
#   -t MS        Ripes --timeout in milliseconds (default 300000)
#   -R VALUE     value forced onto '.equ RENDER, ...' / render guards (default 0)
#   -l LOG       write the program's console output (and Ripes messages) to LOG
#                instead of stderr
#   -H           print the CSV header line first
#   -k           keep the temporary directory (path printed on stderr)
#   state14      14-digit state written into the '# @STATE' line; if omitted
#                the state already in the source is used
#
# The source is copied through scripts/ripes-prep.sh (state, RENDER, render
# guards), then run with: Ripes --mode cli -t asm --proc PROC --iret --cycles
# --json --output <tmp report> --timeout MS. No --isaexts is passed, so the
# Ripes assembler rejects non-RV32I *mnemonics* (e.g. mul). It does not check
# raw encodings: a '.word' in .text is executed (RV32_ISS even executes
# M-extension encodings) or retired as a no-op, never reported. Use
# scripts/rv32i-audit.sh for the RV32I check.
# Ripes runs with TMPDIR set to this run's private temporary directory (Ripes
# writes ripes_system.h there), so parallel runs share no files.
#
# Prints one CSV line on stdout:  state,proc,iret,cycles,status,exit_code
#   status    ok | timeout | asm_error | sim_error
#             (sim_error includes "stopped without an exit ecall")
#   exit_code value from Ripes' "Program exited with code: N" line, or none
# Environment: RIPES = path of the Ripes executable.
# Exit status: 0 if status=ok and exit_code=0, 1 for any other run outcome,
#              2 for usage/setup errors (no CSV line printed).

set -eu

prog=ripes-run.sh
die() { printf '%s: %s\n' "$prog" "$*" >&2; exit 2; }
usage() { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
RIPES=${RIPES:-"/Users/moneychan/Documents/成大/碩一/Computer-Arch-2026/hw1/.tools/Ripes-v2.2.6-106-g5b8a616-mac-universal2.app/Contents/MacOS/Ripes"}

proc=RV32_ISS
timeout_ms=300000
render=0
log=
header=0
keep=0
while getopts p:t:R:l:Hkh opt; do
    case $opt in
    p) proc=$OPTARG ;;
    t) timeout_ms=$OPTARG ;;
    R) render=$OPTARG ;;
    l) log=$OPTARG ;;
    H) header=1 ;;
    k) keep=1 ;;
    *) usage ;;
    esac
done
shift $((OPTIND - 1))
[ $# -ge 1 ] && [ $# -le 2 ] || usage
src=$1
state=${2:-}

case $proc in
'' | *[!A-Za-z0-9_]*) die "invalid processor name '$proc'" ;;
esac
# Validate whole strings with case patterns (a line-oriented grep would
# accept a value with an embedded newline).
case $timeout_ms in
'' | 0* | *[!0-9]*) die "-t expects a positive integer (ms), got '$timeout_ms'" ;;
esac
case $state in
'') ;;
*[!0-9]*) die "state must be exactly 14 digits, got '$state'" ;;
??????????????) ;;
*) die "state must be exactly 14 digits, got '$state'" ;;
esac
[ -f "$src" ] || die "no such source file: $src"
[ -x "$RIPES" ] || die "Ripes executable not found or not executable: $RIPES (set RIPES=...)"
if [ -n "$log" ]; then
    : > "$log" || die "cannot write log file: $log"
fi

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ripes-run.XXXXXX") || die "mktemp failed"
cleanup() {
    if [ "$keep" -eq 1 ]; then
        printf '%s: kept temporary files in %s\n' "$prog" "$tmp" >&2
    else
        rm -rf "$tmp"
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# 1. Preprocess (errors here are source-convention errors -> exit 2).
if [ -n "$state" ]; then
    eff_state=$(sh "$script_dir/ripes-prep.sh" -R "$render" -s "$state" "$src" "$tmp/prog.s") || exit 2
else
    eff_state=$(sh "$script_dir/ripes-prep.sh" -R "$render" "$src" "$tmp/prog.s") || exit 2
fi

# 2. Run Ripes. Console output and the assembly/timeout messages go to
#    stdout; the invalid --proc error goes to stderr; both are kept in the
#    console log. The report goes to its own file. Ripes prints each
#    print_string terminator (NUL byte) too, so NULs are stripped.
#    TMPDIR points at this run's own directory (Ripes writes ripes_system.h
#    into TMPDIR; this keeps parallel runs from sharing it).
rc=0
TMPDIR="$tmp" "$RIPES" --mode cli --src "$tmp/prog.s" -t asm --proc "$proc" \
    --iret --cycles --json --output "$tmp/report.json" \
    --timeout "$timeout_ms" > "$tmp/stdout.raw" 2> "$tmp/stderr.raw" || rc=$?
tr -d '\000' < "$tmp/stdout.raw" > "$tmp/console.txt"
cat "$tmp/stderr.raw" >> "$tmp/console.txt"

if grep -q 'ERROR: Invalid processor model' "$tmp/console.txt"; then
    grep 'ERROR: Invalid processor model' "$tmp/console.txt" >&2
    die "unknown processor model '$proc' (see: \"$RIPES\" --help)"
fi

# Append a runner note to the console log, starting on a fresh line.
note() {
    if [ -s "$tmp/console.txt" ] && [ "$(tail -c 1 "$tmp/console.txt" | od -An -c | tr -d ' ')" != '\n' ]; then
        echo >> "$tmp/console.txt"
    fi
    printf '%s: %s\n' "$prog" "$*" >> "$tmp/console.txt"
}

# 3. Classify.
iret=
cycles=
if [ -s "$tmp/report.json" ]; then
    iret=$(sed -n 's/^[[:space:]]*"# instructions retired":[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$tmp/report.json" | head -n 1)
    cycles=$(sed -n 's/^[[:space:]]*"cycles":[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$tmp/report.json" | head -n 1)
fi
exit_code=$(sed -n 's/.*Program exited with code: \(-\{0,1\}[0-9][0-9]*\).*/\1/p' "$tmp/console.txt" | tail -n 1)
[ -n "$exit_code" ] || exit_code=none

if grep -q 'ERROR: Simulation did not finish within the specified timeout' "$tmp/console.txt"; then
    status=timeout
    # Ripes' timer can fire after the program has already exited (seen with
    # --timeout below ~100 ms); no report is written then, so it stays a
    # timeout, but say so.
    if [ "$exit_code" != none ]; then
        note "the program printed its exit line before Ripes reported the timeout; no report was written (use a larger -t)"
    fi
elif grep -q 'ERROR: Error during assembly' "$tmp/console.txt"; then
    status=asm_error
elif [ "$rc" -ne 0 ] || [ -z "$iret" ]; then
    status=sim_error
elif [ "$exit_code" = none ]; then
    # Ripes stops silently on a jump to an unmapped PC, an unknown ecall, or
    # running off the end of .text. (An illegal instruction word does NOT
    # stop it: it is retired as a no-op and the run continues.)
    status=sim_error
    note "program stopped without an exit ecall (a7=10/93)"
else
    status=ok
fi
if [ "$status" != ok ] && [ "$rc" -ne 0 ]; then
    note "Ripes exit status $rc"
fi

# 4. Report.
if [ -n "$log" ]; then
    cat "$tmp/console.txt" >> "$log"
else
    cat "$tmp/console.txt" >&2
fi
[ "$header" -eq 1 ] && echo 'state,proc,iret,cycles,status,exit_code'
printf '%s,%s,%s,%s,%s,%s\n' "$eff_state" "$proc" "$iret" "$cycles" "$status" "$exit_code"

[ "$status" = ok ] && [ "$exit_code" = 0 ] && exit 0
exit 1
