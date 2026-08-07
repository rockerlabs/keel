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

# WARN (not GAP): a .keel/ marker exists but its ephemeral event log is NOT gitignored — it could leak
d="$(mkproj)"; git -C "$d" init -q
printf '# ctx\n' > "$d/CLAUDE.md"
printf 'CLAUDE.md\n.claude/\n' > "$d/.gitignore"   # baseline clean...
mkdir "$d/.keel"                                    # ...but the event log isn't ignored
run "$doctor" "$d"
check_status "unignored event log → exit 0 (WARN, not GAP)" 0 "$STATUS"
check_contains "warns about the unignored event log" "$OUT" "impact event log (.keel/impact-events.log) is not gitignored"

# ...and once the event log is ignored, the warning is gone (the out-of-the-box enable state). The ledger
# beside it stays trackable — ignoring only the log is exactly what `enable` / init-project do.
printf '/.keel/impact-events.log\n' >> "$d/.gitignore"
run "$doctor" "$d"
check_status "gitignored event log → exit 0" 0 "$STATUS"
check_absent "no warning once the event log is ignored" "$OUT" "impact event log (.keel/impact-events.log) is not gitignored"

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

# AGENTS.md (dir #75): the vendor sibling of CLAUDE.md for Codex/Cursor — absent, it stays silent
d="$(mkproj)"; git -C "$d" init -q
printf '# ctx\n' > "$d/CLAUDE.md"; printf 'CLAUDE.md\n.claude/\n' > "$d/.gitignore"
run "$doctor" "$d"
check_status "no AGENTS.md → exit 0" 0 "$STATUS"
check_absent "no AGENTS.md → no mention of it at all" "$OUT" "AGENTS.md"

# GAP: AGENTS.md exists, untracked, and .gitignore does not ignore it
d="$(mkproj)"; git -C "$d" init -q
printf '# ctx\n' > "$d/CLAUDE.md"; printf 'CLAUDE.md\n.claude/\n' > "$d/.gitignore"
ln -s CLAUDE.md "$d/AGENTS.md"
run "$doctor" "$d"
check_status "unignored AGENTS.md → GAP exit 1" 1 "$STATUS"
check_contains "reports the AGENTS.md gitignore gap" "$OUT" "does not ignore AGENTS.md"

# clean: AGENTS.md symlinked to CLAUDE.md, both ignored → exit 0, no gap/warn
d="$(mkproj)"; git -C "$d" init -q
printf '# ctx\n' > "$d/CLAUDE.md"; printf 'CLAUDE.md\nAGENTS.md\n.claude/\n' > "$d/.gitignore"
ln -s CLAUDE.md "$d/AGENTS.md"
run "$doctor" "$d"
check_status "symlinked + ignored AGENTS.md → exit 0" 0 "$STATUS"
check_absent "no AGENTS.md gap" "$OUT" "does not ignore AGENTS.md"
check_absent "no AGENTS.md inherit gap" "$OUT" "does not match CLAUDE.md's"
check_absent "no AGENTS.md drift warn" "$OUT" "drifted from CLAUDE.md"

# GAP: AGENTS.md's tracked/ignored status does not match CLAUDE.md's — CLAUDE.md ignored, AGENTS.md tracked
d="$(mkproj)"; git -C "$d" init -q
printf '# ctx\n' > "$d/CLAUDE.md"; printf 'CLAUDE.md\n.claude/\n' > "$d/.gitignore"
printf '# ctx\n' > "$d/AGENTS.md"
git -C "$d" add AGENTS.md
git -C "$d" commit -qm add
run "$doctor" "$d"
check_status "AGENTS.md/CLAUDE.md status mismatch → GAP exit 1" 1 "$STATUS"
check_contains "reports the status-inheritance gap" "$OUT" "does not match CLAUDE.md's"

# both tracked → deliberate public fork, no gap
d="$(mkproj)"; git -C "$d" init -q
printf '# public ctx\n' > "$d/CLAUDE.md"; printf '*.log\n' > "$d/.gitignore"
printf '# public ctx\n' > "$d/AGENTS.md"
git -C "$d" add CLAUDE.md AGENTS.md
git -C "$d" commit -qm add
run "$doctor" "$d"
check_status "both CLAUDE.md and AGENTS.md tracked → exit 0" 0 "$STATUS"
check_contains "reports the deliberate public fork" "$OUT" "AGENTS.md is tracked"
check_absent "no status-mismatch gap for matching tracked status" "$OUT" "does not match CLAUDE.md's"

# WARN (not GAP): AGENTS.md is a regular-file copy that has drifted from CLAUDE.md
d="$(mkproj)"; git -C "$d" init -q
printf '# ctx\n' > "$d/CLAUDE.md"; printf 'CLAUDE.md\nAGENTS.md\n.claude/\n' > "$d/.gitignore"
printf '# a stale drifted copy\n' > "$d/AGENTS.md"
run "$doctor" "$d"
check_status "drifted AGENTS.md copy → exit 0 (WARN, not GAP)" 0 "$STATUS"
check_contains "warns about the drifted copy" "$OUT" "drifted from CLAUDE.md"

