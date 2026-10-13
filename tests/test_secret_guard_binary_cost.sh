#!/usr/bin/env bash
# secret-scan.sh — the cost of a large tracked binary (dir #830). `--tracked` decodes each binary into several text
# views and greps every view. One view is the raw printable runs; it used to put a newline after EVERY non-printable
# byte, so a 20 MiB incompressible blob became ~12.6 M tiny lines, and the class-1 grep pays a fixed ~12 µs per line
# however short it is (it measured 8–10 s of CPU per MiB, ~3 min for the blob; on a machine under load the scan never
# seemed to end — every `kb-doctor.sh` run hung on it). The view is now squeezed to maximal printable runs and drops
# every run shorter than the shortest string any pattern can match (`run_floor`, derived from the patterns themselves).
#   (F) the floor derivation: the smallest match length of an ERE subset, 1 (no filtering) for anything it cannot parse
#   (V) the verdict does not move: a key or a personal literal inside a binary is still found
#   (C) the bound: a generated, incompressible 20 MiB blob scans in under CEILING seconds of CPU (user+sys of the
#       scan and its children). CPU, not wall-clock: a wall-clock ceiling measures the machine's load, which varies
#       by an order of magnitude between a quiet laptop and nine sessions sharing eight cores.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

scan="$REPO_ROOT/tools/secret-guard/secret-scan.sh"

# --- (F) the floor derivation ------------------------------------------------------------------------------------
# The calculator is the block between the two `# run-floor:` markers in the scanner; the scanner cannot be sourced
# (it runs on load), so the block is evaluated here.
block="$(sed -n '/^# run-floor:begin/,/^# run-floor:end/p' "$scan")"
check_ne "F0: the scanner carries the run-floor block" "" "$block"
eval "$block"
# floor_of ERE… — the smallest length (bytes) any of the EREs can match
floor_of() { printf '%s\n' "$@" | _min_match_len 2>/dev/null; }

check_eq "F1: a literal is its length"                    3  "$(floor_of 'abc')"
check_eq "F2: an alternation takes its shortest branch"   1  "$(floor_of 'a|bcd')"
check_eq "F3: a starred atom can vanish"                  1  "$(floor_of 'ab*')"
check_eq "F4: a plussed atom counts once"                 1  "$(floor_of 'a+')"
check_eq "F5: {n} multiplies"                             3  "$(floor_of 'a{3}')"
check_eq "F6: {n,} takes its lower bound"                 3  "$(floor_of 'a{3,}')"
check_eq "F7: {n,m} takes its lower bound"                3  "$(floor_of 'a{2,4}b')"
check_eq "F8: a group with an alternation"                2  "$(floor_of '(ab|c)d')"
check_eq "F9: a bracket is one character"                 4  "$(floor_of '[a-z]{4}')"
check_eq "F10: a leading ] is part of the bracket"        2  "$(floor_of '[]a]x')"
check_eq "F11: a [:class:] inside a bracket"              2  "$(floor_of '[[:alpha:]]x')"
check_eq "F12: anchors are zero-width"                    2  "$(floor_of '^ab$')"
check_eq "F13: a dot is one character"                    1  "$(floor_of '.')"
check_eq "F14: an escaped dot is one character"           3  "$(floor_of 'a\.b')"
check_eq "F15: a back-reference can be empty"             1  "$(floor_of '(a)\1')"
check_eq "F27: a GNU word boundary is zero-width"          3  "$(floor_of '\bfoo\b')"
check_eq "F28: a GNU word edge is zero-width"              3  "$(floor_of '\<foo\>')"
check_eq "F16: stacked bounds multiply"                   6  "$(floor_of 'x{2}{3}')"
check_eq "F17: an optional group can vanish"              1  "$(floor_of '(abc)?')"
check_eq "F18: the smallest of several EREs"              4  "$(floor_of 'abcdef' 'wxyz' 'hello')"
# anything the subset cannot read disables the filter (floor 1) instead of guessing
check_eq "F19: an unclosed group → 1"                     1  "$(floor_of 'abcdef' '(xyz')"
check_eq "F20: an unclosed bracket → 1"                   1  "$(floor_of 'abcdef' 'a[bc')"
check_eq "F21: a quantifier with no atom → 1"             1  "$(floor_of 'abcdef' '*a')"
check_eq "F22: a malformed bound → 1"                     1  "$(floor_of 'abcdef' 'a{x}')"
check_eq "F23: a stray ) → 1"                             1  "$(floor_of 'abcdef' 'ab)cd')"
check_eq "F24: no input → 1"                              1  "$(printf '' | _min_match_len 2>/dev/null)"

