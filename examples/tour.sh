#!/usr/bin/env bash
# A self-contained 5-minute tour of Keel's mechanized tools. Runs entirely inside a throwaway
# sandbox: it redirects HOME and the global git config into a temp dir, touches nothing on your
# machine, and cleans up on exit. Walks: init-project -> CLAUDE.md -> doctor -> secret-guard.
#
#   examples/tour.sh
#
# Not `set -e`: one step (a blocked commit) is *meant* to fail, and the tour narrates it.
set -uo pipefail
# dir #647: drop an inherited repo selector before any git call (tests/test_git_env_guard.sh pins this line).
unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE

root="$(cd "$(dirname "$0")/.." && pwd)"

if [ -t 1 ]; then bold=$'\033[1m'; dim=$'\033[2m'; reset=$'\033[0m'; else bold=""; dim=""; reset=""; fi
step() { printf '\n%s== %s ==%s\n' "$bold" "$1" "$reset"; }
note() { printf '%s   %s%s\n' "$dim" "$1" "$reset"; }
show() { printf '\n$ %s\n' "$*"; "$@"; }

sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT
export HOME="$sandbox/home"; mkdir -p "$HOME"
# dir #720 S10-3: HOME alone is not enough — tools/lib/impact-store.sh resolves these overrides BEFORE
# HOME, so an exported one would send this demo's impact events into the operator's REAL store.
# shellcheck source=tools/lib/impact-store.sh
. "$root/tools/lib/impact-store.sh"
# shellcheck disable=SC2086  # IMPACT_ISOLATION_VARS is a space-separated list of NAMES
unset $IMPACT_ISOLATION_VARS
# dir #725: the scanner reads this machine-wide override too, and a set-but-missing value now fails it closed
# (exit 2), so an operator's stale ambient one would end the guard step below in an error, not a BLOCK.
# Unset, it falls back to $HOME/.claude/secret-scan-personal under the sandbox HOME (absent: no personal half).
unset SECRET_SCAN_PERSONAL_FILE
export GIT_CONFIG_GLOBAL="$HOME/.gitconfig"
git config --global user.email you@example.com
git config --global user.name "You"
git config --global init.defaultBranch main

proj="$sandbox/my-project"

step "1. Scaffold a new project"
note "init-project sets up git, a .gitignore that hides private AI context, and a CLAUDE.md."
show "$root/tools/init-project.sh" "$proj"

step "2. The generated CLAUDE.md (the thin, always-loaded core)"
note "Edit the placeholders for your project; everything else loads on demand."
show sed -n '1,10p' "$proj/CLAUDE.md"

step "3. Audit the baseline with doctor"
note "doctor reports drift. secret-guard isn't wired yet, so it flags a WARN (advisory, not a fail)."
show "$root/tools/doctor.sh" "$proj"

step "4. Wire secret-guard into the project"
note "A git hook that blocks key-shaped secrets before they ever reach a commit."
show "$root/tools/install-secret-guard.sh" "$proj"

step "5. Re-audit — the secret-guard WARN is gone"
show "$root/tools/doctor.sh" "$proj"

step "6. secret-guard blocks a key-shaped secret on commit"
note "A developer accidentally stages an AWS-looking key..."
# Build the fake key from parts so this script's own source never holds a whole key.
fake_key="$(printf '%s%s' 'AKIA' 'IOSFODNN7EXAMPLE')"
printf 'aws_key = "%s"\n' "$fake_key" > "$proj/config.txt"
if ( cd "$proj" && git add config.txt && show git commit -m "add config" ); then
  note "(!) commit succeeded — that should not happen"
else
  note "^ the commit was BLOCKED by the hook, exactly as intended."
fi

step "Done"
note "Nothing escaped the sandbox (auto-removed). Next: PRINCIPLES.md, FRAMEWORK.md, ADAPTING.md."
