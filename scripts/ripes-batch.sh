#!/bin/sh
# ripes-batch.sh -- run one assembly source on many cube states in Ripes CLI.
#
# Usage: scripts/ripes-batch.sh [-p PROC] [-j JOBS] [-t TIMEOUT_MS] [-R VALUE]
#                               [-o out.csv] [-L logdir] <file.s> <states.txt>
#
#   -p PROC    Ripes processor model (default RV32_ISS)
#   -j JOBS    parallel Ripes processes (default: CPU count - 2, at least 1)
#   -t MS      per-run Ripes --timeout in ms (default 300000)
#   -R VALUE   RENDER value passed to scripts/ripes-run.sh (default 0)
#   -o FILE    CSV output (default ./<file>-<PROC>-batch.csv; replaced only
#              when the batch has run, never by a batch that aborts early)
#   -L DIR     per-state console logs (default: <out without .csv>.logs/)
#
# states.txt: one state per line; '#' lines and blank lines are skipped. The
# first token (up to whitespace, ',' or '|') must be 14 digits, so
# tests/solutions.txt ("state|solution") can be used directly.
#
# Each state is run with scripts/ripes-run.sh. The CSV has the columns
#   state,proc,iret,cycles,status,exit_code,check
# check = pass  - console has a line whose first word is $PASS_TOKEN (PASS)
#                 and none whose first word is $FAIL_TOKEN (FAIL)
#         fail  - console has a $FAIL_TOKEN line
#         none  - neither token was printed
# A run counts as a failure when status != ok, check = fail, exit_code != 0,
# or check = none while REQUIRE_PASS=1 (default).
# Every failing run and every run with iret > IRET_LIMIT is also written,
# with its reasons and log path, to <out without .csv>.failures.csv
# (columns state,iret,status,check,exit_code,reason,log; header only when
# there are none). The summary on stdout lists the first 20.
#
# Environment: RIPES (Ripes executable), PASS_TOKEN, FAIL_TOKEN,
#              REQUIRE_PASS (1|0), IRET_LIMIT (default 50000000).
# Exit status: 0 if no failures and no run has iret > IRET_LIMIT, 1 otherwise,
#              2 for usage/setup errors.

set -eu

prog=ripes-batch.sh
die() { printf '%s: %s\n' "$prog" "$*" >&2; exit 2; }
usage() { sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SELF="$script_dir/$(basename -- "$0")"
RUN="$script_dir/ripes-run.sh"

# ---------------------------------------------------------------- worker mode
# Invoked by xargs as: ripes-batch.sh __worker <idx>:<state>
if [ "${1:-}" = __worker ]; then
    tok=$2
    idx=${tok%%:*}
    st=${tok#*:}
    res="$B_WORK/res/$idx.csv"
    logf="$B_LOGDIR/$idx-$st.log"
    line=$(sh "$RUN" -p "$B_PROC" -t "$B_TIMEOUT" -R "$B_RENDER" -l "$logf" \
        "$B_SRC" "$st" 2>> "$logf") || true
    case $line in
    *,*,*,*,*,*) ;;
    *) line="$st,$B_PROC,,,runner_error,none" ;;
    esac
    check=$(LC_ALL=C tr -d '\000\r' < "$logf" | awk -v P="$PASS_TOKEN" -v F="$FAIL_TOKEN" '
        $1 == F { f = 1 } $1 == P { p = 1 }
        END { print (f ? "fail" : (p ? "pass" : "none")) }')
    printf '%s,%s\n' "$line" "$check" > "$res.tmp"
    mv "$res.tmp" "$res"
    # Progress "[k/n]": serialise the counter with a mkdir lock so that each
    # finished run gets its own k. If the lock cannot be taken within ~30 s
    # (should not happen), print without it rather than stall the batch.
    got=0
    tries=0
    while [ "$tries" -lt 600 ]; do
        if mkdir "$B_WORK/lock" 2>/dev/null; then got=1; break; fi
        tries=$((tries + 1))
        sleep 0.05 2>/dev/null || sleep 1
    done
    ndone=$(cat "$B_WORK/ndone" 2>/dev/null || echo 0)
    case $ndone in '' | *[!0-9]*) ndone=0 ;; esac
    ndone=$((ndone + 1))
    echo "$ndone" > "$B_WORK/ndone"
    printf '[%s/%s] %s,%s\n' "$ndone" "$B_N" "$line" "$check" >&2
    [ "$got" -eq 0 ] || rmdir "$B_WORK/lock"
    exit 0