# a broader glob (not the literal "AGENTS.md" line) still counts as ignored — the check uses
# git check-ignore, not a literal-line grep, so a *.md-style pattern is recognized correctly
d="$(mkproj)"; git -C "$d" init -q
printf '# ctx\n' > "$d/CLAUDE.md"; printf '*.md\n.claude/\n' > "$d/.gitignore"
ln -s CLAUDE.md "$d/AGENTS.md"
run "$doctor" "$d"
check_status "AGENTS.md ignored via a broader glob → exit 0" 0 "$STATUS"
check_absent "no AGENTS.md gitignore gap under a broader glob" "$OUT" "does not ignore AGENTS.md"

# edge: AGENTS.md exists but CLAUDE.md is entirely absent — only the first GAP signal applies (nothing
# to inherit from or drift against)
d="$(mkproj)"; git -C "$d" init -q
printf '.claude/\n' > "$d/.gitignore"   # ignores neither CLAUDE.md nor AGENTS.md
printf '# ctx\n' > "$d/AGENTS.md"
run "$doctor" "$d"
check_status "AGENTS.md present, CLAUDE.md absent, unignored → GAP exit 1" 1 "$STATUS"
check_contains "reports the AGENTS.md gitignore gap" "$OUT" "does not ignore AGENTS.md"
check_absent "no inherit gap when there's no CLAUDE.md to inherit from" "$OUT" "does not match CLAUDE.md's"
check_absent "no drift warn when there's no CLAUDE.md to drift against" "$OUT" "drifted from CLAUDE.md"

# edge: AGENTS.md is a broken symlink (target CLAUDE.md missing) — never-clobber logic in init-project.sh
# and doctor's existence check both key off `-e || -L`, so a broken symlink must still be picked up
d="$(mkproj)"; git -C "$d" init -q
printf 'CLAUDE.md\nAGENTS.md\n.claude/\n' > "$d/.gitignore"   # both ignored, no CLAUDE.md present
ln -s CLAUDE.md "$d/AGENTS.md"
run "$doctor" "$d"
check_status "broken AGENTS.md symlink, both ignored → exit 0" 0 "$STATUS"
check_absent "no AGENTS.md gitignore gap for a broken but ignored symlink" "$OUT" "does not ignore AGENTS.md"

# WARN: AGENTS.md is a symlink, but NOT to CLAUDE.md — a symlink can't "drift" by content, but pointing
# somewhere else entirely is just as wrong, so the drift check must inspect the target, not just -L
d="$(mkproj)"; git -C "$d" init -q
printf '# ctx\n' > "$d/CLAUDE.md"; printf 'CLAUDE.md\nAGENTS.md\n.claude/\n' > "$d/.gitignore"
printf 'not claude content\n' > "$d/some-other-file.md"
ln -s some-other-file.md "$d/AGENTS.md"
run "$doctor" "$d"
check_status "AGENTS.md symlinked to the wrong target → exit 0 (WARN, not GAP)" 0 "$STATUS"
check_contains "warns the symlink doesn't point at CLAUDE.md" "$OUT" "does not point at CLAUDE.md"

# no WARN: a permission-denied CLAUDE.md must not be misreported as a content drift (cmp's read-error
# exit looks identical to a real diff unless guarded) — skipped on a root CI runner, where chmod 000 is
# a no-op for the root reader (the project's own documented Alpine trap)
if [ "$(id -u 2>/dev/null)" != 0 ]; then
  d="$(mkproj)"; git -C "$d" init -q
  printf '# ctx\n' > "$d/CLAUDE.md"; printf 'CLAUDE.md\nAGENTS.md\n.claude/\n' > "$d/.gitignore"
  printf '# ctx\n' > "$d/AGENTS.md"
  chmod 000 "$d/CLAUDE.md"
  run "$doctor" "$d"
  chmod 644 "$d/CLAUDE.md"   # restore so cleanup can remove the sandbox
  check_absent "unreadable CLAUDE.md is not misreported as AGENTS.md drift" "$OUT" "drifted from CLAUDE.md"
fi

# footprint over budget is advisory: a HINT (dir #45 retiered it from WARN), still exit 0
d="$(mkproj)"; git -C "$d" init -q
printf 'plenty of startup context goes here\n' > "$d/CLAUDE.md"
printf 'CLAUDE.md\n.claude/\n' > "$d/.gitignore"
run env KEEL_STARTUP_WARN_TOKENS=1 "$doctor" "$d"
check_status "footprint over budget → still exit 0" 0 "$STATUS"
check_contains "reports the footprint finding" "$OUT" "footprint"
# The TIER is a separate leading token from the ID (flush_notes prints "  HINT [ID] msg"), so asserting
# on "[H-FOOTPRINT]" alone would pass under WARN too — it has to carry the tier word.
check_contains "footprint is a HINT, not a WARN" "$OUT" "HINT [H-FOOTPRINT]"
check_contains "footprint names the PROJECT file it measured" "$OUT" "project CLAUDE.md startup footprint"

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

