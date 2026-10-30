#!/usr/bin/env bash
# test_fence_blank_lib.sh — dir #169: blank_fenced_blocks() used to be a private copy inside
# tools/self/doctor.sh (already found duplicated once between two of doctor.sh's OWN checks by an
# earlier /code-review medium pass, per that function's own comment) until tools/self/prose-drift.sh
# needed the identical toggle and this was extracted to tools/lib/fence-blank.sh instead of becoming
# a second hand-maintained copy. Pin this at the SOURCE level (grep both consumers for the sourcing
# line, and grep the whole tree for a re-duplicated inline copy of the toggle), not the output level —
# an output-level check would only prove today's two callers happen to agree, not that a third copy
# can't reappear.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

lib="$REPO_ROOT/tools/lib/fence-blank.sh"
check_file "tools/lib/fence-blank.sh exists" "$lib"

# --- both known consumers source the shared lib, not a private copy -----------------------------
check_contains "doctor.sh sources tools/lib/fence-blank.sh" \
  "$(cat "$REPO_ROOT/tools/self/doctor.sh")" 'lib/fence-blank.sh'
check_contains "prose-drift.sh sources tools/lib/fence-blank.sh" \
  "$(cat "$REPO_ROOT/tools/self/prose-drift.sh")" 'lib/fence-blank.sh'

# --- no re-duplicated copy of THIS FUNCTION anywhere else under tools/ --------------------------
# The bare ```/~~~ fence-marker regex is NOT itself the marker — it's a legitimate, independent
# building block several pre-existing tools already use for a DIFFERENT purpose (tools/doctor.sh x3,
# tools/keel-impact.sh x1 — all `{f=!f;next} !f`, which DROPS fenced lines outright rather than
# blanking them to preserve line alignment; verified these predate this file and serve config/registry
# parsing, not this ticket's line-number-preserving need). The marker below is the variable name this
# function's toggle uses, unique to its own body — a re-duplication of blank_fenced_blocks() ITSELF
# would carry it; the unrelated filter-style copies above do not.
marker='infence = !infence'
# `grep -rl` already IS the "which files contain it" scan a hand-rolled find+while loop would
# rebuild line by line; only the lib's own match, plus any allowlisted intentional copy, needs
# excluding from the result. An array, not a bare scalar, matching the allowlist shape doctor.sh's
# own slash-command check already uses (harness_commands/not_commands, tools/self/doctor.sh) — a
# second legitimate exception is then one more element, not a second `grep -vF` to chain.
# tools/changelog-section.sh keeps its own copy ON PURPOSE (its own comment names dir #26's
# "capture only, do not pre-build a shared lib" standing): it is meant to be copy-portable as a
# single file on its own — tests/test_changelog_section.sh's own fixture copies only that one file
# into a sandbox to prove exactly that — and sourcing the shared lib would break that portability.
# A second, unlisted copy anywhere else is still a real finding.
allowlisted_dup_sites=("$REPO_ROOT/tools/changelog-section.sh")
hits="$(grep -rlF "$marker" "$REPO_ROOT/tools" 2>/dev/null | grep -vF "$lib" \
  | grep -vFf <(printf '%s\n' "${allowlisted_dup_sites[@]}") || true)"
if [ -z "$hits" ]; then
  pass "no duplicated fence-toggle pattern outside tools/lib/fence-blank.sh"
else
  fail "no duplicated fence-toggle pattern outside tools/lib/fence-blank.sh" "found in: $hits"
fi

# --- the lib itself blanks fenced content while preserving line count/alignment -----------------
# shellcheck source=/dev/null
. "$lib"
d="$(new_repo)"
printf 'before\n```\nfenced long line %s\n```\nafter\n' "$(rep x 200)" > "$d/f.md"
out="$(blank_fenced_blocks "$d/f.md")"
line_count="$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
if [ "$line_count" = 5 ]; then
  pass "blank_fenced_blocks preserves line count (5)"
else
  fail "blank_fenced_blocks preserves line count (5)" "got $line_count"
fi
check_contains "the line before the fence survives" "$out" "before"
check_contains "the line after the fence survives" "$out" "after"
check_absent "the fenced long line is blanked out" "$out" "fenced long line"
check_absent "the fence markers themselves are blanked too" "$out" '```'

