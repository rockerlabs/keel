#!/usr/bin/env bash
# test_env_census.sh — the environment gate (dir #663 (a)). A shipped script that reads a KEEL_* variable
# from the caller's environment reads the OPERATOR's value when a test runs it, unless tests/lib.sh
# neutralizes it first. Felt once (0.13.0 delta audit S2-1): the suite ran an operator-exported
# KEEL_MACHINE_WATCH_NOTIFIER on test data and 13 assertions went red. The fix there was one `unset`; this
# file closes the class, so the next variable cannot be added to a tool and forgotten here.
#
# Two halves, because neither alone binds:
#   static  — derive, from the shipped scripts, every KEEL_* name read from the environment (below);
#   runtime — export each such name with a poison value, source tests/lib.sh in a child, and assert none
#             still holds the poison (unset, or redirected into the sandbox, both pass). A textual
#             mention in lib.sh would satisfy a grep (a comment does); only the child proves the effect.
#
# The same two halves bind the NON-KEEL_ names a tool reads (dir #704: AGY_BIN / AGY_MODEL / AGY_PRINT_TIMEOUT,
# SECRET_SCAN_*, GITHUB_*, DRYDOCK_*, …). A bare `$NAME` read of an UPPER_CASE name cannot be told from a
# script-internal variable (measured over today's tools: dozens of bare names, nearly all script-internal, awk or lib-owned),
# so the static half derives only the SIGNALS of an intended environment read:
#   - a default-expansion read `${NAME:-d}` / `${NAME-d}` / `${NAME:=d}` / `${NAME:?m}` / `${NAME:+w}` — a
#     script under `set -u` cannot read a possibly-unset variable any other way — or `ENVIRON["NAME"]`, or
#     `printenv NAME`;
#   - a bare or braced read of a CREDENTIAL-shaped name (`*_API_KEY`, `*_TOKEN`, `*_SECRET`, `*_PASSWORD`).
# A self-default assignment (`AGY_BIN="${AGY_BIN:-d}"`) is a READ, not ownership. An explicit, tested register
# (AMBIENT_EXEMPT, below) holds the names the suite cannot neutralize (PATH, TMPDIR), each with its reason.
#
# Axis, named: this binds the names a script spells out literally. It does not see a name built at run
# time (`"KEEL_${x}"`), a variable read only by a tests/ helper (KEEL_TEST_JOBS, a *_SKIP_MUTATIONS
# switch — those are the suite's own knobs, not tool reads), a non-KEEL_ name read bare under a name that is
# not credential-shaped and never default-expanded (`$FOO_BIN`, `[ -n "$FOO_BIN" ]`, `${FOO_BIN%/}`,
# `${FOO_BIN:0:3}`), or an indirect read (`${!v}`).
# Ownership is a line-level approximation: the value word of an assignment is scanned for a read-back of the same
# name, tracking quotes and `$( … )` depth, but not backslash-escaped quotes, backtick substitutions or `$(( … ))`
# arithmetic (`X=$((X+1))`) — a self-read in one of those rare shapes is taken as ownership and slips through.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

echo "test-suite environment gate (dir #663 (a))"

