#!/bin/sh
# ripes-rate.sh -- report Ripes simulation speed for a program you supply.
#
# Usage: scripts/ripes-rate.sh [-p PROC] [-t TIMEOUT_MS] [-n REPEAT] [-H] <file.s>
#
#   -p PROC    Ripes processor model (default RV32_ISS)
#   -t MS      Ripes --timeout in milliseconds (default 300000)
#   -n N       run N times, one CSV line per run (default 1)
#   -H         print the CSV header line first
#
# Runs, unmodified (no @STATE/RENDER rewriting):
#   Ripes --mode cli --src <file.s> -t asm --proc PROC --iret --exectime
#         --json --output <tmp report> --timeout MS
# and prints on stdout:  proc,iret,exectime_ms,iret_per_s
# exectime_ms is Ripes' own "execution time (ms)": wall-clock time of the
# model run only (assembly and process start-up are not included).
# iret_per_s = iret * 1000 / exectime_ms (NA when exectime_ms is 0).
# The program's console output goes to stderr.
# A run counts as completed only if Ripes wrote a report AND the console shows
# "Program exited with code: N" (any N), i.e. the program reached an exit
# ecall (a7=10/93). Ripes also stops, with exit status 0 and a report, on an
# unknown ecall, a jump to an unmapped PC or running off the end of .text;
# such runs are reported as failures here, not as rates.
# Ripes runs with TMPDIR set to a private temporary directory.
# Environment: RIPES = path of the Ripes executable.
# Exit status: 0 if every run completed, 1 if a run failed, timed out or
#              stopped without an exit ecall, 2 for usage errors.

set -eu

prog=ripes-rate.sh
die() { printf '%s: %s\n' "$prog" "$*" >&2; exit 2; }
usage() { sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

RIPES=${RIPES:-"/Users/moneychan/Documents/成大/碩一/Computer-Arch-2026/hw1/.tools/Ripes-v2.2.6-106-g5b8a616-mac-universal2.app/Contents/MacOS/Ripes"}

proc=RV32_ISS
timeout_ms=300000
repeat=1
header=0
while getopts p:t:n:Hh opt; do
    case $opt in
    p) proc=$OPTARG ;;
    t) timeout_ms=$OPTARG ;;
    n) repeat=$OPTARG ;;
    H) header=1 ;;
    *) usage ;;
    esac
done
shift $((OPTIND - 1))
[ $# -eq 1 ] || usage
src=$1

case $proc in '' | *[!A-Za-z0-9_]*) die "invalid processor name '$proc'" ;; esac
# Whole-string checks (a line-oriented grep would accept embedded newlines).
case $timeout_ms in '' | 0* | *[!0-9]*) die "-t expects a positive integer (ms), got '$timeout_ms'" ;; esac
case $repeat in '' | 0* | *[!0-9]*) die "-n expects a positive integer, got '$repeat'" ;; esac
[ -f "$src" ] || die "no such source file: $src"
[ -x "$RIPES" ] || die "Ripes executable not found or not executable: $RIPES (set RIPES=...)"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ripes-rate.XXXXXX") || die "mktemp failed"
trap 'rm -rf "$tmp"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

[ "$header" -eq 1 ] && echo 'proc,iret,exectime_ms,iret_per_s'
failed=0
i=0
while [ "$i" -lt "$repeat" ]; do
    i=$((i + 1))
    rm -f "$tmp/report.json"
    rc=0
    TMPDIR="$tmp" "$RIPES" --mode cli --src "$src" -t asm --proc "$proc" --iret --exectime \
        --json --output "$tmp/report.json" --timeout "$timeout_ms" \
        > "$tmp/stdout.raw" 2>&1 || rc=$?
    tr -d '\000' < "$tmp/stdout.raw" > "$tmp/console.txt"
    cat "$tmp/console.txt" >&2
    # Keep the CSV line (stdout) from running into unterminated console text
    # when both go to a terminal.
    if [ -s "$tmp/console.txt" ] && [ "$(tail -c 1 "$tmp/console.txt" | od -An -c | tr -d ' ')" != '\n' ]; then
        echo >&2
    fi
    if grep -q 'ERROR: Invalid processor model' "$tmp/console.txt"; then
        die "unknown processor model '$proc'"
    fi
    iret=
    ms=
    if [ -s "$tmp/report.json" ]; then
        iret=$(sed -n 's/^[[:space:]]*"# instructions retired":[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$tmp/report.json" | head -n 1)
        ms=$(sed -n 's/^[[:space:]]*"execution time (ms)":[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$tmp/report.json" | head -n 1)
    fi
    if [ "$rc" -ne 0 ] || [ -z "$iret" ] || [ -z "$ms" ]; then
        printf '%s: run %s failed (Ripes exit status %s; see messages above)\n' "$prog" "$i" "$rc" >&2
        failed=1
        continue
    fi
    if ! grep -q 'Program exited with code: ' "$tmp/console.txt"; then
        printf '%s: run %s stopped without an exit ecall (a7=10/93) after %s instructions; no rate reported\n' \
            "$prog" "$i" "$iret" >&2
        failed=1
        continue
    fi
    rate=$(awk -v n="$iret" -v ms="$ms" 'BEGIN { if (ms > 0) printf "%.0f", n * 1000 / ms; else printf "NA" }')
    printf '%s,%s,%s,%s\n' "$proc" "$iret" "$ms" "$rate"
done
exit "$failed"