fi

# ----------------------------------------------------------------- main mode
ncpu() {
    n=$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1)
    case $n in '' | *[!0-9]*) n=1 ;; esac
    echo "$n"
}

proc=RV32_ISS
jobs=
timeout_ms=300000
t_given=0
render=0
out=
logdir=
while getopts p:j:t:R:o:L:h opt; do
    case $opt in
    p) proc=$OPTARG ;;
    j) jobs=$OPTARG ;;
    t) timeout_ms=$OPTARG; t_given=1 ;;
    R) render=$OPTARG ;;
    o) out=$OPTARG ;;
    L) logdir=$OPTARG ;;
    *) usage ;;
    esac
done
shift $((OPTIND - 1))
[ $# -eq 2 ] || usage
src=$1
states=$2

PASS_TOKEN=${PASS_TOKEN:-PASS}
FAIL_TOKEN=${FAIL_TOKEN:-FAIL}
REQUIRE_PASS=${REQUIRE_PASS:-1}
IRET_LIMIT=${IRET_LIMIT:-50000000}
RIPES=${RIPES:-"/Users/moneychan/Documents/成大/碩一/Computer-Arch-2026/hw1/.tools/Ripes-v2.2.6-106-g5b8a616-mac-universal2.app/Contents/MacOS/Ripes"}
export RIPES

[ -f "$src" ] || die "no such source file: $src"
[ -f "$states" ] || die "no such states file: $states"
[ -f "$RUN" ] || die "missing helper: $RUN"
[ -f "$SELF" ] || die "cannot locate this script: $SELF"
[ -x "$RIPES" ] || die "Ripes executable not found or not executable: $RIPES (set RIPES=...)"
if [ -z "$jobs" ]; then
    jobs=$(( $(ncpu) - 2 ))
    [ "$jobs" -ge 1 ] || jobs=1
fi
# Whole-string checks (a line-oriented grep would accept embedded newlines).
case $jobs in '' | 0* | *[!0-9]*) die "-j expects a positive integer, got '$jobs'" ;; esac
case $timeout_ms in '' | 0* | *[!0-9]*) die "-t expects a positive integer (ms), got '$timeout_ms'" ;; esac
case $IRET_LIMIT in '' | *[!0-9]*) die "IRET_LIMIT must be a non-negative integer, got '$IRET_LIMIT'" ;; esac
case $REQUIRE_PASS in 0 | 1) ;; *) die "REQUIRE_PASS must be 0 or 1" ;; esac
case $PASS_TOKEN$FAIL_TOKEN in *[[:space:]]*) die "PASS_TOKEN/FAIL_TOKEN must be single words" ;; esac
[ -n "$PASS_TOKEN" ] && [ -n "$FAIL_TOKEN" ] || die "PASS_TOKEN/FAIL_TOKEN must not be empty"

if [ -z "$out" ]; then
    base=$(basename -- "$src")
    out="./${base%.*}-$proc-batch.csv"
fi
if [ -z "$logdir" ]; then
    logdir="${out%.csv}.logs"
fi
fails="${out%.csv}.failures.csv"
# Check that the outputs can be written, without touching existing files:
# the CSV and the failures list are only replaced after the batch has run.
outdir=$(dirname -- "$out")
mkdir -p "$outdir" || die "cannot create the CSV directory: $outdir"
[ -w "$outdir" ] || die "cannot write to the CSV directory: $outdir"
for f in "$out" "$fails"; do
    [ ! -d "$f" ] || die "output path is a directory: $f"
    [ ! -e "$f" ] || [ -w "$f" ] || die "cannot overwrite: $f"
