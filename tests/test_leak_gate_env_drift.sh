#!/usr/bin/env bash
# test_leak_gate_env_drift.sh — dir #726: tools/lib/leak-gate.sh's _LEAK_GATE_PATH_ENV is the list of
# variables tools/secret-guard/secret-scan.sh reads whose value is a PATH; leak_gate_run absolutizes each
# against the caller's cwd before the scanner's neutral-cwd `cd` (0.14.0 delta audit S7-5: an unlisted
# relative path variable silently fails the gate OPEN). The list was enumerated by hand, so a new
# path-valued read in the scanner re-opened that class with nothing red. This file derives the scanner's
# environment reads (SECRET_SCAN_* / KEEL_* / HOME / TMPDIR, comments excluded) and asserts the list is
# EXACTLY them minus a named non-path set: every read is listed (new read -> red), every listed name is
# still read (dead entry -> red), and all six current names are pinned by that equality (before this,
# KEEL_IMPACT_STORE, KEEL_HOME and TMPDIR were pinned by no test).
#
# A read that is deliberately NOT a path (a flag) goes in NON_PATH_ENV below with its reason; adding
# there is the explicit decision a new variable forces. TMPDIR is read implicitly by a bare `mktemp`
# (no template argument), which is how the scanner reads it, so that shape counts as a TMPDIR read.
# Scope: the scanner and the vendored libs beside it that it may run (range-lib.sh) — the hooks run in the
# caller's cwd, not the scanner's neutral one, so they are out of scope.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

gate_lib="$REPO_ROOT/tools/lib/leak-gate.sh"
scanner="$REPO_ROOT/tools/secret-guard/secret-scan.sh"
range_lib="$REPO_ROOT/tools/secret-guard/range-lib.sh"

# Read by the scanner but not a path: SECRET_SCAN_LOCAL_PUSH is a presence flag (`[ -n "${...:-}" ]`).
NON_PATH_ENV="SECRET_SCAN_LOCAL_PUSH"

# env_reads FILE... — sorted unique environment names the files read, one per line.
env_reads() {
  local f body names
  for f in "$@"; do
    body="$(grep -vE '^[[:space:]]*#' "$f" || true)"
    names="$(grep -oE '\$\{?(SECRET_SCAN_[A-Z0-9_]+|KEEL_[A-Z0-9_]+|HOME|TMPDIR)\b' <<<"$body" | tr -d '${' || true)"
    [ -z "$names" ] || printf '%s\n' "$names"
    if grep -qE 'mktemp( -[A-Za-z]+)*\)' <<<"$body"; then echo TMPDIR; fi
  done | sort -u
}

# expected_list FILE... — what _LEAK_GATE_PATH_ENV must be: the reads minus NON_PATH_ENV, sorted.
expected_list() {
  local n
  env_reads "$@" | while IFS= read -r n; do
    case " $NON_PATH_ENV " in *" $n "*) ;; *) echo "$n" ;; esac
  done
}

# listed — the lib's own _LEAK_GATE_PATH_ENV, sorted, one per line (read from the real file).
listed() {
  local line
  line="$(bash -c '. "$1" && printf "%s" "$_LEAK_GATE_PATH_ENV"' _ "$gate_lib")"
  tr ' ' '\n' <<<"$line" | sort -u
}

# drift LISTED_TEXT FILE... — "" when the list equals the derived set, else a diff-style report.
drift() {
  local have="$1" want
  shift
  want="$(expected_list "$@")"
  diff <(printf '%s\n' "$want") <(printf '%s\n' "$have") || true
}

check_file "tools/secret-guard/secret-scan.sh exists" "$scanner"
check_file "tools/secret-guard/range-lib.sh exists" "$range_lib"

# --- the real tree: quiet ---------------------------------------------------------------------------
have="$(listed)"
check_eq "the lib lists exactly six path variables" "6" "$(grep -c . <<<"$have")"
check_eq "real tree: _LEAK_GATE_PATH_ENV equals the scanner's path-valued reads (no drift)" "" \
  "$(drift "$have" "$scanner" "$range_lib")"

# Each of the six is pinned individually, so a failure names the one that fell out of step.
for v in SECRET_SCAN_PERSONAL_FILE KEEL_IMPACT_LOG KEEL_IMPACT_STORE KEEL_HOME HOME TMPDIR; do
  check_contains "$v is listed" "$have" "$v"
  check_contains "$v is read by the scanner" "$(env_reads "$scanner" "$range_lib")" "$v"
done
check_absent "the non-path flag is not listed" "$have" "SECRET_SCAN_LOCAL_PUSH"

# --- mutations: the check must go red ---------------------------------------------------------------
mut="$SANDBOX/mut"
mkdir -p "$mut"

# A new path-valued read added to the scanner, unlisted.
cp "$scanner" "$mut/new-read.sh"
printf '%s\n' 'extra_dir="${KEEL_NEW_STATE_DIR:-}"' >> "$mut/new-read.sh"
out="$(drift "$have" "$mut/new-read.sh" "$range_lib")"
check_contains "mutation: unlisted new KEEL_* read -> red" "$out" "KEEL_NEW_STATE_DIR"

# A new SECRET_SCAN_* read, bare `$VAR` form.
cp "$scanner" "$mut/new-scan.sh"
printf '%s\n' 'extra_file="$SECRET_SCAN_OTHER_FILE"' >> "$mut/new-scan.sh"
out="$(drift "$have" "$mut/new-scan.sh" "$range_lib")"
check_contains "mutation: unlisted new SECRET_SCAN_* read (bare form) -> red" "$out" "SECRET_SCAN_OTHER_FILE"

# A new read in the sourced lib, not the scanner.
cp "$range_lib" "$mut/new-lib.sh"
printf '%s\n' 'x="${KEEL_LIB_DIR:-}"' >> "$mut/new-lib.sh"
out="$(drift "$have" "$scanner" "$mut/new-lib.sh")"
check_contains "mutation: unlisted new read in the sourced lib -> red" "$out" "KEEL_LIB_DIR"

# A commented mention is not a read.
cp "$scanner" "$mut/comment.sh"
printf '%s\n' '# mentions ${KEEL_ONLY_IN_COMMENT} but never reads it' >> "$mut/comment.sh"
check_eq "a commented mention is not a read -> stays quiet" "" "$(drift "$have" "$mut/comment.sh" "$range_lib")"

# Each listed name dropped from the list, one at a time, is caught.
for v in SECRET_SCAN_PERSONAL_FILE KEEL_IMPACT_LOG KEEL_IMPACT_STORE KEEL_HOME HOME TMPDIR; do
  short="$(grep -vx "$v" <<<"$have")"
  out="$(drift "$short" "$scanner" "$range_lib")"
  check_contains "mutation: $v dropped from the list -> red" "$out" "$v"
done

# A dead entry (listed, no longer read) is caught.
out="$(drift "$(printf '%s\nKEEL_GONE_VAR\n' "$have" | sort -u)" "$scanner" "$range_lib")"
check_contains "mutation: a listed name the scanner no longer reads -> red" "$out" "KEEL_GONE_VAR"

# TMPDIR read implicitly: a scanner whose bare `mktemp -d` is gone no longer reads it.
sed 's/mktemp -d)/mktemp -d "\/x\/y.XXXXXX")/' "$scanner" > "$mut/no-tmpdir.sh"
out="$(drift "$have" "$mut/no-tmpdir.sh" "$range_lib")"
check_contains "mutation: no bare mktemp left -> TMPDIR entry reported dead" "$out" "TMPDIR"

summary
