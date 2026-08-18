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
# core.quotePath=false: with git's default, a tracked path containing a non-ASCII byte is printed
# C-quoted (`"r\303\251sum\303\251.sh"`). That string matches neither the `*.sh` arm (it ends in a
# quote) nor `head`'s idea of a filename, so the file was silently dropped from the selection — the
# one outcome this file exists to make impossible, and invisible because the output is a list nobody
# counts (found by an independent review of dir #170, which consumes this selection).
# `if … then … fi`, NOT `grep -q … && printf`: a non-match is the ORDINARY outcome here (most tracked
# files are not scripts), but as the last command of the loop body it becomes the `while`'s status,
# and through `pipefail` the pipeline's. This script's status was therefore a function of which path
# sorts last — 1 on any repo whose final tracked file is not a shell script, on a completely healthy
# tree. A trailing `exit 0` does NOT fix that: under `set -e` the failing pipeline exits the script
# before ever reaching it. Making each iteration succeed is what actually fixes it, and it keeps a
# real failure (an unreadable repo dir) visible.
git -C "$repo_dir" -c core.quotePath=false ls-files | while IFS= read -r f; do
  case "$f" in
    *.sh) printf '%s\n' "$f" ;;
    *) if head -1 -- "$repo_dir/$f" 2>/dev/null \
            | grep -qE '^#!.*[ /](ba|da|k)?sh([[:space:]]|$)'; then
         printf '%s\n' "$f"
       fi ;;
  esac
done
