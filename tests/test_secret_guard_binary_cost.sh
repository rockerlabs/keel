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
#       On a busybox grep (Alpine) the leg is a sanity bound: 4 MiB, class 1 alone, ceiling 150 s — busybox grep costs
#       ~10x as much per personal pass, so the personal passes' timing is pinned on the macOS and GNU-grep legs only.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

scan="$REPO_ROOT/tools/secret-guard/secret-scan.sh"

# --- (P) the premise -------------------------------------------------------------------------------------------
# A match in a printable run is a substring of the NUL-stripped view, so the runs add no class-1 hit — unless a
# pattern is anchored (an `^` or `$` matches at a run's edge, not at the edge of the line the NUL-stripped view keeps)
# or tests a word boundary (`\b`, `\<`: the NUL-stripped view joins a run to the bytes before a stripped NUL).
eval "$(awk '/^PATTERNS=\(/{f=1} f{print} f&&/^\)/{exit}' "$scan")"
check_ne "P0: the class-1 pattern list was read" 0 "${#PATTERNS[@]}"
for p in "${PATTERNS[@]}"; do
  case "$p" in
    *'^'*|*'$'*|*'\'*) fail "P1: the class-1 pattern '$p' is unanchored" "it holds ^, \$ or a backslash (an anchor or a word boundary) — the run view must be scanned for class 1 again" ;;
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
printf '^zorbanchored$\n' > "$pers_anchor"
pers_short="$SANDBOX/personal.short"
printf '^zorbq$\n' > "$pers_short"
anchored_blob() {  # $1 = the printable run, between non-printable bytes, in a file with a NUL
  printf '\001\002%s\003\004\000tail' "$1" > "$BLOB"
}
anchored_blob "zorbanchored"
repo="$(blob_repo)"
SECRET_SCAN_PERSONAL_FILE="$pers_anchor" run_in "$repo" "$scan" --tracked
check_status "V6: an anchored literal found only in the printable runs → exit 1" 1 "$STATUS"
check_contains "V6: ...reported as the bare match, no spool file name in front of it (grep -h)" "$OUT" "(binary) zorbanchored"
anchored_blob "zorbq"
repo="$(blob_repo)"
SECRET_SCAN_PERSONAL_FILE="$pers_short" run_in "$repo" "$scan" --tracked
check_status "V7: an anchored literal shorter than every key shape is still found → exit 1" 1 "$STATUS"
check_contains "V7: ...reported as the bare match" "$OUT" "(binary) zorbq"
anchored_blob "zorbq-not-the-literal"
repo="$(blob_repo)"
SECRET_SCAN_PERSONAL_FILE="$pers_short" run_in "$repo" "$scan" --tracked
check_status "V8: ...and an anchored literal inside a longer run is not → exit 0" 0 "$STATUS"

# a literal with a multi-byte character under `*`: in a UTF-8 locale `^é*abc$` matches the 3-byte run `abc`, though
# the pattern is 5 bytes long. Skipped where the host has no UTF-8 locale.
utf8_loc="$(pick_utf8_locale)" || utf8_loc=""
if [ -n "$utf8_loc" ]; then
  pers_mb="$SANDBOX/personal.mb"
  printf '^\303\251*abc$\n' > "$pers_mb"
  anchored_blob "abc"
  repo="$(blob_repo)"
  SECRET_SCAN_PERSONAL_FILE="$pers_mb" run_in "$repo" env LC_ALL="$utf8_loc" "$scan" --tracked
  check_status "V9: a multi-byte literal under * matches a run shorter than the pattern → exit 1" 1 "$STATUS"
else
  pass "V9 skipped (no UTF-8 locale on this host)"
fi

