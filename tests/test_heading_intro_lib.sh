#!/usr/bin/env bash
# test_heading_intro_lib.sh — dir #428: tools/lib/heading-intro.sh is the ONE walk that finds the commit that
# introduced a heading into a tracked file (tools/self/doctor.sh and tests/test_release_history.sh both call
# it). Direct cases for what the two parallel copies each had to get right: the line anchor, the fenced
# decoy, a removal commit, the git-failure status; plus a source-level pin that both callers use the lib.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

lib="$REPO_ROOT/tools/lib/heading-intro.sh"
check_file "tools/lib/heading-intro.sh exists" "$lib"
# shellcheck source=tools/lib/heading-intro.sh
. "$lib"
# shellcheck source=tools/lib/regex-escape.sh
. "$REPO_ROOT/tools/lib/regex-escape.sh"

repo="$SANDBOX/repo"; mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" config user.email t@example.invalid
git -C "$repo" config user.name t
commit() { git -C "$repo" add -A && git -C "$repo" commit -qm "$1" && git -C "$repo" rev-parse HEAD; }
re_for() { printf '^%s' "$(escape_bre_literal "## [$1]")"; }
walk() { local rc=0 out; out="$(heading_intro_commit "$repo" CHANGELOG.md "$(re_for "$1")")" || rc=$?; WALK_RC=$rc; WALK_OUT="$out"; }

# 1. the plain case: the introducing commit, not a later one.
printf '# Changelog\n\n## [1.0.0]\n- a\n' > "$repo/CHANGELOG.md"; c1="$(commit one)"
printf '\n- more\n' >> "$repo/CHANGELOG.md"; commit later >/dev/null
walk 1.0.0
check_eq "plain heading -> the commit that added it" "$c1" "$WALK_OUT"; check_eq "  status 0" 0 "$WALK_RC"

# 2. the v0.9.0-cut class (dir #299): an inline prose MENTION earlier must not be taken as the heading.
printf '# Changelog\n\nSee `## [2.0.0]` for the plan.\n\n## [1.0.0]\n- a\n' > "$repo/CHANGELOG.md"; commit mention >/dev/null
printf '# Changelog\n\nSee `## [2.0.0]` for the plan.\n\n## [2.0.0]\n- b\n\n## [1.0.0]\n- a\n' > "$repo/CHANGELOG.md"; c2="$(commit cut2)"
walk 2.0.0
check_eq "an inline mention is skipped: the real heading's commit wins" "$c2" "$WALK_OUT"

# 3. a fenced example holding a literal heading is a decoy, skipped for the real one.
printf '# Changelog\n\n## [3.0.0]\n- c\n' > "$repo/CHANGELOG.md"; c3="$(commit real3)"
printf '# Changelog\n\n## [3.0.0]\n- c\n\n```\n## [3.0.0]\n```\n' > "$repo/CHANGELOG.md"; commit fencedecoy >/dev/null
walk 3.0.0
check_eq "a fence-only re-mention is a decoy: the real introducing commit wins" "$c3" "$WALK_OUT"

# 4. a heading that never appears: nothing printed, status 0 (the designed fail-open).
walk 9.9.9
check_eq "absent heading -> empty output" '' "$WALK_OUT"; check_eq "  status 0" 0 "$WALK_RC"

# 5. a commit that REMOVED the file is a pickaxe hit with the blob absent: not a failure, and not the answer.
git -C "$repo" rm -q CHANGELOG.md && commit rmfile >/dev/null
walk 3.0.0
check_eq "removal commit skipped: the walk still reaches the introducing commit" "$c3" "$WALK_OUT"; check_eq "  and not a failure" 0 "$WALK_RC"

# 6. git itself failing is status 2 (the caller GAPs), not an empty success.
rc=0; heading_intro_commit "$repo/not-a-repo" CHANGELOG.md '^## \[1\.0\.0\]' >/dev/null 2>&1 || rc=$?
check_eq "git failure -> status 2" 2 "$rc"


# Source-level pin: both callers use the lib and neither re-derives the walk.
for f in tools/self/doctor.sh tests/test_release_history.sh; do
  if grep -q 'heading_intro_commit' "$REPO_ROOT/$f"; then pass "$f calls heading_intro_commit"
  else fail "$f calls heading_intro_commit" "no call found"; fi
done
dups="$(grep -rlE 'git .*log -G' "$REPO_ROOT/tools" "$REPO_ROOT/tests" 2>/dev/null | grep -vF -e "$lib" -e test_heading_intro_lib.sh || true)"
check_eq "no other tool or test re-derives a log -G heading walk" '' "$dups"

summary
