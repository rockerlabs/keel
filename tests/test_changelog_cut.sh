#!/usr/bin/env bash
# tools/self/changelog-cut.sh (dir #744 slice 1, B17): the release cut's one CHANGELOG transform.
# Covers the happy path (legacy bullet then fragments in FILENAME order, a fresh empty [Unreleased], the
# fragments gone, README kept, mode kept), a cut with no fragments, every refusal (exit 2, file
# unchanged), a second run, and a cut that stopped after its mv (leftover fragments named as assembled).
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

cut="$REPO_ROOT/tools/self/changelog-cut.sh"

# --- --help / bad arguments ---------------------------------------------------------------------
run "$cut" --help
check_status "--help -> exit 0" 0 "$STATUS"
check_contains "--help prints usage" "$OUT" "Usage:"
run "$cut"
check_status "no arguments -> exit 2" 2 "$STATUS"
run "$cut" 9.9.9
check_status "VERSION without DATE -> exit 2" 2 "$STATUS"
run "$cut" --bogus 9.9.9 2026-01-01
check_status "unknown flag -> exit 2" 2 "$STATUS"
run "$cut" --repo /no/such/dir 9.9.9 2026-01-01
check_status "missing --repo directory -> exit 2" 2 "$STATUS"

# mk_repo — a fixture repo (no git needed: the tool never runs git) with a CHANGELOG.md holding one
# legacy bullet under [Unreleased] and a released 1.0.0, plus changelog.d/ with README.md and two fragments
# created in REVERSE name order (so mtime order differs from filename order).
mk_repo() {
  local d; d="$(mktemp -d "$SANDBOX/cut.XXXXXX")"
  mkdir -p "$d/changelog.d"
  printf '# Changelog\n\nintro text\n\n## [Unreleased]\n\n- legacy bullet\n  continued\n\n## [1.0.0] — 2025-12-31\n\n- the first release\n' \
    > "$d/CHANGELOG.md"
  chmod 644 "$d/CHANGELOG.md"
  printf '# readme\n' > "$d/changelog.d/README.md"
  printf '%s\n' '- dir #2: the second one' > "$d/changelog.d/2-b.md"
  sleep 1
  printf '%s\n' '- dir #1: the first one' '  with a continuation' > "$d/changelog.d/1-a.md"
  printf '%s' "$d"
}
mode_of() { ls -l "$1" | cut -c1-10; }

# --- the happy path -----------------------------------------------------------------------------
d="$(mk_repo)"
run "$cut" --repo "$d" 9.9.9 2026-01-01
check_status "cut -> exit 0" 0 "$STATUS"
check_contains "cut prints its steps (heading)" "$OUT" "renamed [Unreleased] to [9.9.9]"
check_contains "cut prints its steps (a deleted fragment)" "$OUT" "deleted changelog.d/1-a.md"
want="$(cat <<'EOF'
# Changelog

intro text

## [Unreleased]

## [9.9.9] — 2026-01-01

- legacy bullet
  continued

- dir #1: the first one
  with a continuation

- dir #2: the second one

## [1.0.0] — 2025-12-31

- the first release
EOF
)"
check_eq "one [9.9.9] section: legacy bullet, then fragments in filename order; fresh empty [Unreleased] above" \
  "$want" "$(cat "$d/CHANGELOG.md")"
check_nofile "fragment 1-a.md deleted" "$d/changelog.d/1-a.md"
check_nofile "fragment 2-b.md deleted" "$d/changelog.d/2-b.md"
check_file "README.md kept" "$d/changelog.d/README.md"
check_eq "CHANGELOG.md keeps its mode" "-rw-r--r--" "$(mode_of "$d/CHANGELOG.md")"
leftover=0
for f in "$d"/CHANGELOG.md.cut.*; do [ -e "$f" ] && leftover=$((leftover + 1)); done
check_eq "no temp file left behind" "0" "$leftover"

