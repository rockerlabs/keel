#!/usr/bin/env bash
# secret-scan.sh — the cost of a large tracked binary (dir #830). `--tracked` decodes each binary into several text
# views and greps every view. It also read the binary's printable runs, and used to put a newline after EVERY
# non-printable byte: a 20 MiB incompressible blob became ~12.6 M tiny lines, and the class-1 grep pays a fixed ~12 µs
# per line however short it is (it measured 8–10 s of CPU per MiB, ~3 min for the blob; on a machine under load the
# scan never seemed to end — every `kb-doctor.sh` run hung on it). Class 1 now reads no run view (its patterns are
# unanchored printable ASCII, so every match already sits in the NUL-stripped view); the personal passes read the runs,
# squeezed to one line per maximal run, in a file of their own.
#   (P) the premise: no class-1 pattern is anchored
#   (V) the verdict does not move: a key or a personal literal inside a binary is still found
#   (C) the bound: a generated, incompressible 20 MiB blob scans in under CEILING seconds of CPU (user+sys of the
#       scan and its children), with personal literals set, the operator's configuration. CPU, not wall-clock: a
#       wall-clock ceiling measures the machine's load, which varies by an order of magnitude between a quiet laptop
#       and nine sessions sharing eight cores.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

scan="$REPO_ROOT/tools/secret-guard/secret-scan.sh"

# --- (P) the premise -------------------------------------------------------------------------------------------
# A match in a printable run is a substring of the NUL-stripped view, so the runs add no class-1 hit — unless a
# pattern is anchored (an `^` or `$` matches at a run's edge, not at the edge of the line the NUL-stripped view keeps).
eval "$(awk '/^PATTERNS=\(/{f=1} f{print} f&&/^\)/{exit}' "$scan")"
check_ne "P0: the class-1 pattern list was read" 0 "${#PATTERNS[@]}"
for p in "${PATTERNS[@]}"; do
  case "$p" in
    *'^'*|*'$'*) fail "P1: the class-1 pattern '$p' is unanchored" "it holds ^ or \$ — the run view must be scanned for class 1 again" ;;
    *) pass "P1: the class-1 pattern '$p' is unanchored" ;;
  esac
  case "$(printf '%s' "$p" | LC_ALL=C tr -d ' -~')" in
    '') pass "P2: the class-1 pattern '$p' is printable ASCII" ;;
    *) fail "P2: the class-1 pattern '$p' is printable ASCII" "it holds a byte outside the printable range" ;;
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
check_status "V2: the shortest key shape (15 chars) inside a binary is still found (raw views) → exit 1" 1 "$STATUS"

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

# The printable-run view is the only one an anchored pattern can match in a binary: the raw view keeps the junk
# around a run on its line, the run view does not. The personal passes read that view, so a literal of any length is
# found there, and a UTF-8 literal under a quantifier too.
pers_anchor="$SANDBOX/personal.anchor"
printf '^zorbfloor-exact$\n' > "$pers_anchor"
pers_short="$SANDBOX/personal.short"
printf '^zorbq$\n' > "$pers_short"
anchored_blob() {  # $1 = the printable run, between non-printable bytes, in a file with a NUL
  printf '\001\002%s\003\004\000tail' "$1" > "$BLOB"
}
anchored_blob "zorbfloor-exact"
repo="$(blob_repo)"
SECRET_SCAN_PERSONAL_FILE="$pers_anchor" run_in "$repo" "$scan" --tracked
check_status "V6: an anchored literal found only in the printable runs (15 chars) → exit 1" 1 "$STATUS"
check_contains "V6: ...reported as the bare match, no spool file name in front of it (grep -h)" "$OUT" "(binary) zorbfloor-exact"
anchored_blob "zorbq"
repo="$(blob_repo)"
SECRET_SCAN_PERSONAL_FILE="$pers_short" run_in "$repo" "$scan" --tracked
check_status "V7: an anchored literal shorter than every key shape is still found → exit 1" 1 "$STATUS"
check_contains "V7: ...reported as the bare match" "$OUT" "(binary) zorbq"
anchored_blob "zorbq-not-the-literal"
repo="$(blob_repo)"
SECRET_SCAN_PERSONAL_FILE="$pers_short" run_in "$repo" "$scan" --tracked
check_status "V8: ...and an anchored literal inside a longer run is not → exit 0" 0 "$STATUS"

# a literal with a multi-byte character under `*`: in a UTF-8 locale `^é*abc$` matches the 3-byte run `abc` (the
# review of an earlier version, which dropped runs shorter than a byte-wise minimum of 4, found this). Skipped where
# the host has no UTF-8 locale.
utf8_loc="$(pick_utf8_locale)" || utf8_loc=""
if [ -n "$utf8_loc" ]; then
  pers_mb="$SANDBOX/personal.mb"
  printf '^\303\251*abc$\n' > "$pers_mb"
  anchored_blob "abc"
  repo="$(blob_repo)"
  SECRET_SCAN_PERSONAL_FILE="$pers_mb" run_in "$repo" env LC_ALL="$utf8_loc" "$scan" --tracked
  check_status "V9: a multi-byte literal under * matches a run shorter than its byte count → exit 1" 1 "$STATUS"
else
  pass "V9 skipped (no UTF-8 locale on this host)"
fi

# --- (C) the bound ---------------------------------------------------------------------------------------------------
# CEILING — seconds of CPU for the 20 MiB blob below, with two personal literals set. The scan measured ~62 s
# after the fix (macOS, BSD grep) against ~217 s (~45 s and ~178 s with no personal literals) before it; the ceiling sits between, so it fails on the per-line
# blow-up and passes on a slower host. KEEL_TEST_SECRET_SCAN_CPU_CEILING and KEEL_TEST_SECRET_SCAN_BLOB_BYTES
# override the two numbers (the blob size is for a quick look at the scaling; the bound is pinned at the default).
CEILING="${KEEL_TEST_SECRET_SCAN_CPU_CEILING:-130}"
mk_blob "${KEEL_TEST_SECRET_SCAN_BLOB_BYTES:-20971520}" ""
repo="$(blob_repo)"
TIMEFORMAT='%U %S'
out="$( { time env SECRET_SCAN_PERSONAL_FILE="$pers" bash -c 'cd "$1" && "$2" --tracked >/dev/null 2>&1; echo "rc=$?" >&2' _ "$repo" "$scan"; } 2>&1 )"
rc_c="$(printf '%s\n' "$out" | sed -n 's/^rc=//p')"
cpu_c="$(printf '%s\n' "$out" | awk 'NF == 2 && $1 ~ /^[0-9.]+$/ { printf "%d", $1 + $2 + 0.999 }')"
check_eq "C1: a clean generated 20 MiB incompressible blob → exit 0" 0 "${rc_c:-missing}"
if [ -n "$cpu_c" ] && [ "$cpu_c" -le "$CEILING" ]; then
  pass "C2: the 20 MiB blob scans in ${cpu_c} s of CPU (ceiling ${CEILING} s)"
else
  fail "C2: the 20 MiB blob scans within ${CEILING} s of CPU" "took ${cpu_c:-unmeasured} s (output: $out)"
fi

summary
