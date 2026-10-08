#!/bin/sh
# ripes-prep.sh -- rewrite a Ripes assembly source for one CLI run.
#
# Usage: scripts/ripes-prep.sh [-R VALUE] [-s STATE14] <in.s> <out.s>
#
#   -R VALUE   value forced onto every '.equ RENDER, ...' line and used for
#              RENDER guards (default 0).
#   -s STATE   14-digit cube state written into the '# @STATE' line.
#
# Writes <out.s> (same number of lines as <in.s>) and prints the effective
# state (from -s, else the one found in the source, else '-') on stdout.
#
# Why this exists: the Ripes assembler (v2.2.6-106-g5b8a616) only knows
# .text .data .bss .string .asciz .zero .byte .half .short .2byte .word
# .4byte .long .dword .equ .align .global .globl -- there is NO .if/.else/
# .endif, so a source that uses them does not assemble in Ripes (CLI or GUI)
# until it has been through this script.
#
# Conventions handled (see scripts/README.md, "Ripes runners"):
#   * State line: a code line whose trailing comment contains @STATE and whose
#     code part holds exactly one quoted 14-digit string, e.g.
#         input_state: .string "21345671111111"   # @STATE
#     At most one such line may exist; -s requires exactly one.
#   * '.equ RENDER, <anything>' (any spacing) is rewritten to
#     '.equ RENDER, VALUE'. RENDER is also predefined as VALUE.
#   * Render guards, removed or kept according to VALUE:
#       - comment markers (assemble unchanged in the Ripes GUI):
#             # @RENDER-BEGIN
#             ... code kept only when VALUE != 0 ...
#             # @RENDER-END
#       - GNU-style '.if EXPR' / '.else' / '.endif', where EXPR is an integer
#         literal or a symbol given an integer by an earlier '.equ'.
#     Directive lines and inactive lines are turned into '#ripes-prep: ...'
#     comments, so line numbers are preserved. Nesting is allowed; other
#     conditional directives (.ifdef, .elseif, ...) are rejected.
#
# Exit status: 0 on success, 2 on usage or source-convention errors.

set -eu

prog=ripes-prep.sh
die() { printf '%s: %s\n' "$prog" "$*" >&2; exit 2; }
usage() { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

render=0
state=
while getopts R:s:h opt; do
    case $opt in
    R) render=$OPTARG ;;
    s) state=$OPTARG ;;
    *) usage ;;
    esac
done
shift $((OPTIND - 1))
[ $# -eq 2 ] || usage
in=$1
out=$2

# Validate whole strings with case patterns (a line-oriented grep would
# accept a value with an embedded newline).
case $render in
'' | - | *[!0-9-]* | ?*-*) die "-R expects an integer, got '$render'" ;;
esac
case $state in
'') ;;
*[!0-9]*) die "state must be exactly 14 digits, got '$state'" ;;
??????????????) ;;
*) die "state must be exactly 14 digits, got '$state'" ;;
esac
[ -f "$in" ] || die "no such source file: $in"
[ -r "$in" ] || die "cannot read source file: $in"

tmp_out="$out.tmp.$$"
trap 'rm -f "$tmp_out"' EXIT INT TERM

# LC_ALL=C: treat the source as bytes (comments may be UTF-8).
if ! LC_ALL=C awk -v RENDER="$render" -v STATE="$state" -v OUTF="$tmp_out" \
    -v SRC="$in" '
