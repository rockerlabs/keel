#!/usr/bin/env bash
# test_project_slug_lib.sh — dir #916: tools/lib/project-slug.sh is the one string-only encoder for Claude Code's
# project-directory names (every byte outside [A-Za-z0-9] → `-`). Pins the encoder on `/`, `.`, a space, `_` and a
# non-ASCII byte, that it is dependency-free, and that cloud-brief.sh, transcript-usage.sh and doctor.sh use it.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

lib="$REPO_ROOT/tools/lib/project-slug.sh"
check_file "tools/lib/project-slug.sh exists" "$lib"

# Dependency-free: sourced alone in a fresh shell it defines the function and sources nothing.
check_absent "the lib sources no other file" "$(grep -vE '^[[:space:]]*#' "$lib")" "source "
check_absent "the lib sources no other file (dot form)" "$(grep -vE '^[[:space:]]*#' "$lib")" ". \""
run bash -c '. "$1" && keel_project_slug "/Users/a b/.x_y/é/proj"' _ "$lib"
check_status "the encoder runs from a bare shell" 0 "$STATUS"
# `é` is two bytes in UTF-8 → two dashes (byte-wise, a documented limit).
check_eq "/ . space _ and a non-ASCII byte each become -" "$OUT" "-Users-a-b--x-y----proj"
run bash -c '. "$1" && keel_project_slug "/a/Z9z/0"' _ "$lib"
check_eq "letters and digits are kept" "$OUT" "-a-Z9z-0"
run bash -c '. "$1" && printf "[%s]" "$(keel_project_slug "")"' _ "$lib"
check_eq "the empty string encodes to nothing" "$OUT" "[]"
run bash -c '. "$1" && keel_project_slug "/no/such/dir/at.all"' _ "$lib"
check_eq "a path that does not exist still encodes (no directory is resolved)" "$OUT" "-no-such-dir-at-all"

# The callers use it: none keeps a private `/` and `.` encoder.
for c in tools/cloud-brief.sh tools/doctor.sh tools/lib/transcript-usage.sh; do
  check_contains "$c encodes through keel_project_slug" "$(cat "$REPO_ROOT/$c")" 'keel_project_slug'
done
check_absent "transcript-usage.sh has no private tr '/.' encoder" "$(grep -vE '^[[:space:]]*#' "$REPO_ROOT/tools/lib/transcript-usage.sh")" "tr '/.'"
check_absent "cloud-brief.sh has no private tr '/.' encoder" "$(grep -vE '^[[:space:]]*#' "$REPO_ROOT/tools/cloud-brief.sh")" "tr '/.'"
check_absent "doctor.sh has no private slash-dot encoder" "$(grep -vE '^[[:space:]]*#' "$REPO_ROOT/tools/doctor.sh")" 'enc="${cand//'

# tu_project_slug: resolves the directory, then the same encoding (a space and `_` now go too).
# shellcheck source=/dev/null
. "$REPO_ROOT/tools/lib/transcript-usage.sh"
d="$SANDBOX/odd dir_x/.hid"
mkdir -p "$d"
got="$(tu_project_slug "$d")"
want="$(printf '%s' "$(cd "$d" && pwd)" | tr -c 'A-Za-z0-9' '-')"
check_eq "tu_project_slug encodes every non-alphanumeric byte of the resolved path" "$got" "$want"
check_absent "tu_project_slug leaves no space or _" "$got" " "

summary
