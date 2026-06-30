#!/usr/bin/env bash
# doctor — GAP (fails the audit) vs WARN (advisory), the public-fork special case, and the
# --registry sweep over an INSTANCE.md Projects table.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

doctor="$REPO_ROOT/tools/doctor.sh"
mkproj() { mktemp -d "$SANDBOX/proj.XXXXXX"; }

# --help prints usage and exits 0 (not a raw `basename: illegal option` crash); unknown flag → exit 2
run "$doctor" --help
check_status "--help → exit 0" 0 "$STATUS"
check_contains "--help prints usage" "$OUT" "Usage:"
run "$doctor" --bogus
check_status "unknown flag → exit 2" 2 "$STATUS"

# GAP: not a git repo
d="$(mkproj)"
run "$doctor" "$d"
check_status "bare dir → GAP exit 1" 1 "$STATUS"
check_contains "reports not-a-git-repo" "$OUT" "not a git repo"

# GAP: git repo, no project CLAUDE.md, and CLAUDE.md is NOT gitignored (genuinely missing)
d="$(mkproj)"; git -C "$d" init -q
printf '.claude/\n' > "$d/.gitignore"   # ignores .claude/ (no gitignore GAP) but NOT CLAUDE.md
run "$doctor" "$d"
check_status "missing CLAUDE.md (not gitignored) → GAP exit 1" 1 "$STATUS"
check_contains "reports missing CLAUDE.md" "$OUT" "no project CLAUDE.md"

# WARN (not GAP): CLAUDE.md absent but gitignored (a private-fork / mechanism repo like Keel itself)
d="$(mkproj)"; git -C "$d" init -q
printf 'CLAUDE.md\n.claude/\n' > "$d/.gitignore"   # ignores CLAUDE.md; none present in this checkout
run "$doctor" "$d"
check_status "gitignored + absent CLAUDE.md → exit 0 (WARN, not GAP)" 0 "$STATUS"
check_contains "advises rather than GAPs" "$OUT" "gitignored (private/mechanism repo)"

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

# a git WORKTREE — where .git is a FILE, not a dir — must not be mis-detected as "not a git repo"
# (the same trap hits submodules). Regression for the [ -d .git ] → git rev-parse fix.
base="$(mkproj)"; git -C "$base" init -q
printf '# ctx\n' > "$base/CLAUDE.md"; printf 'CLAUDE.md\n.claude/\n' > "$base/.gitignore"
git -C "$base" add .gitignore
git -C "$base" -c user.email=t@keel.invalid -c user.name=t commit -qm init
wt="$SANDBOX/wt.$$"
git -C "$base" worktree add -q "$wt" >/dev/null 2>&1
run "$doctor" "$wt"
check_absent "git worktree not mis-flagged as non-repo" "$OUT" "not a git repo"
check_status "doctor on a worktree → exit 0" 0 "$STATUS"

# a LOCAL core.hooksPath override that carries no guard silently bypasses the machine-global secret-guard
# → WARN (advisory, exit 0). Regression: doctor used to assume "global wired ⇒ covered", missing the override.
d="$(mkproj)"; git -C "$d" init -q
printf '# ctx\n' > "$d/CLAUDE.md"; printf 'CLAUDE.md\n.claude/\n' > "$d/.gitignore"
mkdir -p "$d/emptyhooks"
git -C "$d" config core.hooksPath emptyhooks
run "$doctor" "$d"
check_status "local hooksPath override, no guard → exit 0 (WARN)" 0 "$STATUS"
check_contains "warns the override bypasses the guard" "$OUT" "silently bypassed"

# the same override, but it DOES carry the guard (an executable pre-commit) → no bypass WARN
d="$(mkproj)"; git -C "$d" init -q
printf '# ctx\n' > "$d/CLAUDE.md"; printf 'CLAUDE.md\n.claude/\n' > "$d/.gitignore"
mkdir -p "$d/hooks"; printf '#!/bin/sh\n' > "$d/hooks/pre-commit"; chmod +x "$d/hooks/pre-commit"
git -C "$d" config core.hooksPath hooks
run "$doctor" "$d"
check_absent "guarded local override → no bypass WARN" "$OUT" "silently bypassed"

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

# a non-numeric token budget falls back to the default instead of leaking a `[: integer expected`
d="$(mkproj)"; git -C "$d" init -q
printf '# ctx\n' > "$d/CLAUDE.md"; printf 'CLAUDE.md\n.claude/\n' > "$d/.gitignore"
run env KEEL_STARTUP_WARN_TOKENS=abc "$doctor" "$d"
check_status "non-numeric token budget → exit 0 (no crash)" 0 "$STATUS"
check_absent "no '[: integer expected' diagnostic" "$OUT" "integer expected"

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

# --registry: a table-shaped row inside a fenced code block is a doc example, not a real project
realp="$(mkproj)"; git -C "$realp" init -q
printf '# ctx\n' > "$realp/CLAUDE.md"; printf 'CLAUDE.md\n.claude/\n' > "$realp/.gitignore"
reg="$SANDBOX/INSTANCE-fenced.md"
{
  printf '| Project | Path | CLAUDE.md | Tag |\n'
  printf '|---------|------|-----------|-----|\n'
  printf '| real | %s | link | bash |\n' "$realp"
  printf '\n```\n'
  printf '| example | /nonexistent/should/be/ignored | link | bash |\n'
  printf '```\n'
} > "$reg"
run "$doctor" --registry "$reg"
check_status "fenced example row ignored → clean exit 0" 0 "$STATUS"
check_contains "real registry row still audited" "$OUT" "$(basename "$realp")"

# publication-bound project (.public-audit present) committing with a real email → WARN (not a GAP)
d="$(mkproj)"; git -C "$d" init -q
printf '# ctx\n' > "$d/CLAUDE.md"
printf 'CLAUDE.md\n.claude/\n' > "$d/.gitignore"
printf 'token: secret-name\n' > "$d/.public-audit"
git -C "$d" config user.email person@corp.com
run "$doctor" "$d"
check_status "publication project + real commit email → exit 0 (WARN)" 0 "$STATUS"
check_contains "doctor nudges about the commit email" "$OUT" "not a noreply address"

# dependency pinning (FRAMEWORK "Dependency versioning") — advisory WARN, never a GAP
newbase() {  # a GAP-free baseline project, prints its path
  local d; d="$(mkproj)"; git -C "$d" init -q
  printf '# ctx\n' > "$d/CLAUDE.md"; printf 'CLAUDE.md\n.claude/\n' > "$d/.gitignore"
  printf '%s' "$d"
}
d="$(newbase)"; printf 'FROM postgres:latest\n' > "$d/Dockerfile"
run "$doctor" "$d"
check_status "Docker :latest → still exit 0 (WARN)" 0 "$STATUS"
check_contains "warns about a floating dependency" "$OUT" "floating dependency version"

d="$(newbase)"; mkdir -p "$d/.github/workflows"
printf 'jobs:\n  x:\n    steps:\n      - uses: actions/checkout@v4\n' > "$d/.github/workflows/ci.yml"
run "$doctor" "$d"
check_contains "warns about a major-only Action tag" "$OUT" "floating dependency version"

d="$(newbase)"
printf 'FROM postgres:16.3\n' > "$d/Dockerfile"
mkdir -p "$d/.github/workflows"
printf 'jobs:\n  x:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: actions/checkout@v4.1.1\n' > "$d/.github/workflows/ci.yml"
run "$doctor" "$d"
check_absent "pinned deps + managed runner → no floating WARN" "$OUT" "floating dependency version"

summary