# --- the changelog keeps its 0644 mode when the umask would give a fresh file 0600 ----------------------
d="$(mk_repo)"
chmod 644 "$d/CHANGELOG.md"
run bash -c 'umask 077; exec "$@"' _ "$cut" --repo "$d" 9.9.9 2026-01-01
check_status "cut under umask 077 -> exit 0" 0 "$STATUS"
check_eq "CHANGELOG.md keeps 0644 under umask 077 (written over, not replaced by a fresh file)" "-rw-r--r--" "$(mode_of "$d/CHANGELOG.md")"

# --- a second run refuses, changing nothing -------------------------------------------------------
before="$(cat "$d/CHANGELOG.md")"
run "$cut" --repo "$d" 9.9.9 2026-01-01
check_status "second run -> exit 2" 2 "$STATUS"
check_contains "second run names the existing section" "$OUT" "## [9.9.9] is already in CHANGELOG.md"
check_eq "second run leaves CHANGELOG.md unchanged" "$before" "$(cat "$d/CHANGELOG.md")"

# --- a cut that stopped after its mv: the version is there AND fragments are left ------------------
d="$(mk_repo)"
run "$cut" --repo "$d" 9.9.9 2026-01-01
printf '%s\n' '- dir #1: the first one' > "$d/changelog.d/1-a.md"      # the leftover the interrupted run never deleted
printf '%s\n' '- dir #3: arrived after the cut ran' > "$d/changelog.d/3-late.md"   # merged after the cut
before="$(cat "$d/CHANGELOG.md")"
run "$cut" --repo "$d" 9.9.9 2026-01-01
check_status "rerun after a stopped cut -> exit 2" 2 "$STATUS"
check_contains "refusal labels the leftover whose bullet is already in the section 'assembled'" "$OUT" "changelog.d/1-a.md — assembled"
check_contains "refusal labels a fragment whose bullet is not in the section 'late'" "$OUT" "changelog.d/3-late.md — late"
check_eq "refusal changes nothing" "$before" "$(cat "$d/CHANGELOG.md")"
check_file "the leftover fragment is still there (not deleted by a refusal)" "$d/changelog.d/1-a.md"
check_file "the late fragment is still there too" "$d/changelog.d/3-late.md"

# --- other refusals, each exit 2 with the file unchanged ------------------------------------------
refuses() {   # refuses LABEL EXPECTED-WORDS REPO VERSION DATE
  local before; before="$(cat "$3/CHANGELOG.md")"
  run "$cut" --repo "$3" "$4" "$5"
  check_status "refuses: $1 -> exit 2" 2 "$STATUS"
  check_contains "refuses: $1 -> says why" "$OUT" "$2"
  check_eq "refuses: $1 -> CHANGELOG.md unchanged" "$before" "$(cat "$3/CHANGELOG.md")"
  check_file "refuses: $1 -> fragments untouched" "$3/changelog.d/2-b.md"
}

d="$(mk_repo)"
refuses "a bad DATE (2026-1-1)" "is not YYYY-MM-DD" "$d" 9.9.9 2026-1-1
refuses "a bad DATE (month 13)" "is not YYYY-MM-DD" "$d" 9.9.9 2026-13-01
refuses "a bad VERSION (v9.9.9)" "is not x.y.z" "$d" v9.9.9 2026-01-01
refuses "a bad VERSION (9.9)" "is not x.y.z" "$d" 9.9 2026-01-01
refuses "an existing release section" "is already in CHANGELOG.md" "$d" 1.0.0 2026-01-01

d="$(mk_repo)"
printf '\n## [Unreleased]\n\n- a second one\n' >> "$d/CHANGELOG.md"
refuses "two [Unreleased] headings" "2 '## [Unreleased]' headings" "$d" 9.9.9 2026-01-01

d="$(mk_repo)"
printf '%s\n' '### Added' '- x' > "$d/changelog.d/3-bad.md"
refuses "a fragment with '### Added'" "changelog-fragments.sh --check fails" "$d" 9.9.9 2026-01-01