# owns_name NAME — reads code on stdin; exit 0 when some line ASSIGNS NAME (`NAME=` at a word start, not
# inside a quoted string: an even count of double and of single quotes before it — so `echo "… (KEEL_DIR=~/x)"`
# is prose, while `( cd "$d" && KEEL_X=1 ./run )` is an assignment) WITHOUT reading it back on the same line:
# `X="${X:-d}"` takes the caller's value, so it is a read (dir #704: AGY_BIN). \047 is the single quote,
# spelled so the awk program can stay inside this shell's own single quotes.
owns_name() {
  awk -v n="$1" '
    {
      s = $0; off = 0
      while ((i = index(s, n "=")) > 0) {
        pos = off + i
        ok = 1
        if (pos > 1 && substr($0, pos - 1, 1) ~ /[A-Za-z0-9_]/) ok = 0
        pre = substr($0, 1, pos - 1)
        dq = gsub(/"/, "&", pre); sq = gsub(/\047/, "&", pre)
        # the value word of the assignment: up to the first unquoted space, semicolon, ampersand, pipe or
        # closing paren at depth 0 (a $( … ) substitution is part of the value, spaces and all)
        rest = substr($0, pos + length(n) + 1); val = ""; qd = 0; qs = 0; depth = 0
        for (k = 1; k <= length(rest); k++) {
          c = substr(rest, k, 1)
          if (c == "\"" && !qs) qd = !qd
          else if (c == "\047" && !qd) qs = !qs
          else if (!qd && !qs && c == "(") depth++
          else if (!qd && !qs && c == ")") { if (depth == 0) break; depth-- }
          else if (!qd && !qs && depth == 0 && c ~ /[ \t;&|]/) break
          val = val c
        }
        # self-default: the value reads the SAME name (not a longer one sharing the prefix) -> a read
        for (m = 1; (j = index(substr(val, m), n)) > 0; m += j) {
          b = m + j - 1
          pc = (b > 1) ? substr(val, b - 1, 1) : ""
          nc = substr(val, b + length(n), 1)
          if ((pc == "$" || (pc == "{" && substr(val, b - 2, 1) == "$")) && nc !~ /[A-Za-z0-9_]/) { ok = 0; break }
        }
        if (ok && dq % 2 == 0 && sq % 2 == 0) { found = 1; exit }
        off = pos + length(n); s = substr($0, off + 1)
      }
    }
    END { exit found ? 0 : 1 }'
}

# census_files ROOT... — every regular file under the given files/dirs, sorted per root.
census_files() {
  local root
  for root in "$@"; do
    if [ -d "$root" ]; then
      find "$root" -type f | LC_ALL=C sort
    elif [ -f "$root" ]; then
      printf '%s\n' "$root"
    fi
  done
}
# inherited_reads ROOT... — the KEEL_* names the shipped scripts under the given files/dirs read from the
# environment, one per line, sorted. A READ is `$KEEL_X`, `${KEEL_X…}` or `ENVIRON["KEEL_X"]` on a
# non-comment line. A file that also ASSIGNS the name (`KEEL_X=…` at a word start — a script-owned
# variable, or an inline `KEEL_X=… awk` hand-off) is not reading the caller's value; the verdict is per
# file, so a read in one file is not excused by an assignment in another.
inherited_reads() {
  local root f name
  local -a files=()
  while IFS= read -r f; do files+=("$f"); done < <(census_files "$@")
  for f in ${files[@]+"${files[@]}"}; do
    # non-comment lines only, so a name that appears in prose alone is not a read
    local code; code="$(grep -avE '^[[:space:]]*#' "$f" 2>/dev/null)"
    [ -n "$code" ] || continue
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      # a here-string, not a pipe: owns_name exits at its first match, and a producer killed by SIGPIPE
      # flips the pipeline's status under pipefail — an owned name would fall through as an inherited read
      owns_name "$name" <<<"$code" && continue
      printf '%s\n' "$name"
    done < <(printf '%s\n' "$code" \
      | grep -aoE '(\$\{?|ENVIRON\["|printenv +)KEEL_[A-Z0-9_]+' | grep -aoE 'KEEL_[A-Z0-9_]+' | LC_ALL=C sort -u)
  done | LC_ALL=C sort -u
}

# inherited_other_reads ROOT... — the non-KEEL_ names (dir #704) the shipped scripts read from the environment,
# one per line, sorted: the signals an intended read leaves (see the header) on non-comment lines, minus any
# name the same file ASSIGNS without reading it back (owns_name — the verdict is per file, as above).
inherited_other_reads() {
  local f name code
  while IFS= read -r f; do
    code="$(grep -avE '^[[:space:]]*#' "$f" 2>/dev/null)"
    [ -n "$code" ] || continue
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      owns_name "$name" <<<"$code" && continue
      printf '%s\n' "$name"
    done < <({
      printf '%s\n' "$code" \
        | grep -aoE '(\$\{[A-Z][A-Z0-9_]*:?[-=?+]|ENVIRON\["[A-Z][A-Z0-9_]*|printenv +[A-Z][A-Z0-9_]*)' \
        | sed -E 's/^\$\{//; s/:?[-=?+]$//; s/^ENVIRON\["//; s/^printenv +//'
      printf '%s\n' "$code" \
        | grep -aoE '\$\{?[A-Z][A-Z0-9_]*' | sed -E 's/^\$\{?//' | grep -aE '_(API_KEY|TOKEN|SECRET|PASSWORD)$'
    } | grep -avE '^KEEL_' | LC_ALL=C sort -u)
  done < <(census_files "$@") | LC_ALL=C sort -u
}

# --- non-vacuity of the static half: it flags what it should, and only that, on a planted tree --------------
plant="$(mktemp -d "$SANDBOX/plant.XXXXXX")"
{
  printf '%s\n' 'x="${KEEL_PLANT_BRACE:-d}"'
  printf '%s\n' 'echo "$KEEL_PLANT_BARE"'
  printf '%s\n' "awk '{print ENVIRON[\"KEEL_PLANT_ENV\"]}'"
  printf '%s\n' '# comment: ${KEEL_PLANT_COMMENT} only here'
  printf '%s\n' 'KEEL_PLANT_OWN=1; echo "$KEEL_PLANT_OWN"'
  printf '%s\n' "KEEL_PLANT_HAND=\"\$v\" awk '{print ENVIRON[\"KEEL_PLANT_HAND\"]}'"
  printf '%s\n' 'echo "$KEEL_PLANT_SPLIT"'
  printf '%s\n' 'echo "hint (KEEL_PLANT_PROSE=x)"; echo "$KEEL_PLANT_PROSE"'
  printf '%s\n' '( cd "$d" && KEEL_PLANT_SUBSHELL=1 ./run ); echo "$KEEL_PLANT_SUBSHELL"'
  printf '%s\n' 'KEEL_PLANT_SELF="${KEEL_PLANT_SELF:-d}"'
  printf '%s\n' 'KEEL_PLANT_PREFIX=$KEEL_PLANT_PREFIX_DIR/x; echo "$KEEL_PLANT_PREFIX"'
  printf '%s\n' 'KEEL_PLANT_SUBST=$(printf %s "${KEEL_PLANT_SUBST:-d}")'
} > "$plant/a.sh"
printf '%s\n' 'KEEL_PLANT_SPLIT=assigned-in-the-OTHER-file' > "$plant/b.sh"
planted="$(inherited_reads "$plant")"
check_contains "a \${…} read is flagged" "$planted" 'KEEL_PLANT_BRACE'
check_contains "a bare \$ read is flagged" "$planted" 'KEEL_PLANT_BARE'
check_contains "an ENVIRON read with no assignment is flagged" "$planted" 'KEEL_PLANT_ENV'
check_absent "a name in a comment only is not flagged" "$planted" 'KEEL_PLANT_COMMENT'
check_absent "a script-owned variable is not flagged" "$planted" 'KEEL_PLANT_OWN'
check_absent "an inline hand-off (VAR=… awk … ENVIRON) is not flagged" "$planted" 'KEEL_PLANT_HAND'
check_contains "an assignment in ANOTHER file does not excuse a read (the verdict is per file)" "$planted" 'KEEL_PLANT_SPLIT'
check_contains "an assignment spelled inside a quoted message is prose, not ownership" "$planted" 'KEEL_PLANT_PROSE'
check_absent "an assignment after a quoted word in a subshell still counts as ownership" "$planted" 'KEEL_PLANT_SUBSHELL'
check_contains "a self-default assignment (X=\"\${X:-d}\") is a read, not ownership (dir #704)" "$planted" 'KEEL_PLANT_SELF'
check_contains "a self-default inside a \$( … ) substitution (spaces and all) is a read" "$planted" 'KEEL_PLANT_SUBST'
check_contains "the longer name on the right-hand side is itself a read" "$planted" 'KEEL_PLANT_PREFIX_DIR'
check_eq "a longer name sharing the prefix is not a self-read: the assignment still owns the name" 0 "$(printf '%s\n' "$planted" | grep -cx 'KEEL_PLANT_PREFIX')"
check_eq "exactly the eight reads are reported" 8 "$(printf '%s\n' "$planted" | grep -c .)"
check_eq "an empty root reports nothing, not an error" "" "$(inherited_reads "$SANDBOX/no-such-root")"

# --- the runtime half -----------------------------------------------------------------------------------------
POISON='/keel-env-census-poison'

# unneutralized LIB NAME... — the names still holding POISON after a child sources LIB with every one of
# them exported poisoned. Prints one per line; prints FATAL and returns 99 when LIB cannot be sourced.
unneutralized() {
  local lib="$1" n out rc; shift
  local -a envargs=()
  for n in "$@"; do envargs+=("$n=$POISON"); done
  out="$(env ${envargs[@]+"${envargs[@]}"} bash -c '
    . "$1" || exit 99
    shift
    for v in "$@"; do
      [ "${!v-__unset__}" = "'"$POISON"'" ] && printf "%s\n" "$v"
    done
    exit 0' _ "$lib" "$@" 2>&1)"
  rc=$?
  printf '%s' "$out"
  return "$rc"
}

# non-vacuity of the runtime half: a lib that neutralizes nothing, then one that neutralizes one name
nolib="$(mktemp -d "$SANDBOX/nolib.XXXXXX")"
printf '%s\n' 'SANDBOX="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; unset KEEL_PLANT_BRACE' > "$nolib/lib.sh"
res="$(unneutralized "$nolib/lib.sh" KEEL_PLANT_BRACE KEEL_PLANT_BARE)"
check_eq "a lib that unsets only one name leaves exactly the other one poisoned" "KEEL_PLANT_BARE" "$res"
printf '%s\n' 'export KEEL_PLANT_BARE=/somewhere/else' >> "$nolib/lib.sh"
check_eq "a lib that exports a different value counts as neutralized" "" "$(unneutralized "$nolib/lib.sh" KEEL_PLANT_BRACE KEEL_PLANT_BARE)"
printf '%s\n' 'return 7' > "$nolib/broken.sh"
unneutralized "$nolib/broken.sh" KEEL_PLANT_BRACE >/dev/null; rc=$?
check_ne "a lib that fails to source is a hard failure, not a clean 'nothing poisoned'" "$rc" 0

# --- the real tree --------------------------------------------------------------------------------------------
census_roots=("$REPO_ROOT/tools" "$REPO_ROOT/install.sh" "$REPO_ROOT/uninstall.sh" "$REPO_ROOT/bootstrap.sh" "$REPO_ROOT/keel")
names="$(inherited_reads "${census_roots[@]}")"
count="$(printf '%s\n' "$names" | grep -c .)"
# anchors: names tests/lib.sh handled BEFORE this gate existed — a scanner that cannot see them is blind
for anchor in KEEL_HOME KEEL_IMPACT_LOG KEEL_MACHINE_WATCH_NOTIFIER KEEL_LEDGER_FILE; do
  check_contains "the scan sees $anchor (so it is not vacuous on the real tree)" "$names" "$anchor"
done
check_ne "the scan found KEEL_* reads at all" "$count" 0

# shellcheck disable=SC2086  # word-splitting the newline-separated names is the point
leaked="$(unneutralized "$TESTS_DIR/lib.sh" $names)"; rc=$?
check_eq "sourcing lib.sh succeeds in the poisoned child" 0 "$rc"
if [ -z "$leaked" ]; then
  pass "every KEEL_* a shipped script reads from the environment is neutralized by tests/lib.sh ($count names)"
else
  fail "every KEEL_* a shipped script reads from the environment is neutralized by tests/lib.sh ($count names)" \
    "tests/lib.sh leaves an operator's value of these reaching the suite — add each to its unset block, or give it a sandbox default:
$leaked"
fi

# --- mutation proof: drop ONE name from a scratch copy of lib.sh and the gate must name exactly it ------------
SCRATCH_COPY_PREFIX=envcensus
victim=KEEL_CHECK_VETO
check_contains "the mutation victim ($victim) is one of the derived names" "$names" "$victim"
mut_lib="$(scratch_copy "$TESTS_DIR/lib.sh" lib.sh)"
delete_line_containing "$mut_lib" "$victim"
check_ne "the edit changed the copy of lib.sh" "$(cksum < "$mut_lib")" "$(cksum < "$TESTS_DIR/lib.sh")"
# shellcheck disable=SC2086
res="$(unneutralized "$mut_lib" $names)"
check_eq "lib.sh minus its $victim line: the gate reports $victim, and only it" "$victim" "$res"

# ==== the non-KEEL_ half (dir #704) =================================================================================
echo "test-suite environment gate, non-KEEL_ names (dir #704)"

# Names the suite cannot neutralize, each with the reason. Everything else a tool reads from the environment
# under a non-KEEL_ name must come out of tests/lib.sh unset, or redirected into the sandbox (HOME,
# GIT_CONFIG_GLOBAL). A name that no tool reads any more is a stale entry and fails below.
#   PATH    every fixture and the child's own commands resolve through the operator's PATH
#   TMPDIR  the temp root `mktemp` and the tools' scratch files fall under; lib.sh cannot repoint it
AMBIENT_EXEMPT="PATH TMPDIR"

# --- non-vacuity of the static half on a planted tree ---------------------------------------------------------
oplant="$(mktemp -d "$SANDBOX/oplant.XXXXXX")"
{
  printf '%s\n' 'x="${PLANT_DFLT:-d}"'
  printf '%s\n' ': "${PLANT_ASSIGN_DFLT:=d}"'
  printf '%s\n' 'PLANT_SELF="${PLANT_SELF:-d}"'
  printf '%s\n' 'echo "$PLANT_BARE"'
  printf '%s\n' 'echo "$PLANT_SVC_API_KEY"'
  printf '%s\n' 'echo "${PLANT_SVC_TOKEN}"'
  printf '%s\n' "awk '{print ENVIRON[\"PLANT_ENV\"]}'"
  printf '%s\n' 'printenv PLANT_PRINTENV'
  printf '%s\n' '# comment: ${PLANT_COMMENT:-x} only here'
  printf '%s\n' 'PLANT_OWN=1; echo "${PLANT_OWN:-z}"'
  printf '%s\n' 'echo "${KEEL_PLANT_KEELNAME:-d}"'
  printf '%s\n' 'echo "${PLANT_SUBSTR:0:7} ${PLANT_STRIP#x} ${PLANT_LEN}"'
} > "$oplant/a.sh"
oplanted="$(inherited_other_reads "$oplant")"
for n in PLANT_DFLT PLANT_ASSIGN_DFLT PLANT_SELF PLANT_SVC_API_KEY PLANT_SVC_TOKEN PLANT_ENV PLANT_PRINTENV; do
  check_contains "a non-KEEL_ read signal is flagged: $n" "$oplanted" "$n"
done
check_absent "a bare read of a non-credential name is not a signal (documented axis)" "$oplanted" 'PLANT_BARE'
check_absent "a name in a comment only is not flagged" "$oplanted" 'PLANT_COMMENT'
check_absent "a script-owned variable is not flagged" "$oplanted" 'PLANT_OWN'
check_absent "a KEEL_ name belongs to the other half" "$oplanted" 'KEEL_PLANT_KEELNAME'
check_absent "substring / strip / length expansions are not default-expansion reads" "$oplanted" 'PLANT_SUBSTR'
check_eq "exactly the seven reads are reported" 7 "$(printf '%s\n' "$oplanted" | grep -c .)"

# --- the real tree --------------------------------------------------------------------------------------------
onames_all="$(inherited_other_reads "${census_roots[@]}")"
# anchors: names the ticket names (dir #704) and one per documented family — a scanner blind to them is vacuous
for anchor in AGY_BIN AGY_MODEL AGY_PRINT_TIMEOUT SECRET_SCAN_LOCAL_PUSH GITHUB_EVENT_NAME DRYDOCK_SCOPE_A LEAK_GATE_CWD HOME; do
  check_contains "the non-KEEL_ scan sees $anchor (so it is not vacuous on the real tree)" "$onames_all" "$anchor"
done
onames=""
for n in $onames_all; do
  case " $AMBIENT_EXEMPT " in *" $n "*) continue ;; esac
  onames="$onames$n