# ...but a public-safe noreply commit email draws NO nudge — doctor's safe set mirrors public-audit's
# SAFE_EMAILS (a GitHub numeric-id noreply is on that canonical list).
d="$(mkproj)"; git -C "$d" init -q
printf '# ctx\n' > "$d/CLAUDE.md"; printf 'CLAUDE.md\n.claude/\n' > "$d/.gitignore"
printf 'token: secret-name\n' > "$d/.public-audit"
git -C "$d" config user.email '12345+dev@users.noreply.github.com'
run "$doctor" "$d"
check_absent "github-noreply commit email → no nudge (safe set matches public-audit)" "$OUT" "not a noreply address"

# a deceptive 'noreply'-containing corporate email is NOT public-safe — the old loose `noreply` substring
# waved it through; the aligned set (anchored patterns) nudges, matching public-audit's verdict.
d="$(mkproj)"; git -C "$d" init -q
printf '# ctx\n' > "$d/CLAUDE.md"; printf 'CLAUDE.md\n.claude/\n' > "$d/.gitignore"
printf 'token: secret-name\n' > "$d/.public-audit"
git -C "$d" config user.email 'dev@noreply.corp.com'
run "$doctor" "$d"
check_contains "deceptive noreply-corp email → nudges (no longer waved through)" "$OUT" "not a noreply address"

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

# --- per-stack lint gate (FRAMEWORK "Code conventions") — advisory WARN, never a GAP ------------
# Java stack without a Checkstyle config → WARN; adding one clears it
d="$(newbase)"; printf 'public class A {}\n' > "$d/A.java"
run "$doctor" "$d"
check_status  "Java stack, no checkstyle → exit 0 (WARN)" 0 "$STATUS"
check_contains "flags missing checkstyle" "$OUT" "no checkstyle"
printf '<module name="Indentation"/>\n' > "$d/checkstyle.xml"
run "$doctor" "$d"
check_absent  "checkstyle present → no checkstyle WARN" "$OUT" "no checkstyle"
# a Java wildcard import is flagged
d="$(newbase)"; printf 'import java.util.*;\npublic class B {}\n' > "$d/B.java"
printf '<module name="Indentation"/>\n' > "$d/checkstyle.xml"
run "$doctor" "$d"
check_contains "flags a Java wildcard import" "$OUT" "wildcard import"

# SCALE regression (S1 — pipefail + SIGPIPE): on a large tree the OLD `fp_find … | grep -q .` made find
# keep writing after grep matched and exited, so find died with SIGPIPE (141); `set -o pipefail` propagated
# the 141 and the `if`/`||` gate silently flipped — the stack went undetected, NO WARN. Enough .java paths
# here to overflow the pipe buffer (~64KB on Linux, ~16KB on macOS), which is what triggers the bug.
bulk_java() {  # $1 dir, $2 count — empty .java files under src/ to overflow the pipe buffer with paths
  local dir="$1" n="$2" i=1
  mkdir -p "$dir/src"
  while [ "$i" -le "$n" ]; do : > "$dir/src/File$i.java"; i=$((i + 1)); done
}
d="$(newbase)"; bulk_java "$d" 2000
run "$doctor" "$d"
check_status   "large Java tree → exit 0 (no pipefail/SIGPIPE crash)" 0 "$STATUS"
check_contains "large Java tree still detected despite scale (S1)" "$OUT" "no checkstyle"
# the -exec grep scan (wildcard imports) is the same pipe shape — must still find a real hit at scale
d="$(newbase)"; bulk_java "$d" 2000
printf '<module name="Indentation"/>\n' > "$d/checkstyle.xml"
printf 'import java.util.*;\npublic class Wild {}\n' > "$d/src/Wild.java"
run "$doctor" "$d"
check_contains "wildcard import still found on a large tree (S1 -exec scan)" "$OUT" "wildcard import"

# Python stack (pyproject without [tool.ruff]) → WARN; with it → none
d="$(newbase)"; printf '[project]\nname = "x"\n' > "$d/pyproject.toml"
run "$doctor" "$d"
check_contains "flags missing Ruff config" "$OUT" "no Ruff config"
printf '[tool.ruff]\nline-length = 100\n' >> "$d/pyproject.toml"
run "$doctor" "$d"
check_absent  "[tool.ruff] present → no Ruff WARN" "$OUT" "no Ruff config"

# Swift stack without SwiftLint → WARN; a VENDORED config under .build/ must NOT count (pruning)
d="$(newbase)"; printf 'print("hi")\n' > "$d/main.swift"
mkdir -p "$d/.build/dep"; printf 'rules: []\n' > "$d/.build/dep/.swiftlint.yml"
run "$doctor" "$d"
check_contains "flags missing SwiftLint (vendored .build/ config pruned)" "$OUT" "no SwiftLint"
printf 'rules: []\n' > "$d/.swiftlint.yml"
run "$doctor" "$d"
check_absent  "first-party SwiftLint config → no WARN" "$OUT" "no SwiftLint"