done

work=$(mktemp -d "${TMPDIR:-/tmp}/ripes-batch.XXXXXX") || die "mktemp failed"
trap 'rm -rf "$work"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir "$work/res"

# Parse the states file: "<idx>:<state>" tokens, idx = running number.
if ! LC_ALL=C awk '
    { sub(/\r$/, "") }
    /^[ \t]*(#|$)/ { next }
    {
        s = $0; sub(/^[ \t]+/, "", s); sub(/[ \t,|].*$/, "", s)
        if (s !~ /^[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]$/) {
            printf "ripes-batch.sh: %s:%d: not a 14-digit state: %s\n", FILENAME, NR, $0 > "/dev/stderr"
            bad = 1; next
        }
        printf "%06d:%s\n", ++n, s
    }
    END { exit bad ? 1 : 0 }' "$states" > "$work/tokens"; then
    die "fix the states file first"
fi
n=$(wc -l < "$work/tokens" | tr -d ' ')
[ "$n" -gt 0 ] || die "no states found in $states"

# Pre-flight 1: processor name and Ripes itself, on a 2-instruction program.
printf '.text\n    li a7, 10\n    ecall\n' > "$work/preflight.s"
if ! sh "$RUN" -p "$proc" -t 10000 "$work/preflight.s" > "$work/preflight.csv" 2> "$work/preflight.log"; then
    cat "$work/preflight.log" "$work/preflight.csv" >&2
    die "pre-flight run failed (processor '$proc', RIPES=$RIPES)"
fi
# Pre-flight 2: the source assembles (1 ms timeout: assemble, barely run).
first=$(head -n 1 "$work/tokens"); first=${first#*:}
pf_rc=0
sh "$RUN" -p "$proc" -t 1 -R "$render" "$src" "$first" > "$work/pf2.csv" 2> "$work/pf2.log" || pf_rc=$?
if [ "$pf_rc" -eq 2 ] || grep -q ',asm_error,' "$work/pf2.csv"; then
    cat "$work/pf2.log" >&2
    die "source does not prepare/assemble; nothing was run"
fi

mkdir -p "$logdir" || die "cannot create the log directory: $logdir"
: > "$work/ndone"

printf '%s: %s states, proc %s, %s jobs, timeout %s ms\n' "$prog" "$n" "$proc" "$jobs" "$timeout_ms" >&2
printf '%s: csv %s, logs %s/\n' "$prog" "$out" "$logdir" >&2
if [ "$t_given" -eq 0 ] && [ "$proc" != RV32_ISS ]; then
    printf '%s: note: %s simulates far slower than RV32_ISS; the default -t %s may be\n' "$prog" "$proc" "$timeout_ms" >&2
    printf '%s:       too short for long runs (see scripts/README.md, "Timeouts"); pass -t explicitly\n' "$prog" >&2
fi

B_WORK=$work B_LOGDIR=$logdir B_PROC=$proc B_TIMEOUT=$timeout_ms \
B_RENDER=$render B_SRC=$src B_N=$n RIPES=$RIPES \
PASS_TOKEN=$PASS_TOKEN FAIL_TOKEN=$FAIL_TOKEN
export B_WORK B_LOGDIR B_PROC B_TIMEOUT B_RENDER B_SRC B_N RIPES PASS_TOKEN FAIL_TOKEN

xrc=0
xargs -n 1 -P "$jobs" sh "$SELF" __worker < "$work/tokens" || xrc=$?
[ "$xrc" -eq 0 ] || printf '%s: warning: xargs exit status %s\n' "$prog" "$xrc" >&2

# Assemble the CSV in input order (in the work dir, then move into place).
echo 'state,proc,iret,cycles,status,exit_code,check' > "$work/out.csv"
while IFS= read -r tok; do
    idx=${tok%%:*}
    st=${tok#*:}
    if [ -f "$work/res/$idx.csv" ]; then
        cat "$work/res/$idx.csv" >> "$work/out.csv"
    else
        echo "$st,$proc,,,runner_error,none,none" >> "$work/out.csv"
    fi
done < "$work/tokens"
mv -f "$work/out.csv" "$out" || die "cannot write CSV: $out"
echo 'state,iret,status,check,exit_code,reason,log' > "$fails" \
    || die "cannot write the failures list: $fails"

# Summary.
sum_rc=0
awk -F, -v LIMIT="$IRET_LIMIT" -v REQ="$REQUIRE_PASS" -v OUT="$out" \
    -v LOGDIR="$logdir" -v SRC="$src" -v PROC="$proc" -v STATES="$states" \
    -v PT="$PASS_TOKEN" -v FT="$FAIL_TOKEN" -v FAILF="$fails" '
NR == 1 { next }
{
    n++
    st[$5]++
    chk[$7]++
    if ($6 != "0") nonzero++
    bad = ($5 != "ok") || ($7 == "fail") || ($6 != "0") || (REQ == 1 && $7 != "pass")
    logp = sprintf("%s/%06d-%s.log", LOGDIR, n, $1)
    if (bad) {
        nf++
        if (nf <= 20)
            flist = flist sprintf("    %s status=%s check=%s exit_code=%s log=%s\n", $1, $5, $7, $6, logp)
    }
    isover = 0
    if ($5 == "ok" && $3 ~ /^[0-9]+$/) {
        v = $3 + 0
        if (!bad) {             # min/mean/max only over runs that passed
            k++; tot += v
            if (k == 1 || v < mn) mn = v
            if (k == 1 || v > mx) { mx = v; arg = $1 }
        }
        if (v > LIMIT) {        # limit check over every run that finished
            over++; isover = 1
            if (over <= 20) olist = olist sprintf("    %s iret=%s\n", $1, $3)
        }
    }
    if (bad || isover) {        # full list, one row per problem run
        r = ""
        if ($5 != "ok") r = r ";status=" $5
        if ($7 == "fail") r = r ";" FT
        else if (REQ == 1 && $7 != "pass") r = r ";no_" PT
        if ($6 != "0") r = r ";exit_code=" $6
        if (isover) r = r ";iret>" LIMIT
        print $1 "," $3 "," $5 "," $7 "," $6 "," substr(r, 2) "," logp >> FAILF
        nlist++
    }
}
END {
    printf "ripes-batch summary: %s on %s, states from %s\n", SRC, PROC, STATES
    printf "  runs              : %d\n", n
    printf "  status            : ok=%d timeout=%d asm_error=%d sim_error=%d runner_error=%d\n", \
        st["ok"], st["timeout"], st["asm_error"], st["sim_error"], st["runner_error"]
    printf "  console check     : pass=%d fail=%d none=%d   (tokens %s/%s)\n", \
        chk["pass"], chk["fail"], chk["none"], PT, FT
    printf "  exit_code != 0    : %d   (includes none = no exit ecall reached)\n", nonzero
    printf "  failures          : %d   (status!=ok, %s line, exit_code!=0%s)\n", \
        nf, FT, (REQ == 1 ? ", or no " PT " line" : "")
    printf "%s", flist
    if (nf > 20) printf "    ... %d more, see %s\n", nf - 20, FAILF
    if (k > 0)
        printf "  iret (passed runs): n=%d min=%d mean=%.1f max=%d\n  argmax state      : %s\n", \
            k, mn, tot / k, mx, arg
    else
        printf "  iret (passed runs): none passed\n"
    printf "  iret > IRET_LIMIT : %d   (IRET_LIMIT=%d; any run with status=ok)\n", over, LIMIT
    printf "%s", olist
    if (over > 20) printf "    ... %d more, see %s\n", over - 20, FAILF
    close(FAILF)
    printf "  csv               : %s\n  logs              : %s/\n", OUT, LOGDIR
    printf "  failures list     : %s   (%d rows: every failure and every run over the limit)\n", FAILF, nlist
    exit (nf > 0 || over > 0) ? 1 : 0
}' "$out" || sum_rc=$?
exit "$sum_rc"
