#!/usr/bin/env bash
# changelog-section.sh (dir #162) — a CHANGELOG-section extraction helper, so the release-note
# command in docs/publishing-checklist.md §4 no longer needs a by-hand copy out of CHANGELOG.md.
# Two legs: (a) real output equals the section body for EVERY released version in this repo's own
# CHANGELOG (a loop over `git tag`, per the ticket's own acceptance test); (b) a fenced `## [x.y.z]`
# example inside the file must not be mistaken for a real heading.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

helper="$REPO_ROOT/tools/changelog-section.sh"

# --- arg validation --------------------------------------------------------------------------------
# dir #223: usage errors are exit 2, matching the two sibling tools from the same release
# (tools/drydock/inventory.sh, tools/self/prose-drift.sh) — only a "no matching section" data miss
# and a missing CHANGELOG.md stay exit 1, since those aren't malformed-invocation errors.

run "$helper"
check_status "no version arg -> exit 2 (usage error)" 2 "$STATUS"

run "$helper" not-a-version
check_status "non-semver version -> exit 2 (usage error)" 2 "$STATUS"

# regression: a bash-glob check (`[0-9]*.[0-9]*.[0-9]*`) would accept these — `*` matches any
# characters, not just digits — letting a non-semver string with unescaped ERE metacharacters
# reach the internal grep -E heading search instead of failing validation cleanly.
run "$helper" 0.6.1abc
check_status "semver-prefixed garbage -> exit 2, not silently accepted" 2 "$STATUS"

run "$helper" "1.2.3+(x)"
check_status "version with unescaped regex metacharacters -> exit 2" 2 "$STATUS"

run "$helper" 9.9.9
check_status "version with no matching section -> exit 1 (data miss, not a usage error)" 1 "$STATUS"
check_contains "explains the miss" "$OUT" "no \`## [9.9.9]\` section found"

run "$helper" 0.1.0 --bogus
check_status "unknown option -> exit 2 (usage error)" 2 "$STATUS"

run "$helper" 0.1.0 --digest extra-junk-arg
check_status "unexpected extra argument -> exit 2, not silently ignored" 2 "$STATUS"

# --- -h / --help (dir #223) --------------------------------------------------------------------

run "$helper" -h
check_status "-h -> exit 0" 0 "$STATUS"
check_contains "-h prints usage" "$OUT" "usage: changelog-section.sh"

run "$helper" --help
check_status "--help -> exit 0" 0 "$STATUS"
check_contains "--help prints usage" "$OUT" "usage: changelog-section.sh"

run "$helper" --edit
check_status "--edit with no further args -> exit 2 (usage error)" 2 "$STATUS"

run "$helper" --edit 0.1.0
check_status "--edit with a version but no notes-file -> exit 2 (usage error)" 2 "$STATUS"

# --- (a) real repo: helper output equals the section body for every released tag ------------------
# Mark REPO_ROOT safe: in a container (CI Alpine leg) the mounted repo is owned by a different uid
# than the runner, so git would refuse to fetch/read it ("dubious ownership", exit 128) — same guard
# as tests/test_install.sh's own fetch of $REPO_ROOT.
git config --global --add safe.directory '*'
# Reconciled per CORE's git rail: fetch first so the tag list is current, not a stale local picture.
git -C "$REPO_ROOT" fetch --prune --tags -q 2>/dev/null || true

# release_tag_versions (tests/lib.sh) is the shared tag-shape scan — promoted there (dir #232's own
# /code-review medium pass) once test_release_history.sh turned up a third independent copy of this
# exact regex.
tags="$(release_tag_versions "$REPO_ROOT" | sed 's/^v//' | sort -u)"
n_tags=0
n_matched=0
while IFS= read -r ver; do
  [ -n "$ver" ] || continue
  n_tags=$((n_tags + 1))
  # Independently derive the expected section body from CHANGELOG.md itself: the line range from
  # this version's `## [x.y.z]` heading up to (not including) the next `^## ` heading, trailing
  # blank lines trimmed the same way command substitution trims them in the helper's own output.
  start_line="$(grep -nE "^## \\[${ver//./\\.}\\]" "$REPO_ROOT/CHANGELOG.md" | head -1 | cut -d: -f1)"
  if [ -z "$start_line" ]; then
    fail "tag v$ver has a matching CHANGELOG section" "no \`## [$ver]\` heading found at all"
    continue
  fi
  next_line="$(tail -n "+$((start_line + 1))" "$REPO_ROOT/CHANGELOG.md" | grep -nE '^## ' | head -1 | cut -d: -f1)"
  if [ -n "$next_line" ]; then
    end_line=$((start_line + next_line - 1))
    expected="$(sed -n "${start_line},${end_line}p" "$REPO_ROOT/CHANGELOG.md")"
  else
    expected="$(sed -n "${start_line},\$p" "$REPO_ROOT/CHANGELOG.md")"
  fi
  run "$helper" "$ver"
  if [ "$STATUS" -eq 0 ] && [ "$OUT" = "$expected" ]; then
    n_matched=$((n_matched + 1))
    pass "v$ver: helper output equals the CHANGELOG section body"
  else
    fail "v$ver: helper output equals the CHANGELOG section body" "mismatch (see diff below if run by hand)"
  fi
