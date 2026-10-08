#!/bin/sh
# crosscheck.sh - cross-check the host-side oracle (tools/oracle/oracle) and
# tests/dist11.txt against independent references.  Test tooling only; it
# runs the oracle and the unmodified upstream ./solver, nothing else.
#
# Usage:  sh tools/oracle/crosscheck.sh          (from any directory)
#         sh tools/oracle/crosscheck.sh -h       (print this usage)
#         make -C tools/oracle crosscheck
# Env:    SAMPLE_STRIDE  solve every Nth state of tests/dist11.txt with the
#                        upstream binary; an integer 1..2644 (leading zeros
#                        allowed; default 13 -> 204 of 2644 states)
#         SOLVER         upstream binary (default: <repo>/solver; build it
#                        with "make solver" in the repository root)
# Checks:
#   1. oracle hist == depth table in report.md ("Exact Distance
#      Distribution"), and == the face-turn-metric totals published by Jaap
#      Scherphuis, https://www.jaapsch.net/puzzles/cube2.htm (embedded below,
#      transcribed 2026-10-07).
#   2. each vector of tests/solutions.txt: oracle dist == number of moves in
#      the expected solution, and oracle verify confirms those moves solve it.
#   3. tests/dist11.txt: header + 2644 states, identical to "oracle list 11",
#      all at oracle distance 11, contains 21345671111111; every
#      SAMPLE_STRIDE-th state is solved by upstream ./solver in exactly 11
#      moves, and oracle verify confirms the printed moves solve it.
# Requires tools/oracle/oracle built from the current sources (a binary
# older than oracle.c, oracle.h, oracle_cli.c or ../../solver.c is refused).
# Prints one line per check and "crosscheck: ALL PASSED"; exits 1 on the
# first failure, 2 on bad usage (arguments, SAMPLE_STRIDE), before any check.
set -eu

JAAP_HTM="1 9 54 321 1847 9992 50136 227536 870072 1887748 623800 2644"
JAAP_TOTAL=3674160
SAMPLE=21345671111111

die() {
    printf 'crosscheck: FAIL: %s\n' "$*" >&2
    exit 1
}

usage() {
    echo "usage: [SAMPLE_STRIDE=N] [SOLVER=PATH] sh crosscheck.sh   (no arguments; N = 1..2644)"
}

bad_usage() {
    printf 'crosscheck: %s\n' "$*" >&2
    usage >&2
    exit 2
}

case $# in
0) ;;
1) case "$1" in -h | --help) usage; exit 0 ;; esac
   bad_usage "unexpected argument '$1'" ;;
*) bad_usage "expected no arguments, got $#" ;;
esac

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd) || die "cannot locate script"
root=$(CDPATH='' cd -- "$here/../.." && pwd) || die "cannot locate repository"
oracle="$here/oracle"
solver="${SOLVER:-$root/solver}"
stride="${SAMPLE_STRIDE:-13}"
report="$root/report.md"
vectors="$root/tests/solutions.txt"
dist11="$root/tests/dist11.txt"