d="$(mk_repo)"
printf 'no unreleased heading here\n' > "$d/CHANGELOG.md"
run "$cut" --repo "$d" 9.9.9 2026-01-01
check_status "refuses: no [Unreleased] -> exit 2" 2 "$STATUS"

d="$(mktemp -d "$SANDBOX/nocl.XXXXXX")"
run "$cut" --repo "$d" 9.9.9 2026-01-01
check_status "refuses: no CHANGELOG.md -> exit 2" 2 "$STATUS"

# A `## [Unreleased]` inside a fenced example is not a section.
d="$(mk_repo)"
printf '\nExample:\n\n```\n## [Unreleased]\n```\n' >> "$d/CHANGELOG.md"
run "$cut" --repo "$d" 9.9.9 2026-01-01
check_status "a fenced '## [Unreleased]' example is not counted -> cut succeeds" 0 "$STATUS"

# --- no fragments: rename + fresh [Unreleased] only ------------------------------------------------
d="$(mk_repo)"
rm -f "$d/changelog.d/1-a.md" "$d/changelog.d/2-b.md"
run "$cut" --repo "$d" 9.9.9 2026-01-01
check_status "no fragments -> exit 0" 0 "$STATUS"
want="$(cat <<'EOF'
# Changelog

intro text

## [Unreleased]

## [9.9.9] — 2026-01-01

- legacy bullet
  continued

## [1.0.0] — 2025-12-31

- the first release
EOF
)"
check_eq "no fragments: only the rename and a fresh [Unreleased]" "$want" "$(cat "$d/CHANGELOG.md")"
check_file "README.md kept" "$d/changelog.d/README.md"

# No changelog.d/ at all behaves the same.
d="$(mk_repo)"
rm -f "$d/changelog.d/"*
rmdir "$d/changelog.d"
run "$cut" --repo "$d" 9.9.9 2026-01-01
check_status "no changelog.d/ -> exit 0" 0 "$STATUS"

# An empty [Unreleased] body: the fragments follow the heading directly.
d="$(mk_repo)"
printf '# Changelog\n\n## [Unreleased]\n\n## [1.0.0] — 2025-12-31\n\n- the first release\n' > "$d/CHANGELOG.md"
run "$cut" --repo "$d" 9.9.9 2026-01-01
check_status "empty [Unreleased] body, fragments present -> exit 0" 0 "$STATUS"
want="$(cat <<'EOF'
# Changelog

## [Unreleased]

## [9.9.9] — 2026-01-01

- dir #1: the first one
  with a continuation

- dir #2: the second one

## [1.0.0] — 2025-12-31

- the first release
EOF
)"
check_eq "empty body: fragments straight under the new heading" "$want" "$(cat "$d/CHANGELOG.md")"

# [Unreleased] as the last section (no release below it).
d="$(mk_repo)"
printf '# Changelog\n\n## [Unreleased]\n\n- only bullet\n' > "$d/CHANGELOG.md"
run "$cut" --repo "$d" 9.9.9 2026-01-01
check_status "[Unreleased] is the last section -> exit 0" 0 "$STATUS"
check_eq "last section: nothing follows the cut section" "$(printf '# Changelog\n\n## [Unreleased]\n\n## [9.9.9] — 2026-01-01\n\n- only bullet\n\n- dir #1: the first one\n  with a continuation\n\n- dir #2: the second one')" "$(cat "$d/CHANGELOG.md")"


# A body that ends in a fenced block keeps its fence (the last non-blank line is found on the RAW file).
d="$(mk_repo)"
printf '# Changelog\n\n## [Unreleased]\n\n- bullet with a block:\n  ```\n  code\n  ```\n\n## [1.0.0] — 2025-12-31\n\n- the first release\n' > "$d/CHANGELOG.md"
rm -f "$d/changelog.d/1-a.md" "$d/changelog.d/2-b.md"
run "$cut" --repo "$d" 9.9.9 2026-01-01
check_status "a body ending in a fenced block -> exit 0" 0 "$STATUS"
want="$(printf '# Changelog\n\n## [Unreleased]\n\n## [9.9.9] — 2026-01-01\n\n- bullet with a block:\n  ```\n  code\n  ```\n\n## [1.0.0] — 2025-12-31\n\n- the first release')"
check_eq "the closing fence survives the cut" "$want" "$(cat "$d/CHANGELOG.md")"