# the same multi-byte literal when the iconv sanitizer FAILS (the musl case): pu_grep must fall back to reading the run
# file beside FILE, not drop it. A stub `iconv` that exits 1 makes that deterministic on any host; it still needs a
# UTF-8 locale for the run to match, so it is skipped where the host has none (the alpine leg).
if [ -n "$utf8_loc" ]; then
  noic="$SANDBOX/noiconv"
  mkdir -p "$noic"
  printf '#!/bin/sh\nexit 1\n' > "$noic/iconv"
  chmod +x "$noic/iconv"
  anchored_blob "abc"
  repo="$(blob_repo)"
  SECRET_SCAN_PERSONAL_FILE="$pers_mb" run_in "$repo" env PATH="$noic:$PATH" LC_ALL="$utf8_loc" "$scan" --tracked
  check_status "V10: ...and with a failing iconv sanitizer the run file is still read → exit 1" 1 "$STATUS"
else
  pass "V10 skipped (no UTF-8 locale on this host)"
fi

# --- (R) the same verdicts over --range (dir #850) ---------------------------------------------------------------------
# --range counts matches on a NUL-stripped stream before it runs the detailed scan, so a personal literal that matches
# only a printable run (an unescaped `^` or `$`, a `\<` `\>` word boundary) reads clean there unless the fast path is
# skipped. Each blob is added by the last commit of the range; `--tracked` already answered these (V6–V8 above).
range_blob_repo() {  # $1 = the blob's printf format; prints a repo whose HEAD~1..HEAD adds it as data.bin
  local d; d="$(new_repo)"
  git -C "$d" commit -q --allow-empty -m base
  printf "$1" > "$d/data.bin"
  git -C "$d" add data.bin
  git -C "$d" commit -q -m blob
  printf '%s' "$d"
}
pers_wb="$SANDBOX/personal.wb";   printf '\\bzorbquux\\b\n' > "$pers_wb"
pers_alt="$SANDBOX/personal.alt"; printf '(^|[^a-z])zorbquux($|[^a-z])\n' > "$pers_alt"
pers_start="$SANDBOX/personal.start"; printf '^zorbq\n' > "$pers_start"
pers_end="$SANDBOX/personal.end"; printf 'zorbquux$\n' > "$pers_end"
pers_esc="$SANDBOX/personal.esc"; printf 'zorb\\$quux\n' > "$pers_esc"
pers_gnuwb="$SANDBOX/personal.gnuwb"; printf '\\<zorbquux\\>\n' > "$pers_gnuwb"
pers_gnuend="$SANDBOX/personal.gnuend"; printf 'zorbquux\\'"'"'\n' > "$pers_gnuend"

repo="$(range_blob_repo '\001\002zorbanchored\003\004\000tail')"
SECRET_SCAN_PERSONAL_FILE="$pers_anchor" run_in "$repo" "$scan" --range HEAD~1..HEAD
check_status "V6r: an ^…\$ literal found only in the printable runs, over --range → exit 1" 1 "$STATUS"
check_contains "V6r: ...naming the blob" "$OUT" "data.bin"

repo="$(range_blob_repo '\001\002zorbq-extra\003\000tail')"
SECRET_SCAN_PERSONAL_FILE="$pers_start" run_in "$repo" "$scan" --range HEAD~1..HEAD
check_status "V6r: a lone leading ^ literal (^zorbq) over --range → exit 1" 1 "$STATUS"