# The class-1 patterns themselves: the derivation must read every one (a fallback to 1 here would silently turn the
# bound off) and the shortest is the Slack shape, xox + [baprs] + - + {10,} = 15. A new, shorter pattern changes
# this number on purpose: re-check that nothing else assumed it.
eval "$(awk '/^PATTERNS=\(/{f=1} f{print} f&&/^\)/{exit}' "$scan")"
joined_t=""
for p in "${PATTERNS[@]}"; do joined_t="${joined_t:+$joined_t|}$p"; done
check_eq "F25: the class-1 patterns' floor is the Slack shape's 15" 15 "$(floor_of "$joined_t")"
# ...and no single class-1 pattern reads as 1 (which would hide a parse failure behind the smallest-of rule)
for p in "${PATTERNS[@]}"; do
  f26="$(floor_of "$p")"
  case "$f26" in
    ''|0|1) fail "F26: the floor of '$p' is derived, not the fallback" "got '$f26'" ;;
    *) pass "F26: the floor of '$p' is derived, not the fallback" ;;
  esac
done

# --- (V) the verdict -----------------------------------------------------------------------------------------------
# blob_repo NAME — a sandbox repo holding the generated binary $BLOB (staged, not committed: --tracked reads the index)
blob_repo() {
  local d; d="$(new_repo)"
  cp "$BLOB" "$d/data.bin"
  git -C "$d" add data.bin
  printf '%s' "$d"
}
BLOB="$SANDBOX/blob.bin"
pers="$SANDBOX/personal.lit"
printf 'zorbquux-alpha\nplughxyzzy-beta\n' > "$pers"

# 2 MiB of incompressible bytes, a key line in the middle
mk_blob() {  # $1 = size in bytes, $2 = text to embed ('' for none)
  local half=$(($1 / 2))
  head -c "$half" /dev/urandom > "$BLOB"
  [ -z "$2" ] || printf '\n%s\n' "$2" >> "$BLOB"
  head -c "$half" /dev/urandom >> "$BLOB"
}

mk_blob 2097152 "tok = $(key 'ghp_' "$(rep A 36)")"
repo="$(blob_repo)"
SECRET_SCAN_PERSONAL_FILE="$pers" run_in "$repo" "$scan" --tracked
check_status "V1: a key inside a 2 MiB binary is still found → exit 1" 1 "$STATUS"
check_contains "V1: … in data.bin" "$OUT" "data.bin"

mk_blob 2097152 "$(key 'xox' 'b-1234567890')"
repo="$(blob_repo)"
SECRET_SCAN_PERSONAL_FILE="$pers" run_in "$repo" "$scan" --tracked
check_status "V2: the shortest key shape (15 chars) inside a binary is still found → exit 1" 1 "$STATUS"

mk_blob 2097152 "name = zorbquux-alpha"
repo="$(blob_repo)"
SECRET_SCAN_PERSONAL_FILE="$pers" run_in "$repo" "$scan" --tracked
check_status "V3: a personal literal inside a binary is still found → exit 1" 1 "$STATUS"

mk_blob 2097152 "short run xoxb-123456789"
repo="$(blob_repo)"
SECRET_SCAN_PERSONAL_FILE="$pers" run_in "$repo" "$scan" --tracked
check_status "V4: a key-like run one character short of a key → exit 0" 0 "$STATUS"

mk_blob 2097152 ""
repo="$(blob_repo)"
SECRET_SCAN_PERSONAL_FILE="$pers" run_in "$repo" "$scan" --tracked
check_status "V5: a clean 2 MiB binary → exit 0" 0 "$STATUS"

# --- (C) the bound ---------------------------------------------------------------------------------------------------
# CEILING — seconds of CPU for the 20 MiB blob below. The scan measured ~30 s of CPU after the fix (macOS, BSD grep,
# class 1 only) against ~180 s before it; the ceiling sits between, so it fails on the per-line blow-up and passes
# on a slower host. KEEL_TEST_SECRET_SCAN_CPU_CEILING and KEEL_TEST_SECRET_SCAN_BLOB_BYTES override the two numbers
# (the blob size is for a quick look at the scaling; the bound is pinned at the default).
CEILING="${KEEL_TEST_SECRET_SCAN_CPU_CEILING:-100}"
mk_blob "${KEEL_TEST_SECRET_SCAN_BLOB_BYTES:-20971520}" ""
repo="$(blob_repo)"
TIMEFORMAT='%U %S'
out="$( { time env SECRET_SCAN_PERSONAL_FILE=/dev/null bash -c 'cd "$1" && "$2" --tracked >/dev/null 2>&1; echo "rc=$?" >&2' _ "$repo" "$scan"; } 2>&1 )"
rc_c="$(printf '%s\n' "$out" | sed -n 's/^rc=//p')"
cpu_c="$(printf '%s\n' "$out" | awk 'NF == 2 && $1 ~ /^[0-9.]+$/ { printf "%d", $1 + $2 + 0.999 }')"
check_eq "C1: a clean generated 20 MiB incompressible blob → exit 0" 0 "${rc_c:-missing}"
if [ -n "$cpu_c" ] && [ "$cpu_c" -le "$CEILING" ]; then
  pass "C2: the 20 MiB blob scans in ${cpu_c} s of CPU (ceiling ${CEILING} s)"
else
  fail "C2: the 20 MiB blob scans within ${CEILING} s of CPU" "took ${cpu_c:-unmeasured} s (output: $out)"
fi

summary
