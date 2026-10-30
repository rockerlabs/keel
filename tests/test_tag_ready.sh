#!/usr/bin/env bash
# tools/self/tag-ready.sh (dir #867): the pre-tag gate on a `[PLACEHOLDER` marker, driven against fixture repos.
# Deliberately NOT a check on the real HEAD: a cut PR may carry the marker, so that would turn it red.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh" || { echo "lib.sh missing — refusing to run outside the sandbox" >&2; exit 1; }

tool="$REPO_ROOT/tools/self/tag-ready.sh"
# the expected hit lines, held in variables so this file carries no literal path:LINE citation (line-citations.sh)
hist_ln=6; log_ln=8
check_file "tools/self/tag-ready.sh exists" "$tool"

# mk_fx — a fixture repo with a clean docs/release-history.md and CHANGELOG.md, committed. Prints its path.
mk_fx() {
  local d; d="$(mktemp -d "$SANDBOX/fx.XXXXXX")"
  mkdir -p "$d/docs"
  printf '# Release history\n\n## v1.0.0 — 2025-12-31\n\n**Verification.** **Scope:** 3 files.\n' > "$d/docs/release-history.md"
  printf '# Changelog\n\n## [Unreleased]\n\n## [1.0.0] — 2025-12-31\n\n- the first release\n' > "$d/CHANGELOG.md"
  printf '# readme\n' > "$d/README.md"
  git -C "$d" init -q
  git -C "$d" add -A
  git -C "$d" -c user.name=fx -c user.email=fx@example.invalid commit -qm seed
  printf '%s' "$d"
}
# commit_all DIR — commit whatever the fixture holds now.
commit_all() { git -C "$1" add -A && git -C "$1" -c user.name=fx -c user.email=fx@example.invalid commit -qm "$2"; }

run_in "$SANDBOX" bash "$tool" --help
check_status "--help -> exit 0" 0 "$STATUS"
check_contains "--help prints usage" "$OUT" "Usage:"
fx="$(mk_fx)"
run_in "$fx" bash "$tool" --bogus
check_status "unknown flag -> exit 2" 2 "$STATUS"
run_in "$fx" bash "$tool" HEAD HEAD
check_status "two revs -> exit 2" 2 "$STATUS"
run_in "$fx" bash "$tool" ""
check_status "an empty rev (an unset \$SHA) -> exit 2, never HEAD" 2 "$STATUS"
run_in "$fx" bash "$tool" no-such-rev
check_status "an unresolvable rev -> exit 2" 2 "$STATUS"
notrepo="$(mktemp -d "$SANDBOX/plain.XXXXXX")"
run_in "$notrepo" env GIT_CEILING_DIRECTORIES="$SANDBOX" bash "$tool"
check_status "outside a git work tree -> exit 2" 2 "$STATUS"

run_in "$fx" bash "$tool"
check_status "clean fixture -> exit 0" 0 "$STATUS"
check_contains "...says so" "$OUT" "no [PLACEHOLDER marker"

# the 0.16.0 shape: a hand-written placeholder Verification block in the history entry
printf '**Verification.** **Scope:** [PLACEHOLDER — filled from the audit GO record at the tag.]\n' >> "$fx/docs/release-history.md"
commit_all "$fx" "placeholder in history"
run_in "$fx" bash "$tool"
check_status "a [PLACEHOLDER in release-history.md -> exit 1" 1 "$STATUS"
check_contains "...names the file and line" "$OUT" "docs/release-history.md:${hist_ln}:"
check_contains "...and says what to do" "$OUT" "fill it from the audit GO record"
bad_rev="$(git -C "$fx" rev-parse HEAD)"

# filled in the next commit: HEAD passes, the earlier rev still fails
sed '$d' "$fx/docs/release-history.md" > "$fx/h.tmp" && mv "$fx/h.tmp" "$fx/docs/release-history.md"
commit_all "$fx" "filled"
run_in "$fx" bash "$tool"
check_status "the filled entry at HEAD -> exit 0" 0 "$STATUS"
run_in "$fx" bash "$tool" "$bad_rev"
check_status "...and the earlier placeholder commit, named by rev -> exit 1" 1 "$STATUS"

# the same marker in CHANGELOG.md, in lower case
printf -- '- a [placeholder] bullet\n' >> "$fx/CHANGELOG.md"
commit_all "$fx" "marker in changelog"
run_in "$fx" bash "$tool"
check_status "a lower-case [placeholder in CHANGELOG.md -> exit 1" 1 "$STATUS"
check_contains "...names CHANGELOG.md" "$OUT" "CHANGELOG.md:${log_ln}:"
git -C "$fx" reset -q --hard HEAD~1

# committed content only: an uncommitted marker is not read
printf '[PLACEHOLDER]\n' >> "$fx/docs/release-history.md"
run_in "$fx" bash "$tool"
check_status "an uncommitted marker in the working copy -> exit 0 (committed content only)" 0 "$STATUS"
git -C "$fx" checkout -q -- docs/release-history.md

# scope: a marker in any other file is not this gate's business
printf '[PLACEHOLDER]\n' >> "$fx/README.md"
commit_all "$fx" "marker elsewhere"
run_in "$fx" bash "$tool"
check_status "a marker only in README.md -> exit 0 (scope is the two named files)" 0 "$STATUS"

# refuse to pass on a missing file
git -C "$fx" rm -q docs/release-history.md
commit_all "$fx" "history removed"
run_in "$fx" bash "$tool"
check_status "release-history.md absent at the rev -> exit 2" 2 "$STATUS"
check_contains "...names the file" "$OUT" "docs/release-history.md is absent"

run_in "$fx" env GIT_CONFIG_PARAMETERS="'grep.threads=abc'" bash "$tool" "$bad_rev"
check_status "git grep failing (a bad grep.threads) on a placeholder commit -> exit 2, never 0" 2 "$STATUS"

summary