# Nothing at all to carry (empty body, no fragments): exactly one blank line before the next section.
d="$(mk_repo)"
printf '# Changelog\n\n## [Unreleased]\n\n## [1.0.0] — 2025-12-31\n\n- the first release\n' > "$d/CHANGELOG.md"
rm -f "$d/changelog.d/1-a.md" "$d/changelog.d/2-b.md"
run "$cut" --repo "$d" 9.9.9 2026-01-01
want="$(printf '# Changelog\n\n## [Unreleased]\n\n## [9.9.9] — 2026-01-01\n\n## [1.0.0] — 2025-12-31\n\n- the first release')"
check_eq "an empty cut leaves no doubled blank line" "$want" "$(cat "$d/CHANGELOG.md")"

# An unclosed fence in CHANGELOG.md would hide every later heading: refused, nothing changed.
d="$(mk_repo)"
printf '# Changelog\n\n## [Unreleased]\n\n- bullet:\n  ```\n  never closed\n\n## [1.0.0] — 2025-12-31\n\n- the first release\n' > "$d/CHANGELOG.md"
refuses "an unclosed fence in CHANGELOG.md" "odd number of fence markers" "$d" 9.9.9 2026-01-01

# The lint runs BEFORE the already-present diagnosis: a malformed leftover fragment is refused with the lint's
# own message, never labelled assembled/late (it can be neither carried nor honestly judged).
d="$(mk_repo)"
run "$cut" --repo "$d" 9.9.9 2026-01-01
printf '%s\n' '### Added' '- dir #4: malformed leftover' > "$d/changelog.d/4-bad.md"
before="$(cat "$d/CHANGELOG.md")"
run "$cut" --repo "$d" 9.9.9 2026-01-01
check_status "already-present version + a malformed fragment -> exit 2" 2 "$STATUS"
check_contains "...the lint's message, not an assembled/late label" "$OUT" "changelog-fragments.sh --check fails"
check_absent "...and no label is invented for it" "$OUT" "4-bad.md — "
check_eq "...CHANGELOG.md unchanged" "$before" "$(cat "$d/CHANGELOG.md")"

# 'assembled' needs EVERY bullet of the fragment in the section: one missing and deleting the file would lose it.
d="$(mk_repo)"
run "$cut" --repo "$d" 9.9.9 2026-01-01
printf '%s\n' '- dir #1: the first one' '- dir #5: a second bullet that was never carried' > "$d/changelog.d/1-a.md"
run "$cut" --repo "$d" 9.9.9 2026-01-01
check_status "partly-carried leftover -> exit 2" 2 "$STATUS"
check_contains "a fragment with a bullet missing from the section is labelled late, not assembled" "$OUT" "changelog.d/1-a.md — late"
check_contains "...and the late message says to add the missing bullet(s), not the whole file" "$OUT" "not the whole file"

# A fully carried MULTI-bullet fragment is still 'assembled'.
d="$(mk_repo)"
printf '%s\n' '- dir #6: first of two' '- dir #7: second of two' > "$d/changelog.d/6-two.md"
run "$cut" --repo "$d" 9.9.9 2026-01-01
check_contains "precondition: bullet one was carried into the section" "$(cat "$d/CHANGELOG.md")" "- dir #6: first of two"
printf '%s\n' '- dir #6: first of two' '- dir #7: second of two' > "$d/changelog.d/6-two.md"
run "$cut" --repo "$d" 9.9.9 2026-01-01
check_contains "a fully carried multi-bullet leftover is assembled" "$OUT" "changelog.d/6-two.md — assembled"

summary