done <<< "$tags"

# A silent 0/0 here (e.g. `git tag` unreachable — restricted-network CI, a shallow/tagless clone)
# would let this leg's whole acceptance test — exact-equality against every real release — pass by
# never running a single comparison. Fail loudly instead of no-op'ing.
if [ "$n_tags" -gt 0 ]; then
  # Each tag already pass/fail'd individually above; this is a summary assertion, not a duplicate —
  # it catches the case where every per-tag loop iteration was silently skipped for some OTHER reason
  # (e.g. a `continue` this file doesn't currently have) despite n_tags being nonzero.
  check_status "at least one released tag was exercised ($n_matched/$n_tags matched)" "$n_tags" "$n_matched"
else
  fail "at least one released tag was exercised" "no tags found at all (git tag -l 'v*' returned empty) — this leg ran zero real comparisons"
fi

# --- (b) a fenced example inside CHANGELOG.md is not mistaken for a real heading -------------------

fenced_repo="$SANDBOX/fenced-repo/tools"
mkdir -p "$fenced_repo"
cp "$helper" "$fenced_repo/changelog-section.sh"
cat > "$SANDBOX/fenced-repo/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased]

- work in progress

## [1.0.0] — 2026-01-01

Real release.

```
## [9.0.0] — not a real section, just an example inside a fence
### Fake
- this must not be picked up as a heading
```

More prose after the fence, still before the real subheading.

### Added
- the real thing
EOF

run "$fenced_repo/changelog-section.sh" 9.0.0
check_status "version only appearing inside a fence -> exit 1 (not fooled)" 1 "$STATUS"

run "$fenced_repo/changelog-section.sh" 1.0.0
check_status "real section still extracted -> exit 0" 0 "$STATUS"
check_contains "real section body included" "$OUT" "Real release."
check_contains "real section's own subheading included" "$OUT" "### Added"

# --- digest mode -------------------------------------------------------------------------------

run "$fenced_repo/changelog-section.sh" 1.0.0 --digest
check_status "digest mode -> exit 0" 0 "$STATUS"
check_contains "digest keeps the opener prose" "$OUT" "Real release."
check_contains "digest keeps the ### heading" "$OUT" "### Added"
check_absent "digest drops the heading's own bullet body" "$OUT" "the real thing"
# regression: a `### `-shaped line inside a FENCE within the section ("### Fake" above) must not be
# mistaken for a real subheading by digest mode's own heading scan — the same fence-safety digest
# mode already gets for the outer `##` section boundary. A prior version cut the opener off at the
# fenced fake heading instead of the real one, silently dropping the prose that follows the fence.
check_contains "digest is fence-safe: prose after the fence is still part of the opener" \
  "$OUT" "More prose after the fence"

# --- --edit mode (dir #189) ---------------------------------------------------------------------
# Stubbed $EDITOR via a fake editor script on PATH, not a real interactive editor, mirroring the
# three scenarios manually re-verified by hand across dir #162's own review rounds: unset EDITOR,
# a flag-carrying EDITOR (re-split correctly in both shells), and a failing editor exit code.

edit_repo="$SANDBOX/edit-repo"
mkdir -p "$edit_repo/tools" "$edit_repo/bin"
cp "$helper" "$edit_repo/tools/changelog-section.sh"
cat > "$edit_repo/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased]

## [1.0.0] — 2026-01-01

Real release.

### Added
- the real thing
EOF

# ok: appends a marker line to whatever file it's pointed at (last arg) and exits 0 — proves the
# script's own scratch file (not the caller's real file) is what the editor actually touched, and
# that the marked-up version is what lands in <notes-file>.
cat > "$edit_repo/bin/editor-ok.sh" <<'EOF'
#!/bin/sh
eval 'f="${'"$#"'}"'
printf '\nEDITED\n' >> "$f"
EOF
chmod +x "$edit_repo/bin/editor-ok.sh"

# fail: never touches the file, exits 1 — proves a failing editor leaves <notes-file> untouched.
cat > "$edit_repo/bin/editor-fail.sh" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$edit_repo/bin/editor-fail.sh"

# fail-after-write: writes real content, THEN exits nonzero — a --wait wrapper's own housekeeping
# failing, a window-close race, or a Ctrl-C can all leave genuine curated content behind even though
# the editor itself reports failure. Proves that content is not silently destroyed by the cleanup trap.
cat > "$edit_repo/bin/editor-fail-after-write.sh" <<'EOF'
#!/bin/sh
eval 'f="${'"$#"'}"'
printf '\nUSER TYPED THIS\n' >> "$f"
exit 3
EOF
chmod +x "$edit_repo/bin/editor-fail-after-write.sh"