# Digits only; strip leading zeros; then 1 <= stride <= 2644 (checked on the
# digit count first so huge values cannot overflow shell arithmetic).
case "$stride" in
'' | *[!0-9]*) bad_usage "SAMPLE_STRIDE must be an integer 1..2644, got '$stride'" ;;
esac
digits=$(printf '%s\n' "$stride" | sed 's/^0*//')
if [ -z "$digits" ] || [ ${#digits} -gt 4 ] || [ "$digits" -gt 2644 ]; then
    bad_usage "SAMPLE_STRIDE must be an integer 1..2644, got '$stride'"
fi
stride=$digits
[ -x "$oracle" ] || die "missing $oracle; build: make -C \"$here\""
# Refuse a binary older than its sources (POSIX find -newer).
stale=$(find "$here/oracle.c" "$here/oracle.h" "$here/oracle_cli.c" \
    "$root/solver.c" -newer "$oracle" -print) || die "cannot stat oracle sources"
[ -z "$stale" ] ||
    die "$oracle is older than $(printf '%s\n' "$stale" | paste -s -d ' ' -); rebuild: make -C \"$here\""
[ -x "$solver" ] || die "missing upstream $solver; build: (cd \"$root\" && make solver)"
for f in "$report" "$vectors" "$dist11"; do
    [ -r "$f" ] || die "cannot read $f"
done

work=$(mktemp -d "${TMPDIR:-/tmp}/oracle-crosscheck.XXXXXX") || die "mktemp failed"
trap 'rm -rf "$work"' 0
trap 'exit 1' 1 2 15

# 1. Histogram ---------------------------------------------------------------
"$oracle" hist >"$work/hist" || die "oracle hist failed"

awk '
    /^###* *Exact Distance Distribution/ { on = 1; next }
    on && /^#/ { on = 0 }
    on && /^\|/ {
        split($0, f, "|"); d = f[2]; c = f[3]
        gsub(/[ ,]/, "", d); gsub(/[ ,]/, "", c)
        if (d ~ /^[0-9]+$/ && c ~ /^[0-9]+$/) print d, c
        else if (d == "Total" && c ~ /^[0-9]+$/) print "total", c
    }' "$report" >"$work/report"
nrep=$(wc -l <"$work/report")
[ $((nrep + 0)) -eq 13 ] ||
    die "could not parse 12 depth rows + total from $report"
diff "$work/report" "$work/hist" >"$work/diff" ||
    { cat "$work/diff" >&2; die "oracle hist differs from report.md (< report, > oracle)"; }
echo "crosscheck: oracle hist == report.md depth table (12 depths + total)"

i=0
for c in $JAAP_HTM; do
    echo "$i $c"
    i=$((i + 1))
done >"$work/jaap"
echo "total $JAAP_TOTAL" >>"$work/jaap"
diff "$work/jaap" "$work/hist" >"$work/diff" ||
    { cat "$work/diff" >&2; die "oracle hist differs from Jaap's table (< Jaap, > oracle)"; }
echo "crosscheck: oracle hist == Jaap Scherphuis face-turn-metric table"

# 2. tests/solutions.txt ----------------------------------------------------
awk -F'|' '/^[ \t]*$/ || /^#/ { next }
    { print $1, split($2, w, " ") }' "$vectors" >"$work/vec_len"
awk -F'|' '/^[ \t]*$/ || /^#/ { next } { print $1 }' "$vectors" >"$work/vec_states"
"$oracle" dist - <"$work/vec_states" >"$work/vec_dist" ||
    die "oracle dist rejected a state in $vectors"
"$oracle" verify - <"$vectors" >"$work/vec_verify" ||
    { cat "$work/vec_verify" >&2; die "an expected solution in $vectors does not solve its state"; }
paste -d' ' "$work/vec_len" "$work/vec_dist" "$work/vec_verify" |
    awk -v out="$work/vec_n" '
    {   # fields: state words state dist state ok moves=N distance=D optimal=X
        if ($1 != $3 || $1 != $5 || $2 != $4 || $6 != "ok" ||
            $7 != "moves=" $2 || $9 != "optimal=yes") {
            print "crosscheck: mismatch: " $0 > "/dev/stderr"; bad = 1
        }
        n++
    }
    END { if (n == 0) bad = 1; print n > out; exit bad }' ||
    die "tests/solutions.txt length != oracle distance"
echo "crosscheck: $(cat "$work/vec_n") vectors in tests/solutions.txt: oracle dist == solution word count, and oracle verify solves each"

# 3. tests/dist11.txt -------------------------------------------------------
[ "$(grep -c '^#' "$dist11")" -eq 2 ] || die "$dist11 should have a 2-line '#' header"
grep -v '^#' "$dist11" >"$work/d11" || die "no states in $dist11"
n11=$(wc -l <"$work/d11")
[ $((n11 + 0)) -eq 2644 ] || die "$dist11 has $((n11 + 0)) states, expected 2644"
"$oracle" list 11 >"$work/list11" || die "oracle list 11 failed"
cmp -s "$work/d11" "$work/list11" || die "$dist11 is stale: differs from oracle list 11"
grep -qx "$SAMPLE" "$work/d11" || die "$SAMPLE missing from $dist11"
"$oracle" dist - <"$work/d11" >"$work/d11_dist" || die "oracle dist rejected a dist11 state"
awk '$2 != 11 { bad = 1 } END { exit bad || NR != 2644 }' "$work/d11_dist" ||
    die "a dist11 state is not at oracle distance 11"
echo "crosscheck: tests/dist11.txt: 2644 states == oracle list 11, all distance 11, contains $SAMPLE"

awk -v s="$stride" '(NR - 1) % s == 0' "$work/d11" >"$work/sample"
: >"$work/solved"
while IFS= read -r state; do
    moves=$("$solver" "$state") || die "upstream $solver failed on $state"
    words=$(printf '%s\n' "$moves" | awk '{ print NF }')
    [ "$words" -eq 11 ] || die "upstream solver gave $words moves for $state: $moves"
    printf '%s|%s\n' "$state" "$moves" >>"$work/solved"
done <"$work/sample"
ns=$(wc -l <"$work/solved")
"$oracle" verify - <"$work/solved" >"$work/solved_verify" ||
    { cat "$work/solved_verify" >&2; die "an upstream solution does not solve its state"; }
awk '$2 != "ok" || $3 != "moves=11" || $4 != "distance=11" { bad = 1 }
    END { exit bad }' "$work/solved_verify" ||
    die "unexpected verify result for an upstream solution"
echo "crosscheck: upstream $(basename -- "$solver") solved $((ns + 0)) sampled dist11 states (stride $stride) in exactly 11 moves each; oracle verify confirms every solution"

echo "crosscheck: ALL PASSED"