function err(msg) {
    printf "ripes-prep.sh: %s:%d: %s\n", SRC, NR, msg > "/dev/stderr"
    failed = 1
    exit 2
}
function errfile(msg) {
    printf "ripes-prep.sh: %s: %s\n", SRC, msg > "/dev/stderr"
    failed = 1
    exit 2
}
function hexval(s,    i, c, v) {
    v = 0
    s = tolower(s)
    for (i = 3; i <= length(s); i++) {
        c = index("0123456789abcdef", substr(s, i, 1)) - 1
        v = v * 16 + c
    }
    return v
}
function intval(s) {        # integer literal -> number; "" if not a literal
    if (s ~ /^-?[0-9]+$/) return s + 0
    if (s ~ /^0[xX][0-9a-fA-F]+$/) return hexval(s)
    if (s ~ /^-0[xX][0-9a-fA-F]+$/) return -hexval(substr(s, 2))
    return ""
}
function evalcond(e,    v) {
    gsub(/^[ \t]+|[ \t]+$/, "", e)
    v = intval(e)
    if (v != "") return v != 0
    if (e ~ /^[A-Za-z_.$][A-Za-z0-9_.$]*$/) {
        if (!(e in sym))
            err("\".if " e "\": no earlier \".equ " e ", <integer literal>\"")
        return sym[e] != 0
    }
    err("unsupported .if expression \"" e "\" (use an integer or one symbol)")
}
function active(    i) {
    for (i = 1; i <= depth; i++) if (!cond[i]) return 0
    return 1
}
function emit_off(line) { print "#ripes-prep: " line > OUTF }
BEGIN {
    depth = 0; nstate = 0; found_state = ""
    sym["RENDER"] = RENDER + 0
}
{
    line = $0
    sub(/\r$/, "", line)
    # Code part = text before the first "#"; comment-only lines have none.
    hpos = index(line, "#")
    code = hpos ? substr(line, 1, hpos - 1) : line
    comment = hpos ? substr(line, hpos) : ""
    is_comment_only = (code ~ /^[ \t]*$/)

    # ---- render guard comment markers ----
    if (is_comment_only && comment ~ /^#[ \t]*@RENDER-BEGIN([^A-Za-z0-9_-]|$)/) {
        depth++; cond[depth] = (RENDER + 0 != 0); kind[depth] = "marker"
        seen_else[depth] = 0; open_line[depth] = NR
        print $0 > OUTF; next
    }
    if (is_comment_only && comment ~ /^#[ \t]*@RENDER-END([^A-Za-z0-9_-]|$)/) {
        if (depth == 0 || kind[depth] != "marker")
            err("@RENDER-END without matching @RENDER-BEGIN")
        depth--
        print $0 > OUTF; next
    }

    # ---- conditional directives ----
    if (code ~ /^[ \t]*\.(if|ifdef|ifndef|ifeq|ifne|ifgt|ifge|iflt|ifle|ifc|ifnc|ifb|ifnb|elseif|else|endif)([ \t]|$)/) {
        d = code
        sub(/^[ \t]*/, "", d)
        name = d; sub(/[ \t].*$/, "", name)
        rest = substr(d, length(name) + 1)
        if (name == ".if") {
            # The condition is evaluated even inside an inactive block so a
            # typo is reported regardless of the RENDER value.
            c = evalcond(rest)
            depth++; cond[depth] = c; kind[depth] = "if"
            seen_else[depth] = 0; open_line[depth] = NR
        } else if (name == ".else") {
            if (depth == 0 || kind[depth] != "if") err(".else without .if")
            if (seen_else[depth]) err("second .else for the same .if")
            seen_else[depth] = 1; cond[depth] = !cond[depth]
        } else if (name == ".endif") {
            if (depth == 0 || kind[depth] != "if") err(".endif without .if")
            depth--
        } else {
            err("unsupported conditional directive " name " (only .if/.else/.endif)")
        }
        emit_off(line); next
    }

    if (!active()) { emit_off(line); next }

    # ---- .equ: force RENDER, remember integer symbols for .if ----
    if (code ~ /^[ \t]*\.equ[ \t]/) {
        e = code
        sub(/^[ \t]*\.equ[ \t]+/, "", e)
        n = index(e, ",")
        if (n) {
            nm = substr(e, 1, n - 1); gsub(/[ \t]/, "", nm)
            val = substr(e, n + 1); gsub(/^[ \t]+|[ \t]+$/, "", val)
            if (nm == "RENDER") {
                match(code, /^[ \t]*/)
                lead = substr(code, 1, RLENGTH)
                line = lead ".equ RENDER, " RENDER (comment != "" ? "   " comment : "")
                nrender++
            } else {
                v = intval(val)
                if (v != "") sym[nm] = v; else delete sym[nm]
            }
        }
    }

    # ---- @STATE line ----
    if (!is_comment_only && comment ~ /@STATE([^A-Za-z0-9_-]|$)/) {
        nstate++
        if (nstate > 1) err("more than one @STATE line (first was line " state_line ")")
        state_line = NR
        tmpc = code
        k = gsub(/"[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]"/, "&", tmpc)
        if (k != 1)
            err("@STATE line must hold exactly one quoted 14-digit string, found " k)
        match(code, /"[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]"/)
        found_state = substr(code, RSTART + 1, 14)
        if (STATE != "") {
            code = substr(code, 1, RSTART) STATE substr(code, RSTART + 15)
            line = code comment
        }
    }
    print line > OUTF
}
END {
    if (failed) exit 2
    if (depth > 0)
        errfile("unterminated " (kind[depth] == "if" ? ".if" : "@RENDER-BEGIN") \
            " opened at line " open_line[depth])
    if (STATE != "" && nstate == 0)
        errfile("a state was given but the source has no \"# @STATE\" line")
    close(OUTF)
    print (STATE != "" ? STATE : (found_state != "" ? found_state : "-"))
}
' "$in"; then
    exit 2
fi
mv "$tmp_out" "$out"
trap - EXIT INT TERM
