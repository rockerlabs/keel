#!/usr/bin/env bash
# doctor — GAP (fails the audit) vs WARN (advisory), the public-fork special case, and the
# --registry sweep over an INSTANCE.md Projects table.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

doctor="$REPO_ROOT/tools/doctor.sh"
mkproj() { mktemp -d "$SANDBOX/proj.XXXXXX"; }

# GAP: not a git repo
d="$(mkproj)"
run "$doctor" "$d"
check_status "bare dir → GAP exit 1" 1 "$STATUS"
check_contains "reports not-a-git-repo" "$OUT" "not a git repo"

# GAP: git repo, but no project CLAUDE.md
d="$(mkproj)"; git -C "$d" init -q
printf 'CLAUDE.md\n.claude/\n' > "$d/.gitignore"
run "$doctor" "$d"
check_status "missing CLAUDE.md → GAP exit 1" 1 "$STATUS"
check_contains "reports missing CLAUDE.md" "$OUT" "no project CLAUDE.md"

# GAP: CLAUDE.md present, untracked, but .gitignore does not ignore the private context
d="$(mkproj)"; git -C "$d" init -q
printf '# ctx\n' > "$d/CLAUDE.md"
printf '*.log\n' > "$d/.gitignore"
run "$doctor" "$d"
check_status "unignored private context → GAP exit 1" 1 "$STATUS"
check_contains "reports gitignore gap" "$OUT" "does not ignore the private AI context"

# clean baseline → exit 0 (an un-wired secret-guard is a WARN, not a GAP)
d="$(mkproj)"; git -C "$d" init -q
printf '# ctx\n' > "$d/CLAUDE.md"
printf 'CLAUDE.md\n.claude/\n' > "$d/.gitignore"
run "$doctor" "$d"
check_status "clean baseline → exit 0" 0 "$STATUS"
check_contains "reports baseline OK" "$OUT" "baseline OK"

# public fork: a tracked CLAUDE.md is deliberate, so no gitignore GAP
d="$(mkproj)"; git -C "$d" init -q
printf '# public ctx\n' > "$d/CLAUDE.md"
printf '*.log\n' > "$d/.gitignore"
git -C "$d" add CLAUDE.md
git -C "$d" commit -qm add
run "$doctor" "$d"
check_status "public fork (tracked CLAUDE.md) → exit 0" 0 "$STATUS"
check_absent "no gitignore GAP for public fork" "$OUT" "does not ignore"

# footprint over budget is advisory: WARN but still exit 0
d="$(mkproj)"; git -C "$d" init -q
printf 'plenty of startup context goes here\n' > "$d/CLAUDE.md"
printf 'CLAUDE.md\n.claude/\n' > "$d/.gitignore"
run env KEEL_STARTUP_WARN_TOKENS=1 "$doctor" "$d"
check_status "footprint over budget → still exit 0" 0 "$STATUS"
check_contains "reports footprint WARN" "$OUT" "footprint"

# --registry: sweep an INSTANCE.md Projects table, skipping the unfilled placeholder row
good="$(mkproj)"; git -C "$good" init -q
printf '# ctx\n' > "$good/CLAUDE.md"
printf 'CLAUDE.md\n.claude/\n' > "$good/.gitignore"
reg="$SANDBOX/INSTANCE.md"
{
  printf '| Project | Path | CLAUDE.md | Tag |\n'
  printf '|---------|------|-----------|-----|\n'
  printf '| <name> | <abs path> | <link> | <lang> |\n'
  printf '| good | %s | link | bash |\n' "$good"
} > "$reg"
run "$doctor" --registry "$reg"
check_status "--registry clean sweep → exit 0" 0 "$STATUS"
check_contains "--registry visited the real project" "$OUT" "$(basename "$good")"

# --registry: a missing registry file is a usage error → exit 2
run "$doctor" --registry "$SANDBOX/nope.md"
check_status "--registry missing file → exit 2" 2 "$STATUS"

summary
