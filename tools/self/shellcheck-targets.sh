#!/usr/bin/env bash
# tools/self/shellcheck-targets.sh — the tracked scripts shellcheck should lint: every *.sh plus any
# file whose shebang says it's a shell script (extensionless git hooks, etc.), so a new shell script can't slip
# past the gate. One canonical source for this selection — ci.yml's shellcheck job and
# tools/self/doctor.sh both call this instead of each keeping their own copy. That duplication is
# exactly the "two hand-maintained copies drift apart" shape self/doctor.sh's ship-skip-list check
# polices for install.sh/tools/doctor.sh; this file removes the risk here by construction instead of
# only detecting it after the fact.
#
# Usage: tools/self/shellcheck-targets.sh [REPO_DIR]   (default: current directory)
# Prints one repo-relative path per line.
set -euo pipefail
repo_dir="${1:-.}"
git -C "$repo_dir" ls-files | while IFS= read -r f; do
  case "$f" in
    *.sh) printf '%s\n' "$f" ;;
    *) head -1 -- "$repo_dir/$f" 2>/dev/null | grep -qE '^#!.*[ /](ba|da|k)?sh([[:space:]]|$)' \
         && printf '%s\n' "$f" ;;
  esac
done