wbblob='hdr\000abc\000zorbquux\000defg\000end\000'
repo="$(range_blob_repo "$wbblob")"
SECRET_SCAN_PERSONAL_FILE="$pers_end" run_in "$repo" "$scan" --range HEAD~1..HEAD
check_status "V7r: a trailing \$ literal (zorbquux\$) over --range → exit 1" 1 "$STATUS"
SECRET_SCAN_PERSONAL_FILE="$pers_wb" run_in "$repo" "$scan" --range HEAD~1..HEAD
check_status "V7r: a \\b word-boundary literal over --range → exit 1 (the wide skip already caught it)" 1 "$STATUS"
SECRET_SCAN_PERSONAL_FILE="$pers_alt" run_in "$repo" "$scan" --range HEAD~1..HEAD
check_status "V7r: a (^|[^a-z])…(\$|[^a-z]) literal over --range → exit 1 (the wide skip already caught it)" 1 "$STATUS"
SECRET_SCAN_PERSONAL_FILE="$pers_gnuwb" run_in "$repo" "$scan" --range HEAD~1..HEAD
check_status "V7r: a \\<…\\> word-boundary literal over --range → exit 1" 1 "$STATUS"
# \' is an end-of-buffer anchor for GNU grep only (BSD and busybox read it differently), so the row needs a grep that has it
if printf 'xa\n' | LC_ALL=C grep -qE "a\\'"; then
  SECRET_SCAN_PERSONAL_FILE="$pers_gnuend" run_in "$repo" "$scan" --range HEAD~1..HEAD
  check_status "V7r: a GNU \\' end-of-buffer anchor literal over --range → exit 1" 1 "$STATUS"
else
  pass "V7r \\' row skipped (this grep has no \\' anchor)"
fi

repo="$(range_blob_repo '\001\002zorbq-not-the-literal\003\000tail')"
SECRET_SCAN_PERSONAL_FILE="$pers_short" run_in "$repo" "$scan" --range HEAD~1..HEAD
check_status "V8r: ...and an ^…\$ literal inside a longer run is not, over --range → exit 0" 0 "$STATUS"

# behaviour rows: an escaped \$ is a literal, and the detailed scan answers it either way
repo="$(range_blob_repo 'a\000zorbquux\000zorb$quux\000')"
SECRET_SCAN_PERSONAL_FILE="$pers_esc" run_in "$repo" "$scan" --range HEAD~1..HEAD
check_status "V8r: an escaped \\\$ literal matches the literal dollar sign over --range → exit 1" 1 "$STATUS"
repo="$(range_blob_repo 'a\000zorbquux\000')"
SECRET_SCAN_PERSONAL_FILE="$pers_esc" run_in "$repo" "$scan" --range HEAD~1..HEAD
check_status "V8r: ...and not the same bytes without the dollar sign → exit 0" 0 "$STATUS"

# --- (R2) the fast path's gate is the stream, not the literal (dir #897) -----------------------------------------------
# The count runs over the NUL-stripped stream, which is the blobs themselves when none holds a NUL. A blob with a NUL
# is decoded by the detailed scan, and a personal literal sees more there than in the stripped view: a wide or anchored
# one (dir #761, dir #850), and a letter the host's `grep -i` folds to a non-ASCII one (GNU grep in a UTF-8 locale:
# `s` matches U+017F, `i` matches U+0131; the BSD grep of macOS folds none). So a range holding a NUL byte and a
# personal literal skips the count; every other range keeps it, whatever the literal looks like.
fold_row() {  # $1 = row label, $2 = literal, $3 = UTF-16LE blob (printf format), $4 = the folded character (printf format), $5 = its ASCII letter
  if [ -z "$utf8_loc" ] || [ "$(printf "$4" | LC_ALL="$utf8_loc" grep -ci "$5")" != 1 ]; then
    pass "F $1 skipped (this host's grep -i does not fold the character, or it has no UTF-8 locale)"
    return
  fi
  local f="$SANDBOX/personal.fold"
  printf '%s\n' "$2" > "$f"
  repo="$(range_blob_repo "$3")"
  SECRET_SCAN_PERSONAL_FILE="$f" run_in "$repo" env LC_ALL="$utf8_loc" "$scan" --range HEAD~1..HEAD
  check_status "F $1: literal '$2' against the folded character in UTF-16LE, over --range → exit 1" 1 "$STATUS"
  check_contains "F $1: ...naming the blob" "$OUT" "data.bin"
}
fold_row s risk 'r\000i\000\177\001k\000' '\305\277' s
fold_row i skin 's\000k\000\061\001n\000' '\304\261' i
fold_row k oak 'o\000a\000*!' '\342\204\252' k
# the detailed scan does not over-report: a different literal does not match the folded character
if [ -n "$utf8_loc" ]; then
  printf 'rask\n' > "$SANDBOX/personal.fold"
  repo="$(range_blob_repo 'r\000i\000\177\001k\000')"
  SECRET_SCAN_PERSONAL_FILE="$SANDBOX/personal.fold" run_in "$repo" env LC_ALL="$utf8_loc" "$scan" --range HEAD~1..HEAD
  check_status "F control: 'rask' does not match 'ri<U+017F>k' in UTF-16LE → exit 0" 0 "$STATUS"