# Bash stack without ShellCheck config → WARN; a VENDORED config under node_modules/ must NOT count (pruning)
d="$(newbase)"; printf '#!/usr/bin/env bash\necho hi\n' > "$d/run.sh"
mkdir -p "$d/node_modules/dep"; printf 'disable=SC2034\n' > "$d/node_modules/dep/.shellcheckrc"
run "$doctor" "$d"
check_contains "flags missing ShellCheck config (vendored node_modules/ config pruned)" "$OUT" "no ShellCheck"
printf 'disable=SC2034\n' > "$d/.shellcheckrc"
run "$doctor" "$d"
check_absent  "first-party .shellcheckrc → no WARN" "$OUT" "no ShellCheck"
# a CI-wired shellcheck invocation with no rc file (no config-file signal available) must still clear the gate
d="$(newbase)"; printf '#!/usr/bin/env bash\necho hi\n' > "$d/run.sh"
mkdir -p "$d/.github/workflows"
printf 'jobs:\n  x:\n    steps:\n      - run: shellcheck run.sh\n' > "$d/.github/workflows/ci.yml"
run "$doctor" "$d"
check_absent  "shellcheck invoked in CI with no rc file → no WARN" "$OUT" "no ShellCheck"

# --- worktree CLAUDE.md bridge (FRAMEWORK "Worktree discipline") — advisory WARN -----------------
# private-fork project (gitignored CLAUDE.md): a linked worktree checks out WITHOUT one → bridge WARN
base="$(mkproj)"; git -C "$base" init -q
printf '# ctx\n' > "$base/CLAUDE.md"; printf 'CLAUDE.md\n.claude/\n' > "$base/.gitignore"
git -C "$base" add .gitignore
git -C "$base" -c user.email=t@keel.invalid -c user.name=t commit -qm init
wtb="$SANDBOX/wtbridge.$$"
git -C "$base" worktree add -q "$wtb" >/dev/null 2>&1
run "$doctor" "$base"
check_contains "private-fork worktree missing CLAUDE.md → bridge WARN" "$OUT" "missing the CLAUDE.md bridge"
# adding the bridge symlink clears it
ln -s "$base/CLAUDE.md" "$wtb/CLAUDE.md"
run "$doctor" "$base"
check_absent  "bridged worktree → no bridge WARN" "$OUT" "missing the CLAUDE.md bridge"

# public-fork project (committed CLAUDE.md): a worktree checks it out → exempt, no bridge WARN
base="$(mkproj)"; git -C "$base" init -q
printf '# pub\n' > "$base/CLAUDE.md"; printf '*.log\n' > "$base/.gitignore"
git -C "$base" add CLAUDE.md .gitignore
git -C "$base" -c user.email=t@keel.invalid -c user.name=t commit -qm init
wtp="$SANDBOX/wtpub.$$"
git -C "$base" worktree add -q "$wtp" >/dev/null 2>&1
run "$doctor" "$base"
check_absent  "public-fork worktree → exempt from bridge WARN" "$OUT" "missing the CLAUDE.md bridge"

# --- impact-tracking split-brain (dir #10 residue (b)): a worktree-local .keel/ marker alongside the
# main checkout's own → advisory WARN, both directions -------------------------------------------
base="$(mkproj)"; git -C "$base" init -q
git -C "$base" -c user.email=t@keel.invalid -c user.name=t commit -qm init --allow-empty >/dev/null
wts="$SANDBOX/wtsplit.$$"
git -C "$base" worktree add -q "$wts" >/dev/null 2>&1
# neither side has a marker yet → no split-brain WARN
run "$doctor" "$wts"
check_absent "no .keel/ anywhere → no split-brain WARN" "$OUT" "coexists with the main checkout"
mkdir "$base/.keel"
run "$doctor" "$wts"
check_absent "only the main-top marker → no split-brain WARN from the worktree side" "$OUT" "coexists with the main checkout"
run "$doctor" "$base"
check_absent "only the main-top marker → no split-brain WARN from the main side" "$OUT" "carry their own .keel/ marker"
# now plant a stray marker in the worktree too → split-brain WARN, checked from BOTH sides
mkdir "$wts/.keel"
run "$doctor" "$wts"
check_contains "worktree-local + main-top .keel/ → split-brain WARN (from the worktree)" "$OUT" "coexists with the main checkout"
run "$doctor" "$base"
check_contains "worktree-local + main-top .keel/ → split-brain WARN (from the main checkout)" "$OUT" "carry their own .keel/ marker"

# --- secret-guard drift: an installed copy that differs from the shipped engine → WARN -----------
shipped="$REPO_ROOT/tools/secret-guard/secret-scan.sh"

# a WIRED local-override copy that drifted
d="$(mkproj)"; git -C "$d" init -q
printf '# ctx\n' > "$d/CLAUDE.md"; printf 'CLAUDE.md\n.claude/\n' > "$d/.gitignore"
mkdir -p "$d/vhooks"; cp "$shipped" "$d/vhooks/secret-scan.sh"; printf '\n# stale\n' >> "$d/vhooks/secret-scan.sh"
git -C "$d" config core.hooksPath vhooks
run "$doctor" "$d"
check_status "drifted local-override guard → exit 0 (WARN)" 0 "$STATUS"
check_contains "warns the vendored engine drifted" "$OUT" "differs from the engine this Keel checkout ships"