notes_out="$SANDBOX/edit-notes-ok.md"
rm -f "$notes_out"
run env "EDITOR=$edit_repo/bin/editor-ok.sh" "$edit_repo/tools/changelog-section.sh" --edit 1.0.0 "$notes_out"
check_status "--edit with a working editor -> exit 0" 0 "$STATUS"
check_contains "notes-file gets the section body" "$(cat "$notes_out" 2>/dev/null)" "Real release."
check_contains "notes-file reflects the editor's own edit" "$(cat "$notes_out" 2>/dev/null)" "EDITED"

# flag-carrying $EDITOR: re-split correctly under both bash and zsh (the exact fix dir #162 landed
# for the standalone recipe — an unquoted `$EDITOR <file>` breaks in zsh whenever $EDITOR carries a
# flag). Run the helper itself under each shell explicitly.
for sh_bin in bash zsh; do
  if command -v "$sh_bin" >/dev/null 2>&1; then
    notes_flag="$SANDBOX/edit-notes-flag-$sh_bin.md"
    rm -f "$notes_flag"
    run env "EDITOR=$edit_repo/bin/editor-ok.sh --some-flag" "$sh_bin" "$edit_repo/tools/changelog-section.sh" --edit 1.0.0 "$notes_flag"
    check_status "--edit with a flag-carrying \$EDITOR under $sh_bin -> exit 0" 0 "$STATUS"
    check_contains "$sh_bin: notes-file still gets the edited content" "$(cat "$notes_flag" 2>/dev/null)" "EDITED"
  fi
done

notes_untouched="$SANDBOX/edit-notes-untouched.md"
printf 'SENTINEL\n' > "$notes_untouched"
run env "EDITOR=$edit_repo/bin/editor-fail.sh" "$edit_repo/tools/changelog-section.sh" --edit 1.0.0 "$notes_untouched"
check_status "--edit with a failing editor -> nonzero exit" 1 "$STATUS"
check_contains "notes-file is left untouched on editor failure" "$(cat "$notes_untouched")" "SENTINEL"

run env -u EDITOR "$edit_repo/tools/changelog-section.sh" --edit 1.0.0 "$SANDBOX/edit-notes-unset.md"
check_status "--edit with \$EDITOR unset -> nonzero exit" 1 "$STATUS"
check_contains "clear message, no bare \$EDITOR sigil (bash/zsh escaping trap)" "$OUT" "set the EDITOR environment variable"

# regression (medium code-review finding): an editor that WRITES real content and THEN exits
# nonzero must not have that content silently destroyed by the cleanup trap — only a `cp` failure
# was hardened this way before; an editor failure has to be too.
notes_after_write="$SANDBOX/edit-notes-fail-after-write.md"
rm -f "$notes_after_write"
run env "EDITOR=$edit_repo/bin/editor-fail-after-write.sh" "$edit_repo/tools/changelog-section.sh" --edit 1.0.0 "$notes_after_write"
check_status "--edit whose editor writes content then fails -> nonzero exit" 1 "$STATUS"
check_contains "notes-file itself still not written (editor failure never copies)" "$([ -f "$notes_after_write" ] && cat "$notes_after_write" || echo NOTHING_WRITTEN)" "NOTHING_WRITTEN"
check_contains "failure names a recoverable scratch-file path" "$OUT" "preserved at"
recovered_scratch="$(printf '%s\n' "$OUT" | sed -n 's/.*preserved at \(.*\)$/\1/p')"
check_contains "the scratch file with the user's real content actually survives on disk" \
  "$(cat "$recovered_scratch" 2>/dev/null)" "USER TYPED THIS"
rm -f "$recovered_scratch"

# regression (cross-model second-opinion review finding): a flag-shaped <notes-file> must not be
# read as a `cp` option — BSD and GNU `cp` disagree on unknown long options, so an unguarded `cp`
# would silently create a file literally named `--digest` on one platform and abort on the other.
notes_flag_shaped="$edit_repo/--digest"
rm -f "$notes_flag_shaped"
run_in "$edit_repo" env "EDITOR=$edit_repo/bin/editor-ok.sh" "$edit_repo/tools/changelog-section.sh" --edit 1.0.0 "--digest"
check_status "--edit with a flag-shaped notes-file -> exit 0, not swallowed as a cp option" 0 "$STATUS"
check_contains "the flag-shaped file is actually written, not silently dropped" "$(cat "$notes_flag_shaped" 2>/dev/null)" "Real release."
rm -f "$notes_flag_shaped"

# regression (cross-model second-opinion review finding): a `cp` failure after a successful edit
# must not discard the user's curated draft — the scratch file must survive so it can be recovered.
notes_bad_dir="$edit_repo/no-such-directory/out.md"
run env "EDITOR=$edit_repo/bin/editor-ok.sh" "$edit_repo/tools/changelog-section.sh" --edit 1.0.0 "$notes_bad_dir"
check_status "--edit whose cp destination fails -> nonzero exit" 1 "$STATUS"
check_contains "failure names a recoverable scratch-file path, not silent data loss" "$OUT" "your edited draft is preserved at"

summary