fi

# A range with no NUL keeps the fast path for a wide or anchored literal. The verdict is the same either way; the
# observable is how many times `iconv` runs (the fast path sanitizes the stream once, the detailed scan once per blob
# and per decode pass), counted by a shim that logs its calls and runs the real one.
real_iconv="$(command -v iconv 2>/dev/null)" || real_iconv=""
text_range_repo() {  # $1 = a.txt, $2 = b.txt (printf formats); prints a repo whose HEAD~1..HEAD adds them and a third text blob (no NUL)
  local d; d="$(new_repo)"
  git -C "$d" commit -q --allow-empty -m base
  printf "$1" > "$d/a.txt"
  printf "$2" > "$d/b.txt"
  printf "plain text\n" > "$d/c.txt"
  git -C "$d" add a.txt b.txt c.txt
  git -C "$d" commit -q -m text
  printf '%s' "$d"
}
pers_dot="$SANDBOX/personal.dot"; printf 'micha.ek\n' > "$pers_dot"
pers_plain="$SANDBOX/personal.plainlit"; printf 'michalek\n' > "$pers_plain"
repo="$(text_range_repo "alpha\n" "beta\n")"      # no literal below matches it
if [ -n "$real_iconv" ] && [ -n "$utf8_loc" ]; then
  cnt="$SANDBOX/iconv.calls"; icsh="$SANDBOX/iconvlog"; mkdir -p "$icsh"
  printf '#!/bin/sh\necho x >> "%s"\nexec "%s" "$@"\n' "$cnt" "$real_iconv" > "$icsh/iconv"; chmod +x "$icsh/iconv"
  iconv_calls() {  # $1 = personal file, $2 = repo; prints the number of iconv calls of one --range run
    : > "$cnt"
    SECRET_SCAN_PERSONAL_FILE="$1" run_in "$2" env PATH="$icsh:$PATH" LC_ALL="$utf8_loc" "$scan" --range HEAD~1..HEAD
    wc -l < "$cnt" | tr -d ' '
  }
  n_plain="$(iconv_calls "$pers_plain" "$repo")"
  n_dot="$(iconv_calls "$pers_dot" "$repo")"
  pers_hit="$SANDBOX/personal.hit"; printf 'plain text\n' > "$pers_hit"       # matches c.txt: the count hits, so the detailed scan runs too
  n_hit="$(iconv_calls "$pers_hit" "$repo")"
  if [ "$n_dot" -lt "$n_hit" ] && [ "$n_plain" -lt "$n_hit" ]; then pass "N0: a hit costs more iconv calls ($n_hit) than a clean fast path ($n_plain, $n_dot): the shim tells the two apart"
  else fail "N0: a hit costs more iconv calls than a clean fast path" "hit $n_hit, plain $n_plain, wide $n_dot"; fi
  check_eq "N1: a wide literal (micha.ek) over a range with no NUL costs the fast path's iconv calls, not the detailed scan's" "$n_plain" "$n_dot"
  n_anch="$(iconv_calls "$pers_anchor" "$repo")"
  check_eq "N2: an anchored literal (^zorbanchored\$) over a range with no NUL costs the fast path's iconv calls" "$n_plain" "$n_anch"
  repo_nul="$(range_blob_repo 'a\000b\000')"
  n_nul="$(iconv_calls "$pers_plain" "$repo_nul")"
  check_ne "N3: the same plain literal over a range holding a NUL byte takes the detailed scan (more iconv calls)" "$n_plain" "$n_nul"