"
done
for n in $AMBIENT_EXEMPT; do
  check_contains "the exempt name $n is still read by some tool (an unread entry is stale)" "$onames_all" "$n"
done
ocount="$(printf '%s' "$onames" | grep -c .)"
check_ne "the scan found non-KEEL_ reads at all" "$ocount" 0

# shellcheck disable=SC2086
oleaked="$(unneutralized "$TESTS_DIR/lib.sh" $onames)"; rc=$?
check_eq "sourcing lib.sh succeeds in the poisoned child (non-KEEL_ names)" 0 "$rc"
if [ -z "$oleaked" ]; then
  pass "every non-KEEL_ name a shipped script reads from the environment is neutralized by tests/lib.sh ($ocount names)"
else
  fail "every non-KEEL_ name a shipped script reads from the environment is neutralized by tests/lib.sh ($ocount names)" \
    "tests/lib.sh leaves an operator's value of these reaching the suite — add each to its unset block (or to AMBIENT_EXEMPT here, with the reason):
$oleaked"
fi

# --- mutation proof: drop ONE name from a scratch copy of lib.sh and the gate must name exactly it ------------
SCRATCH_COPY_PREFIX=envcensus_other
ovictim=AGY_BIN
check_contains "the mutation victim ($ovictim) is one of the derived names" "$onames" "$ovictim"
omut_lib="$(scratch_copy "$TESTS_DIR/lib.sh" lib.sh)"
delete_line_containing "$omut_lib" "$ovictim"
check_ne "the edit changed the copy of lib.sh (non-KEEL_)" "$(cksum < "$omut_lib")" "$(cksum < "$TESTS_DIR/lib.sh")"
# shellcheck disable=SC2086
ores="$(unneutralized "$omut_lib" $onames)"
check_eq "lib.sh minus its $ovictim line: the gate reports $ovictim, and only it" "$ovictim" "$ores"

# --- a NEW tool's variable: a fixture tool reading an unlisted name turns the census red ---------------------
newtool="$(mktemp -d "$SANDBOX/newtool.XXXXXX")"
printf '%s\n' 'x="${VR_PLANT_NEWKNOB:-d}"' 'k="${PLANT_NEWVENDOR_API_KEY:-}"' > "$newtool/new.sh"
newnames="$(inherited_other_reads "$newtool")"
# shellcheck disable=SC2086
newleak="$(unneutralized "$TESTS_DIR/lib.sh" $newnames)"
check_eq "a new tool's non-KEEL_ names (a knob and an *_API_KEY) are reported by the scan" 2 "$(printf '%s\n' "$newnames" | grep -c .)"
check_eq "...and tests/lib.sh does not neutralize them yet, so the census would go red" "$newnames" "$newleak"

summary