# --- fence_marker_lines (dir #907) lists exactly the lines blank_fenced_blocks toggles on: rebuilding the blanked
# text by toggling at the listed lines gives blank_fenced_blocks' own output, every marker shape included ----------
printf 'text\n```sh\ncode\n```\nbetween\n  ~~~\ntilde code\n~~~\nafter\n````\ninner\n````\ntail\n' > "$d/m.md"
check_eq "fence_marker_lines lists every marker line" "2 4 6 8 10 12" "$(fence_marker_lines "$d/m.md" | tr '\n' ' ' | sed 's/ $//')"
rebuilt="$(fence_marker_lines "$d/m.md" | awk 'NR == FNR { m[$1] = 1; next }
  FNR in m { f = !f; print ""; next } f { print ""; next } { print }' - "$d/m.md")"
check_eq "toggling at those lines reproduces blank_fenced_blocks' output" "$(blank_fenced_blocks "$d/m.md")" "$rebuilt"

# --- blank_inline_code_spans (dir #240 item 3): drops an INLINE `code span` on a line; text outside
# any span, on the same or a different line, survives --------------------------------------------
out="$(printf 'before `[x](#nope)` after\nplain line\n' | blank_inline_code_spans)"
check_contains "text before the span survives" "$out" "before"
check_contains "text after the span survives" "$out" "after"
check_absent "the span's own content is dropped" "$out" "nope"
check_absent "the backticks themselves are dropped too" "$out" '`'
check_contains "an unrelated line is untouched" "$out" "plain line"

# --- NUL contract (dir #917): a NUL in the input must not shift line numbers, under ANY awk. busybox awk (the alpine
# leg's) turns a NUL into a newline, which re-splits the line; the lib strips NULs first so cloud-brief's line numbers
# (applied to the raw file) stay aligned. Run under whichever awk is the system's AND, when a busybox binary exists
# on a non-alpine host, under busybox awk too (a PATH shim) so the shift is exercised everywhere --------------------
printf 'one\n```\nfen\0ced\n```\nfive\0six\nseven\n' > "$d/nul.md"
check_eq "NUL fixture: blank_fenced_blocks keeps the raw file's line count (system awk)" 6 "$(blank_fenced_blocks "$d/nul.md" | wc -l | tr -d ' ')"
check_eq "NUL fixture: fence_marker_lines numbers the raw file's lines (system awk)" "2 4" "$(fence_marker_lines "$d/nul.md" | tr '\n' ' ' | sed 's/ $//')"
if command -v busybox >/dev/null 2>&1 && busybox awk 'BEGIN { exit 0 }' >/dev/null 2>&1; then
  mkdir "$d/bbbin" && ln -s "$(command -v busybox)" "$d/bbbin/awk"
  check_eq "NUL fixture: blank_fenced_blocks keeps the raw file's line count (busybox awk)" 6 \
    "$(PATH="$d/bbbin:$PATH" blank_fenced_blocks "$d/nul.md" | wc -l | tr -d ' ')"
  check_eq "NUL fixture: fence_marker_lines numbers the raw file's lines (busybox awk)" "2 4" \
    "$(PATH="$d/bbbin:$PATH" fence_marker_lines "$d/nul.md" | tr '\n' ' ' | sed 's/ $//')"
else
  pass "no busybox binary on this host: the busybox-awk NUL legs run on the alpine CI leg (system awk there IS busybox)"
fi

# --- an unreadable input still fails (awk's exit 2 before the NUL strip), it is not read as an empty file
rc=0; blank_fenced_blocks "$d/absent.md" >/dev/null 2>&1 || rc=$?
check_eq "blank_fenced_blocks on a missing file exits 2" 2 "$rc"
rc=0; fence_marker_lines "$d/absent.md" >/dev/null 2>&1 || rc=$?
check_eq "fence_marker_lines on a missing file exits 2" 2 "$rc"

# --- header census (dir #917): every file under tools/ and commands/ that mentions blank_fenced_blocks is named in the
# lib's header, so a new caller (or a rename) cannot leave the adopter-facing-callers list stale -----------------------
header="$(sed -n '/^[^#]/q;p' "$lib")"
census="$(cd "$REPO_ROOT" && grep -rl blank_fenced_blocks tools commands | grep -vx 'tools/lib/fence-blank.sh' | sort)"
missing=""
for f in $census; do
  case "$header" in *"$f"*) ;; *) missing="$missing $f" ;; esac
done
if [ -z "$missing" ]; then
  pass "the lib header names every file the blank_fenced_blocks census finds"
else
  fail "the lib header names every file the blank_fenced_blocks census finds" "not named:$missing"
fi
check_contains "the header states busybox awk's NUL behaviour" "$header" "busybox awk turns a NUL into a newline"
check_contains "the header states the measured result" "$header" "measured"

summary