else
  pass "N0-N3 skipped (no iconv or no UTF-8 locale on this host)"
fi
# the fast path still answers: a wide or anchored literal that matches a text blob blocks
repo="$(text_range_repo 'Micha\305\201ek\n' 'zorbanchored\n')"
SECRET_SCAN_PERSONAL_FILE="$pers_dot" run_in "$repo" env LC_ALL="${utf8_loc:-C}" "$scan" --range HEAD~1..HEAD
if [ -n "$utf8_loc" ]; then check_status "N4: micha.ek matches the UTF-8 text 'Micha<U+0141>ek' over --range → exit 1" 1 "$STATUS"
else pass "N4 skipped (no UTF-8 locale on this host)"; fi
SECRET_SCAN_PERSONAL_FILE="$pers_anchor" run_in "$repo" "$scan" --range HEAD~1..HEAD
check_status "N5: ^zorbanchored\$ matches the text line over --range → exit 1" 1 "$STATUS"
check_contains "N5: ...naming b.txt" "$OUT" "b.txt"

# --- (C) the bound ---------------------------------------------------------------------------------------------------
# CEILING — seconds of CPU for the 20 MiB blob below, with two personal literals set. The scan measured ~55 s after
# the fix (macOS, BSD grep) against ~217 s before it (~37 s and ~178 s with no personal literals); the ceiling sits
# between, so it fails on the per-line blow-up and passes on a slower host. KEEL_TEST_SECRET_SCAN_CPU_CEILING and
# KEEL_TEST_SECRET_SCAN_BLOB_BYTES override the two numbers (the blob size is for a quick look at the scaling; the
# bound is pinned at the default).
CEILING="${KEEL_TEST_SECRET_SCAN_CPU_CEILING:-130}"
pers_c="$pers"
BLOB_BYTES="${KEEL_TEST_SECRET_SCAN_BLOB_BYTES:-20971520}"
# busybox grep is ~10x slower than BSD/GNU grep here (Alpine 3.21: 258 s of CPU for the 20 MiB blob with NO personal
# literal, ~700 s with two), so there the bound is a sanity check on a smaller blob with class 1 alone; the 20 MiB
# bound binds on the macOS legs.
case "$(grep --help 2>&1)" in
  *BusyBox*)
    pers_c=/dev/null
    BLOB_BYTES="${KEEL_TEST_SECRET_SCAN_BLOB_BYTES:-4194304}"
    CEILING="${KEEL_TEST_SECRET_SCAN_CPU_CEILING:-150}" ;;
esac
MIB=$((BLOB_BYTES / 1048576))
mk_blob "$BLOB_BYTES" ""
repo="$(blob_repo)"
TIMEFORMAT='%U %S'
out="$( { time env SECRET_SCAN_PERSONAL_FILE="$pers_c" bash -c 'cd "$1" && "$2" --tracked >/dev/null 2>&1; echo "rc=$?" >&2' _ "$repo" "$scan"; } 2>&1 )"
rc_c="$(printf '%s\n' "$out" | sed -n 's/^rc=//p')"
cpu_c="$(printf '%s\n' "$out" | awk 'NF == 2 && $1 ~ /^[0-9.]+$/ { printf "%d", $1 + $2 + 0.999 }')"
check_eq "C1: a clean generated ${MIB} MiB incompressible blob → exit 0" 0 "${rc_c:-missing}"
if [ -n "$cpu_c" ] && [ "$cpu_c" -le "$CEILING" ]; then
  pass "C2: the ${MIB} MiB blob scans in ${cpu_c} s of CPU (ceiling ${CEILING} s)"
else
  fail "C2: the ${MIB} MiB blob scans within ${CEILING} s of CPU" "took ${cpu_c:-unmeasured} s (output: $out)"
fi

summary