# the same override with an IDENTICAL copy → no drift WARN
d="$(mkproj)"; git -C "$d" init -q
printf '# ctx\n' > "$d/CLAUDE.md"; printf 'CLAUDE.md\n.claude/\n' > "$d/.gitignore"
mkdir -p "$d/vhooks"; cp "$shipped" "$d/vhooks/secret-scan.sh"
git -C "$d" config core.hooksPath vhooks
run "$doctor" "$d"
check_absent "up-to-date local-override guard → no drift WARN" "$OUT" "differs from the engine"

# a vendored copy in the REAL hooks dir (no override, no global) that drifted
d="$(mkproj)"; git -C "$d" init -q
printf '# ctx\n' > "$d/CLAUDE.md"; printf 'CLAUDE.md\n.claude/\n' > "$d/.gitignore"
vh="$(git -C "$d" rev-parse --git-path hooks)"; case "$vh" in /*) ;; *) vh="$d/$vh" ;; esac
mkdir -p "$vh"; printf '#!/bin/sh\n' > "$vh/pre-commit"; chmod +x "$vh/pre-commit"
cp "$shipped" "$vh/secret-scan.sh"; printf '\n# stale\n' >> "$vh/secret-scan.sh"
run "$doctor" "$d"
check_contains "drifted git-path-hooks vendored guard → WARN" "$OUT" "differs from the engine this Keel checkout ships"

# machine-global drift: reported ONCE (sandboxed global gitconfig), silent when in sync
d="$(mkproj)"; git -C "$d" init -q
printf '# ctx\n' > "$d/CLAUDE.md"; printf 'CLAUDE.md\n.claude/\n' > "$d/.gitignore"
gdir="$SANDBOX/ghooks-drift"; mkdir -p "$gdir"
cp "$shipped" "$gdir/secret-scan.sh"; printf '\n# stale\n' >> "$gdir/secret-scan.sh"
git config --global core.hooksPath "$gdir"
run "$doctor" "$d"
check_status "machine-global drifted guard → exit 0 (WARN)" 0 "$STATUS"
check_contains "warns the machine-global engine drifted" "$OUT" "machine-global secret-guard"
cp "$shipped" "$gdir/secret-scan.sh"
run "$doctor" "$d"
check_absent "machine-global guard in sync → no drift WARN" "$OUT" "machine-global secret-guard"
git config --global --unset core.hooksPath

# ...and from a linked WORKTREE, the machine-global drift accept file resolves at the MAIN checkout
# — not the raw CWD toplevel (which, inside a worktree, is the worktree itself). A regression test for
# a bug found in review: an earlier version keyed this one WARN's accept lookup off the raw worktree
# toplevel, so accepting it there would have planted exactly the worktree-local .keel/ marker the
# split-brain check (W-KEEL-SPLIT) exists to catch.
base="$(mkproj)"; git -C "$base" init -q
printf '# ctx\n' > "$base/CLAUDE.md"; printf 'CLAUDE.md\n.claude/\n' > "$base/.gitignore"
git -C "$base" add .gitignore
git -C "$base" -c user.email=t@keel.invalid -c user.name=t commit -qm init
wtg="$SANDBOX/wtguard.$$"
git -C "$base" worktree add -q "$wtg" >/dev/null 2>&1
ln -s "$base/CLAUDE.md" "$wtg/CLAUDE.md"
gdir2="$SANDBOX/ghooks-drift-wt"; mkdir -p "$gdir2"
cp "$shipped" "$gdir2/secret-scan.sh"; printf '\n# stale\n' >> "$gdir2/secret-scan.sh"
git config --global core.hooksPath "$gdir2"
# invoked FROM inside the worktree (cwd, not a positional arg) — the case the fix targets
run_in "$wtg" "$doctor" .
check_contains "worktree-cwd run flags the drift (no accept yet)" "$OUT" "machine-global secret-guard"
mkdir -p "$base/.keel"; printf 'W-GUARD-GLOBAL-STALE\n' > "$base/.keel/doctor-accept"
run_in "$wtg" "$doctor" .
check_absent "main-checkout accept file suppresses it from the worktree cwd" "$OUT" "machine-global secret-guard"
check_absent "no worktree-local .keel/ needed to accept it" "$OUT" "coexists with the main checkout"
git config --global --unset core.hooksPath

# --- map-drift (dir #39 T1): a backtick-spanned path in the LIVE map that no longer exists ------
# a bare filename with a known extension that exists on disk → no drift WARN
d="$(newbase)"; printf '# ctx\nSee `doctor.sh` for the checks.\n' >> "$d/CLAUDE.md"
mkdir -p "$d/tools"; : > "$d/doctor.sh"
run "$doctor" "$d"
check_absent "existing path mentioned → no map-drift WARN" "$OUT" "map may be stale"

# a slash-path that does NOT exist on disk → WARN, names the missing token
d="$(newbase)"; printf '# ctx\nSee `scripts/ghost.sh` for details.\n' >> "$d/CLAUDE.md"
run "$doctor" "$d"
check_status "missing mapped path → still exit 0 (WARN)" 0 "$STATUS"
check_contains "map-drift WARN fires" "$OUT" "map may be stale"
check_contains "map-drift WARN names the missing path" "$OUT" "scripts/ghost.sh"

# a trailing-args span (`scripts/ghost.sh --quiet`) still checks only the first token as the path
d="$(newbase)"; printf '# ctx\nRun `scripts/ghost.sh --quiet` first.\n' >> "$d/CLAUDE.md"
run "$doctor" "$d"
check_contains "trailing-args span still flags the leading path token" "$OUT" "scripts/ghost.sh"

# a backtick span with no path signal (no slash, no known extension) is never a candidate
d="$(newbase)"; printf '# ctx\nRun `git status` first.\n' >> "$d/CLAUDE.md"
run "$doctor" "$d"
check_absent "non-path backtick span → no map-drift WARN" "$OUT" "map may be stale"

# placeholders, globs, ~-paths, and absolute paths (incl. KB neutral stand-ins) are unverifiable by
# design — never flagged even though none of them exist on disk
d="$(newbase)"
{
  printf 'placeholder: `<project>/CLAUDE.md`\n'
  printf 'glob: `src/*.ts`\n'
  printf 'home: `~/.claude/CLAUDE.md`\n'
  printf 'stand-in: `/Users/x/pet-projects/ghost/CLAUDE.md`\n'
} >> "$d/CLAUDE.md"
run "$doctor" "$d"
check_absent "placeholder/glob/~/absolute mentions → no map-drift WARN" "$OUT" "map may be stale"

# a backtick-quoted URL is never a candidate — it contains a slash but has no relative-path meaning,
# and would otherwise sail past the extension-requirement branch (that branch only fires when there's
# no slash) straight into a doomed existence check
d="$(newbase)"; printf '# ctx\nSee `https://github.com/rockerlabs/keel/blob/main/ghost.sh` for details.\n' >> "$d/CLAUDE.md"
run "$doctor" "$d"
check_absent "backtick-quoted URL → no map-drift WARN" "$OUT" "map may be stale"

# a mid-token env-var reference is unverifiable wherever it sits, not just at the start
d="$(newbase)"; printf '# ctx\nWrites to `output/$BUILD_ID/report.md`.\n' >> "$d/CLAUDE.md"
run "$doctor" "$d"
check_absent "mid-token env-var reference → no map-drift WARN" "$OUT" "map may be stale"

# a literal trailing ~ (an editor backup name) is a real, checkable filename — NOT swept up by the
# ~-path skip rule the way a mid-token $ is, since ~-paths stay prefix-anchored
d="$(newbase)"; printf '# ctx\nSee `scripts/ghost.sh~` for details.\n' >> "$d/CLAUDE.md"
mkdir -p "$d/scripts"; : > "$d/scripts/ghost.sh~"
run "$doctor" "$d"
check_absent "literal trailing ~ filename that exists → no map-drift WARN" "$OUT" "map may be stale"

# a `path:LINE` doc-link decoration (this file's own convention, e.g. `tools/doctor.sh:42`) is stripped
# before the existence check — the decoration isn't part of the path
d="$(newbase)"; printf '# ctx\nSee `scripts/ghost.sh:42` for details.\n' >> "$d/CLAUDE.md"
mkdir -p "$d/scripts"; : > "$d/scripts/ghost.sh"
run "$doctor" "$d"
check_absent "path:LINE decoration stripped, existing target → no map-drift WARN" "$OUT" "map may be stale"
d="$(newbase)"; printf '# ctx\nSee `scripts/ghost.sh:42` for details.\n' >> "$d/CLAUDE.md"
run "$doctor" "$d"
check_contains "path:LINE decoration stripped, missing target → WARN names the bare path" "$OUT" "scripts/ghost.sh"
check_absent "the report never leaks the :LINE decoration itself" "$OUT" "scripts/ghost.sh:42"

# a long dot-led name (a real dotfile's whole name, e.g. .gitignore/.editorconfig) is a candidate —
# distinct from a short bare extension mention (`.sh`, `.json`), which is a file-TYPE reference in
# prose with no basename to check
d="$(newbase)"; printf '# ctx\nSee `.editorconfig` for style rules.\n' >> "$d/CLAUDE.md"
run "$doctor" "$d"
check_contains "missing long dotfile name → WARN names it" "$OUT" ".editorconfig"
d="$(newbase)"; printf '# ctx\nSee `.editorconfig` for style rules.\n' >> "$d/CLAUDE.md"
: > "$d/.editorconfig"
run "$doctor" "$d"
check_absent "existing long dotfile name → no map-drift WARN" "$OUT" "map may be stale"

# a backtick-quoted illustrative path INSIDE a fenced code block is a doc example, not a live map
# reference — the live-map-only rule (dir #39 spec) applies to fences the same way it applies to
# CLAUDE-archive.md/BACKLOG.md: a fence's own content is not the author's current map assertion
d="$(newbase)"
{
  printf '# ctx\n'
  printf '```bash\n'
  printf '# example: see `scripts/old-example.sh` for the old approach\n'
  printf '```\n'
} >> "$d/CLAUDE.md"
run "$doctor" "$d"
check_absent "backtick span inside a fenced code block → no map-drift WARN" "$OUT" "map may be stale"

# a baseline-accepted mention (gitignored .keel/map-drift-baseline) never warns again
d="$(newbase)"; printf '# ctx\nSee `scripts/ghost.sh` for details.\n' >> "$d/CLAUDE.md"
mkdir -p "$d/.keel"; printf 'scripts/ghost.sh\n' > "$d/.keel/map-drift-baseline"
run "$doctor" "$d"
check_absent "baseline-accepted path → no map-drift WARN" "$OUT" "map may be stale"

# a linked worktree's map-drift baseline resolves to the MAIN checkout's .keel/, never a worktree-local
# one (mirrors the split-brain discipline just above — a worktree-local .keel/ would itself draw a WARN)
base="$(mkproj)"; git -C "$base" init -q
printf '# ctx\nSee `scripts/ghost.sh` for details.\n' > "$base/CLAUDE.md"
printf 'CLAUDE.md\n.claude/\n' > "$base/.gitignore"
git -C "$base" add .gitignore
git -C "$base" -c user.email=t@keel.invalid -c user.name=t commit -qm init
wtd="$SANDBOX/wtdrift.$$"
git -C "$base" worktree add -q "$wtd" >/dev/null 2>&1
ln -s "$base/CLAUDE.md" "$wtd/CLAUDE.md"
run "$doctor" "$wtd"
check_contains "worktree audit still flags the missing path (no baseline yet)" "$OUT" "map may be stale"
mkdir -p "$base/.keel"; printf 'scripts/ghost.sh\n' > "$base/.keel/map-drift-baseline"
run "$doctor" "$wtd"
check_absent "main-checkout baseline suppresses the WARN from the worktree" "$OUT" "map may be stale"
check_absent "no worktree-local .keel/ was created just to look up the baseline" "$OUT" "coexists with the main checkout"

# report cap: more than 5 missing paths → top 5 named plus a "and K more" tail
d="$(newbase)"
{
  printf 'a: `one.sh` b: `two.sh` c: `three.sh`\n'
  printf 'd: `four.sh` e: `five.sh` f: `six.sh` g: `seven.sh`\n'
} >> "$d/CLAUDE.md"
run "$doctor" "$d"
check_contains "report cap: names the tail count" "$OUT" "and 2 more"

# CLAUDE-archive.md / BACKLOG.md are historical by convention — doctor never reads them for drift,
# only the live project CLAUDE.md, so a dead path mentioned there must NOT surface here
d="$(newbase)"; printf '# ctx\nDead: `ghost-in-archive.sh`\n' > "$d/CLAUDE-archive.md"
run "$doctor" "$d"
check_absent "CLAUDE-archive.md mentions are never checked" "$OUT" "ghost-in-archive.sh"

# --- dir #45: triaged output — tiers ordered GAP→WARN→HINT, stable IDs, accept file, tail summary
# a mixed run: GAP (no CLAUDE.md) + WARN (event log) + HINT (floating dep) — every line carries its
# ID, and the tiers print in severity order regardless of check order in the code
mixed() {  # a project that draws one finding of each tier; prints its path
  local d; d="$(mkproj)"; git -C "$d" init -q
  printf '.claude/\n' > "$d/.gitignore"             # no CLAUDE.md, not gitignored → GAP
  mkdir "$d/.keel"                                  # event log not gitignored → WARN
  printf 'FROM postgres:latest\n' > "$d/Dockerfile" # floating dep → HINT
  printf '%s' "$d"
}
d="$(mixed)"
run "$doctor" "$d"
check_status   "mixed run → GAP still fails (exit 1)" 1 "$STATUS"
check_contains "GAP line carries its stable ID"  "$OUT" "[G-CLAUDEMD-MISSING]"
check_contains "WARN line carries its stable ID" "$OUT" "[W-EVENTLOG-TRACKED]"
check_contains "HINT line carries its stable ID" "$OUT" "[H-DEP-FLOATING]"
ord="$(printf '%s\n' "$OUT" | grep -oE 'G-CLAUDEMD-MISSING|W-EVENTLOG-TRACKED|H-DEP-FLOATING' | tr '\n' ' ')"
if [ "$ord" = "G-CLAUDEMD-MISSING W-EVENTLOG-TRACKED H-DEP-FLOATING " ]; then
  pass "findings print in tier order GAP → WARN → HINT"
else
  fail "findings print in tier order GAP → WARN → HINT" "got order: $ord"
fi
# (exact warn count varies with the sandbox: no global guard there adds W-GUARD-UNWIRED)
check_contains "dirty run prints the tail summary" "$OUT" "doctor: 1 gap,"
check_contains "dirty summary counts the hint" "$OUT" "1 hint"

# the tail summary prints on a CLEAN run too (alongside the baseline-OK line)
d="$(newbase)"
run "$doctor" "$d"
check_contains "clean run keeps the baseline-OK line" "$OUT" "baseline OK"
check_contains "clean run prints the tail summary"    "$OUT" "doctor: 0 gap,"

# --quiet: GAP/WARN lines only — hints hidden from the listing but still counted in the summary
d="$(mixed)"
run "$doctor" --quiet "$d"
check_contains "--quiet keeps the GAP line"  "$OUT" "[G-CLAUDEMD-MISSING]"
check_contains "--quiet keeps the WARN line" "$OUT" "[W-EVENTLOG-TRACKED]"
check_absent   "--quiet hides the HINT line" "$OUT" "[H-DEP-FLOATING]"
check_contains "--quiet still counts the hidden hint in the summary" "$OUT" "1 hint"

# .keel/doctor-accept: a listed WARN/HINT ID is suppressed with an honest hidden-count; --all reveals it
d="$(newbase)"; printf 'FROM postgres:latest\n' > "$d/Dockerfile"
mkdir -p "$d/.keel"
printf '# convention nudges reviewed 2026-07-20\nH-DEP-FLOATING  # pinning parked\n' > "$d/.keel/doctor-accept"
printf '/.keel/impact-events.log\n' >> "$d/.gitignore"   # keep the .keel/ dir itself finding-free
run "$doctor" "$d"
check_absent   "accepted HINT is suppressed" "$OUT" "[H-DEP-FLOATING]"
check_contains "suppressed finding is counted in the summary" "$OUT" "(1 accepted hidden)"
run "$doctor" --all "$d"
check_contains "--all reveals the accepted finding" "$OUT" "[H-DEP-FLOATING]"
check_contains "--all marks it as accepted" "$OUT" "(accepted)"
check_absent   "--all hides nothing" "$OUT" "accepted hidden"

# accepting a GAP ID is ignored — a hard failure can't be waved away into a green exit
d="$(mkproj)"; git -C "$d" init -q
printf '.claude/\n/.keel/impact-events.log\n' > "$d/.gitignore"   # no CLAUDE.md → GAP
mkdir -p "$d/.keel"; printf 'G-CLAUDEMD-MISSING\n' > "$d/.keel/doctor-accept"
run "$doctor" "$d"
check_status   "accepted GAP still fails the audit" 1 "$STATUS"
check_contains "accepted GAP still prints" "$OUT" "[G-CLAUDEMD-MISSING]"

# a linked worktree resolves the accept file at the MAIN checkout's .keel/ — same discipline as the
# map-drift baseline (a worktree-local .keel/ would itself draw the split-brain WARN)
base="$(mkproj)"; git -C "$base" init -q
printf '# ctx\n' > "$base/CLAUDE.md"
printf 'CLAUDE.md\n.claude/\n/.keel/impact-events.log\n' > "$base/.gitignore"
printf 'FROM postgres:latest\n' > "$base/Dockerfile"
git -C "$base" add .gitignore Dockerfile
git -C "$base" -c user.email=t@keel.invalid -c user.name=t commit -qm init
wta="$SANDBOX/wtaccept.$$"
git -C "$base" worktree add -q "$wta" >/dev/null 2>&1
ln -s "$base/CLAUDE.md" "$wta/CLAUDE.md"
run "$doctor" "$wta"
check_contains "worktree audit flags the floating dep (no accept yet)" "$OUT" "[H-DEP-FLOATING]"
mkdir -p "$base/.keel"; printf 'H-DEP-FLOATING\n' > "$base/.keel/doctor-accept"
run "$doctor" "$wta"
check_absent   "main-checkout accept file suppresses it from the worktree" "$OUT" "[H-DEP-FLOATING]"
check_contains "worktree run counts the hidden finding" "$OUT" "(1 accepted hidden)"

# an EXISTING-but-UNREADABLE .keel/doctor-accept (or map-drift-baseline) must degrade to "treat as
# empty," not crash the whole run under set -euo pipefail — regression for a review finding: the two
# files are read via a bare (non-`local`) assignment, so an unguarded `sed`/`cat` failure there used
# to kill the script mid-unit, silently dropping every finding already buffered for it.
# `chmod 000` is meaningless as root (root reads regardless of mode bits — the CI alpine-busybox leg
# runs as root in its container), so the content assertion only holds under a real unprivileged user;
# skip it there rather than assert something the platform can't produce (a `0 failed` skip beats a
# guaranteed-false red herring). The `exit 0` / no-crash half is platform-independent and always runs.
d="$(newbase)"; printf 'FROM postgres:latest\n' > "$d/Dockerfile"
mkdir -p "$d/.keel"; printf 'H-DEP-FLOATING\n' > "$d/.keel/doctor-accept"
chmod 000 "$d/.keel/doctor-accept"
run "$doctor" "$d"
check_status "unreadable doctor-accept → doesn't crash (exit 0)" 0 "$STATUS"
if [ "$(id -u 2>/dev/null)" != 0 ]; then
  check_contains "unreadable doctor-accept → treated as empty, finding still shown" "$OUT" "[H-DEP-FLOATING]"
fi
chmod 644 "$d/.keel/doctor-accept"

d="$(newbase)"; printf '# ctx\nSee `scripts/ghost.sh` for details.\n' >> "$d/CLAUDE.md"
mkdir -p "$d/.keel"; printf 'scripts/ghost.sh\n' > "$d/.keel/map-drift-baseline"
chmod 000 "$d/.keel/map-drift-baseline"
run "$doctor" "$d"
check_status "unreadable map-drift-baseline → doesn't crash (exit 0)" 0 "$STATUS"
if [ "$(id -u 2>/dev/null)" != 0 ]; then
  check_contains "unreadable map-drift-baseline → treated as empty, drift still flagged" "$OUT" "map may be stale"
fi
chmod 644 "$d/.keel/map-drift-baseline"

summary
